import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kira/backup/backup_category.dart';
import 'package:kira/backup/backup_schedule.dart';
import 'package:kira/backup/backup_settings.dart';
import 'package:kira/backup/webdav_config.dart';
import 'package:kira/models/secure_credential_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../account_storage_test_support.dart';

import 'backup_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'default encryption keeps credentials outside portable settings',
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

  group('default prefs-backed persistence', () {
    late AccountPreferencesPlatform platform;

    setUp(() {
      platform = AccountPreferencesPlatform()..install();
      SecureCredentialStore.resetInstance();
    });
    tearDown(() {
      SecureCredentialStore.resetInstance();
      platform.dispose();
    });

    test(
      'WebDAV and remembered password survive repeated instance recreation',
      () async {
        final settings = BackupSettings();
        await settings.saveConnection(
          WebDavConfig(
            serverUrl: 'https://dav.example/dav/',
            directory: 'backups/',
          ),
          const WebDavCredentials(
            username: 'dav-user',
            password: ' dav-secret ',
          ),
        );
        await settings.saveEncryption(
          encrypted: true,
          remember: true,
          password: ' remembered-backup-secret ',
        );
        for (var start = 0; start < 2; start++) {
          SharedPreferences.resetStatic();
          SecureCredentialStore.resetInstance();
          final restarted = BackupSettings();
          final loaded = await restarted.load();
          expect(loaded.webDavEnabled, isTrue);
          expect(loaded.connection?.directory, 'backups/');
          expect(loaded.credentials.username, 'dav-user');
          expect(loaded.credentials.password, ' dav-secret ');
          expect(loaded.rememberedPassword, ' remembered-backup-secret ');
          expect(
            await restarted.activePassword(),
            ' remembered-backup-secret ',
          );
        }
      },
    );

    test(
      'retention limit is local, durable and rejects failed writes',
      () async {
        final settings = BackupSettings();
        expect((await settings.load()).retentionLimit, 0);
        expect(
          BackupSchema.categoryOf(BackupSettings.retentionLimitKey),
          isNull,
        );
        await settings.saveRetentionLimit(4);
        SharedPreferences.resetStatic();
        expect((await BackupSettings().load()).retentionLimit, 4);
        platform.failKey = BackupSettings.retentionLimitKey;
        platform.failValue = 1;
        await expectLater(
          settings.saveRetentionLimit(1),
          throwsA(isA<Exception>()),
        );
        // 定时备份也不能从插件的内存缓存读到未落盘的较小上限。
        expect((await settings.load()).retentionLimit, 4);
        SharedPreferences.resetStatic();
        expect((await BackupSettings().load()).retentionLimit, 4);
        await settings.saveRetentionLimit(0);
        SharedPreferences.resetStatic();
        expect((await BackupSettings().load()).retentionLimit, 0);
      },
    );

    test(
      'forgetting password removes both names and only keeps current session in memory',
      () async {
        final settings = BackupSettings();
        await settings.saveEncryption(
          encrypted: true,
          remember: true,
          password: 'previous-backup-password',
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('backup_password_v1', 'stale-password');
        await settings.saveEncryption(
          encrypted: true,
          remember: false,
          password: 'session-only-password',
        );
        expect(await settings.activePassword(), 'session-only-password');
        expect((await settings.load()).rememberedPassword, isNull);
        expect(
          jsonEncode(platform.values),
          isNot(contains('session-only-password')),
        );
        expect(prefs.containsKey('backup_password_v1'), isFalse);
        expect(
          prefs.containsKey(
            '${SecureCredentialStore.preferencePrefix}backup_password_v1',
          ),
          isFalse,
        );
        SharedPreferences.resetStatic();
        SecureCredentialStore.resetInstance();
        expect(await BackupSettings().activePassword(), isNull);
      },
    );

    test(
      'clearing WebDAV removes legacy alias without clearing login or backup password',
      () async {
        final settings = BackupSettings();
        final credentials = SecureCredentialStore();
        await credentials.writeToken('primary-token');
        await credentials.writeBackupPassword('backup-password');
        await settings.saveConnection(
          WebDavConfig(serverUrl: 'https://dav.example/'),
          const WebDavCredentials(
            username: 'dav-user',
            password: 'dav-password',
          ),
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'backup_webdav_credentials_v1',
          'stale-dav-record',
        );
        await settings.clearConnection();
        SharedPreferences.resetStatic();
        SecureCredentialStore.resetInstance();
        final restarted = await BackupSettings().load();
        expect(restarted.connection, isNull);
        expect(restarted.credentials.password, isEmpty);
        expect(await SecureCredentialStore().readWebDavCredentials(), isNull);
        expect(
          await SecureCredentialStore().readBackupPassword(),
          'backup-password',
        );
        expect(await SecureCredentialStore().readToken(), 'primary-token');
      },
    );
  });

  test(
    'resetting credential storage clears all new backup credentials',
    () async {
      final secrets = InMemorySecureCredentialStore();
      await secrets.writeWebDavCredentials('dav');
      await secrets.writeBackupPassword('backup');
      await secrets.writeBackupRollbackKey('rollback');
      await secrets.deleteAll();
      expect(await secrets.readWebDavCredentials(), isNull);
      expect(await secrets.readBackupPassword(), isNull);
      expect(await secrets.readBackupRollbackKey(), isNull);
    },
  );
}
