import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_logger.dart';
import '../utils/app_storage.dart';
import 'user_manager.dart';

/// Stores credentials in the app's private SharedPreferences, without encryption.
///
/// The class name and `secure_mirror_` keys are retained for compatibility. The
/// former mirrors are now the only backing store; no Keystore/Keychain calls
/// are made. Older unprefixed preferences can be read without mutating them.
/// Encrypted-only data from older installations cannot be recovered here.
class SecureCredentialStore {
  static SecureCredentialStore _instance = SecureCredentialStore._();
  factory SecureCredentialStore() => _instance;

  static void setInstance(SecureCredentialStore store) => _instance = store;

  static void resetInstance() => _instance = SecureCredentialStore._();

  SecureCredentialStore._();

  static const _keyUsername = 'saved_username';
  static const _keyToken = 'user_token';
  static const _keyPassword = 'saved_password';
  static const _keyCredentials = 'saved_credentials';
  static const _keyMigrated = 'credentials_migrated_to_secure';
  static const _keyWebDavCredentials = 'backup_webdav_credentials_v1';
  static const _keyBackupPassword = 'backup_password_v1';
  static const _keyBackupRollbackKey = 'backup_rollback_key_v1';
  static const _keyCopyAccount = 'copy_account_v1';

  /// Historical prefix, now used for the primary plaintext credential records.
  static const preferencePrefix = 'secure_mirror_';

  static const _savedCredentialKeys = {
    _keyUsername,
    _keyPassword,
    _keyCredentials,
  };
  static const _credentialKeys = {
    _keyToken,
    ..._savedCredentialKeys,
    _keyWebDavCredentials,
    _keyBackupPassword,
    _keyBackupRollbackKey,
    _keyCopyAccount,
  };
  static const _allKeys = {..._credentialKeys, _keyMigrated};

  /// Recognizes both current records and their unprefixed legacy aliases.
  static String? logicalKeyForPreference(String key) {
    final logicalKey = key.startsWith(preferencePrefix)
        ? key.substring(preferencePrefix.length)
        : key;
    return _allKeys.contains(logicalKey) ? logicalKey : null;
  }

  Future<void>? _pendingWrite;

  /// Memory-only test stores must not read or remove real preferences.
  @protected
  bool get legacyPreferencesEnabled => true;

  @protected
  Future<String?> doRead(String key) async {
    final prefs = await AppStorage.sharedPreferences();
    final value = prefs.get('$preferencePrefix$key');
    if (value == null) return null;
    if (value is String) return value;
    if (value is List && value.length == 1) {
      final text = value.single;
      if (text is String) return text;
    }
    throw const FormatException('Invalid credential preference');
  }

  @protected
  Future<void> doWrite(String key, String value) async {
    final prefs = await AppStorage.sharedPreferences();
    final preferenceKey = '$preferencePrefix$key';
    await _checkedMutation(
      prefs,
      preferenceKey,
      () => _setPreference(prefs, preferenceKey, value),
    );
  }

  @protected
  Future<void> doDelete(String key) async {
    final prefs = await AppStorage.sharedPreferences();
    await _removePreference(prefs, '$preferencePrefix$key');
  }

  // Android reserves these String prefixes for its other preference types.
  // A single-element StringList escapes just those values without changing
  // ordinary records or ambiguously adding a prefix to existing passwords.
  static const _reservedStringPrefixes = [
    'VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu',
    'VGhpcyBpcyB0aGUgcHJlZml4IGZvciBCaWdJbnRlZ2Vy',
    'VGhpcyBpcyB0aGUgcHJlZml4IGZvciBEb3VibGUu',
  ];

  Future<bool> _setPreference(
    SharedPreferences prefs,
    String key,
    Object? value,
  ) {
    if (value == null) return prefs.remove(key);
    if (value is String) {
      return _reservedStringPrefixes.any(value.startsWith)
          ? prefs.setStringList(key, [value])
          : prefs.setString(key, value);
    }
    if (value is bool) return prefs.setBool(key, value);
    if (value is int) return prefs.setInt(key, value);
    if (value is double) return prefs.setDouble(key, value);
    if (value is List && value.every((item) => item is String)) {
      return prefs.setStringList(key, value.whereType<String>().toList());
    }
    throw const FormatException('Invalid credential preference');
  }

