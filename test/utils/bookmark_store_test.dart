import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/bookmark_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BookmarkStore().debugReset();
  });

  ComicBookmark sample({String chapter = 'chapter-1', int page = 3}) =>
      ComicBookmark(
        pathWord: 'comic-a',
        comicName: '漫画A',
        chapterUuid: chapter,
        chapterName: '第1话',
        page: page,
        updatedAt: DateTime(2026, 7, 24, 12),
      );

  test('老数据：只有书签、没有分组元数据时仍视为已加入书签页', () async {
    // 分组元数据是后加的功能，旧版本只写了书签列表。
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'comic_bookmarks_v1',
      jsonEncode([sample().toJson()]),
    );
    BookmarkStore().debugReset();
    await BookmarkStore().ensureLoaded();

    expect(BookmarkStore().hasGroup('comic-a'), isTrue);
    expect(BookmarkStore().groups.single.comicName, '漫画A');
    expect(BookmarkStore().groups.single.pinned, isFalse);
  });

  test('旧分组置顶不改时间顺序，增删条目和重新加载均保留置顶', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      BookmarkStore.groupsStorageKey,
      jsonEncode([
        {'pathWord': 'comic-a', 'comicName': '漫画A', 'cover': 'cover'},
      ]),
    );
    final store = BookmarkStore();
    await store.ensureLoaded();
    final original = store.groups.single;
    expect(original.pinned, isFalse);
    await store.addGroup(pathWord: 'other', comicName: '其他');
    var notifications = 0;
    void listener() => notifications++;
    store.addListener(listener);
    addTearDown(() => store.removeListener(listener));
    await store.setGroupPinned('comic-a', true);
    await store.setGroupPinned('comic-a', true);
    await store.setGroupPinned('missing', true);
    expect(notifications, 1);
    expect(store.groups.map((g) => g.pathWord), ['other', 'comic-a']);
    expect(store.groups.last.toJson(), {...original.toJson(), 'pinned': true});
    await store.toggle(
      pathWord: 'comic-a',
      comicName: '漫画A',
      chapterUuid: '1',
      chapterName: '第一话',
      page: 1,
    );
    await store.remove(store.bookmarks.single.id);
    store.debugReset();
    await store.ensureLoaded();
    expect(store.groups.first.pinned, isTrue);
    expect(store.groups.first.cover, 'cover');
    await store.setGroupPinned('comic-a', false);
    await store.reload();
    expect(store.groups.first.pinned, isFalse);
  });

  test('置顶或删除组写失败不通知，不通过 prefs 缓存或重启暴露失败结果', () async {
    final platform = _FailingGroupPreferences();
    SharedPreferencesStorePlatform.instance = platform;
    final store = BookmarkStore();
    await store.toggle(
      pathWord: 'comic-a',
      comicName: '漫画A',
      chapterUuid: '1',
      chapterName: '第一话',
      page: 1,
    );
    final prefs = await SharedPreferences.getInstance();
    final items = prefs.getString('comic_bookmarks_v1');
    final groups = prefs.getString(BookmarkStore.groupsStorageKey);
    var notifications = 0;
    void listener() => notifications++;
    store.addListener(listener);
    addTearDown(() => store.removeListener(listener));
    platform.failNext = true;
    await expectLater(store.setGroupPinned('comic-a', true), throwsStateError);
    expect(store.groups.single.pinned, isFalse);
    expect(prefs.getString(BookmarkStore.groupsStorageKey), groups);
    platform.failNext = true;
    await expectLater(store.removeGroup('comic-a'), throwsStateError);
    expect(notifications, 0);
    expect(prefs.getString('comic_bookmarks_v1'), items);
    SharedPreferences.resetStatic();
    store.debugReset();
    await store.ensureLoaded();
    expect(store.bookmarks.single.pathWord, 'comic-a');
    expect(store.groups.single.pinned, isFalse);
    await store.setGroupPinned('comic-a', true);
    expect(store.groups.single.pinned, isTrue);
    expect(notifications, 1);
  });

  test('toggle adds then removes a bookmark', () async {
    final store = BookmarkStore();
    final added = await store.toggle(
      pathWord: 'comic-a',
      comicName: '漫画A',
      chapterUuid: 'chapter-1',
      chapterName: '第1话',
      page: 3,
    );

    expect(added, isTrue);
    expect(store.isBookmarked('chapter-1', 3), isTrue);
    expect(store.bookmarks, hasLength(1));

    final removed = await store.toggle(
      pathWord: 'comic-a',
      comicName: '漫画A',
      chapterUuid: 'chapter-1',
      chapterName: '第1话',
      page: 3,
    );

    expect(removed, isFalse);
    expect(store.isBookmarked('chapter-1', 3), isFalse);
    expect(store.bookmarks, isEmpty);
  });

  test('same page in different chapters are distinct bookmarks', () async {
    final store = BookmarkStore();
    await store.toggle(
      pathWord: 'comic-a',
      comicName: '漫画A',
      chapterUuid: 'chapter-1',
      chapterName: '第1话',
      page: 3,
    );
    await store.toggle(
      pathWord: 'comic-a',
      comicName: '漫画A',
      chapterUuid: 'chapter-2',
      chapterName: '第2话',
      page: 3,
    );

    expect(store.bookmarks, hasLength(2));
    expect(store.isBookmarked('chapter-1', 3), isTrue);
    expect(store.isBookmarked('chapter-2', 3), isTrue);
  });

  test('newest bookmark is first', () async {
    final store = BookmarkStore();
    await store.toggle(
      pathWord: 'comic-a',
      comicName: '漫画A',
      chapterUuid: 'chapter-1',
      chapterName: '第1话',
      page: 1,
    );
    await store.toggle(
      pathWord: 'comic-a',
      comicName: '漫画A',
      chapterUuid: 'chapter-2',
      chapterName: '第2话',
      page: 2,
    );

    expect(store.bookmarks.first.chapterUuid, 'chapter-2');
    expect(store.bookmarks.last.chapterUuid, 'chapter-1');
  });

  test('persists bookmarks across reload', () async {
    final store = BookmarkStore();
    await store.toggle(
      pathWord: 'comic-a',
      comicName: '漫画A',
      chapterUuid: 'chapter-1',
      chapterName: '第1话',
      page: 5,
    );

    store.debugReset();
    await store.ensureLoaded();

    expect(store.bookmarks, hasLength(1));
    final bookmark = store.bookmarks.single;
    expect(bookmark.pathWord, 'comic-a');
    expect(bookmark.comicName, '漫画A');
    expect(bookmark.chapterUuid, 'chapter-1');
    expect(bookmark.chapterName, '第1话');
    expect(bookmark.page, 5);
    expect(bookmark.updatedAt, isNotNull);
  });

  test('remove deletes by id only', () async {
    final store = BookmarkStore();
    await store.toggle(
      pathWord: 'comic-a',
      comicName: '漫画A',
      chapterUuid: 'chapter-1',
      chapterName: '第1话',
      page: 1,
    );
    await store.toggle(
      pathWord: 'comic-a',
      comicName: '漫画A',
      chapterUuid: 'chapter-2',
      chapterName: '第2话',
      page: 2,
    );

    await store.remove(sample(page: 1).id);

    expect(store.bookmarks, hasLength(1));
    expect(store.bookmarks.single.chapterUuid, 'chapter-2');

    await store.remove('not-exists');
    expect(store.bookmarks, hasLength(1));
  });

  test('clear empties the list and persists', () async {
    final store = BookmarkStore();
    await store.toggle(
      pathWord: 'comic-a',
      comicName: '漫画A',
      chapterUuid: 'chapter-1',
      chapterName: '第1话',
      page: 1,
    );
    final removed = await store.clear();

    expect(removed, hasLength(1));
    expect(store.bookmarks, isEmpty);

    store.debugReset();
    await store.ensureLoaded();
    expect(store.bookmarks, isEmpty);
  });

  test('removeForComic removes only that comic and returns removed', () async {
    final store = BookmarkStore();
    await store.toggle(
      pathWord: 'comic-a',
      comicName: '漫画A',
      chapterUuid: 'chapter-1',
      chapterName: '第1话',
      page: 1,
    );
    await store.toggle(
      pathWord: 'comic-a',
      comicName: '漫画A',
      chapterUuid: 'chapter-2',
      chapterName: '第2话',
      page: 2,
    );
    await store.toggle(
      pathWord: 'comic-b',
      comicName: '漫画B',
      chapterUuid: 'chapter-9',
      chapterName: '第9话',
      page: 4,
    );

    final removed = await store.removeForComic('comic-a');

    expect(removed, hasLength(2));
    expect(store.bookmarks, hasLength(1));
    expect(store.bookmarks.single.pathWord, 'comic-b');

    final removedAgain = await store.removeForComic('comic-a');
    expect(removedAgain, isEmpty);
  });

  test('空分组可删除并持久化，撤销恢复原始元数据但不覆盖新分组', () async {
    final store = BookmarkStore();
    await store.addGroup(pathWord: 'comic-a', comicName: '漫画A');
    await store.addGroup(pathWord: 'comic-b', comicName: '漫画B');
    await store.setGroupPinned('comic-a', true);
    final original = store.groups.firstWhere((g) => g.pathWord == 'comic-a');
    expect(original.pinned, isTrue);
    expect(await store.removeGroup('comic-a'), isEmpty);
    await store.reload();
    expect(store.hasGroup('comic-a'), isFalse);
    expect(store.hasGroup('comic-b'), isTrue);

    await store.restoreAll(const [], groups: [original, original]);
    await store.reload();
    expect(store.groups, hasLength(2));
    expect(
      store.groups.firstWhere((g) => g.pathWord == 'comic-a').toJson(),
      original.toJson(),
    );
    expect(store.bookmarks, isEmpty);
    await store.removeGroup('comic-a');
    await store.addGroup(pathWord: 'comic-a', comicName: '新名称');
    await store.restoreAll(const [], groups: [original]);
    expect(store.groups.first.comicName, '新名称');
    expect(store.groups.first.pinned, isFalse);
  });

  test('restoreAll re-adds removed bookmarks sorted newest first', () async {
    final store = BookmarkStore();
    final older = ComicBookmark(
      pathWord: 'comic-a',
      comicName: '漫画A',
      chapterUuid: 'chapter-1',
      chapterName: '第1话',
      page: 1,
      updatedAt: DateTime(2026, 7, 24, 10),
    );
    final newer = ComicBookmark(
      pathWord: 'comic-b',
      comicName: '漫画B',
      chapterUuid: 'chapter-2',
      chapterName: '第2话',
      page: 2,
      updatedAt: DateTime(2026, 7, 24, 12),
    );

    await store.restoreAll([older, newer]);

    expect(store.bookmarks, hasLength(2));
    expect(store.bookmarks.first.chapterUuid, 'chapter-2');
    expect(store.bookmarks.last.chapterUuid, 'chapter-1');

    // 重复恢复不产生重复条目
    await store.restoreAll([newer]);
    expect(store.bookmarks, hasLength(2));

    store.debugReset();
    await store.ensureLoaded();
    expect(store.bookmarks, hasLength(2));
  });

  test('reload picks up externally replaced preferences', () async {
    final store = BookmarkStore();
    await store.toggle(
      pathWord: 'comic-a',
      comicName: '漫画A',
      chapterUuid: 'chapter-1',
      chapterName: '第1话',
      page: 1,
    );
    expect(store.bookmarks, hasLength(1));

    // 模拟导入/重置：底层存储被外部覆写，内存仍是旧数据
    SharedPreferences.setMockInitialValues({});
    expect(store.bookmarks, hasLength(1));

    await store.reload();
    expect(store.bookmarks, isEmpty);
  });

  test('ignores corrupted persisted data', () async {
    SharedPreferences.setMockInitialValues({'comic_bookmarks_v1': 'not-json'});
    final store = BookmarkStore()..debugReset();

    await store.ensureLoaded();

    expect(store.bookmarks, isEmpty);
  });

  test('bookmark json round-trips', () {
    final bookmark = sample();
    final restored = ComicBookmark.fromJson(bookmark.toJson());

    expect(restored.id, bookmark.id);
    expect(restored.pathWord, bookmark.pathWord);
    expect(restored.comicName, bookmark.comicName);
    expect(restored.cover, bookmark.cover);
    expect(restored.chapterUuid, bookmark.chapterUuid);
    expect(restored.chapterName, bookmark.chapterName);
    expect(restored.page, bookmark.page);
    expect(restored.updatedAt, bookmark.updatedAt);
  });

  test('cover persists when provided and defaults to empty', () async {
    final store = BookmarkStore();
    await store.toggle(
      pathWord: 'comic-a',
      comicName: '漫画A',
      cover: 'https://example.com/cover.jpg',
      chapterUuid: 'chapter-1',
      chapterName: '第1话',
      page: 1,
    );
    await store.toggle(
      pathWord: 'comic-b',
      comicName: '漫画B',
      chapterUuid: 'chapter-2',
      chapterName: '第2话',
      page: 2,
    );

    store.debugReset();
    await store.ensureLoaded();

    expect(store.bookmarks, hasLength(2));
    final withCover = store.bookmarks.firstWhere(
      (b) => b.pathWord == 'comic-a',
    );
    final withoutCover = store.bookmarks.firstWhere(
      (b) => b.pathWord == 'comic-b',
    );
    expect(withCover.cover, 'https://example.com/cover.jpg');
    expect(withoutCover.cover, '');
    // 空封面不写入 JSON（旧数据兼容）
    expect(withoutCover.toJson().containsKey('cover'), isFalse);
  });
}

class _FailingGroupPreferences extends InMemorySharedPreferencesStore {
  _FailingGroupPreferences() : super.empty();
  bool failNext = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    final ok = await super.setValue(valueType, key, value);
    if (failNext && key == 'flutter.${BookmarkStore.groupsStorageKey}') {
      failNext = false;
      return false;
    }
    return ok;
  }
}
