import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/secure_credential_store.dart';
import '../models/user_manager.dart';
import 'backup_error.dart';

abstract interface class BackupPreferences {
  Future<Map<String, Object>> readAll();
  Future<void> write(String key, Object value);
  Future<void> remove(String key);
}

/// Exposes portable account keys through the credential-store contract, not its
/// physical preference names. COPY and other device-local records stay private.
class SharedBackupPreferences implements BackupPreferences {
  static const secureAccountKeys = {
    'user_token',
    'saved_username',
    'saved_password',
    'saved_credentials',
  };

  final SecureCredentialStore _secure;

  SharedBackupPreferences({SecureCredentialStore? secure})
    : _secure = secure ?? SecureCredentialStore();

  @override
  Future<Map<String, Object>> readAll() => UserManager().readAccountStorage(
    () async {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().toList()..sort();
      final snapshot = <String, Object>{};
      for (final key in keys) {
        final value = prefs.get(key);
        if (value != null) {
          snapshot[key] = value is List<String>
              ? List<String>.of(value)
              : value;
        }
      }

      // Reads already resolve current records, empty logout values and legacy
      // aliases. Never let a stale raw preference override that effective view,
      // including an explicitly empty saved-account array before migration.
      snapshot.removeWhere((key, _) => secureAccountKeys.contains(key));
      for (final entry in {
        'user_token': await _secure.readToken(),
        'saved_username': await _secure.readUsername(),
        'saved_password': await _secure.readPassword(),
      }.entries) {
        final value = entry.value;
        if (value != null) snapshot[entry.key] = value;
      }
      final credentials = await _secure.readCredentials();
      if (credentials.isNotEmpty || await _secure.hasCredentialsRecord()) {
        snapshot['saved_credentials'] = jsonEncode(
          credentials.map((credential) => credential.toJson()).toList(),
        );
      }
      return snapshot;
    },
  );

  @override
  Future<void> write(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    if (secureAccountKeys.contains(key)) {
      if (value is! String) {
        throw const SettingsBackupException(
          SettingsBackupErrorCode.unsupportedFieldType,
        );
      }
      switch (key) {
        case 'user_token':
          await _secure.writeToken(value);
        case 'saved_username':
          await _secure.writeUsername(value);
        case 'saved_password':
          await _secure.writePassword(value);
        case 'saved_credentials':
          final Object? decoded = jsonDecode(value);
          if (decoded is! List ||
              decoded.any((item) => item is! Map<String, dynamic>)) {
            throw const SettingsBackupException(
              SettingsBackupErrorCode.invalidFieldFormat,
            );
          }
          // Restore is replacement, not an account-list edit: do not merge
          // opaque entries from the profile being replaced into the backup.
          await _secure.writeCredentialsRecord(value);
      }
      await _checkWrite(prefs.remove(key));
      return;
    }
    await _checkWrite(switch (value) {
      String() => prefs.setString(key, value),
      bool() => prefs.setBool(key, value),
      int() => prefs.setInt(key, value),
      double() => prefs.setDouble(key, value),
      List<String>() => prefs.setStringList(key, value),
      _ => throw const SettingsBackupException(
        SettingsBackupErrorCode.unsupportedFieldType,
      ),
    });
  }

  @override
  Future<void> remove(String key) async {
    switch (key) {
      case 'user_token':
        await _secure.writeToken(null);
      case 'saved_username':
        await _secure.writeUsername(null);
      case 'saved_password':
        await _secure.writePassword(null);
      case 'saved_credentials':
        await _secure.writeCredentials([]);
    }
    final prefs = await SharedPreferences.getInstance();
    await _checkWrite(prefs.remove(key));
  }

  Future<void> _checkWrite(Future<bool> write) async {
    if (!await write) {
      throw const SettingsBackupException(SettingsBackupErrorCode.writeFailed);
    }
  }
}