  Future<void> _checkedMutation(
    SharedPreferences prefs,
    String key,
    Future<bool> Function() mutation,
  ) async {
    final previous = prefs.get(key);
    try {
      if (!await mutation()) {
        throw StateError('Credential preferences write failed');
      }
    } catch (error, stack) {
      // Native prefs can update their own cache even when disk persistence
      // fails. Reload alone cannot undo that: compensate before refreshing.
      try {
        if (!await _setPreference(prefs, key, previous)) {
          throw StateError('Credential preferences rollback failed');
        }
      } catch (_, rollbackStack) {
        unawaited(
          AppLogger.instance.recordWarning(
            StateError('Credential preferences rollback failed'),
            stackTrace: rollbackStack,
            source: 'credential_store.rollback',
          ),
        );
      }
      try {
        await prefs.reload();
      } catch (_, reloadStack) {
        unawaited(
          AppLogger.instance.recordWarning(
            StateError('Credential preferences reload failed'),
            stackTrace: reloadStack,
            source: 'credential_store.reload',
          ),
        );
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<void> _removePreference(SharedPreferences prefs, String key) async {
    // Cache absence is not proof a previous failed delete reached the disk.
    await _checkedMutation(prefs, key, () => prefs.remove(key));
  }

  Future<T> _serializeWrite<T>(Future<T> Function() operation) async {
    final previous = _pendingWrite;
    final completed = Completer<void>();
    final pending = completed.future;
    _pendingWrite = pending;
    if (previous != null) await previous;
    try {
      return await operation();
    } finally {
      // An idle queue must not retain a Future created in another test Zone.
      if (identical(_pendingWrite, pending)) _pendingWrite = null;
      completed.complete();
    }
  }

  String? _legacyValue(String key, Object? value) {
    if (value is String) return value;
    if (value is List && value.length == 1) {
      final text = value.single;
      if (text is String) return text;
    }
    if (key == _keyMigrated && value is bool) return value.toString();
    return null;
  }

  Future<String?> _read(String key) async {
    final value = await doRead(key);
    if (value != null || !legacyPreferencesEnabled) return value;

    final prefs = await AppStorage.sharedPreferences();
    if (_savedCredentialKeys.contains(key)) {
      final migrated =
          await doRead(_keyMigrated) ??
          _legacyValue(_keyMigrated, prefs.get(_keyMigrated));
      // The old marker covered these three fields, but never the token.
      // Missing saved fields after migration mean they were explicitly cleared.
      if (migrated == 'true') return null;
    }
    return _legacyValue(key, prefs.get(key));
  }

  Future<void> _write(String key, String value) =>
      _serializeWrite(() => doWrite(key, value));

  Future<void> _delete(String key) => _serializeWrite(() async {
    // Remove the fallback first. If deletion fails, the current record stays
    // authoritative instead of exposing a stale legacy credential on restart.
    if (legacyPreferencesEnabled) {
      final prefs = await AppStorage.sharedPreferences();
      await _removePreference(prefs, key);
    }
    await doDelete(key);
  });

  Future<String?> readUsername() => _read(_keyUsername);

  // Empty is a logout tombstone, distinct from an unmigrated missing record.
  Future<String?> readToken() => _read(_keyToken);
  Future<void> writeToken(String? value) => _write(_keyToken, value ?? '');

  Future<String?> readPassword() => _read(_keyPassword);

  Future<bool> credentialsMigrated() async =>
      await _read(_keyMigrated) == 'true';

  Future<String?> readWebDavCredentials() => _read(_keyWebDavCredentials);
  Future<String?> readBackupPassword() => _read(_keyBackupPassword);
  Future<String?> readBackupRollbackKey() => _read(_keyBackupRollbackKey);
  Future<String?> readCopyAccountRecord() => _read(_keyCopyAccount);

  /// A null session belongs in the record, not in a deleted preference: the
  /// record also carries the explicit logout and legacy-import markers.
  Future<void> writeCopyAccountRecord(String value) =>
      _write(_keyCopyAccount, value);

  Future<void> writeWebDavCredentials(String? value) =>
      _writeOptional(_keyWebDavCredentials, value);
  Future<void> writeBackupPassword(String? value) =>
      _writeOptional(_keyBackupPassword, value);
  Future<void> writeBackupRollbackKey(String? value) =>
      _writeOptional(_keyBackupRollbackKey, value);

  Future<void> _writeOptional(String key, String? value) =>
      value == null ? _delete(key) : _write(key, value);

  /// Distinguishes an explicitly cleared list from older single-account data.
  Future<bool> hasCredentialsRecord() async =>
      await _read(_keyCredentials) != null;

  /// Raw snapshots let account transactions roll back without normalization.
  Future<String?> readCredentialsRecord() => _read(_keyCredentials);

  Future<void> writeCredentialsRecord(String? value) =>
      _writeOptional(_keyCredentials, value);

  List<dynamic> _decodeCredentialsRecord(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : [];
    } catch (error, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          error,
          stackTrace: stack,
          source: 'credential_store.decode',
        ),
      );
      return [];
    }
  }

