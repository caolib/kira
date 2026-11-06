import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/secure_credential_store.dart';
import 'package:kira/utils/settings_backup.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../account_storage_test_support.dart';
import 'backup_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AccountPreferencesPlatform platform;
  late MemoryBackupJournal journal;
  late TestBackupLogger logger;
  late SettingsBackupService service;

  SettingsBackupService createService() => SettingsBackupService(
    journal: journal,
    runtime: TestBackupRuntime(),
    logger: logger,
  );

  setUp(() {
    platform = AccountPreferencesPlatform()..install();
    SecureCredentialStore.resetInstance();
    journal = MemoryBackupJournal();
    logger = TestBackupLogger();
    service = createService();
  });

  tearDown(() async {
    platform.failKey = null;
    platform.failRemoveKey = null;
    await service.recoverPendingRestore();
    platform.dispose();
    SecureCredentialStore.resetInstance();
  });

  Future<SharedPreferences> recreateStores() async {
    SharedPreferences.resetStatic();
    SecureCredentialStore.resetInstance();
    service = createService();
    return SharedPreferences.getInstance();
  }

  Future<void> seed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('banner_visible', true);
    await prefs.setInt('theme_mode', 1);
    await prefs.setDouble('comment_font_scale', 1.25);
    await prefs.setStringList('comment_blockwords', ['keep', '简繁']);
    await prefs.setString('cache_home', 'untouched-cache');
    await SecureCredentialStore().writeToken('untouched-token');
    platform.operations.clear();
  }

  test(
    'identical settings do not commit, including after recreation',
    () async {
      await seed();
      final document = (await service.capture()).select({
        BackupCategory.settings,
      });
      final original = Map.of(platform.values);

      await service.restore(document, {BackupCategory.settings});

      expect(platform.operations, isEmpty);
      expect(platform.values, original);
      final prefs = await recreateStores();
      expect(prefs.getBool('banner_visible'), isTrue);
      expect(prefs.getInt('theme_mode'), 1);
      expect(prefs.getDouble('comment_font_scale'), 1.25);
      expect(prefs.getStringList('comment_blockwords'), ['keep', '简繁']);
      expect(await SecureCredentialStore().readToken(), 'untouched-token');
      await service.restore(document, {BackupCategory.settings});
      expect(platform.operations, isEmpty);
    },
  );

  test(
    'changed settings use only necessary commits and persist after recreation',
    () async {
      await seed();
      await service.restore(
        backupDocument({
          'banner_visible': false,
          'theme_mode': 2,
          'comment_blockwords': <String>['new'],
        }),
        {BackupCategory.settings},
      );

      expect(platform.operations, hasLength(4));
      expect(
        platform.operations
            .where((operation) => operation.method == 'remove')
            .map((operation) => operation.key),
        ['flutter.comment_font_scale'],
      );
      final prefs = await recreateStores();
      expect(prefs.getBool('banner_visible'), isFalse);
      expect(prefs.getInt('theme_mode'), 2);
      expect(prefs.getStringList('comment_blockwords'), ['new']);
      expect(prefs.containsKey('comment_font_scale'), isFalse);
      expect(prefs.getString('cache_home'), 'untouched-cache');
      expect(await SecureCredentialStore().readToken(), 'untouched-token');
      expect(journal.pending, isNull);
    },
  );

  for (final failure in ['set', 'remove']) {
    for (final throws in [false, true]) {
      test(
        '$failure failure (throws: $throws) restores durable original values',
        () async {
          await seed();
          final original = Map.of(platform.values);
          platform.throwOnFailure = throws;
          if (failure == 'set') {
            platform.failKey = 'theme_mode';
            platform.failValue = 2;
          } else {
            platform.failRemoveKey = 'comment_font_scale';
          }

          await expectLater(
            service.restore(
              backupDocument({'banner_visible': false, 'theme_mode': 2}),
              {BackupCategory.settings},
            ),
            throwsA(
              isA<SettingsBackupException>().having(
                (error) => error.code,
                'code',
                SettingsBackupErrorCode.writeFailed,
              ),
            ),
          );

          expect(platform.values, original);
          expect(journal.pending, isNull);
          final prefs = await recreateStores();
          expect(prefs.getBool('banner_visible'), isTrue);
          expect(prefs.getInt('theme_mode'), 1);
          expect(prefs.getDouble('comment_font_scale'), 1.25);
          expect(prefs.getStringList('comment_blockwords'), ['keep', '简繁']);
          expect(await SecureCredentialStore().readToken(), 'untouched-token');
        },
      );
    }
  }

  for (final hasCurrentRecord in [false, true]) {
    test(
      'unchanged account token still cleans aliases (current: $hasCurrentRecord)',
      () async {
        const token = 'imported-token';
        final prefs = await SharedPreferences.getInstance();
        if (hasCurrentRecord) {
          await SecureCredentialStore().writeToken(token);
        }
        await prefs.setString(
          'user_token',
          hasCurrentRecord ? 'stale-token' : token,
        );
        await SecureCredentialStore().writeCopyAccountRecord(
          'private-copy-record',
        );

        await service.restore(backupDocument({'user_token': token}), {
          BackupCategory.account,
        });

        expect(prefs.containsKey('user_token'), isFalse);
        await recreateStores();
        expect(await SecureCredentialStore().readToken(), token);
        expect(
          await SecureCredentialStore().readCopyAccountRecord(),
          'private-copy-record',
        );
      },
    );
  }
}
