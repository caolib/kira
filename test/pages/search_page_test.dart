import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/models/api_ordering.dart';
import 'package:kira/models/comic.dart' as m;
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/home_page.dart' show ComicCard;
import 'package:kira/repositories/search_init_repository.dart';
import 'package:kira/utils/app_storage.dart';
import 'package:kira/widgets/error_retry_view.dart';
import 'package:kira/widgets/load_more_footer.dart';
import 'package:kira/widgets/sliver_comic_grid_skeleton.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';
import 'search_page_test_support.dart';

void _configureView(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpSearchFrames(tester);
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  SearchTestRig rig, {
  int tab = 0,
  Size size = const Size(480, 960),
  double textScale = 1,
}) async {
  _configureView(tester, size);
  await UserManager().setSearchTabIndex(tab);
  await tester.pumpWidget(searchTestApp(rig.page, textScale: textScale));
  await pumpSearchFrames(tester);
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(TabBar)))!;

List<String> _visibleComics(WidgetTester tester) => tester
    .widgetList<ComicCard>(find.byType(ComicCard))
    .map((card) => card.comic.name)
    .toList();

ScrollController _scrollController(WidgetTester tester) =>
    tester.widget<CustomScrollView>(find.byType(CustomScrollView)).controller!;

LoadMoreFooter _footer(WidgetTester tester) =>
    tester.widget<LoadMoreFooter>(find.byType(LoadMoreFooter));

Future<void> _tapMore(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(LoadMoreFooter),
      matching: find.byType(OutlinedButton),
    ),
  );
  await pumpSearchFrames(tester);
}

Future<void> _selectFilter(WidgetTester tester, String label) async {
  final chip = find.widgetWithText(FilterChip, label);
  await tester.ensureVisible(chip);
  await pumpSearchFrames(tester);
  await tester.tap(chip);
  await pumpSearchFrames(tester);
}

/// 排序行行尾的源切换按钮显示**当前**源，点击后切到另一个源。
Future<void> _selectSource(WidgetTester tester, String targetLabel) async {
  final l10n = _l10n(tester);
  final tooltip = targetLabel == l10n.homeSourceCopy
      ? l10n.switchToCopySource
      : l10n.switchToHotSource;
  final toggle = find.byTooltip(tooltip);
  await tester.ensureVisible(toggle);
  await pumpSearchFrames(tester);
  await tester.tap(toggle);
  await pumpSearchFrames(tester);
}

/// 行尾按钮显示当前生效的源名称。
bool _sourceToggleShows(WidgetTester tester, String label) => find
    .descendant(of: _sourceToggle, matching: find.text(label))
    .evaluate()
    .isNotEmpty;

Finder get _sourceToggle => find.ancestor(
  of: find.byIcon(Icons.swap_horiz),
  matching: find.byType(FilledButton),
);

