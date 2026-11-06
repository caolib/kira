import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../backup/backup_category.dart';
import '../backup/backup_codec.dart';
import '../backup/backup_document.dart';
import '../backup/backup_error.dart';
import '../backup/backup_journal.dart';
import '../backup/backup_preferences.dart';
import '../backup/backup_runtime.dart';
import '../models/secure_credential_store.dart';
import '../models/user_manager.dart' show SavedCredential;
import 'app_logger.dart';

export '../backup/backup_category.dart';
export '../backup/backup_document.dart';
export '../backup/backup_error.dart';

class SettingsBackupSummary {
  final int preferenceCount;
  final int sensitivePreferenceCount;
  final DateTime? exportedAt;

  const SettingsBackupSummary({
    required this.preferenceCount,
    required this.sensitivePreferenceCount,
    required this.exportedAt,
  });

  factory SettingsBackupSummary.fromDocument(BackupDocument document) =>
      SettingsBackupSummary(
        preferenceCount: document.preferences.length,
        sensitivePreferenceCount: document.preferences.keys
            .where((key) => BackupSchema.categoryOf(key)?.isSensitive == true)
            .length,
        exportedAt: document.exportedAt,
      );
}

class SettingsBackupOptions {
  final Set<BackupCategory> categories;
  final bool includeSensitive;

  const SettingsBackupOptions({
    this.categories = const {BackupCategory.settings},
    this.includeSensitive = false,
  });

  Set<BackupCategory> get selected => {
    ...categories,
    if (includeSensitive) ...{
      BackupCategory.account,
      BackupCategory.aiConnection,
    },
  };
}

/// Snapshot/filter and transactional category replacement; encoding and
/// transport live separately. No restore path clears "all non-cache keys".
class SettingsBackupService {
  final BackupPreferences _preferences;
  final BackupJournal _journal;
  final BackupRuntime _runtime;
  final AppLogger _logger;
  static bool _restoring = false;
  static bool _recoveryRequired = false;

  SettingsBackupService({
    BackupPreferences? preferences,
    BackupJournal? journal,
    BackupRuntime? runtime,
    AppLogger? logger,
  }) : _preferences = preferences ?? SharedBackupPreferences(),
       _journal = journal ?? EncryptedBackupJournal(),
       _runtime = runtime ?? SettingsBackupRuntime(),
       _logger = logger ?? AppLogger.instance;

  Future<BackupDocument> capture() async {
    _ensureAvailable();
    await _runtime.flush();
    // A restore can start while pending writes are being drained. Do not read
    // credentials alongside a profile that is still being replaced.
    _ensureAvailable();
    final snapshot = await _preferences.readAll();
    return _documentFrom(snapshot, BackupCategory.values.toSet());
  }

  BackupDocument _documentFrom(
    Map<String, Object> snapshot,
    Set<BackupCategory> categories,
  ) => BackupDocument(
    categories: categories,
    preferences: {
      for (final entry in snapshot.entries)
        if (categories.contains(BackupSchema.categoryOf(entry.key)))
          entry.key: _preferenceOf(entry),
    },
    exportedAt: DateTime.now().toUtc(),
  );

  /// One unsupported value type aborts the whole capture, so name the key and
  /// its runtime type instead of leaving the generic error to stand alone.
  /// Only the key and type are reported, never the value.
  BackupPreference _preferenceOf(MapEntry<String, Object> entry) {
    try {
      final preference = BackupPreference.fromValue(entry.value);
      // [BackupDocument.validate] would catch this too, but only here is the
      // offending key still known.
      if (preference.type != BackupSchema.typeOf(entry.key)) {
        throw const SettingsBackupException(
          SettingsBackupErrorCode.unsupportedFieldType,
        );
      }
      return preference;
    } catch (error, stack) {
      final type = entry.value.runtimeType.toString();
      debugPrint('Backup capture rejected ${entry.key}: $type');
      unawaited(
        AppLogger.instance.recordWarning(
          const SettingsBackupException(
            SettingsBackupErrorCode.unsupportedFieldType,
          ),
          stackTrace: stack,
          source: 'backup.capture',
          context: {'key': entry.key, 'type': type},
        ),
      );
      rethrow;
    }
  }

  Future<String> exportPlainText({
    SettingsBackupOptions options = const SettingsBackupOptions(),
  }) async {
    final document = (await capture()).select(options.selected);
    return jsonEncode(document.toJson());
  }

  SettingsBackupSummary inspectPlainText(String raw) =>
      SettingsBackupSummary.fromDocument(_parseLegacyInput(raw));

