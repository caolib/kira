import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/bookmark_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
