import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/secure_credential_store.dart';
import 'package:kira/models/user_manager.dart';

void main() {
  late InMemorySecureCredentialStore store;

  setUp(() {
    store = InMemorySecureCredentialStore();
    SecureCredentialStore.setInstance(store);
  });

  tearDown(() {
    SecureCredentialStore.resetInstance();
  });

  // ── Username round-trip ──────────────────────────────────────────────

  group('writeUsername / readUsername', () {
    test('round-trip for non-empty value', () async {
      await store.writeUsername('alice');
      expect(await store.readUsername(), 'alice');
    });

    test('null value deletes the key', () async {
      await store.writeUsername('alice');
      await store.writeUsername(null);
      expect(await store.readUsername(), isNull);
    });

    test('empty string deletes the key', () async {
      await store.writeUsername('alice');
      await store.writeUsername('');
      expect(await store.readUsername(), isNull);
    });
  });

  // ── Password round-trip ──────────────────────────────────────────────

  group('writePassword / readPassword', () {
    test('round-trip for non-empty value', () async {
      await store.writePassword('secret123');
      expect(await store.readPassword(), 'secret123');
    });

    test('null value deletes the key', () async {
      await store.writePassword('secret123');
      await store.writePassword(null);
      expect(await store.readPassword(), isNull);
    });

    test('empty string deletes the key', () async {
      await store.writePassword('secret123');
      await store.writePassword('');
      expect(await store.readPassword(), isNull);
    });
  });

  // ── Credentials round-trip ───────────────────────────────────────────

  group('writeCredentials / readCredentials', () {
    test('round-trip with 2 SavedCredential items', () async {
      final creds = [
        const SavedCredential(username: 'user1', password: 'pass1'),
        const SavedCredential(
          username: 'user2',
          password: 'pass2',
          token: 'tok',
          loginSource: 'hotmanga',
        ),
      ];
      await store.writeCredentials(creds);
      final result = await store.readCredentials();
      expect(result.length, 2);
      expect(result[0].username, 'user1');
      expect(result[0].password, 'pass1');
      expect(result[1].username, 'user2');
      expect(result[1].password, 'pass2');
      expect(result[1].token, 'tok');
      expect(result[1].loginSource, 'hotmanga');
    });

    test('returns empty list when nothing stored', () async {
      expect(await store.readCredentials(), <SavedCredential>[]);
    });

    test('empty list deletes the key', () async {
      await store.writeCredentials([
        const SavedCredential(username: 'u', password: 'p'),
      ]);
      await store.writeCredentials([]);
      expect(await store.readCredentials(), <SavedCredential>[]);
    });

    test('handles corrupted JSON gracefully', () async {
      // Write raw corrupted data directly
      await store.doWrite('saved_credentials', '{{invalid json');
      expect(await store.readCredentials(), <SavedCredential>[]);
    });

    test('filters out entries with empty username', () async {
      final creds = [
        const SavedCredential(username: '', password: 'p'),
        const SavedCredential(username: 'valid', password: 'p'),
      ];
      await store.writeCredentials(creds);
      final result = await store.readCredentials();
      expect(result.length, 1);
      expect(result.first.username, 'valid');
    });
  });

  // ── deleteAll ────────────────────────────────────────────────────────

  group('deleteAll', () {
    test('clears all stored keys', () async {
      await store.writeUsername('alice');
      await store.writePassword('secret');
      await store.writeCredentials([
        const SavedCredential(username: 'u', password: 'p'),
      ]);

      await store.deleteAll();

      expect(await store.readUsername(), isNull);
      expect(await store.readPassword(), isNull);
      expect(await store.readCredentials(), <SavedCredential>[]);
    });
  });

  // ── Migration ─────────────────────────────────────────────────────────

  group('migrateFromSharedPreferences', () {
    test('moves old values and calls removePref for each key', () async {
      final removedKeys = <String>[];
      final prefsMap = <String, Object?>{
        'saved_username': 'old_user',
        'saved_password': 'old_pass',
        'saved_credentials': jsonEncode([
          {'username': 'cred_user', 'password': 'cred_pass'},
        ]),
      };

      await store.migrateFromSharedPreferences(
        prefsMap,
        (key) async => removedKeys.add(key),
      );

      expect(await store.readUsername(), 'old_user');
      expect(await store.readPassword(), 'old_pass');
      expect(removedKeys, [
        'saved_username',
        'saved_password',
        'saved_credentials',
      ]);

      // Migrated flag should be set
      expect(await store.doRead('credentials_migrated_to_secure'), 'true');
    });

    test('is idempotent — second call does nothing', () async {
      final removedKeys = <String>[];
      final prefsMap = <String, Object?>{
        'saved_username': 'old_user',
        'saved_password': 'old_pass',
      };

      await store.migrateFromSharedPreferences(
        prefsMap,
        (key) async => removedKeys.add(key),
      );
      final firstRemoveCount = removedKeys.length;

      // Second call — should skip because migrated flag is set
      await store.migrateFromSharedPreferences(
        prefsMap,
        (key) async => removedKeys.add(key),
      );

      expect(removedKeys.length, firstRemoveCount);
    });

    test('skips empty values in prefs map', () async {
      final removedKeys = <String>[];
      final prefsMap = <String, Object?>{
        'saved_username': '',
        'saved_password': '',
      };

      await store.migrateFromSharedPreferences(
        prefsMap,
        (key) async => removedKeys.add(key),
      );

      // Empty strings should not be written to secure storage
      expect(await store.readUsername(), isNull);
      expect(await store.readPassword(), isNull);
      // But removePref should still be called for cleanup
      expect(removedKeys, [
        'saved_username',
        'saved_password',
        'saved_credentials',
      ]);
    });
  });
}
