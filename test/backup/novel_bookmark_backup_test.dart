import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kira/backup/backup_preferences.dart';
import 'package:kira/backup/backup_runtime.dart';
import 'package:kira/backup/backup_validation.dart';
import 'package:kira/models/novel_reading_progress.dart';
import 'package:kira/models/secure_credential_store.dart';
import 'package:kira/utils/bookmark_store.dart';
import 'package:kira/utils/novel_bookmark_store.dart';
import 'package:kira/utils/settings_backup.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backup_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final novelStore = NovelBookmarkStore();
  final comicStore = BookmarkStore();
  late SharedPreferences prefs;
  late SettingsBackupService service;

  setUp(() async {
    // 账号凭据走系统安全存储；测试里换成内存实现，避免真实平台通道。
    SecureCredentialStore.setInstance(InMemorySecureCredentialStore());
    await novelStore.flush();
    await comicStore.flush();
    novelStore.debugReset();
    comicStore.debugReset();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    service = SettingsBackupService(journal: MemoryBackupJournal());
  });

  tearDown(() async {
    SecureCredentialStore.resetInstance();
    await novelStore.flush();
    await comicStore.flush();
    novelStore.resumeAfterRestore();
    comicStore.resumeAfterRestore();
    novelStore.debugReset();
    comicStore.debugReset();
  });

  test('novel bookmarks register as portable bookmarks, not history/cache', () {
    expect(
      BackupSchema.categoryOf(NovelBookmarkStore.storageKey),
      BackupCategory.bookmarks,
    );
    expect(BackupSchema.typeOf(NovelBookmarkStore.storageKey), 'string');
    expect(BackupSchema.categoryOf('cache_novel_bookmarks_v1'), isNull);
  });

  test('validation preserves original indexes and negative alignment', () {
    final bookmark = _bookmark();
    expect(
      () => validateBackupRecords({
        NovelBookmarkStore.storageKey: BackupPreference.fromValue(
          jsonEncode([bookmark.toJson()]),
        ),
      }),
      returnsNormally,
    );
  });

  test(
    'validation rejects malformed, duplicate and oversized bookmark lists',
    () {
      final valid = _bookmark().toJson();
      for (final encoded in [
        '{}',
        '[null]',
        'not-json',
        jsonEncode([
          {...valid, 'volumeId': ''},
        ]),
        jsonEncode([
          {...valid, 'paragraphIndex': -1},
        ]),
        jsonEncode([
          {...valid, 'entryIndex': '8'},
        ]),
        jsonEncode([
          {...valid, 'paragraphAlignment': 'NaN'},
        ]),
        jsonEncode([
          {...valid, 'progress': 1.1},
        ]),
        jsonEncode([
          {...valid, 'updatedAt': 'invalid-date'},
        ]),
        jsonEncode([valid, valid]),
        jsonEncode([
          for (var i = 0; i <= NovelBookmarkStore.maxBookmarks; i++)
            {...valid, 'paragraphIndex': i},
        ]),
      ]) {
        expect(
          () => validateBackupRecords({
            NovelBookmarkStore.storageKey: BackupPreference.fromValue(encoded),
          }),
          throwsA(isA<SettingsBackupException>()),
        );
      }
    },
  );

  test('组置顶导出、解析、恢复后保留；旧备份缺少字段时取消置顶', () async {
    await novelStore.toggle(progress: _bookmark().position);
    await _seedComic();
    await novelStore.setGroupPinned('novel-a', true);
    await comicStore.setGroupPinned('comic-a', true);
    const categories = {BackupCategory.bookmarks};
    final document = BackupDocument.parse(
      await service.exportPlainText(
        options: const SettingsBackupOptions(categories: categories),
      ),
    );
    final keys = [
      BookmarkStore.groupsStorageKey,
      NovelBookmarkStore.groupsStorageKey,
    ];
    expect(
      document.preferences.keys,
      unorderedEquals([
        ...keys,
        'comic_bookmarks_v1',
        NovelBookmarkStore.storageKey,
      ]),
    );
    for (final key in keys) {
      expect(document.preferences[key]!.type, 'string');
      expect(jsonDecode(document.preferences[key]!.value.toString()), [
        containsPair('pinned', true),
      ]);
    }
    await novelStore.setGroupPinned('novel-a', false);
    await comicStore.setGroupPinned('comic-a', false);
    await service.restore(document, categories);
    expect(novelStore.groups.single.pinned, isTrue);
    expect(comicStore.groups.single.pinned, isTrue);
    final legacy = backupDocument({
      BookmarkStore.groupsStorageKey: jsonEncode([
        comicStore.groups.single.toJson()..remove('pinned'),
      ]),
      NovelBookmarkStore.groupsStorageKey: jsonEncode([
        novelStore.groups.single.toJson()..remove('pinned'),
      ]),
    });
    await service.restore(legacy, categories);
    expect(novelStore.groups.single.pinned, isFalse);
    expect(comicStore.groups.single.pinned, isFalse);
  });

  test('拒绝非布尔值的组置顶字段', () {
    for (final key in [
      BookmarkStore.groupsStorageKey,
      NovelBookmarkStore.groupsStorageKey,
    ]) {
      for (final invalid in [null, 'true', 1]) {
        expect(
          () => validateBackupRecords({
            key: BackupPreference.fromValue(
              jsonEncode([
                {'pathWord': 'a', 'pinned': invalid},
              ]),
            ),
          }),
          throwsA(isA<SettingsBackupException>()),
        );
      }
    }
  });

  test('snapshot includes both types when selecting bookmarks', () async {
    await novelStore.toggle(progress: _bookmark().position);
    await _seedComic();
    await prefs.setString('cache_novel_detail_a', 'not-portable');
    final snapshot = (await service.capture()).select({
      BackupCategory.bookmarks,
    });
    expect(
      snapshot.preferences.keys,
      containsAll([
        NovelBookmarkStore.storageKey,
        NovelBookmarkStore.groupsStorageKey,
        'comic_bookmarks_v1',
        'comic_bookmark_groups_v1',
      ]),
    );
    // 两种书签 + 两份分组元数据（书签删光后组头仍要保留）。
    expect(snapshot.preferences.keys, hasLength(4));
  });

  test(
    'restore replaces bookmark category and refreshes both live stores',
    () async {
      await novelStore.toggle(progress: _bookmark().position);
      await _seedComic();
      await prefs.setString('novel_reading_history_a', 'preserve-history');
      await prefs.setString('reader_novel_settings_v1', 'preserve-settings');
      final restored = _bookmark(volumeId: 'restored-volume');
      var notifications = 0;
      void listener() => notifications++;
      novelStore.addListener(listener);
      addTearDown(() => novelStore.removeListener(listener));
      await service.restore(
        backupDocument({
          NovelBookmarkStore.storageKey: jsonEncode([restored.toJson()]),
        }),
        {BackupCategory.bookmarks},
      );
      expect(novelStore.bookmarks.single.volumeId, 'restored-volume');
      expect(novelStore.bookmarks.single.entryIndex, 8);
      expect(novelStore.bookmarks.single.paragraphAlignment, -0.35);
      expect(comicStore.bookmarks, isEmpty);
      expect(notifications, greaterThan(0));
      expect(prefs.getString('novel_reading_history_a'), 'preserve-history');
      expect(prefs.getString('reader_novel_settings_v1'), 'preserve-settings');
      await novelStore.toggle(progress: _bookmark().position);
      expect(novelStore.bookmarks, hasLength(2));
    },
  );

  test(
    'restoring empty bookmark category clears both without restart',
    () async {
      await novelStore.toggle(progress: _bookmark().position);
      await _seedComic();
      await service.restore(
        backupDocument({}, categories: {BackupCategory.bookmarks}),
        {BackupCategory.bookmarks},
      );
      expect(novelStore.bookmarks, isEmpty);
      expect(comicStore.bookmarks, isEmpty);
      expect(prefs.containsKey(NovelBookmarkStore.storageKey), isFalse);
      expect(prefs.containsKey('comic_bookmarks_v1'), isFalse);
    },
  );

  test('备份恢复暂停时拦截两类置顶，恢复后可重试', () async {
    final runtime = SettingsBackupRuntime();
    await novelStore.addGroup(pathWord: 'book', name: '小说');
    await comicStore.addGroup(pathWord: 'book', comicName: '漫画');
    await runtime.pause();
    try {
      await novelStore.setGroupPinned('book', true);
      await comicStore.setGroupPinned('book', true);
      await novelStore.reload();
      await comicStore.reload();
      expect(novelStore.groups.single.pinned, isFalse);
      expect(comicStore.groups.single.pinned, isFalse);
    } finally {
      runtime.resume();
    }
    await novelStore.setGroupPinned('book', true);
    await comicStore.setGroupPinned('book', true);
    expect(novelStore.groups.single.pinned, isTrue);
    expect(comicStore.groups.single.pinned, isTrue);
  });

  test('runtime restore pause also blocks novel bookmark writes', () async {
    final runtime = SettingsBackupRuntime();
    await novelStore.ensureLoaded();
    await runtime.pause();
    try {
      await novelStore.toggle(progress: _bookmark().position);
      expect(prefs.containsKey(NovelBookmarkStore.storageKey), isFalse);
    } finally {
      runtime.resume();
    }
    await novelStore.toggle(progress: _bookmark().position);
    await runtime.flush();
    expect(prefs.containsKey(NovelBookmarkStore.storageKey), isTrue);
  });

  test(
    'failed restore rolls prefs and live novel bookmarks back together',
    () async {
      await novelStore.toggle(progress: _bookmark().position);
      await _seedComic();
      await novelStore.setGroupPinned('novel-a', true);
      await comicStore.setGroupPinned('comic-a', true);
      final oldJson = prefs.getString(NovelBookmarkStore.storageKey);
      service = SettingsBackupService(
        preferences: _FailOncePreferences(),
        journal: MemoryBackupJournal(),
      );
      await expectLater(
        service.restore(
          backupDocument({
            NovelBookmarkStore.storageKey: jsonEncode([
              _bookmark(volumeId: 'new-volume').toJson(),
            ]),
          }),
          {BackupCategory.bookmarks},
        ),
        throwsA(isA<SettingsBackupException>()),
      );
      expect(prefs.getString(NovelBookmarkStore.storageKey), oldJson);
      expect(novelStore.bookmarks.single.volumeId, 'volume-1');
      expect(comicStore.bookmarks, hasLength(1));
      expect(novelStore.groups.single.pinned, isTrue);
      expect(comicStore.groups.single.pinned, isTrue);
    },
  );
}

NovelBookmark _bookmark({String volumeId = 'volume-1'}) => NovelBookmark(
  position: NovelReadingProgress(
    pathWord: 'novel-a',
    name: '小说 A',
    cover: '',
    volumeId: volumeId,
    volumeName: '第一卷',
    chapterName: '第二章',
    entryIndex: 8,
    paragraphIndex: 12,
    paragraphAlignment: -0.35,
    progress: 0.42,
    updatedAt: DateTime.utc(2026, 9, 25),
  ),
);

Future<void> _seedComic() async {
  await BookmarkStore().toggle(
    pathWord: 'comic-a',
    comicName: '漫画 A',
    chapterUuid: 'chapter-1',
    chapterName: '第一话',
    page: 7,
  );
}

class _FailOncePreferences extends SharedBackupPreferences {
  bool _failed = false;

  @override
  Future<void> write(String key, Object value) async {
    if (!_failed) {
      _failed = true;
      throw StateError('injected write failure');
    }
    await super.write(key, value);
  }
}
