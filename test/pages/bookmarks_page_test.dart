import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kira/pages/bookmarks_page.dart';
import 'package:kira/routing/app_router.dart';
import 'package:kira/utils/bookmark_store.dart';
import 'package:kira/utils/reading_history.dart';
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
    final row = tester.widget<Dismissible>(
      find.byKey(const ValueKey('bookmark_chapter-1:7')),
    );
    expect(row.direction, DismissDirection.endToStart);
    expect(find.byType(Dismissible), findsOneWidget);
    expect(
      find.byKey(const ValueKey('bookmark_continue_comic-a')),
      findsNothing,
    );
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

  testWidgets('窄屏续读按钮在组头最右侧，长章节名不挤掉页码，点击恢复历史页', (tester) async {
    setBookmarkTestWidth(tester, 320);
    await ReadingHistory.save(
      pathWord: 'comic-a',
      chapterUuid: 'history-chapter',
      chapterName: '这是比窄屏按钮宽得多的历史章节标题，与已保存的书签不同',
      page: 36,
      totalPage: 80,
    );
    await ReadingHistory.flush();
    final router = _createRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(_buildTestApp(router));
    await tester.pumpAndSettle();

    final resume = find.byKey(const ValueKey('bookmark_continue_comic-a'));
    expectBookmarkResume(
      tester,
      header: _header('comic-a'),
      resume: resume,
      title: '漫画 A',
      progress: '36/80',
    );
    await tester.tap(resume);
    await tester.pumpAndSettle();
    expect(find.text('reader:comic-a:history-chapter:36'), findsOneWidget);
  });

  testWidgets('双列漫画左滑只展开操作，收起不进详情；置顶交换列，取消恢复原位', (tester) async {
    setBookmarkTestWidth(tester, 800);
    final store = BookmarkStore();
    // 显式错开书签时间，不依赖两次 toggle 的系统时钟粒度或同时间的排序规则。
    final newerTime = store.bookmarks.single.updatedAt!.add(
      const Duration(days: 1),
    );
    await store.restoreAll(
      [
        ComicBookmark(
          pathWord: 'comic-b',
          comicName: '新漫画',
          chapterUuid: 'new',
          chapterName: '新章',
          page: 1,
          updatedAt: newerTime,
        ),
      ],
      groups: [
        ComicBookmarkGroup(
          pathWord: 'comic-b',
          comicName: '新漫画',
          updatedAt: newerTime,
        ),
      ],
    );
    final router = _createRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(_buildTestApp(router));
    await tester.pumpAndSettle();

    final older = _header('comic-a');
    final newer = _header('comic-b');
    final oldSlot = tester.getTopLeft(older);
    final newSlot = tester.getTopLeft(newer);
    expect(oldSlot.dy, newSlot.dy);
    expect(oldSlot.dx, greaterThan(newSlot.dx));

    await revealBookmarkActions(tester, older);
    // 点仍露在左边的组头，而非右侧的操作按钮。
    await tester.tapAt(tester.getRect(older).centerLeft + const Offset(12, 0));
    await tester.pumpAndSettle();
    expect(find.text('置顶').hitTestable(), findsNothing);
    expect(find.text('删除').hitTestable(), findsNothing);
    expect(find.text('detail:comic-a'), findsNothing);
    expect(store.bookmarks, hasLength(2));
    expect(tester.getTopLeft(older), oldSlot);

    await revealBookmarkActions(tester, _header('comic-a'));
    await tester.tap(find.text('置顶').hitTestable());
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(older), newSlot);
    expect(tester.getTopLeft(newer), oldSlot);
    await revealBookmarkActions(tester, _header('comic-a'), pinned: true);
    await tester.tap(find.text('取消置顶').hitTestable());
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(older), oldSlot);
    expect(tester.getTopLeft(newer), newSlot);
    expect(store.bookmarks, hasLength(2));
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
    await revealBookmarkActions(tester, _header('comic-a'));
    expect(store.bookmarks.map((b) => b.toJson()).toList(), bookmarks);
    expect(store.groups.single.toJson(), group);
    expect(find.text('撤销'), findsNothing);
    await tester.tap(find.text('删除').hitTestable());
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
    testWidgets('删光书签后可展开操作删除空组、撤销与持久化：${width}dp', (tester) async {
      setBookmarkTestWidth(tester, width);
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

      await revealBookmarkActions(tester, _header('comic-a'));
      expect(store.groups.single.toJson(), group.toJson());
      await tester.tap(find.text('删除').hitTestable());
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

    // 搜索时展开删除操作也按整组处理，包含未命中的第 2 话。
    await tester.enterText(find.byType(TextField), '第 1 话');
    await tester.pumpAndSettle();
    await revealBookmarkActions(tester, _header('comic-a'));
    expect(_bookmarkFinder('chapter-2:3'), findsOneWidget);
    await tester.tap(find.text('删除').hitTestable());
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

void setBookmarkTestWidth(WidgetTester tester, double width) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Finder _header(String pathWord) =>
    find.byKey(ValueKey('bookmark_group_$pathWord'));

Future<void> revealBookmarkActions(
  WidgetTester tester,
  Finder header, {
  bool pinned = false,
}) async {
  await tester.drag(header, const Offset(-550, 0));
  await tester.pumpAndSettle();
  for (final label in [pinned ? '取消置顶' : '置顶', '删除']) {
    expect(
      find.descendant(of: header, matching: find.text(label)).hitTestable(),
      findsOneWidget,
    );
  }
  // 除这两个操作外，展开时没有可点击的按钮（包括底下的详情与续读）。
  final buttons = find.byWidgetPredicate(
    (w) => w is InkResponse && w.onTap != null,
  );
  expect(
    find.descendant(of: header, matching: buttons).hitTestable(),
    findsNWidgets(2),
  );
}

void expectBookmarkResume(
  WidgetTester tester, {
  required Finder header,
  required Finder resume,
  required String title,
  required String progress,
}) {
  final button = find.descendant(
    of: resume,
    matching: find.byType(OutlinedButton),
    matchRoot: true,
  );
  expect(button.hitTestable(), findsOneWidget);
  final bounds = tester.getRect(button);
  expect(bounds.left, greaterThan(tester.getRect(find.text(title)).right));
  expect(tester.getRect(header).right - bounds.right, inInclusiveRange(0, 24));
  final material = tester.widget<Material>(
    find.descendant(of: button, matching: find.byType(Material)),
  );
  expect(material.color?.a ?? 0, 0, reason: '续读按钮不填充底色');
  final side = (material.shape! as OutlinedBorder).side;
  expect(side.style, BorderStyle.solid);
  expect(side.width, lessThanOrEqualTo(1));
  expect(side.color.a, greaterThan(0));
  expect(
    find.descendant(of: button, matching: find.byIcon(Icons.play_arrow)),
    findsNothing,
  );

  final digits = find.descendant(
    of: button,
    matching: find.textContaining(progress),
  );
  expect(
    tester.renderObject<RenderParagraph>(digits).didExceedMaxLines,
    isFalse,
    reason: '应先截断章节名，保留数字',
  );
  expect(bounds.contains(tester.getRect(digits).centerRight), isTrue);
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