  Future<List<SavedCredential>> readCredentials() async =>
      _decodeCredentialsRecord(await readCredentialsRecord())
          .whereType<Map>()
          .map((e) => SavedCredential.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.hasAccountKey)
          .toList();

  Future<void> writeUsername(String? value) => value == null || value.isEmpty
      ? _delete(_keyUsername)
      : _write(_keyUsername, value);

  Future<void> writePassword(String? value) => value == null || value.isEmpty
      ? _delete(_keyPassword)
      : _write(_keyPassword, value);

  // An explicit [] prevents old remembered credentials being synthesized again.
  Future<void> writeCredentials(List<SavedCredential> credentials) =>
      _serializeWrite(() async {
        final records = <dynamic>[
          for (final credential in credentials) credential.toJson(),
        ];
        if (credentials.isNotEmpty) {
          // Opaque records belong to newer versions, not the visible account
          // list. Keep them during edits; an explicit clear still removes all.
          for (final record in _decodeCredentialsRecord(
            await readCredentialsRecord(),
          )) {
            if (record is! Map ||
                !SavedCredential.fromJson(
                  Map<String, dynamic>.from(record),
                ).hasAccountKey) {
              records.add(record);
            }
          }
        }
        await doWrite(_keyCredentials, jsonEncode(records));
      });

  Future<void> deleteAll() => _serializeWrite(() async {
    if (legacyPreferencesEnabled) {
      final prefs = await AppStorage.sharedPreferences();
      for (final key in _credentialKeys) {
        await _removePreference(prefs, key);
      }
    }
    for (final key in _credentialKeys) {
      await doDelete(key);
    }
  });

  /// Copies legacy plaintext values without overwriting current records.
  /// Reads themselves never migrate, so backup reloads can remain read-only.
  Future<void> migrateFromSharedPreferences(
    Map<String, Object?> prefsMap,
    Future<void> Function(String key) removePref,
  ) => _serializeWrite(() async {
    // A queued migration must not resurrect a value deleted since its caller
    // captured prefsMap. Production uses the live prefs; tests can supply a map.
    final Map<String, Object?> source;
    if (legacyPreferencesEnabled) {
      final prefs = await AppStorage.sharedPreferences();
      source = {for (final key in _allKeys) key: prefs.get(key)};
    } else {
      source = prefsMap;
    }
    final currentMarker = await doRead(_keyMigrated);
    final migrated =
        (currentMarker ?? _legacyValue(_keyMigrated, source[_keyMigrated])) ==
        'true';
    final obsoleteKeys = <String>[];

    for (final key in _credentialKeys) {
      final legacy = _legacyValue(key, source[key]);
      if (legacy == null) continue;
      final current = await doRead(key);
      final cleared = migrated && _savedCredentialKeys.contains(key);
      if (current == null && !cleared) {
        if (!_savedCredentialKeys.contains(key) || legacy.isNotEmpty) {
          // Preserve the original JSON, including fields unknown to this build.
          await doWrite(key, legacy);
        }
      }
      obsoleteKeys.add(key);
    }

    if (currentMarker != 'true') await doWrite(_keyMigrated, 'true');
    // Every accepted value and the marker are persisted before deleting any
    // source. A failed write leaves the legacy values available for retry.
    for (final key in obsoleteKeys) {
      await removePref(key);
    }
    if (source[_keyMigrated] != null) await removePref(_keyMigrated);
  });
}

/// Isolated credential storage for tests; never reads or writes preferences.
class InMemorySecureCredentialStore extends SecureCredentialStore {
  final _map = <String, String>{};

  InMemorySecureCredentialStore() : super._();

  @override
  bool get legacyPreferencesEnabled => false;

  @override
  Future<String?> doRead(String key) async => _map[key];

  @override
  Future<void> doWrite(String key, String value) async => _map[key] = value;

  @override
  Future<void> doDelete(String key) async => _map.remove(key);
}
