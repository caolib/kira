import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'user_manager.dart';

/// Manages secure storage of user credentials using platform keychain/keystore.
///
/// On first launch after migration, transparently moves any plaintext
/// credentials previously stored in SharedPreferences into secure storage
/// and deletes the old entries.
///
/// In test environments, call [setInstance] with an in-memory override
/// before running any code that accesses this store.
class SecureCredentialStore {
  static SecureCredentialStore _instance = SecureCredentialStore._();
  factory SecureCredentialStore() => _instance;

  /// Replace the singleton with a custom instance (e.g. for tests).
  static void setInstance(SecureCredentialStore store) => _instance = store;

  /// Reset to the default platform-backed instance.
  static void resetInstance() => _instance = SecureCredentialStore._();

  SecureCredentialStore._();

  // ── Keys ───────────────────────────────────────────────────────────

  static const _keyUsername = 'saved_username';
  static const _keyPassword = 'saved_password';
  static const _keyCredentials = 'saved_credentials';
  static const _keyMigrated = 'credentials_migrated_to_secure';

  // ── Read ───────────────────────────────────────────────────────────

  @protected
  Future<String?> doRead(String key) =>
      const FlutterSecureStorage(aOptions: AndroidOptions()).read(key: key);

  @protected
  Future<void> doWrite(String key, String value) =>
      const FlutterSecureStorage(aOptions: AndroidOptions()).write(key: key, value: value);

  @protected
  Future<void> doDelete(String key) =>
      const FlutterSecureStorage(aOptions: AndroidOptions()).delete(key: key);

  Future<String?> readUsername() => doRead(_keyUsername);

  Future<String?> readPassword() => doRead(_keyPassword);

  Future<List<SavedCredential>> readCredentials() async {
    final raw = await doRead(_keyCredentials);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => SavedCredential.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.username.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Write ──────────────────────────────────────────────────────────

  Future<void> writeUsername(String? value) async {
    if (value == null || value.isEmpty) {
      await doDelete(_keyUsername);
    } else {
      await doWrite(_keyUsername, value);
    }
  }

  Future<void> writePassword(String? value) async {
    if (value == null || value.isEmpty) {
      await doDelete(_keyPassword);
    } else {
      await doWrite(_keyPassword, value);
    }
  }

  Future<void> writeCredentials(List<SavedCredential> credentials) async {
    if (credentials.isEmpty) {
      await doDelete(_keyCredentials);
    } else {
      await doWrite(
        _keyCredentials,
        jsonEncode(credentials.map((e) => e.toJson()).toList()),
      );
    }
  }

  // ── Delete ─────────────────────────────────────────────────────────

  Future<void> deleteAll() async {
    await doDelete(_keyUsername);
    await doDelete(_keyPassword);
    await doDelete(_keyCredentials);
  }

  // ── Migration ──────────────────────────────────────────────────────

  Future<void> migrateFromSharedPreferences(
    Map<String, Object?> prefsMap,
    Future<void> Function(String key) removePref,
  ) async {
    final alreadyMigrated = await doRead(_keyMigrated) == 'true';
    if (alreadyMigrated) return;

    final oldUsername = prefsMap[_keyUsername] as String?;
    final oldPassword = prefsMap[_keyPassword] as String?;
    final oldCredentialsRaw = prefsMap[_keyCredentials] as String?;

    if (oldUsername != null && oldUsername.isNotEmpty) {
      await doWrite(_keyUsername, oldUsername);
    }
    if (oldPassword != null && oldPassword.isNotEmpty) {
      await doWrite(_keyPassword, oldPassword);
    }
    if (oldCredentialsRaw != null && oldCredentialsRaw.isNotEmpty) {
      await doWrite(_keyCredentials, oldCredentialsRaw);
    }

    await removePref(_keyUsername);
    await removePref(_keyPassword);
    await removePref(_keyCredentials);

    await doWrite(_keyMigrated, 'true');
  }
}

/// In-memory implementation for unit tests where platform channels
/// are unavailable.
class InMemorySecureCredentialStore extends SecureCredentialStore {
  final _map = <String, String>{};

  InMemorySecureCredentialStore() : super._();

  @override
  Future<String?> doRead(String key) async => _map[key];

  @override
  Future<void> doWrite(String key, String value) async => _map[key] = value;

  @override
  Future<void> doDelete(String key) async => _map.remove(key);
}