  Future<SettingsBackupSummary> importPlainText(
    String raw, {
    Set<BackupCategory>? categories,
  }) async {
    final document = _parseLegacyInput(raw);
    // Compatibility API is safe by default too; sensitive groups always need
    // an explicit selection. The new page handles all formats via BackupCodec.
    return restore(
      document,
      categories ?? document.categories.intersection({BackupCategory.settings}),
    );
  }

  BackupDocument _parseLegacyInput(String raw) {
    if (utf8.encode(raw).length > BackupCodec.maxFileBytes) {
      throw const SettingsBackupException(SettingsBackupErrorCode.tooLarge);
    }
    return BackupDocument.parse(raw);
  }

  Future<SettingsBackupSummary> restore(
    BackupDocument document,
    Set<BackupCategory> categories,
  ) async {
    _ensureAvailable();
    final replacement = document.select(categories);
    replacement.validate();
    _restoring = true;
    final diagnostics = _RestoreDiagnostics(_logger, replacement.categories);
    var mayResume = true;
    try {
      // Pause first, then drain: no older asynchronous reading write can land
      // after this point, including writes already removed from debounce maps.
      await diagnostics.measure('pause', _runtime.pause);
      final current = await diagnostics.measure(
        'snapshot',
        _preferences.readAll,
      );
      final original = _documentFrom(current, replacement.categories);
      await diagnostics.measure('journal_save', () => _journal.save(original));
      try {
        await diagnostics.measure(
          'replace',
          () =>
              _replace(replacement, current: current, diagnostics: diagnostics),
        );
        await diagnostics.measure(
          'reload',
          () => _runtime.reload(replacement.categories),
        );
        // Journal deletion is the commit point. A crash before it causes
        // startup recovery; a crash after it leaves the fully written backup.
        await diagnostics.measure('journal_clear', _journal.clear);
      } catch (error, stack) {
        diagnostics.recordFailure(error, stack);
        try {
          // A failed platform write can leave its cache ahead of the disk.
          // Rollback must replay values even if that cache claims they match.
          await diagnostics.measure(
            'rollback_replace',
            () => _replace(original, forceWrite: true),
          );
          await diagnostics.measure(
            'rollback_reload',
            () => _runtime.reload(replacement.categories),
          );
          await diagnostics.measure('rollback_journal_clear', _journal.clear);
        } catch (rollbackError, rollbackStack) {
          unawaited(
            _logger.recordWarning(
              rollbackError,
              stackTrace: rollbackStack,
              source: 'backup.restore.rollback',
            ),
          );
          diagnostics.outcome = 'recovery_required';
          mayResume = false;
          _recoveryRequired = true;
          throw const SettingsBackupException(
            SettingsBackupErrorCode.recoveryRequired,
          );
        }
        diagnostics.outcome = 'rolled_back';
        throw const SettingsBackupException(
          SettingsBackupErrorCode.writeFailed,
        );
      }
      diagnostics.outcome = 'completed';
      return SettingsBackupSummary.fromDocument(replacement);
    } catch (error, stack) {
      diagnostics.recordFailure(error, stack);
      rethrow;
    } finally {
      if (mayResume) _runtime.resume();
      _restoring = false;
      diagnostics.report();
    }
  }

  Future<void> _replace(
    BackupDocument document, {
    Map<String, Object>? current,
    bool forceWrite = false,
    _RestoreDiagnostics? diagnostics,
  }) async {
    current ??= await _preferences.readAll();
    final desired = document.preferences.map(
      (key, preference) => MapEntry(key, preference.value),
    );
    // Materialize legacy single-account backups before diffing. An explicit []
    // remains authoritative and must never synthesize remembered credentials.
    if (document.categories.contains(BackupCategory.account) &&
        !desired.containsKey('saved_credentials')) {
      final username = desired['saved_username'];
      final password = desired['saved_password'];
      final source = desired['login_source'];
      if (username is String && username.isNotEmpty && password is String) {
        desired['saved_credentials'] = jsonEncode([
          SavedCredential(
            username: username,
            password: password,
            loginSource: source is String ? source : null,
          ).toJson(),
        ]);
      }
    }
    final keys = {
      ...current.keys,
      // A migrated, absent credential can mask a stale legacy alias. Clear
      // both names even when that key was not in the effective snapshot.
      if (document.categories.contains(BackupCategory.account))
        ...SharedBackupPreferences.secureAccountKeys,
    };
    for (final key in keys) {
      if (document.categories.contains(BackupSchema.categoryOf(key)) &&
          !desired.containsKey(key)) {
        await _preferences.remove(key);
        if (diagnostics != null) diagnostics.removed++;
      }
    }
    for (final entry in desired.entries) {
      // Effective credential reads can hide a stale alias or use legacy-only
      // storage. Still route these keys through the credential writer to clean
      // aliases and persist logout/clear records in the authoritative backend.
      if (!forceWrite &&
          !SharedBackupPreferences.secureAccountKeys.contains(entry.key) &&
          _samePreferenceValue(current[entry.key], entry.value)) {
        if (diagnostics != null) diagnostics.unchanged++;
        continue;
      }
      await _preferences.write(entry.key, entry.value);
      if (diagnostics != null) diagnostics.written++;
    }
  }

