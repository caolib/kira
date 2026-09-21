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
  static bool _restoring = false;
  static bool _recoveryRequired = false;

  SettingsBackupService({
    BackupPreferences? preferences,
    BackupJournal? journal,
    BackupRuntime? runtime,
  }) : _preferences = preferences ?? SharedBackupPreferences(),
       _journal = journal ?? EncryptedBackupJournal(),
       _runtime = runtime ?? SettingsBackupRuntime();

  Future<BackupDocument> capture() async {
    _ensureAvailable();
    await _runtime.flush();
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
    var mayResume = true;
    try {
      // Pause first, then drain: no older asynchronous reading write can land
      // after this point, including writes already removed from debounce maps.
      await _runtime.pause();
      final original = _documentFrom(
        await _preferences.readAll(),
        replacement.categories,
      );
      await _journal.save(original);
      try {
        await _replace(replacement);
        await _runtime.reload(replacement.categories);
        // Journal deletion is the commit point. A crash before it causes
        // startup recovery; a crash after it leaves the fully written backup.
        await _journal.clear();
      } catch (_) {
        try {
          await _replace(original);
          await _runtime.reload(replacement.categories);
          await _journal.clear();
        } catch (_) {
          mayResume = false;
          _recoveryRequired = true;
          throw const SettingsBackupException(
            SettingsBackupErrorCode.recoveryRequired,
          );
        }
        throw const SettingsBackupException(
          SettingsBackupErrorCode.writeFailed,
        );
      }
      return SettingsBackupSummary.fromDocument(replacement);
    } finally {
      if (mayResume) _runtime.resume();
      _restoring = false;
    }
  }

  Future<void> _replace(BackupDocument document) async {
    final current = await _preferences.readAll();
    for (final key in current.keys) {
      if (document.categories.contains(BackupSchema.categoryOf(key))) {
        await _preferences.remove(key);
      }
    }
    for (final entry in document.preferences.entries) {
      await _preferences.write(entry.key, entry.value.value);
    }
  }

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
      await _replace(original);
      await _journal.clear();
      _recoveryRequired = false;
      return true;
    } catch (_) {
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
      await SecureCredentialStore().deleteAll();
      for (final key in keys) {
        await _preferences.remove(key);
      }
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
