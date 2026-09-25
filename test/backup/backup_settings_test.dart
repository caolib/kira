import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kira/backup/backup_category.dart';
import 'package:kira/backup/backup_schedule.dart';
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

  test('the master switch survives a reload and is never backed up', () async {
    final prefs = MemoryBackupPreferences();
    final settings = BackupSettings(
      preferences: prefs,
      secrets: InMemorySecureCredentialStore(),
    );
    // 没配置过的用户默认关闭。
    expect((await settings.load()).webDavEnabled, isFalse);

    await settings.saveEnabled(true);
    expect((await settings.load()).webDavEnabled, isTrue);
    await settings.saveEnabled(false);
    expect((await settings.load()).webDavEnabled, isFalse);
    expect(BackupSchema.categoryOf(BackupSettings.enabledKey), isNull);
    expect(BackupSchema.categoryOf(BackupSettings.configKey), isNull);
  });

  test('a connection saved before the switch existed counts as on', () async {
    final prefs = MemoryBackupPreferences({
      BackupSettings.configKey: jsonEncode({
        'server': 'https://dav.example/dav/',
        'directory': '',
        'allowHttp': false,
      }),
    });
    final settings = BackupSettings(
      preferences: prefs,
      secrets: InMemorySecureCredentialStore(),
    );
    expect((await settings.load()).webDavEnabled, isTrue);

    // 清空后仍停在配置流程里，开关不会被推断成关闭。
    await settings.clearConnection();
    expect((await settings.load()).webDavEnabled, isTrue);

    // 用户显式关过之后，就不再回退到「已配置即开启」。
    await settings.saveEnabled(false);
    expect((await settings.load()).webDavEnabled, isFalse);
  });

  test(
    'saving a connection turns the switch on, clearing it drops the rest',
    () async {
      final prefs = MemoryBackupPreferences();
      final secrets = InMemorySecureCredentialStore();
      final settings = BackupSettings(preferences: prefs, secrets: secrets);
      const schedule = BackupSchedule(
        enabled: true,
        value: 6,
        unit: BackupIntervalUnit.hours,
      );
      await settings.saveConnection(
        WebDavConfig(serverUrl: 'https://dav.example/dav/', directory: 'kira/'),
        const WebDavCredentials(username: 'user', password: 'secret'),
      );
      await settings.saveSchedule(schedule);
      await settings.markAutoBackup(DateTime(2026, 9, 24, 10));
      expect((await settings.load()).webDavEnabled, isTrue);

      await settings.clearConnection();

      final cleared = await settings.load();
      expect(cleared.connection, isNull);
      expect(cleared.credentials.username, isEmpty);
      expect(cleared.credentials.password, isEmpty);
      expect(await secrets.readWebDavCredentials(), isNull);
      // 定时备份与上次运行时刻一起清掉，否则重配后会立刻补一次备份。
      expect(cleared.schedule.enabled, isFalse);
      expect(cleared.lastAutoBackupAt, isNull);
      // 总开关保留：它是清空后唯一还能回到配置入口的开关。
      expect(cleared.webDavEnabled, isTrue);
      // 清除只影响连接相关键。
      expect(prefs.values.containsKey(BackupSettings.enabledKey), isTrue);
    },
  );

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
