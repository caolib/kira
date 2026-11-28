import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kira/models/novel_reading_progress.dart';
import 'package:kira/pages/bookmarks_page.dart';
import 'package:kira/providers/novel_providers.dart';
import 'package:kira/routing/app_router.dart';
import 'package:kira/utils/bookmark_store.dart';
import 'package:kira/utils/novel_bookmark_store.dart';
import 'package:kira/utils/novel_reading_store.dart';
import 'package:kira/widgets/novel_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';
import 'bookmarks_page_test.dart'
    show expectBookmarkResume, revealBookmarkActions, setBookmarkTestWidth;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NovelBookmarkStore novelStore;
  late SharedPreferences prefs;

  // 必须在 testWidgets 的 FakeAsync zone 内创建注入的 Future。
  // setUp 中创建的 Future 会把后续 await 排到真实 zone，pumpAndSettle
  // 并不等待它，导致删除后的断言偶发早于持久化完成。
  Future<void> seedBookmarks() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    novelStore = NovelBookmarkStore.forTesting(prefs: Future.value(prefs));
    BookmarkStore().debugReset();
    await BookmarkStore().toggle(
      pathWord: 'comic-a',
      comicName: '漫画 A',
      chapterUuid: 'chapter-1',
      chapterName: '第一话',
      page: 7,
    );
    await novelStore.toggle(progress: _position());
  }

  setUp(setupSecureCredentialStoreForTest);

  tearDown(() async {
    teardownSecureCredentialStoreForTest();
    await novelStore.flush();
    novelStore.dispose();
    await BookmarkStore().flush();
    BookmarkStore().debugReset();
  });

  testWidgets(
    'tabs preserve comics and show novel groups, chapters and percent',
    (tester) async {
      await seedBookmarks();
      await _pump(tester, novelStore);
      expect(find.text('漫画 A'), findsOneWidget);
      expect(find.text('第一话'), findsOneWidget);
      await _showNovels(tester);
      expect(find.text('小说 A'), findsOneWidget);
      // 卷名前缀去重：章节名「第一卷 第二章」显示为「第一卷 · 第二章」。
      expect(find.text('第一卷 · 第二章'), findsOneWidget);
      expect(find.text('第一卷 · 第一卷 第二章'), findsNothing);
      expect(find.textContaining('42.00%'), findsOneWidget);
      expect(find.text('1 条书签'), findsOneWidget);
      await tester.tap(find.text('漫画'));
      await tester.pumpAndSettle();
      expect(find.text('漫画 A'), findsOneWidget);
      expect(BookmarkStore().bookmarks, hasLength(1));
    },
  );

  testWidgets('组内书签和组头续读分别跳到各自保存的卷、章节和段落断点', (tester) async {
    await seedBookmarks();
    final history = NovelReadingStore(prefs: Future.value(prefs));
    final lastRead = _position().copyWith(
      volumeId: 'last-read-volume',
      volumeName: '这是续读断点保存的长卷名，不能把后面的百分比挤掉',
      progress: 0.6525,
      entryIndex: 99,
      paragraphIndex: 88,
      paragraphAlignment: -0.9,
    );
    await history.saveProgress(lastRead);
    final historyBefore = prefs.getString('${NovelReadingStore.prefix}novel-a');
    final saved = novelStore.bookmarks.single;
    final router = await _pump(tester, novelStore);
    await _showNovels(tester);
    await tester.tap(find.byKey(ValueKey('novel_bookmark_open_${saved.id}')));
    await tester.pumpAndSettle();
    expect(
      find.text('reader:novel-a:volume-1:8:12:-0.35:false'),
      findsOneWidget,
    );
    router.pop();
    await tester.pumpAndSettle();
    final resume = find.byKey(
      const ValueKey('novel_bookmark_continue_novel-a'),
    );
    expectBookmarkResume(
      tester,
      header: _header('novel-a'),
      resume: resume,
      title: '小说 A',
      progress: '65.25%',
    );
    await tester.tap(resume);
    await tester.pumpAndSettle();
    expect(
      find.text('reader:novel-a:last-read-volume:99:88:-0.9:false'),
      findsOneWidget,
    );
    expect(
      prefs.getString('${NovelReadingStore.prefix}novel-a'),
      historyBefore,
    );
  });

  testWidgets('novel group header opens details', (tester) async {
    await seedBookmarks();
    await _pump(tester, novelStore);
    await _showNovels(tester);
    expect(
      find.byKey(const ValueKey('novel_bookmark_continue_novel-a')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey('novel_bookmark_details_novel-a')),
    );
    await tester.pumpAndSettle();
    expect(find.text('novel-detail:novel-a'), findsOneWidget);
  });

  testWidgets('窄屏轻小说组可右滑收起；置顶排到首位，取消后回到时间顺序', (tester) async {
    setBookmarkTestWidth(tester, 360);
    await seedBookmarks();
    final older = _position().copyWith(
      pathWord: 'novel-b',
      name: '旧小说',
      updatedAt: DateTime.utc(2000),
    );
    await novelStore.restoreAll(
      [NovelBookmark(position: older)],
      groups: [
        NovelBookmarkGroup(
          pathWord: older.pathWord,
          name: older.name,
          updatedAt: older.updatedAt,
        ),
      ],
    );
    await _pump(tester, novelStore);
    await _showNovels(tester);

    final oldHeader = _header('novel-b');
    final newHeader = _header('novel-a');
    expect(tester.getTopLeft(oldHeader).dx, tester.getTopLeft(newHeader).dx);
    expect(
      tester.getTopLeft(oldHeader).dy,
      greaterThan(tester.getTopLeft(newHeader).dy),
    );
    await revealBookmarkActions(tester, oldHeader);
    await tester.dragFrom(
      tester.getRect(oldHeader).centerLeft + const Offset(12, 0),
      const Offset(220, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('删除').hitTestable(), findsNothing);
    expect(find.text('置顶').hitTestable(), findsNothing);
    expect(find.text('novel-detail:novel-b'), findsNothing);
    expect(novelStore.bookmarks, hasLength(2));
    expect(oldHeader.hitTestable(), findsOneWidget);

    await revealBookmarkActions(tester, oldHeader);
    await tester.tap(find.text('置顶').hitTestable());
    await _settleBookmarks(tester, novelStore);
    expect(
      tester.getTopLeft(oldHeader).dy,
      lessThan(tester.getTopLeft(newHeader).dy),
    );
    await revealBookmarkActions(tester, oldHeader, pinned: true);
    await tester.tap(find.text('取消置顶').hitTestable());
    await _settleBookmarks(tester, novelStore);
    expect(
      tester.getTopLeft(oldHeader).dy,
      greaterThan(tester.getTopLeft(newHeader).dy),
    );
    expect(novelStore.bookmarks, hasLength(2));
  });

  testWidgets('single deletion and undo preserve exact anchors and comics', (
    tester,
  ) async {
    await seedBookmarks();
    final saved = novelStore.bookmarks.single;
    await _pump(tester, novelStore);
    await _showNovels(tester);
    // 删除入口是条目左滑（与漫画书签一致），尾部只有导航箭头。
    final row = find.byKey(ValueKey('novel_bookmark_${saved.id}'));
    expect(
      tester.widget<Dismissible>(row).direction,
      DismissDirection.endToStart,
    );
    await tester.drag(row, const Offset(-550, 0));
    await _settleBookmarks(tester, novelStore);
    expect(novelStore.bookmarks, isEmpty);
    expect(BookmarkStore().bookmarks, hasLength(1));
    // 书签删光后组头保留：仍能看到这部轻小说，只是没有条目。
    expect(find.text('小说 A'), findsOneWidget);
    expect(find.text('0 条书签'), findsOneWidget);
    expect(find.textContaining('阅读轻小说时'), findsNothing);
    await tester.tap(find.text('撤销'));
    await _settleBookmarks(tester, novelStore);
    expect(novelStore.bookmarks.single.id, saved.id);
    expect(novelStore.bookmarks.single.paragraphAlignment, -0.35);
    expect(tester.takeException(), isNull);
  });

  for (final width in [360.0, 800.0]) {
    testWidgets('删光轻小说书签后可展开操作删除空组、撤销与持久化：${width}dp', (tester) async {
      setBookmarkTestWidth(tester, width);
      await seedBookmarks();
      final saved = novelStore.bookmarks.single;
      await _pump(tester, novelStore);
      await _showNovels(tester);
      await tester.drag(
        find.byKey(ValueKey('novel_bookmark_${saved.id}')),
        const Offset(-550, 0),
      );
      await _settleBookmarks(tester, novelStore);
      final group = novelStore.groups.single;
      expect(find.text('0 条书签'), findsOneWidget);

      await revealBookmarkActions(tester, _header('novel-a'));
      expect(novelStore.groups.single.toJson(), group.toJson());
      await tester.tap(find.text('删除').hitTestable());
      await _settleBookmarks(tester, novelStore);
      expect(novelStore.hasGroup('novel-a'), isFalse);
      expect(find.text('小说 A'), findsNothing);
      expect(find.text('还没有书签'), findsOneWidget);
      await novelStore.reload();
      await tester.pumpAndSettle();
      expect(novelStore.groups, isEmpty);
      expect(BookmarkStore().bookmarks, hasLength(1));

      await tester.tap(find.text('撤销'));
      await _settleBookmarks(tester, novelStore);
      expect(novelStore.bookmarks, isEmpty);
      expect(novelStore.groups.single.toJson(), group.toJson());
      expect(find.text('0 条书签'), findsOneWidget);
      await novelStore.reload();
      await tester.pumpAndSettle();
      expect(novelStore.hasGroup('novel-a'), isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('swiping one novel bookmark does not remove its sibling', (
    tester,
  ) async {
    await seedBookmarks();
    final saved = novelStore.bookmarks.single;
    await novelStore.toggle(progress: _position().copyWith(paragraphIndex: 44));
    await _pump(tester, novelStore);
    await _showNovels(tester);
    await tester.drag(
      find.byKey(ValueKey('novel_bookmark_${saved.id}')),
      const Offset(-550, 0),
    );
    await _settleBookmarks(tester, novelStore);
    expect(novelStore.bookmarks, hasLength(1));
    expect(novelStore.bookmarks.single.paragraphIndex, 44);
    await tester.tap(find.text('撤销'));
    await _settleBookmarks(tester, novelStore);
    expect(novelStore.bookmarks, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('整组删除仅移除目标小说组头，撤销完整恢复并持久化', (tester) async {
    await seedBookmarks();
    await novelStore.toggle(progress: _position().copyWith(paragraphIndex: 44));
    await novelStore.toggle(
      progress: _position().copyWith(pathWord: 'novel-b', name: '小说 B'),
    );
    final bookmarks = novelStore.bookmarks.map((b) => b.toJson()).toList();
    final groups = novelStore.groups.map((g) => g.toJson()).toList();
    await _pump(tester, novelStore);
    await _showNovels(tester);
    await revealBookmarkActions(tester, _header('novel-a'));
    expect(novelStore.bookmarks.map((b) => b.toJson()).toList(), bookmarks);
    expect(novelStore.groups.map((g) => g.toJson()).toList(), groups);
    expect(find.text('撤销'), findsNothing);
    await tester.tap(find.text('删除').hitTestable());
    await _settleBookmarks(tester, novelStore);
    expect(novelStore.bookmarks.single.pathWord, 'novel-b');
    expect(novelStore.groups.single.pathWord, 'novel-b');
    expect(find.text('小说 A'), findsNothing);
    expect(find.text('小说 B'), findsOneWidget);
    await novelStore.reload();
    await tester.pumpAndSettle();
    expect(novelStore.bookmarks.single.pathWord, 'novel-b');
    expect(novelStore.groups.single.pathWord, 'novel-b');

    await tester.tap(find.text('撤销'));
    await _settleBookmarks(tester, novelStore);
    expect(novelStore.bookmarks.map((b) => b.toJson()).toList(), bookmarks);
    expect(novelStore.groups.map((g) => g.toJson()).toList(), groups);
    expect(find.text('小说 A'), findsOneWidget);
    expect(find.text('小说 B'), findsOneWidget);
    await novelStore.reload();
    await tester.pumpAndSettle();
    expect(novelStore.bookmarks.map((b) => b.toJson()).toList(), bookmarks);
    expect(novelStore.groups.map((g) => g.toJson()).toList(), groups);
    expect(BookmarkStore().bookmarks, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('clear current type confirms novels only and supports undo', (
    tester,
  ) async {
    await seedBookmarks();
    await _pump(tester, novelStore);
    await _showNovels(tester);
    await tester.tap(
      find.byKey(const ValueKey('bookmarks_clear_current_type')),
    );
    await tester.pumpAndSettle();
    expect(find.text('确定清空所有轻小说书签？'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ),
    );
    await _settleBookmarks(tester, novelStore);
    expect(novelStore.bookmarks, isEmpty);
    expect(BookmarkStore().bookmarks, hasLength(1));
    await tester.tap(find.text('撤销'));
    await _settleBookmarks(tester, novelStore);
    expect(novelStore.bookmarks, hasLength(1));
  });

  testWidgets('clearing comics never touches novel bookmarks', (tester) async {
    await seedBookmarks();
    await _pump(tester, novelStore);
    await tester.tap(
      find.byKey(const ValueKey('bookmarks_clear_current_type')),
    );
    await tester.pumpAndSettle();
    expect(find.text('确定清空所有漫画书签？'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pumpAndSettle();
    expect(BookmarkStore().bookmarks, isEmpty);
    expect(novelStore.bookmarks, hasLength(1));
    await _showNovels(tester);
    expect(find.text('小说 A'), findsOneWidget);
    expect(find.text('撤销'), findsNothing);
  });

  testWidgets('small novel covers stay flat inside elevated bookmark groups', (
    tester,
  ) async {
    await seedBookmarks();
    await _pump(tester, novelStore);
    await _showNovels(tester);
    final coverMaterials = tester.widgetList<Material>(
      find.descendant(
        of: find.byType(NovelCover),
        matching: find.byType(Material),
      ),
    );
    expect(coverMaterials.where((material) => material.elevation > 0), isEmpty);
    final title = tester.widget<Text>(find.text('小说 A'));
    expect(title.style?.fontWeight, FontWeight.bold);
  });

  testWidgets(
    'swipe waits for persistence and failed deletion keeps the bookmark without undo',
    (tester) async {
      await seedBookmarks();
      final controlled = _ControlledPreferences(prefs);
      await novelStore.flush();
      novelStore.dispose();
      novelStore = NovelBookmarkStore.forTesting(
        prefs: Future.value(controlled),
      );
      await _pump(tester, novelStore);
      await _showNovels(tester);
      final saved = novelStore.bookmarks.single;
      final gate = Completer<void>();
      controlled.writeGate = gate;
      controlled.failWrite = true;
      await tester.drag(
        find.byKey(ValueKey('novel_bookmark_${saved.id}')),
        const Offset(-550, 0),
      );
      await tester.pumpAndSettle();
      expect(novelStore.bookmarks, hasLength(1));
      expect(
        find.byKey(ValueKey('novel_bookmark_open_${saved.id}')),
        findsOneWidget,
      );
      expect(find.text('撤销'), findsNothing);
      gate.complete();
      await _settleBookmarks(tester, novelStore);
      expect(novelStore.bookmarks, hasLength(1));
      expect(
        find.byKey(ValueKey('novel_bookmark_open_${saved.id}')),
        findsOneWidget,
      );
      expect(find.text('撤销'), findsNothing);
      expect(tester.takeException(), isNull);

      controlled.failWrite = false;
      await tester.drag(
        find.byKey(ValueKey('novel_bookmark_${saved.id}')),
        const Offset(-550, 0),
      );
      await _settleBookmarks(tester, novelStore);
      expect(novelStore.bookmarks, isEmpty);
      // 组头保留，只是条目没了；空态不应出现。
      expect(find.text('0 条书签'), findsOneWidget);
      expect(find.text('还没有书签'), findsNothing);
      expect(find.text('撤销'), findsOneWidget);
    },
  );

  testWidgets('returning from reader reflects bookmark changes', (
    tester,
  ) async {
    await seedBookmarks();
    final saved = novelStore.bookmarks.single;
    final router = await _pump(tester, novelStore);
    await _showNovels(tester);
    await tester.tap(find.byKey(ValueKey('novel_bookmark_open_${saved.id}')));
    await tester.pumpAndSettle();
    await novelStore.remove(saved.id);
    router.pop();
    await tester.pumpAndSettle();
    // 书签删光后组头保留：仍能看到这部轻小说，只是条目已移除。
    expect(find.text('小说 A'), findsOneWidget);
    expect(find.text('0 条书签'), findsOneWidget);
    expect(
      find.byKey(ValueKey('novel_bookmark_open_${saved.id}')),
      findsNothing,
    );
  });

  testWidgets('搜索词在切换 tab 后沿用，命中书名与章节名', (tester) async {
    await seedBookmarks();
    await _pump(tester, novelStore);
    expect(find.text('漫画 A'), findsOneWidget);

    // 漫画 tab 下无命中：轻小说名不匹配漫画书签。
    await tester.enterText(find.byType(TextField), '小说');
    await tester.pumpAndSettle();
    expect(find.text('没有找到相关书签，试试其他关键词'), findsOneWidget);
    expect(find.text('漫画 A'), findsNothing);

    // 关键词随 tab 切换保留。
    await _showNovels(tester);
    expect(find.text('小说 A'), findsOneWidget);
    expect(find.text('第一卷 · 第二章'), findsOneWidget);

    // 章节名（含卷名前缀的原始名）同样命中：只命中第三章时，
    // 同一轻小说的第二章也照常显示（整组展示）。
    await novelStore.toggle(
      progress: _position().copyWith(
        chapterName: '第一卷 第三章',
        entryIndex: 9,
        paragraphIndex: 0,
      ),
    );
    await tester.enterText(find.byType(TextField), '第三章');
    await tester.pumpAndSettle();
    expect(find.text('小说 A'), findsOneWidget);
    expect(find.text('第一卷 · 第二章'), findsOneWidget);
    expect(find.text('第一卷 · 第三章'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '不存在的书');
    await tester.pumpAndSettle();
    expect(find.text('没有找到相关书签，试试其他关键词'), findsOneWidget);
    expect(find.text('小说 A'), findsNothing);
    expect(find.textContaining('阅读轻小说时'), findsNothing);
  });

  testWidgets('搜索时左滑展开操作，点删除才移除该轻小说的全部书签', (tester) async {
    await seedBookmarks();
    await novelStore.toggle(
      progress: _position().copyWith(
        chapterName: '第一卷 第三章',
        entryIndex: 9,
        paragraphIndex: 0,
      ),
    );
    await _pump(tester, novelStore);
    await _showNovels(tester);

    // 只命中第三章，点组头的删除按钮仍会删掉两条。
    await tester.enterText(find.byType(TextField), '第三章');
    await tester.pumpAndSettle();
    await revealBookmarkActions(tester, _header('novel-a'));
    expect(novelStore.bookmarks, hasLength(2));
    await tester.tap(find.text('删除').hitTestable());
    await _settleBookmarks(tester, novelStore);
    expect(novelStore.bookmarks, isEmpty);
    expect(novelStore.groups, isEmpty);
    expect(find.text('小说 A'), findsNothing);
    expect(find.text('没有找到相关书签，试试其他关键词'), findsOneWidget);
    expect(find.text('已删除 2 条书签'), findsOneWidget);
    await tester.tap(find.text('撤销'));
    await _settleBookmarks(tester, novelStore);
    expect(novelStore.bookmarks, hasLength(2));
    expect(novelStore.hasGroup('novel-a'), isTrue);
    expect(find.text('小说 A'), findsOneWidget);
    expect(find.text('第一卷 · 第二章'), findsOneWidget);
    expect(find.text('第一卷 · 第三章'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Finder _header(String pathWord) =>
    find.byKey(ValueKey('novel_bookmark_group_$pathWord'));

Future<void> _settleBookmarks(
  WidgetTester tester,
  NovelBookmarkStore store,
) async {
  // 先完成手势/滑动动画，再等待业务写队列，最后绘制通知产生的新帧。
  await tester.pumpAndSettle();
  await store.flush();
  await tester.pumpAndSettle();
}

Future<void> _showNovels(WidgetTester tester) async {
  await tester.tap(find.text('轻小说'));
  await tester.pumpAndSettle();
}

Future<GoRouter> _pump(WidgetTester tester, NovelBookmarkStore store) async {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const BookmarksPage()),
      GoRoute(
        path: '/novel/:pathWord',
        name: AppRoutes.novelDetail,
        builder: (_, state) => Scaffold(
          body: Text('novel-detail:${state.pathParameters['pathWord']}'),
        ),
      ),
      GoRoute(
        path: '/novel-reader/:pathWord/:volumeId',
        name: AppRoutes.novelReader,
        builder: (_, state) {
          final extra = state.extra;
          if (extra is! NovelReaderExtra) {
            return const Scaffold(body: Text('missing-reader-extra'));
          }
          return Scaffold(
            body: Text(
              'reader:${state.pathParameters['pathWord']}:'
              '${state.pathParameters['volumeId']}:'
              '${extra.entryIndex}:${extra.initialParagraphIndex}:'
              '${extra.initialParagraphAlignment}:${extra.resume}',
            ),
          );
        },
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [novelBookmarkStoreProvider.overrideWithValue(store)],
      child: wrapWithApp(
        Theme(
          data: ThemeData(cardTheme: const CardThemeData(elevation: 8)),
          child: Router.withConfig(config: router),
        ),
        wrapInScaffold: false,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

class _ControlledPreferences implements SharedPreferences {
  _ControlledPreferences(this.delegate);

  final SharedPreferences delegate;
  Completer<void>? writeGate;
  bool failWrite = false;

  @override
  Object? get(String key) => delegate.get(key);

  @override
  Future<bool> setString(String key, String value) async {
    final gate = writeGate;
    writeGate = null;
    await gate?.future;
    return failWrite ? false : delegate.setString(key, value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

NovelReadingProgress _position() => NovelReadingProgress(
  pathWord: 'novel-a',
  name: '小说 A',
  cover: '',
  volumeId: 'volume-1',
  volumeName: '第一卷',
  chapterName: '第一卷 第二章',
  entryIndex: 8,
  paragraphIndex: 12,
  paragraphAlignment: -0.35,
  progress: 0.42,
  updatedAt: DateTime.utc(2026, 9, 25),
);
