import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kira/pages/bookmarks_page.dart';
import 'package:kira/routing/app_router.dart';
import 'package:kira/utils/bookmark_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    setupSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({});
    BookmarkStore().debugReset();
    await BookmarkStore().toggle(
      pathWord: 'comic-a',
      comicName: '漫画 A',
      group: 'default',
      chapterUuid: 'chapter-1',
      chapterName: '第 1 话',
      page: 7,
    );
  });

  tearDown(() {
    BookmarkStore().debugReset();
    teardownSecureCredentialStoreForTest();
  });

  testWidgets('single bookmark still renders as a list and card opens detail', (
    tester,
  ) async {
    final router = _createRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(_buildTestApp(router));
    await tester.pumpAndSettle();

    expect(find.text('1 条书签'), findsOneWidget);
    expect(find.text('第 1 话'), findsOneWidget);
    expect(find.byType(Dismissible), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('bookmark_comic_comic-a')),
        matching: find.byType(IconButton),
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('bookmark_comic_comic-a')));
    await tester.pumpAndSettle();

    expect(find.text('detail:comic-a'), findsOneWidget);
  });

  testWidgets('bookmark list item opens its saved reader position', (
    tester,
  ) async {
    final router = _createRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(_buildTestApp(router));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('bookmark_open_chapter-1:7')));
    await tester.pumpAndSettle();

    expect(find.text('reader:comic-a:chapter-1:7'), findsOneWidget);
  });

  testWidgets('整组删除移除漫画组头，撤销完整恢复并持久化', (tester) async {
    final router = _createRouter();
    addTearDown(router.dispose);

    await BookmarkStore().toggle(
      pathWord: 'comic-a',
      comicName: '漫画 A',
      group: 'default',
      chapterUuid: 'chapter-2',
      chapterName: '第 2 话',
      page: 3,
    );
    await tester.pumpWidget(_buildTestApp(router));
    await tester.pumpAndSettle();

    final store = BookmarkStore();
    final bookmarks = store.bookmarks.map((b) => b.toJson()).toList();
    final group = store.groups.single.toJson();
    expect(store.bookmarks, hasLength(2));
    await tester.drag(
      find.byKey(const ValueKey('bookmark_group_comic-a')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();

    expect(store.bookmarks, isEmpty);
    expect(store.groups, isEmpty);
    expect(_groupFinder('comic-a'), findsNothing);
    expect(find.text('还没有书签'), findsOneWidget);
    await store.reload();
    await tester.pumpAndSettle();
    expect(store.bookmarks, isEmpty);
    expect(store.groups, isEmpty);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(store.bookmarks.map((b) => b.toJson()).toList(), bookmarks);
    expect(store.groups.single.toJson(), group);
    expect(_groupFinder('comic-a'), findsOneWidget);
    expect(find.text('2 条书签'), findsOneWidget);
    await store.reload();
    await tester.pumpAndSettle();
    expect(store.bookmarks.map((b) => b.toJson()).toList(), bookmarks);
    expect(store.groups.single.toJson(), group);
    expect(tester.takeException(), isNull);
  });

  for (final width in [360.0, 800.0]) {
    testWidgets('删光书签后空组头可左滑删除、撤销与持久化：${width}dp', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final router = _createRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_buildTestApp(router));
      await tester.pumpAndSettle();
      final store = BookmarkStore();
      await tester.drag(
        find.byKey(const ValueKey('bookmark_chapter-1:7')),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle();
      expect(store.bookmarks, isEmpty);
      final group = store.groups.single;
      expect(find.text('0 条书签'), findsOneWidget);

      await tester.drag(
        find.byKey(const ValueKey('bookmark_group_comic-a')),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle();
      expect(store.hasGroup('comic-a'), isFalse);
      expect(_groupFinder('comic-a'), findsNothing);
      expect(find.text('还没有书签'), findsOneWidget);
      await store.reload();
      await tester.pumpAndSettle();
      expect(store.groups, isEmpty);

      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(store.bookmarks, isEmpty);
      expect(store.groups.single.toJson(), group.toJson());
      expect(find.text('0 条书签'), findsOneWidget);
      await store.reload();
      await tester.pumpAndSettle();
      expect(store.hasGroup('comic-a'), isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('搜索按漫画名与章节名过滤，命中即整组展示，无结果与空态区分', (tester) async {
    // 同一漫画再存一条：用于验证命中一条时整组都显示。
    await BookmarkStore().toggle(
      pathWord: 'comic-a',
      comicName: '漫画 A',
      group: 'default',
      chapterUuid: 'chapter-2',
      chapterName: '第 2 话',
      page: 3,
    );
    await BookmarkStore().toggle(
      pathWord: 'comic-b',
      comicName: '漫画 B',
      group: 'default',
      chapterUuid: 'chapter-9',
      chapterName: '第 9 话',
      page: 1,
    );
    final router = _createRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(_buildTestApp(router));
    await tester.pumpAndSettle();
    expect(_groupFinder('comic-a'), findsOneWidget);
    expect(_groupFinder('comic-b'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '漫画 B');
    await tester.pumpAndSettle();
    expect(_groupFinder('comic-b'), findsOneWidget);
    expect(_groupFinder('comic-a'), findsNothing);

    // 只命中「第 1 话」，但同一漫画的「第 2 话」也一并显示。
    await tester.enterText(find.byType(TextField), '第 1 话');
    await tester.pumpAndSettle();
    expect(_groupFinder('comic-a'), findsOneWidget);
    expect(_groupFinder('comic-b'), findsNothing);
    expect(_bookmarkFinder('chapter-1:7'), findsOneWidget);
    expect(_bookmarkFinder('chapter-2:3'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '不存在的漫画');
    await tester.pumpAndSettle();
    expect(find.text('没有找到相关书签，试试其他关键词'), findsOneWidget);
    expect(find.text('还没有书签'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('bookmarks_search_clear')));
    await tester.pumpAndSettle();
    expect(_groupFinder('comic-a'), findsOneWidget);
    expect(_groupFinder('comic-b'), findsOneWidget);

    // 搜索时整组左滑照旧删除该漫画的全部书签（含未命中的第 2 话）。
    await tester.enterText(find.byType(TextField), '第 1 话');
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('bookmark_group_comic-a')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('已删除 2 条书签'), findsOneWidget);
    expect(BookmarkStore().bookmarks.single.pathWord, 'comic-b');
    expect(BookmarkStore().groups.single.pathWord, 'comic-b');
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(BookmarkStore().bookmarks, hasLength(3));
    expect(BookmarkStore().groups, hasLength(2));
    expect(_groupFinder('comic-a'), findsOneWidget);
    expect(_bookmarkFinder('chapter-2:3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// 搜索框自身也是文本，断言列表内容时按分组/条目 key 定位而非按文本。
Finder _groupFinder(String pathWord) =>
    find.byKey(ValueKey('bookmark_comic_$pathWord'));

Finder _bookmarkFinder(String bookmarkId) =>
    find.byKey(ValueKey('bookmark_open_$bookmarkId'));

/// 书签页的轻小说分页是 Riverpod 消费者，TabBarView 可能惰性挂载它，
/// 因此测试树必须自带 ProviderScope。
Widget _buildTestApp(GoRouter router) {
  return ProviderScope(
    child: wrapWithApp(
      Router.withConfig(config: router),
      wrapInScaffold: false,
    ),
  );
}

GoRouter _createRouter() {
  return GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const BookmarksPage()),
      GoRoute(
        path: '/comic/:pathWord',
        name: AppRoutes.comicDetail,
        builder: (_, state) =>
            Scaffold(body: Text('detail:${state.pathParameters['pathWord']}')),
      ),
      GoRoute(
        path: '/reader/:pathWord/:chapterUuid',
        name: AppRoutes.reader,
        builder: (_, state) {
          final extra = state.extra as ReaderExtra;
          return Scaffold(
            body: Text(
              'reader:${state.pathParameters['pathWord']}:'
              '${state.pathParameters['chapterUuid']}:${extra.initialPage}',
            ),
          );
        },
      ),
    ],
  );
}