  bool _samePreferenceValue(Object? current, Object desired) =>
      switch ((current, desired)) {
        (final String a, final String b) => a == b,
        (final bool a, final bool b) => a == b,
        (final int a, final int b) => a == b,
        (final double a, final double b) => a == b,
        (final List<Object?> a, final List<String> b) => listEquals(a, b),
        _ => false,
      };

  /// Called before ANY preference-backed singleton is initialized.
  /// Recovery is idempotent; failures leave the encrypted journal in place.
  Future<bool> recoverPendingRestore() async {
    if (_restoring) {
      throw const SettingsBackupException(SettingsBackupErrorCode.busy);
    }
    _restoring = true;
    try {
      final original = await _journal.read();
      if (original == null) return false;
      await _replace(original, forceWrite: true);
      await _journal.clear();
      _recoveryRequired = false;
      return true;
    } catch (error, stack) {
      unawaited(
        _logger.recordWarning(
          error,
          stackTrace: stack,
          source: 'backup.restore.recovery',
        ),
      );
      _recoveryRequired = true;
      throw const SettingsBackupException(
        SettingsBackupErrorCode.recoveryRequired,
      );
    } finally {
      _restoring = false;
    }
  }

  Future<int> clearAllPreferences() async {
    _ensureAvailable();
    _restoring = true;
    try {
      await _runtime.pause();
      final keys = (await _preferences.readAll()).keys.toList();
      for (final key in {
        ...keys,
        ...SharedBackupPreferences.secureAccountKeys,
      }) {
        await _preferences.remove(key);
      }
      // Run last: removing a primary token writes a logout tombstone, whereas
      // a full app reset deliberately deletes every device-local secret.
      await SecureCredentialStore().deleteAll();
      return keys.length;
    } finally {
      _runtime.resume();
      _restoring = false;
    }
  }

  void _ensureAvailable() {
    if (_recoveryRequired) {
      throw const SettingsBackupException(
        SettingsBackupErrorCode.recoveryRequired,
      );
    }
    if (_restoring) {
      throw const SettingsBackupException(SettingsBackupErrorCode.busy);
    }
  }
}

class _RestoreDiagnostics {
  final AppLogger _logger;
  final Set<BackupCategory> _categories;
  final Stopwatch _total = Stopwatch()..start();
  final _timings = <String, int>{};
  Object? _error;
  StackTrace? _stack;
  String outcome = 'failed';
  int written = 0;
  int removed = 0;
  int unchanged = 0;

  _RestoreDiagnostics(this._logger, this._categories);

  Future<T> measure<T>(String stage, Future<T> Function() operation) async {
    final watch = Stopwatch()..start();
    try {
      return await operation();
    } finally {
      watch.stop();
      _timings['${stage}_ms'] = watch.elapsedMilliseconds;
      debugPrint('Backup restore $stage: ${watch.elapsedMilliseconds}ms');
    }
  }

  void recordFailure(Object error, StackTrace stack) {
    _error ??= error;
    _stack ??= stack;
  }

  void report() {
    _total.stop();
    // Counts and timings only: never log preference values, credentials or paths.
    final context = <String, Object?>{
      'categories': BackupCategory.values
          .where(_categories.contains)
          .map((category) => category.name)
          .join(','),
      'outcome': outcome,
      'total_ms': _total.elapsedMilliseconds,
      ..._timings,
      'write_count': written,
      'remove_count': removed,
      'unchanged_count': unchanged,
    };
    debugPrint('Backup restore: $context');
    final message = _error ?? 'Settings restore $outcome';
    // Keep slow restores visible at the default warning threshold, without
    // enabling logs or changing the user's chosen logging settings.
    unawaited(
      _error != null || _total.elapsed >= const Duration(seconds: 2)
          ? _logger.recordWarning(
              message,
              stackTrace: _stack,
              source: 'backup.restore',
              context: context,
            )
          : _logger.recordInfo(
              message,
              source: 'backup.restore',
              context: context,
            ),
    );
  }
}