void _finishStale(PendingComicRequest request, {required bool fails}) {
  if (fails) {
    request.fail();
  } else {
    request.succeed(['过期结果']);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(installSearchImageCache);

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'disclaimer_accepted': true,
      'auto_check_update': false,
      'remote_notice_enabled': false,
      'app_logging_enabled': false,
      'manga_home_source': 'hot',
      'discover_source': 'hot',
      'search_tab_index': 0,
      'nav_swipe_enabled': true,
    });
    setupSecureCredentialStoreForTest();
    await UserManager().init();
    // AppStorage 保留自己的 prefs future；仅重置插件 mock 不会清掉旧实例缓存。
    await AppStorage.cache.remove('search_init_v3_copy');
    await AppStorage.cache.remove('copy_filter_options_v1');
    await AppStorage.preferences.remove('search_history_v1');
  });

  tearDown(teardownSecureCredentialStoreForTest);

  group('搜索状态与历史', () {
    testWidgets('空结果不会回落到热门搜索，清空后回到 idle', (tester) async {
      final rig = SearchTestRig();
      await _pumpPage(tester, rig);
      expect(find.text('测试热搜'), findsOneWidget);

      await submitSearch(tester, '  不存在  ');
      expect(rig.manga.searches.single.query, '不存在');
      rig.manga.searches.single.succeed([]);
      await pumpSearchFrames(tester);

      expect(find.text(_l10n(tester).searchEmptyResults), findsOneWidget);
      expect(find.text(_l10n(tester).hotSearchTitle), findsNothing);
      expect(find.text('测试热搜'), findsNothing);
      expect(find.byType(SliverErrorRetryView), findsNothing);

      await tester.tap(find.byTooltip(_l10n(tester).searchClearTooltip));
      await pumpSearchFrames(tester);
      expect(find.text('测试热搜'), findsOneWidget);
      expect(find.text(_l10n(tester).searchHistoryTitle), findsOneWidget);
      expect(find.widgetWithText(InputChip, '不存在'), findsOneWidget);
      expect(find.text(_l10n(tester).searchEmptyResults), findsNothing);
    });

    testWidgets('首屏错误显示标准错误视图，按钮重试同一关键词', (tester) async {
      final rig = SearchTestRig();
      await _pumpPage(tester, rig);
      await submitSearch(tester, '重试词');
      rig.manga.searches.single.fail();
      await pumpSearchFrames(tester);

      expect(find.byType(SliverErrorRetryView), findsOneWidget);
      expect(find.text(_l10n(tester).searchRequestFailed), findsOneWidget);
      expect(find.text('测试热搜'), findsNothing);
      await tester.tap(find.text(_l10n(tester).retryButton));
      await pumpSearchFrames(tester);
      expect(rig.manga.searches, hasLength(2));
      expect(rig.manga.searches.last.query, '重试词');
      expect(find.byType(SliverComicGridSkeleton), findsOneWidget);

      rig.manga.searches.last.succeed(['重试成功']);
      await pumpSearchFrames(tester);
      expect(_visibleComics(tester), ['重试成功']);
      expect(find.byType(SliverErrorRetryView), findsNothing);
    });

    testWidgets('热门词加载失败可独立重试，不会启动关键词搜索', (tester) async {
      final rig = SearchTestRig();
      final first = Completer<SearchInitData>();
      rig.init
        ..cached = null
        ..loader = () => first.future;
      await _pumpPage(tester, rig);
      first.completeError(StateError('热搜不可用'));
      await pumpSearchFrames(tester);
      expect(find.byType(SliverErrorRetryView), findsOneWidget);

      rig.init.loader = () async => hotInitData();
      await tester.tap(find.text(_l10n(tester).retryButton));
      await pumpSearchFrames(tester);
      expect(find.text('测试热搜'), findsOneWidget);
      expect(rig.init.fetchCalls, 2);
      expect(rig.manga.searches, isEmpty);
    });

    testWidgets('热搜刷新失败保留已有关键词并提供重试', (tester) async {
      final rig = SearchTestRig();
      await _pumpPage(tester, rig);
      rig.init.loader = () => Future.error(StateError('刷新失败'));
      final refresh = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await pumpSearchFrames(tester);
      await refresh;

      expect(find.text('测试热搜'), findsOneWidget);
      expect(find.byType(SliverErrorRetryView), findsOneWidget);
      rig.init.loader = () async => hotInitData();
      await tester.tap(find.text(_l10n(tester).retryButton));
      await pumpSearchFrames(tester);
      expect(find.text('测试热搜'), findsOneWidget);
      expect(find.byType(SliverErrorRetryView), findsNothing);
    });

    testWidgets('历史支持点选搜索、删除和清空，且只在 idle 展示', (tester) async {
      late SharedPreferences prefs;
      await tester.runAsync(() async {
        prefs = await AppStorage.sharedPreferences();
        await prefs.setStringList('search_history_v1', ['保留历史', '删除历史']);
      });
      final rig = SearchTestRig();
      await _pumpPage(tester, rig);
      expect(find.byType(InputChip), findsNWidgets(2));

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(InputChip, '删除历史'),
          matching: find.byTooltip(_l10n(tester).searchHistoryDelete),
        ),
      );
      await pumpSearchFrames(tester);
      expect(find.widgetWithText(InputChip, '删除历史'), findsNothing);
      expect(prefs.getStringList('search_history_v1'), ['保留历史']);

      await tester.tap(find.widgetWithText(InputChip, '保留历史'));
      await pumpSearchFrames(tester);
      expect(rig.manga.searches.single.query, '保留历史');
      expect(find.byType(InputChip), findsNothing);
      rig.manga.searches.single.succeed(['历史结果']);
      await pumpSearchFrames(tester);
      expect(_visibleComics(tester), ['历史结果']);

      await tester.tap(find.byTooltip(_l10n(tester).searchClearTooltip));
      await pumpSearchFrames(tester);
      await tester.tap(find.text(_l10n(tester).searchHistoryClear));
      await pumpSearchFrames(tester);
      expect(find.byType(InputChip), findsNothing);
      expect(prefs.getStringList('search_history_v1') ?? [], isEmpty);
      expect(find.text('测试热搜'), findsOneWidget);
    });

    for (final sameQuery in [false, true]) {
      for (final fails in [false, true]) {
        testWidgets(
          '${sameQuery ? '重复相同查询' : '快速切换查询'}：旧${fails ? '错误/finally' : '成功/finally'}不结束新请求',
          (tester) async {
            final rig = SearchTestRig();
            await _pumpPage(tester, rig);
            await submitSearch(tester, '第一次');
            await submitSearch(tester, sameQuery ? '第一次' : '第二次');
            expect(rig.manga.searches, hasLength(2));

            _finishStale(rig.manga.searches.first, fails: fails);
            await pumpSearchFrames(tester);
            expect(find.byType(SliverComicGridSkeleton), findsOneWidget);
            expect(find.byType(SliverErrorRetryView), findsNothing);
            expect(_visibleComics(tester), isEmpty);

            rig.manga.searches.last.succeed(['当前结果']);
            await pumpSearchFrames(tester);
            expect(_visibleComics(tester), ['当前结果']);
          },
        );
      }
    }

    testWidgets('旧查询晚于新查询成功，不能覆盖新列表', (tester) async {
      final rig = SearchTestRig();
      await _pumpPage(tester, rig);
      await submitSearch(tester, '旧查询');
      await submitSearch(tester, '新查询');
      rig.manga.searches.last.succeed(['新结果']);
      await pumpSearchFrames(tester);
      rig.manga.searches.first.succeed(['旧结果']);
      await pumpSearchFrames(tester);
      expect(_visibleComics(tester), ['新结果']);
    });

    for (final fails in [false, true]) {
      testWidgets('清空使在途搜索${fails ? '错误' : '成功'}失效，保持 idle', (tester) async {
        final rig = SearchTestRig();
        await _pumpPage(tester, rig);
        await submitSearch(tester, '将被清空');
        await tester.tap(find.byTooltip(_l10n(tester).searchClearTooltip));
        await pumpSearchFrames(tester);
        _finishStale(rig.manga.searches.single, fails: fails);
        await pumpSearchFrames(tester);
        expect(find.text('测试热搜'), findsOneWidget);
        expect(find.byType(SliverErrorRetryView), findsNothing);
        expect(find.byType(SliverComicGridSkeleton), findsNothing);
        expect(_visibleComics(tester), isEmpty);
      });
    }
  });

  group('分页与刷新', () {
    for (final discover in [false, true]) {
      testWidgets('${discover ? '发现' : '搜索'}分页错误保留结果，显式重试从原 offset 继续', (
        tester,
      ) async {
        final rig = SearchTestRig();
        await _pumpPage(tester, rig, tab: discover ? 1 : 0);
        if (!discover) await submitSearch(tester, '分页词');
        final requests = discover ? rig.manga.listings : rig.manga.searches;
        requests.single.succeed(['首屏漫画'], total: 10);
        await pumpSearchFrames(tester);
        await _tapMore(tester);
        expect(requests.last.offset, 1);
        requests.last.fail();
        await pumpSearchFrames(tester);

        expect(_visibleComics(tester), ['首屏漫画']);
        expect(find.text(_l10n(tester).searchLoadMoreFailed), findsOneWidget);
        expect(find.text(_l10n(tester).retryButton), findsOneWidget);
        // 错误后滚动通知不能悄悄连续重试。
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -90));
        await pumpSearchFrames(tester);
        expect(requests, hasLength(2));

        await tester.tap(find.text(_l10n(tester).retryButton));
        await pumpSearchFrames(tester);
        expect(requests, hasLength(3));
        expect(requests.last.offset, 1);
        requests.last.succeed(['第二页漫画'], total: 2);
        await pumpSearchFrames(tester);
        expect(_visibleComics(tester), ['首屏漫画', '第二页漫画']);
        expect(find.text(_l10n(tester).searchLoadMoreFailed), findsNothing);
        expect(find.byType(LoadMoreFooter), findsNothing);
      });

      testWidgets('${discover ? '发现' : '搜索'}空分页即终止，即使 total 仍宣称有更多', (
        tester,
      ) async {
        final rig = SearchTestRig();
        await _pumpPage(tester, rig, tab: discover ? 1 : 0);
        if (!discover) await submitSearch(tester, '过期总数');
        final requests = discover ? rig.manga.listings : rig.manga.searches;
        requests.single.succeed(['唯一结果'], total: 100);
        await pumpSearchFrames(tester);
        await _tapMore(tester);
        requests.last.succeed([], total: 100);
        await pumpSearchFrames(tester);
        expect(_visibleComics(tester), ['唯一结果']);
        expect(find.byType(LoadMoreFooter), findsNothing);
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -90));
        await pumpSearchFrames(tester);
        expect(requests, hasLength(2));
      });
    }

    for (final fails in [false, true]) {
      testWidgets('旧搜索分页${fails ? '错误/finally' : '成功/finally'}不影响新查询的在途分页', (
        tester,
      ) async {
        final rig = SearchTestRig();
        await _pumpPage(tester, rig);
        await submitSearch(tester, '旧词');
        rig.manga.searches.single.succeed(['旧首屏'], total: 10);
        await pumpSearchFrames(tester);
        await _tapMore(tester);
        final oldPage = rig.manga.searches.last;

        await submitSearch(tester, '新词');
        rig.manga.searches.last.succeed(['新首屏'], total: 10);
        await pumpSearchFrames(tester);
        await _tapMore(tester);
        final newPage = rig.manga.searches.last;
        expect(newPage.query, '新词');
        expect(newPage.offset, 1);

        _finishStale(oldPage, fails: fails);
        await pumpSearchFrames(tester);
        expect(_visibleComics(tester), ['新首屏']);
        expect(_footer(tester).loading, isTrue);
        expect(find.text(_l10n(tester).searchLoadMoreFailed), findsNothing);
        expect(rig.manga.searches, hasLength(4));

        newPage.succeed(['新分页'], total: 2);
        await pumpSearchFrames(tester);
        expect(_visibleComics(tester), ['新首屏', '新分页']);
      });
    }

    testWidgets('搜索短列表可真实下拉刷新，并保持指示器到请求完成', (tester) async {
      final rig = SearchTestRig();
      await _pumpPage(tester, rig);
      await submitSearch(tester, '短列表');
      rig.manga.searches.single.succeed(['原结果']);
      await pumpSearchFrames(tester);
      final scroll = tester.widget<CustomScrollView>(
        find.byType(CustomScrollView),
      );
      expect(scroll.physics, isA<AlwaysScrollableScrollPhysics>());
      expect(_scrollController(tester).position.maxScrollExtent, 0);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, 350));
      await pumpSearchFrames(tester);
      expect(rig.manga.searches, hasLength(2));
      expect(rig.manga.searches.last.query, '短列表');
      expect(find.byType(RefreshProgressIndicator), findsOneWidget);
      await pumpSearchFrames(tester);
      expect(find.byType(RefreshProgressIndicator), findsOneWidget);

      rig.manga.searches.last.succeed(['刷新结果']);
      await pumpSearchFrames(tester);
      expect(_visibleComics(tester), ['刷新结果']);
      expect(find.byType(RefreshProgressIndicator), findsNothing);
    });

    testWidgets('发现刷新并行更新标签和列表，等两者完成才返回', (tester) async {
      final rig = SearchTestRig();
      await _pumpPage(tester, rig, tab: 1);
      rig.manga.listings.single.succeed(['原漫画']);
      await pumpSearchFrames(tester);
      final metadata = Completer<SearchInitData>();
      rig.init.loader = () => metadata.future;
      var refreshDone = false;
      final refresh = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh()
          .then((_) => refreshDone = true);
      await pumpSearchFrames(tester);
      expect(rig.init.fetchCalls, 1);
      expect(rig.manga.listings, hasLength(2));
      expect(rig.manga.listings.last.offset, 0);
      expect(refreshDone, isFalse);

      metadata.complete(
        SearchInitData(
          keywords: const [],
          tags: [m.Theme(name: '新题材', pathWord: 'new-tag')],
        ),
      );
      await pumpSearchFrames(tester);
      expect(find.text('新题材'), findsOneWidget);
      expect(refreshDone, isFalse);
      rig.manga.listings.last.succeed(['刷新漫画']);
      await refresh;
      await pumpSearchFrames(tester);
      expect(refreshDone, isTrue);
      expect(_visibleComics(tester), ['刷新漫画']);
      expect(
        tester.widget<CustomScrollView>(find.byType(CustomScrollView)).physics,
        isA<AlwaysScrollableScrollPhysics>(),
      );
    });

    testWidgets('初始缓存在途时强刷失败，发现页仍恢复缓存题材', (tester) async {
      final rig = SearchTestRig();
      final cacheRead = Completer<SearchInitData?>();
      final metadata = Completer<SearchInitData>();
      rig.init.cacheLoader = () => cacheRead.future;
      rig.init.loader = () => metadata.future;
      await _pumpPage(tester, rig, tab: 1);
      final refresh = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await pumpSearchFrames(tester);
      cacheRead.complete(hotInitData());
      await pumpSearchFrames(tester);
      metadata.completeError(StateError('强刷失败'));
      rig.manga.listings.first.succeed(['旧漫画']);
      rig.manga.listings.last.succeed(['当前漫画']);
      await refresh;
      await pumpSearchFrames(tester);
      expect(find.text('冒险'), findsOneWidget);
      expect(_visibleComics(tester), ['当前漫画']);
      expect(tester.takeException(), isNull);
    });
  });

  group('发现筛选与源', () {
    testWidgets('进入即加载全部+热度，源控件和筛选随列表滚走，展开题材不重复', (tester) async {
      final rig = SearchTestRig();
      await _pumpPage(tester, rig, tab: 1);
      final initial = rig.manga.listings.single;
      expect(initial.source, 'hot');
      expect(initial.ordering, ApiOrdering.popular);
      expect(initial.theme, isNull);
      expect(initial.top, isNull);
      expect(initial.offset, 0);
      // 源切换在排序行行尾，属于筛选区（随列表滚走）。
      expect(_sourceToggleShows(tester, _l10n(tester).homeSourceHot), isTrue);
      expect(
        find.ancestor(
          of: _sourceToggle,
          matching: find.byType(CustomScrollView),
        ),
        findsOneWidget,
      );
      initial.succeed(List.generate(30, (index) => '发现漫画$index'));
      await pumpSearchFrames(tester);
      await tester.tap(find.text(_l10n(tester).tagsExpandAll));
      await pumpSearchFrames(tester);
      expect(find.text('冒险', findRichText: true), findsOneWidget);
      expect(find.text('恋爱', findRichText: true), findsOneWidget);
      expect(find.text(_l10n(tester).tagsCollapseAll), findsOneWidget);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -650));
      await pumpSearchFrames(tester);
      expect(_scrollController(tester).offset, greaterThan(100));
      expect(_sourceToggle.hitTestable(), findsNothing);
      expect(find.widgetWithText(Tab, '发现').hitTestable(), findsOneWidget);
    });

    testWidgets('COPY 的地区、题材、排序可叠加，重置重新加载默认列表', (tester) async {
      final rig = SearchTestRig();
      await _pumpPage(tester, rig, tab: 1);
      rig.manga.listings.single.succeed(['HOT漫画']);
      await pumpSearchFrames(tester);
      await _selectSource(tester, _l10n(tester).homeSourceCopy);
      // 发现页与首页数据源互相独立：切源不改动首页设置。
      expect(UserManager().discoverSource, 'copy');
      expect(UserManager().mangaHomeSource, 'hot');
      expect(_sourceToggleShows(tester, _l10n(tester).homeSourceCopy), isTrue);
      expect(rig.manga.listings.last.source, 'copy');
      rig.manga.listings.last.succeed(['COPY漫画']);
      await pumpSearchFrames(tester);

      await _selectFilter(tester, '韩漫');
      expect(rig.manga.listings.last.top, 'korea');
      rig.manga.listings.last.succeed(['韩漫结果']);
      await pumpSearchFrames(tester);
      await _selectFilter(tester, '冒险');
      expect(rig.manga.listings.last.theme, 'adventure');
      expect(rig.manga.listings.last.top, 'korea');
      rig.manga.listings.last.succeed(['叠加结果']);
      await pumpSearchFrames(tester);
      await _selectFilter(tester, _l10n(tester).updateOrder);
      expect(rig.manga.listings.last.ordering, ApiOrdering.datetimeUpdated);
      expect(rig.manga.listings.last.theme, 'adventure');
      expect(rig.manga.listings.last.top, 'korea');
      rig.manga.listings.last.succeed(['排序结果']);
      await pumpSearchFrames(tester);

      await tester.tap(find.text(_l10n(tester).resetButton));
      await pumpSearchFrames(tester);
      final reset = rig.manga.listings.last;
      expect(reset.source, 'copy');
      expect(reset.theme, isNull);
      expect(reset.top, isNull);
      expect(reset.ordering, ApiOrdering.popular);
      expect(reset.offset, 0);
      reset.succeed(['默认列表']);
      await pumpSearchFrames(tester);
      expect(_visibleComics(tester), ['默认列表']);
      expect(find.text(_l10n(tester).resetButton), findsNothing);
    });

    testWidgets('发现空结果和失败各有明确状态，错误可重试', (tester) async {
      final rig = SearchTestRig();
      await _pumpPage(tester, rig, tab: 1);
      rig.manga.listings.single.succeed([]);
      await pumpSearchFrames(tester);
      expect(find.text(_l10n(tester).discoverEmptyResults), findsOneWidget);

      await _selectFilter(tester, '冒险');
      rig.manga.listings.last.fail();
      await pumpSearchFrames(tester);
      expect(find.text(_l10n(tester).discoverRequestFailed), findsOneWidget);
      expect(find.byType(SliverErrorRetryView), findsOneWidget);
      await tester.tap(find.text(_l10n(tester).retryButton));
      await pumpSearchFrames(tester);
      expect(rig.manga.listings.last.theme, 'adventure');
      rig.manga.listings.last.succeed(['恢复漫画']);
      await pumpSearchFrames(tester);
      expect(_visibleComics(tester), ['恢复漫画']);
      expect(find.byType(SliverErrorRetryView), findsNothing);
    });

    for (final fails in [false, true]) {
      testWidgets('快速切筛选：旧${fails ? '错误/finally' : '成功/finally'}不结束新首屏请求', (
        tester,
      ) async {
        final rig = SearchTestRig();
        await _pumpPage(tester, rig, tab: 1);
        rig.manga.listings.single.succeed(['默认漫画']);
        await pumpSearchFrames(tester);
        await _selectFilter(tester, '冒险');
        final previous = rig.manga.listings.last;
        await _selectFilter(tester, '恋爱');
        final current = rig.manga.listings.last;
        expect(current.theme, 'romance');

        _finishStale(previous, fails: fails);
        await pumpSearchFrames(tester);
        expect(find.byType(SliverComicGridSkeleton), findsOneWidget);
        expect(find.byType(SliverErrorRetryView), findsNothing);
        current.succeed(['恋爱结果']);
        await pumpSearchFrames(tester);
        expect(_visibleComics(tester), ['恋爱结果']);
      });

      testWidgets('切源：旧${fails ? '错误/finally' : '成功/finally'}不污染 COPY 首屏', (
        tester,
      ) async {
        final rig = SearchTestRig();
        await _pumpPage(tester, rig, tab: 1);
        final hot = rig.manga.listings.single;
        await _selectSource(tester, _l10n(tester).homeSourceCopy);
        final copy = rig.manga.listings.last;
        expect(copy.source, 'copy');
        expect(copy.ordering, ApiOrdering.popular);
        _finishStale(hot, fails: fails);
        await pumpSearchFrames(tester);
        expect(find.byType(SliverComicGridSkeleton), findsOneWidget);
        expect(find.byType(SliverErrorRetryView), findsNothing);
        copy.succeed(['COPY新结果']);
        await pumpSearchFrames(tester);
        expect(_visibleComics(tester), ['COPY新结果']);
      });

      testWidgets('旧发现分页${fails ? '错误/finally' : '成功/finally'}不影响筛选后的在途分页', (
        tester,
      ) async {
        final rig = SearchTestRig();
        await _pumpPage(tester, rig, tab: 1);
        rig.manga.listings.single.succeed(['全部首屏'], total: 10);
        await pumpSearchFrames(tester);
        await _tapMore(tester);
        final previousPage = rig.manga.listings.last;
        await _selectFilter(tester, '冒险');
        rig.manga.listings.last.succeed(['冒险首屏'], total: 10);
        await pumpSearchFrames(tester);
        await _tapMore(tester);
        final currentPage = rig.manga.listings.last;
        expect(currentPage.theme, 'adventure');
        expect(currentPage.offset, 1);
        _finishStale(previousPage, fails: fails);
        await pumpSearchFrames(tester);
        expect(_visibleComics(tester), ['冒险首屏']);
        expect(_footer(tester).loading, isTrue);
        expect(find.text(_l10n(tester).searchLoadMoreFailed), findsNothing);
        currentPage.succeed(['冒险分页'], total: 2);
        await pumpSearchFrames(tester);
        expect(_visibleComics(tester), ['冒险首屏', '冒险分页']);
      });
    }

    testWidgets('旧源标签和地区回包晚到，不能覆盖新源元数据', (tester) async {
      final rig = SearchTestRig();
      final tags = Completer<List<m.Theme>>();
      final tops = Completer<m.CopyFilterOptions>();
      rig.manga.copyTagsLoader = () => tags.future;
      rig.manga.copyFiltersLoader = () => tops.future;
      await _pumpPage(tester, rig, tab: 1);
      rig.manga.listings.single.succeed(['HOT初始']);
      await pumpSearchFrames(tester);
      await _selectSource(tester, _l10n(tester).homeSourceCopy);
      final oldCopy = rig.manga.listings.last;
      await _selectSource(tester, _l10n(tester).homeSourceHot);
      rig.manga.listings.last.succeed(['HOT当前']);
      await pumpSearchFrames(tester);
      tags.complete([m.Theme(name: '过期题材', pathWord: 'old')]);
      tops.complete(
        m.CopyFilterOptions(
          tops: [m.Theme(name: '过期地区', pathWord: 'old')],
        ),
      );
      oldCopy.succeed(['COPY过期']);
      await pumpSearchFrames(tester);
      expect(find.text('冒险'), findsOneWidget);
      expect(find.text('过期题材'), findsNothing);
      expect(find.text('过期地区'), findsNothing);
      expect(_visibleComics(tester), ['HOT当前']);
    });
  });

  group('标签保活与布局手势', () {
    testWidgets('点击切换保留查询、筛选、列表和各自滚动位置', (tester) async {
      final rig = SearchTestRig();
      await _pumpPage(tester, rig);
      expect(
        tester.widget<TabBarView>(find.byType(TabBarView)).physics,
        isA<NeverScrollableScrollPhysics>(),
      );
      await submitSearch(tester, '保活查询');
      rig.manga.searches.single.succeed(List.generate(30, (i) => '搜索$i'));
      await pumpSearchFrames(tester);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -450));
      await pumpSearchFrames(tester);
      final searchOffset = _scrollController(tester).offset;
      expect(searchOffset, greaterThan(100));

      await tapSearchTab(tester, '发现');
      rig.manga.listings.single.succeed(['初始发现']);
      await pumpSearchFrames(tester);
      await _selectFilter(tester, '冒险');
      rig.manga.listings.last.succeed(List.generate(30, (i) => '发现$i'));
      await pumpSearchFrames(tester);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -450));
      await pumpSearchFrames(tester);
      final discoverOffset = _scrollController(tester).offset;
      expect(discoverOffset, greaterThan(100));

      await tapSearchTab(tester, '搜索');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '保活查询',
      );
      expect(_scrollController(tester).offset, closeTo(searchOffset, 1));
      expect(rig.manga.searches, hasLength(1));
      expect(UserManager().searchTabIndex, 0);
      await tapSearchTab(tester, '发现');
      expect(_scrollController(tester).offset, closeTo(discoverOffset, 1));
      expect(rig.manga.listings, hasLength(2));
      expect(UserManager().searchTabIndex, 1);
      _scrollController(tester).jumpTo(0);
      await pumpSearchFrames(tester);
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, '冒险'))
            .selected,
        isTrue,
      );
    });

    testWidgets('320 宽和两倍字体：历史、源选择、筛选展开及结果无布局溢出', (tester) async {
      await tester.runAsync(() async {
        final prefs = await AppStorage.sharedPreferences();
        await prefs.setStringList('search_history_v1', [
          '这是一个较长的历史关键词用于验证窄屏显示',
        ]);
      });
      final rig = SearchTestRig();
      await _pumpPage(tester, rig, size: const Size(320, 800), textScale: 2);
      expect(tester.takeException(), isNull);
      await tapSearchTab(tester, '发现');
      rig.manga.listings.single.succeed(['较长标题用于验证漫画卡片布局']);
      await pumpSearchFrames(tester);
      expect(tester.takeException(), isNull);
      await _selectSource(tester, _l10n(tester).homeSourceCopy);
      rig.manga.listings.last.succeed(['COPY结果']);
      await pumpSearchFrames(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(_l10n(tester).tagsExpandAll));
      await pumpSearchFrames(tester);
      expect(find.text('冒险', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(_l10n(tester).tagsCollapseAll));
      await pumpSearchFrames(tester);
      await _selectFilter(tester, _l10n(tester).updateOrder);
      rig.manga.listings.last.succeed([]);
      await pumpSearchFrames(tester);
      expect(tester.takeException(), isNull);
    });

    for (final discover in [false, true]) {
      testWidgets('竖屏 GNav 保留：${discover ? '发现' : '搜索'}普通内容区左右滑切主导航', (
        tester,
      ) async {
        _configureView(tester, const Size(420, 900));
        await UserManager().setSearchTabIndex(discover ? 1 : 0);
        await UserManager().setLastNavKey('search');
        await UserManager().setBottomNavLabelMode(
          BottomNavLabelMode.selectedOnly,
        );
        await UserManager().theme.setNavSwipeEnabled(true);
        final rig = SearchTestRig();
        final router = searchShellRouter(rig);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          router.dispose();
        });
        await tester.pumpWidget(
          MaterialApp.router(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        );
        await pumpSearchFrames(tester);
        if (discover) {
          rig.manga.listings.single.succeed(['可滑动发现漫画']);
        } else {
          await submitSearch(tester, '主导航测试');
          rig.manga.searches.single.succeed(['可滑动搜索漫画']);
        }
        await pumpSearchFrames(tester, count: 30);
        expect(find.byType(GNav), findsOneWidget);
        expect(find.byType(NavigationRail), findsNothing);
        expect(tester.widget<GNav>(find.byType(GNav)).selectedIndex, 1);

        // 从结果卡片区域拖动，而非 TabBar、横向筛选行或底部导航。
        await tester.timedDrag(
          find.byType(ComicCard).first,
          const Offset(-320, 0),
          const Duration(milliseconds: 300),
        );
        await pumpSearchFrames(tester);
        expect(find.text('主导航-我的'), findsOneWidget);
        expect(tester.widget<GNav>(find.byType(GNav)).selectedIndex, 2);
        await tester.timedDrag(
          find.text('主导航-我的'),
          const Offset(320, 0),
          const Duration(milliseconds: 300),
        );
        await pumpSearchFrames(tester);
        expect(find.byType(ComicCard), findsOneWidget);

        await tester.timedDrag(
          find.byType(ComicCard).first,
          const Offset(320, 0),
          const Duration(milliseconds: 300),
        );
        await pumpSearchFrames(tester);
        expect(find.text('主导航-漫画'), findsOneWidget);
        expect(tester.widget<GNav>(find.byType(GNav)).selectedIndex, 0);
        await tester.timedDrag(
          find.text('主导航-漫画'),
          const Offset(-320, 0),
          const Duration(milliseconds: 300),
        );
        await pumpSearchFrames(tester);
        expect(find.byType(ComicCard), findsOneWidget);
        expect(UserManager().searchTabIndex, discover ? 1 : 0);
        expect(find.byType(GNav), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
