import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kira/backup/backup_category.dart';
import 'package:kira/backup/backup_settings.dart';
import 'package:kira/backup/webdav_config.dart';
import 'package:kira/models/secure_credential_store.dart';

import 'backup_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'default encryption, no remembered password and secure-only credentials',
    () async {
      final prefs = MemoryBackupPreferences();
      final secrets = InMemorySecureCredentialStore();
      final settings = BackupSettings(preferences: prefs, secrets: secrets);
      expect((await settings.load()).encrypted, isTrue);
      expect((await settings.load()).rememberedPassword, isNull);
      final config = WebDavConfig(
        serverUrl: 'https://dav.example/中文/',
        directory: '漫画/备份/',
      );
      await settings.saveConnection(
        config,
        const WebDavCredentials(username: '用户', password: ' dav-password '),
      );
      await settings.saveEncryption(
        encrypted: true,
        remember: true,
        password: '  backup-password  ',
      );
      final data = await settings.load();
      expect(data.credentials.password, ' dav-password ');
      expect(data.rememberedPassword, '  backup-password  ');
      expect(jsonEncode(prefs.values), isNot(contains('password')));
      expect(BackupSchema.categoryOf(BackupSettings.configKey), isNull);
      expect(BackupSchema.categoryOf(BackupSettings.encryptionKey), isNull);
      await settings.saveEncryption(
        encrypted: false,
        remember: false,
        password: '',
      );
      expect((await settings.load()).rememberedPassword, isNull);
    },
  );

  test(
    'credentials cannot be paired with a different server after a partial save',
    () async {
      final prefs = MemoryBackupPreferences();
      final secrets = InMemorySecureCredentialStore();
      final settings = BackupSettings(preferences: prefs, secrets: secrets);
      await settings.saveConnection(
        WebDavConfig(serverUrl: 'https://one.example'),
        const WebDavCredentials(username: 'one', password: 'one-secret'),
      );
      prefs.failAllWrites = true;
      await expectLater(
        settings.saveConnection(
          WebDavConfig(serverUrl: 'https://two.example'),
          const WebDavCredentials(username: 'two', password: 'two-secret'),
        ),
        throwsStateError,
      );
      final data = await settings.load();
      expect(data.connection?.server.host, 'one.example');
      expect(data.credentials.password, isEmpty);
    },
  );

  test('an empty directory survives a save and reload', () async {
    final prefs = MemoryBackupPreferences();
    final secrets = InMemorySecureCredentialStore();
    final settings = BackupSettings(preferences: prefs, secrets: secrets);
    await settings.saveConnection(
      WebDavConfig(serverUrl: 'https://dav.example/dav/'),
      const WebDavCredentials(username: 'user', password: 'secret'),
    );
    final data = await settings.load();
    expect(data.connection?.directory, '');
    expect(data.connection?.root.toString(), 'https://dav.example/dav/');
    expect(data.credentials.username, 'user');
  });

  test('resetting secure storage clears all new backup credentials', () async {
    final secrets = InMemorySecureCredentialStore();
    await secrets.writeWebDavCredentials('dav');
    await secrets.writeBackupPassword('backup');
    await secrets.writeBackupRollbackKey('rollback');
    await secrets.deleteAll();
    expect(await secrets.readWebDavCredentials(), isNull);
    expect(await secrets.readBackupPassword(), isNull);
    expect(await secrets.readBackupRollbackKey(), isNull);
  });
}
