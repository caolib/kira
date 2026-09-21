import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/backup/backup_codec.dart';
import 'package:kira/utils/settings_backup.dart';

import 'backup_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryBackupPreferences preferences;
  late MemoryBackupJournal journal;
  late TestBackupRuntime runtime;
  late SettingsBackupService service;

  setUp(() {
    preferences = MemoryBackupPreferences({
      'banner_visible': true,
      'theme_color': 'old-color',
      'user_token': 'local-account',
      'user_username': 'local-user',
      'auto_login': true,
      'ai_active_provider': 'local-provider',
      'ai_providers': '[{"id":"local-provider","apiKey":"local-key"}]',
      'reading_history_a': '{"chapterUuid":"old"}',
      'reading_stats_v1': '{}',
      'comic_bookmarks_v1': '[]',
      'backup_webdav_config_v1': '{"server":"https://local.example/dav/"}',
      'backup_encryption_enabled': true,
      'download_save_directory': 'local-path',
      'download_queue_state_v1': 'local-queue',
      'cache_home': 'local-cache',
    });
    journal = MemoryBackupJournal();
    runtime = TestBackupRuntime();
    service = SettingsBackupService(
      preferences: preferences,
      journal: journal,
      runtime: runtime,
    );
  });

  tearDown(() async {
    preferences.failAllWrites = false;
    preferences.beforeWrite = null;
    journal.failClear = false;
    await service.recoverPendingRestore();
    runtime.resume();
  });

  test(
    'snapshot reads preferences exactly once; selection/codec reuse it',
    () async {
      final snapshot = await service.capture();
      final codec = BackupCodec();
      await codec.prepare(snapshot.select({BackupCategory.settings}));
      await codec.prepare(snapshot.select({BackupCategory.account}));
      expect(preferences.reads, 1);
      expect(runtime.flushes, 1);
      expect(
        snapshot.preferences.keys,
        isNot(contains('backup_webdav_config_v1')),
      );
      expect(
        snapshot.preferences.keys,
        isNot(contains('download_queue_state_v1')),
      );
      expect(snapshot.preferences.keys, isNot(contains('cache_home')));
    },
  );

  test(
    'desktop JSON-decoded string lists are captured as string lists',
    () async {
      // Windows/Linux keep every preference in one JSON file, so a stored list
      // is decoded as List<dynamic> and the capture path must still accept it.
      final decoded =
          jsonDecode(
                jsonEncode({
                  'comment_blockwords': ['a', '简繁'],
                }),
              )
              as Map<String, dynamic>;
      final list = decoded['comment_blockwords'] as Object;
      expect(list, isNot(isA<List<String>>()));
      preferences.values['comment_blockwords'] = list;

      final snapshot = await service.capture();
      final preference = snapshot.preferences['comment_blockwords'];
      expect(preference?.type, 'string_list');
      expect(preference?.value, ['a', '简繁']);

      // The exported document must round-trip through the codec as well.
      final prepared = await BackupCodec().prepare(
        snapshot.select({BackupCategory.settings}),
      );
      final encoded = await BackupCodec().encode(prepared);
      final restored = await BackupCodec().decode(encoded.bytes);
      expect(restored.preferences['comment_blockwords']?.value, ['a', '简繁']);
    },
  );

  test('a rejected value reports its key and type without its value', () async {
    final logged = <String>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => logged.add(message ?? '');
    addTearDown(() => debugPrint = original);
    // A value whose type the format supports, stored under a key that declares
    // another type: only the key identifies which setting is at fault.
    preferences.values['banner_visible'] = 7;

    await expectLater(
      service.capture(),
      throwsA(
        isA<SettingsBackupException>().having(
          (e) => e.code,
          'code',
          SettingsBackupErrorCode.unsupportedFieldType,
        ),
      ),
    );
    expect(logged.join(), contains('banner_visible'));
    expect(logged.join(), isNot(contains('7')));
  });

  test(
    'only selected categories are replaced; unselected account/AI/local data survive',
    () async {
      final before = Map.of(preferences.values);
      final doc = backupDocument({
        'banner_visible': false,
        'user_token': 'remote-account',
        'reading_history_a': '{"chapterUuid":"remote"}',
        'ai_providers': '[{"id":"remote-provider"}]',
      });
      await service.restore(doc, {BackupCategory.settings});
      final expected = Map.of(before)
        ..remove('theme_color')
        ..['banner_visible'] = false;
      expect(preferences.values, expected);
      expect(runtime.reloadedCategories, {BackupCategory.settings});
      expect(runtime.paused, isFalse);
      expect(journal.pending, isNull);
      expect(journal.saves, 1);
    },
  );

  test('selected empty category clears only that category', () async {
    final before = Map.of(preferences.values)..remove('reading_history_a');
    await service.restore(
      backupDocument({}, categories: {BackupCategory.readingHistory}),
      {BackupCategory.readingHistory},
    );
    expect(preferences.values, before);
  });

  test(
    'sensitive groups are replaced atomically, including provider references',
    () async {
      final before = Map.of(preferences.values);
      await service.restore(
        backupDocument({
          'user_token': 'remote-account',
          'user_username': 'remote-user',
          'ai_providers': '[{"id":"new","apiKey":"new-key"}]',
          'ai_active_provider': 'new',
        }),
        {BackupCategory.account, BackupCategory.aiConnection},
      );
      expect(preferences.values['user_token'], 'remote-account');
      expect(preferences.values.containsKey('auto_login'), isFalse);
      expect(preferences.values['ai_active_provider'], 'new');
      for (final entry in before.entries) {
        if (BackupSchema.categoryOf(entry.key)?.isSensitive != true) {
          expect(preferences.values[entry.key], entry.value);
        }
      }
    },
  );

  test(
    'write failure rolls back exact original values before resuming',
    () async {
      final before = Map.of(preferences.values);
      preferences.failAtWrite = 3;
      await expectLater(
        service.restore(backupDocument({'banner_visible': false}), {
          BackupCategory.settings,
        }),
        throwsA(
          isA<SettingsBackupException>().having(
            (e) => e.code,
            'code',
            SettingsBackupErrorCode.writeFailed,
          ),
        ),
      );
      expect(preferences.values, before);
      expect(journal.pending, isNull);
      expect(runtime.paused, isFalse);
    },
  );

  test(
    'runtime reload failure also rolls back instead of reporting success',
    () async {
      final before = Map.of(preferences.values);
      runtime.failReloads = 1;
      await expectLater(
        service.restore(backupDocument({'banner_visible': false}), {
          BackupCategory.settings,
        }),
        throwsA(isA<SettingsBackupException>()),
      );
      expect(runtime.reloads, 2);
      expect(preferences.values, before);
      expect(journal.pending, isNull);
    },
  );

  test('journal must be durable before the first preferences write', () async {
    preferences.beforeWrite = () async {
      expect(journal.pending, isNotNull);
      expect(runtime.paused, isTrue);
    };
    await service.restore(backupDocument({'banner_visible': false}), {
      BackupCategory.settings,
    });
  });

  test('journal failure never changes preferences', () async {
    final before = Map.of(preferences.values);
    journal.failSave = true;
    await expectLater(
      service.restore(backupDocument({'banner_visible': false}), {
        BackupCategory.settings,
      }),
      throwsStateError,
    );
    expect(preferences.values, before);
    expect(preferences.writes, 0);
    expect(runtime.paused, isFalse);
  });

  test(
    'interrupted replacement is recovered on next startup without initializing runtime',
    () async {
      final before = Map.of(preferences.values);
      final original = (await service.capture()).select({
        BackupCategory.settings,
      });
      await journal.save(original);
      preferences.values
        ..remove('banner_visible')
        ..['theme_color'] = 'half-written';
      final recovered = await service.recoverPendingRestore();
      expect(recovered, isTrue);
      expect(preferences.values, before);
      expect(runtime.reloads, 0);
      expect(runtime.paused, isFalse);
      expect(await service.recoverPendingRestore(), isFalse);
    },
  );

  test(
    'failed rollback keeps the journal and blocks new writes until recovery',
    () async {
      final before = Map.of(preferences.values);
      preferences.failAllWrites = true;
      await expectLater(
        service.restore(backupDocument({'banner_visible': false}), {
          BackupCategory.settings,
        }),
        throwsA(
          isA<SettingsBackupException>().having(
            (e) => e.code,
            'code',
            SettingsBackupErrorCode.recoveryRequired,
          ),
        ),
      );
      expect(journal.pending, isNotNull);
      expect(runtime.paused, isTrue);
      await expectLater(
        service.capture(),
        throwsA(isA<SettingsBackupException>()),
      );
      preferences.failAllWrites = false;
      expect(await service.recoverPendingRestore(), isTrue);
      expect(preferences.values, before);
      expect(journal.pending, isNull);
    },
  );

  test(
    'concurrent restore is rejected while the first write is in flight',
    () async {
      final blocked = Completer<void>();
      final started = Completer<void>();
      preferences.beforeWrite = () async {
        if (!started.isCompleted) started.complete();
        await blocked.future;
      };
      final first = service.restore(backupDocument({'banner_visible': false}), {
        BackupCategory.settings,
      });
      await started.future;
      await expectLater(
        service.restore(backupDocument({'banner_visible': true}), {
          BackupCategory.settings,
        }),
        throwsA(
          isA<SettingsBackupException>().having(
            (e) => e.code,
            'code',
            SettingsBackupErrorCode.busy,
          ),
        ),
      );
      blocked.complete();
      await first;
    },
  );
}
