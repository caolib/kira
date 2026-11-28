import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/novel_reading_progress.dart';
import 'package:kira/models/reader_settings.dart';
import 'package:kira/pages/stats_page.dart';
import 'package:kira/providers/novel_providers.dart';
import 'package:kira/utils/novel_reading_store.dart';
import 'package:kira/utils/reading_stats.dart';
import 'package:kira/widgets/app_sheet.dart';
import 'package:kira/widgets/bar_chart_grid.dart';
import 'package:kira/widgets/heatmap_grid.dart';
import 'package:kira/widgets/settings_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

Widget _buildTestApp(Widget child) =>
    ProviderScope(child: wrapWithApp(child, wrapInScaffold: false));

String _dayKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

Future<void> _seedBothStats({int novelWords = 12345}) async {
  final today = _dayKey(DateTime.now());
  SharedPreferences.setMockInitialValues({
    'reader_reading_stats_enabled': true,
    'reading_stats_v1': jsonEncode({
      'comicMeta': {
        'comic-a': {
          'name': '漫画A',
          'tags': ['恋爱'],
          'chapterImages': {'ch-1': 12},
        },
      },
      'daily': {today: 12},
      'since': '2026-08-03',
      'novelMeta': {
        'novel-a': {
          'name': '小说A',
          'tags': ['奇幻'],
          'totalWords': novelWords,
          'chapters': {
            'volume-a': {'0': today, '2': today},
            'volume-b': {'0': today},
          },
        },
      },
      'novelDaily': {today: 6789},
      'novelSince': '2026-09-04',
    }),
  });
  ReaderSettings().resetPrefsCache();
  await ReaderSettings().initFromPrefs(await SharedPreferences.getInstance());
  ReadingStats.reloadFromPrefs();
}

Finder _domain(String type) => find.byKey(ValueKey('stats-$type'));
Finder _within(String type, Finder finder) =>
    find.descendant(of: _domain(type), matching: finder);

Future<void> _showPageItem(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find
        .descendant(
          of: find.byKey(const PageStorageKey('reading-stats')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    await tester.tap(finder);
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pumpAndSettle();
}

Future<void> _selectSettingsTab(WidgetTester tester, {required bool isNovel}) =>
    _tapVisible(
      tester,
      find.byKey(ValueKey('stats-settings-${isNovel ? 'novel' : 'comic'}-tab')),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(teardownSecureCredentialStoreForTest);

  setUp(() async {
    setupSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({});
    ReadingStats.reloadFromPrefs();
    ReaderSettings().resetPrefsCache();
    await ReaderSettings().initFromPrefs(await SharedPreferences.getInstance());
  });

  testWidgets('disabled state shows enable button and privacy note', (
    tester,
  ) async {
    await tester.pumpWidget(_buildTestApp(const StatsPage()));
    await tester.pumpAndSettle();

    // 开关默认关闭 → 显示开启按钮与隐私说明
    expect(find.byIcon(Icons.insights_rounded), findsOneWidget);
    expect(find.text('开启'), findsOneWidget);
    expect(find.textContaining('数据仅保存在本地'), findsOneWidget);
    expect(find.text('读过的漫画与轻小说数量'), findsOneWidget);
    expect(find.text('漫画阅读页数与小说阅读字数'), findsOneWidget);
  });

  testWidgets(
    'empty novel statistics initialize from local history on first open',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'reader_reading_stats_enabled': true,
      });
      ReaderSettings().resetPrefsCache();
      await ReaderSettings().initFromPrefs(
        await SharedPreferences.getInstance(),
      );
      await NovelReadingStore().saveProgress(
        NovelReadingProgress(
          pathWord: 'old-book',
          name: '旧小说',
          cover: '',
          volumeId: 'v2',
          volumeName: '第二卷',
          chapterName: '读到的章节',
          entryIndex: 8,
          updatedAt: DateTime(2026, 8, 3),
          readVolumeIds: const {'v1'},
        ),
      );
      ReadingStats.reloadFromPrefs();
      await tester.pumpWidget(_buildTestApp(const StatsPage()));
      await tester.pumpAndSettle();
      final overview = find.byKey(const ValueKey('stats-novel-overview'));
      await _showPageItem(tester, overview);
      expect(
        find.descendant(of: overview, matching: find.text('1')),
        findsNWidgets(2),
      );
      expect(
        find.descendant(of: overview, matching: find.text('2')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: overview, matching: find.text('0')),
        findsOneWidget,
      );
      expect((await ReadingStats.load()).novelHistoryInitialized, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('已有阅读记录缺标签时从本机补齐，不必再读一章', (tester) async {
    await ReaderSettings().setReadingStatsEnabled(true);
    await ReadingStats.recordNovelReading(
      pathWord: 'book',
      volumeId: 'v1',
      entryIndex: 1,
      paragraphIndex: 0,
      text: '正文',
      start: 0,
      end: 2,
    );
    final lookups = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localNovelTagsProvider.overrideWithValue((pathWord) async {
            lookups.add(pathWord);
            return ['日常'];
          }),
        ],
        child: wrapWithApp(const StatsPage(), wrapInScaffold: false),
      ),
    );
    await tester.pumpAndSettle();
    final tag = _within('novel', find.text('日常'));
    await _showPageItem(tester, tag);
    expect(tag, findsOneWidget);
    expect(lookups, ['book']);
    ReadingStats.reloadFromPrefs();
    final stats = await ReadingStats.load();
    expect(stats.novelMeta['book']!.tags, ['日常']);
    expect(novelWordsReadCount(stats), 2);
    expect(novelChaptersReadCount(stats), 1);
  });

  testWidgets('reference hint appears once below the statistics', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(320, 640)
      ..devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await _seedBothStats();
    await tester.pumpWidget(_buildTestApp(const StatsPage()));
    await tester.pumpAndSettle();
    final hint = find.byKey(const ValueKey('stats-accuracy-hint'));
    await _showPageItem(tester, hint);
    final text = tester.widget<Text>(hint);
    expect(text.data, '统计数据供参考，并非精确数据');
    expect(text.textAlign, TextAlign.center);
    expect(text.style!.fontSize, 12);
    expect(
      text.style!.color,
      Theme.of(tester.element(hint)).colorScheme.onSurfaceVariant,
    );
    expect(find.text('统计数据供参考，并非精确数据'), findsOneWidget);
    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const PageStorageKey('reading-stats')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(hint).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(FloatingActionButton)).top),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('enabled state shows overview card when data exists', (
    tester,
  ) async {
    // 预置：开启统计 + 写入一条统计数据
    SharedPreferences.setMockInitialValues({
      'reader_reading_stats_enabled': true,
      'reading_stats_v1':
          '{"comicMeta":{"comic-a":{"name":"漫画A","tags":["恋爱"],"chapterImages":{"ch-1":12}}},"daily":{},"since":"2026-08-03"}',
    });
    ReaderSettings().resetPrefsCache();
    await ReaderSettings().initFromPrefs(await SharedPreferences.getInstance());
    ReadingStats.reloadFromPrefs();

    await tester.pumpWidget(_buildTestApp(const StatsPage()));
    await tester.pumpAndSettle();

    // 已开启态：显示概览卡（漫画/章节/页数）与常看类型标题
    expect(find.text('漫画'), findsWidgets);
    expect(find.text('章节'), findsWidgets);
    expect(find.text('页数'), findsWidgets);
    expect(_within('comic', find.text('常看类型')), findsOneWidget);
    expect(find.text('恋爱'), findsOneWidget);
    expect(find.text('开始于 2026-08-03'), findsOneWidget);
  });

  testWidgets('enabled empty state shows zeros instead of empty hint', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'reader_reading_stats_enabled': true,
      // reading_stats_v1 缺失 → 空快照，按 0 渲染
    });
    ReaderSettings().resetPrefsCache();
    await ReaderSettings().initFromPrefs(await SharedPreferences.getInstance());
    ReadingStats.reloadFromPrefs();

    await tester.pumpWidget(_buildTestApp(const StatsPage()));
    await tester.pumpAndSettle();

    // 无空态提示；概览三数字均显示 0
    expect(find.text('还没有阅读数据'), findsNothing);
    expect(find.text('漫画'), findsWidgets);
    expect(find.text('章节'), findsWidgets);
    expect(find.text('页数'), findsWidgets);
    expect(_within('comic', find.text('0')), findsNWidgets(3));
    await _showPageItem(
      tester,
      find.byKey(const ValueKey('stats-novel-overview')),
    );
    await tester.pumpAndSettle();
    expect(_within('novel', find.text('0')), findsNWidgets(4));
  });

  testWidgets(
    'both domains show independent overview, dates and heatmap units',
    (tester) async {
      await _seedBothStats();
      await tester.pumpWidget(_buildTestApp(const StatsPage()));
      await tester.pumpAndSettle();
      expect(find.byType(TabBar), findsNothing);
      expect(_domain('comic'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('stats-comic-overview')),
          matching: find.text('12'),
        ),
        findsOneWidget,
      );
      expect(_within('comic', find.text('开始于 2026-08-03')), findsOneWidget);
      await _showPageItem(
        tester,
        find.byKey(const ValueKey('stats-novel-activity')),
      );
      await tester.pumpAndSettle();
      for (final label in ['小说', '卷数', '章节', '字数', '1', '2', '3', '12,345']) {
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('stats-novel-overview')),
            matching: find.text(label),
          ),
          findsOneWidget,
        );
      }
      expect(_within('novel', find.text('奇幻')), findsOneWidget);
      expect(_within('novel', find.text('开始于 2026-09-04')), findsOneWidget);
      final heatmap = tester.widget<HeatmapGrid>(
        _within('novel', find.byType(HeatmapGrid)),
      );
      expect(heatmap.dailyCounts, {_dayKey(DateTime.now()): 6789});
      expect(heatmap.thresholds, [1000, 5000, 10000]);
      expect(heatmap.countLabel!(6789), '6789 字');
      final tooltip = find.byTooltip('${_dayKey(DateTime.now())} · 6789 字');
      expect(tooltip, findsOneWidget);
      await _tapVisible(tester, tooltip);
      expect(find.text('${_dayKey(DateTime.now())} · 6789 字'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'charts keep default page labels including zero and exact dates',
    (tester) async {
      final end = DateTime(2026, 10, 4);
      await tester.pumpWidget(
        wrapWithApp(
          Column(
            children: [
              HeatmapGrid(
                dailyCounts: const {'2026-10-04': 12},
                weeks: 1,
                end: end,
              ),
              BarChartGrid(dailyCounts: const {'2026-10-04': 12}, end: end),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('2026-10-04 · 12 页'), findsNWidgets(2));
      expect(find.byTooltip('2026-09-28 · 0 页'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('word bars and manga pages use independent chart settings', (
    tester,
  ) async {
    await _seedBothStats();
    await tester.runAsync(
      () => ReaderSettings().setNovelReadingStatsChartStyle(1),
    );
    await tester.pumpWidget(_buildTestApp(const StatsPage()));
    await tester.pumpAndSettle();
    expect(_within('comic', find.byType(HeatmapGrid)), findsOneWidget);
    expect(find.byTooltip('${_dayKey(DateTime.now())} · 12 页'), findsOneWidget);
    await _showPageItem(
      tester,
      find.byKey(const ValueKey('stats-novel-activity')),
    );
    await tester.pumpAndSettle();
    final chart = tester.widget<BarChartGrid>(
      _within('novel', find.byType(BarChartGrid)),
    );
    expect(chart.dailyCounts, {_dayKey(DateTime.now()): 6789});
    expect(chart.countLabel!(6789), '6789 字');
    expect(
      find.byTooltip('${_dayKey(DateTime.now())} · 6789 字'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'visibility hides a domain without disabling collection and keeps one visible',
    (tester) async {
      await _seedBothStats();
      await tester.pumpWidget(_buildTestApp(const StatsPage()));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.byIcon(Icons.tune_rounded));
      await _selectSettingsTab(tester, isNovel: true);
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('stats-novel-visible')),
      );
      expect(ReaderSettings().readingStatsShowNovels, isFalse);
      expect(ReaderSettings().readingStatsEnabled, isTrue);
      await _selectSettingsTab(tester, isNovel: false);
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('stats-comic-visible')),
      );
      expect(ReaderSettings().readingStatsShowComics, isTrue);
      expect(find.text('至少显示一类统计'), findsOneWidget);
      Navigator.of(tester.element(find.byType(AppSheet))).pop();
      await tester.pumpAndSettle();
      expect(_domain('novel'), findsNothing);
      expect(novelWordsReadCount(await ReadingStats.load()), 12345);
      await _tapVisible(tester, find.byIcon(Icons.tune_rounded));
      await _selectSettingsTab(tester, isNovel: true);
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('stats-novel-visible')),
      );
      await _selectSettingsTab(tester, isNovel: false);
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('stats-comic-visible')),
      );
      Navigator.of(tester.element(find.byType(AppSheet))).pop();
      await tester.pumpAndSettle();
      expect(_domain('novel'), findsOneWidget);
      expect(_domain('comic'), findsNothing);
      expect(ReaderSettings().readingStatsEnabled, isTrue);
    },
  );

  testWidgets('novel components reorder and hide without changing manga', (
    tester,
  ) async {
    await _seedBothStats();
    await tester.runAsync(
      () => ReaderSettings().setNovelReadingStatsSectionOrder([
        'activity',
        'overview',
        'tags',
      ]),
    );
    await tester.pumpWidget(_buildTestApp(const StatsPage()));
    await tester.pumpAndSettle();
    await _showPageItem(
      tester,
      find.byKey(const ValueKey('stats-novel-overview')),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('stats-novel-activity'))).dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const ValueKey('stats-novel-overview')))
            .dy,
      ),
    );
    await _tapVisible(tester, find.byIcon(Icons.tune_rounded));
    await _selectSettingsTab(tester, isNovel: true);
    final card = find.byKey(
      const ValueKey('stats-novel-section-settings-card'),
    );
    final tagsToggle = find
        .descendant(of: card, matching: find.byType(Switch))
        .last;
    await _tapVisible(tester, tagsToggle);
    expect(ReaderSettings().novelReadingStatsShowTags, isFalse);
    expect(ReaderSettings().readingStatsShowTags, isTrue);
    final radio = find
        .descendant(
          of: find.byKey(const ValueKey('stats-novel-chart-settings-card')),
          matching: find.byType(RadioListTile<int>),
        )
        .last;
    await _tapVisible(tester, radio);
    expect(ReaderSettings().novelReadingStatsChartStyle, 1);
    expect(ReaderSettings().readingStatsChartStyle, 0);
    Navigator.of(tester.element(find.byType(AppSheet))).pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stats-novel-overview')), findsOneWidget);
    expect(find.byKey(const ValueKey('stats-novel-tags')), findsNothing);
    // 漫画分区可能已被懒列表回收，先回到顶部再检查实际显示的卡片。
    final pageScroll = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const PageStorageKey('reading-stats')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    pageScroll.position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stats-comic-tags')), findsOneWidget);
  });

  testWidgets('clearing novels automatically reinitializes local history', (
    tester,
  ) async {
    await _seedBothStats();
    await NovelReadingStore().saveProgress(
      NovelReadingProgress(
        pathWord: 'old-book',
        name: '旧小说',
        cover: '',
        volumeId: 'v2',
        volumeName: '第二卷',
        chapterName: '当前章节',
        entryIndex: 8,
        updatedAt: DateTime(2026, 8, 3),
        readVolumeIds: const {'v1'},
      ),
    );
    await tester.pumpWidget(_buildTestApp(const StatsPage()));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byIcon(Icons.tune_rounded));
    await _selectSettingsTab(tester, isNovel: true);
    await _tapVisible(tester, find.byKey(const ValueKey('stats-novel-clear')));
    await _tapVisible(tester, find.widgetWithText(FilledButton, '清除'));
    final snapshot = await ReadingStats.load();
    expect(snapshot.novelMeta.keys, ['old-book']);
    expect(novelVolumesReadCount(snapshot), 2);
    expect(novelChaptersReadCount(snapshot), 1);
    expect(novelWordsReadCount(snapshot), 0);
    expect(snapshot.novelDaily, isEmpty);
    expect(pagesReadCount(snapshot), 12);
    final overview = find.byKey(const ValueKey('stats-novel-overview'));
    await _showPageItem(tester, overview);
    expect(
      find.descendant(of: overview, matching: find.text('1')),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: overview, matching: find.text('2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: overview, matching: find.text('0')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final novel in [false, true]) {
    testWidgets(
      'clearing ${novel ? 'novels' : 'manga'} requires confirmation and preserves the other domain',
      (tester) async {
        await _seedBothStats();
        await tester.pumpWidget(_buildTestApp(const StatsPage()));
        await tester.pumpAndSettle();
        await _tapVisible(tester, find.byIcon(Icons.tune_rounded));
        await _selectSettingsTab(tester, isNovel: novel);
        await _tapVisible(
          tester,
          find.byKey(ValueKey('stats-${novel ? 'novel' : 'comic'}-clear')),
        );
        expect(find.text(novel ? '清除轻小说阅读统计？' : '清除漫画阅读统计？'), findsOneWidget);
        expect(find.textContaining('不影响另一类统计'), findsOneWidget);
        await _tapVisible(tester, find.widgetWithText(TextButton, '取消'));
        expect(novelWordsReadCount(await ReadingStats.load()), 12345);
        await _tapVisible(tester, find.byIcon(Icons.tune_rounded));
        await _selectSettingsTab(tester, isNovel: novel);
        await _tapVisible(
          tester,
          find.byKey(ValueKey('stats-${novel ? 'novel' : 'comic'}-clear')),
        );
        await _tapVisible(tester, find.widgetWithText(FilledButton, '清除'));
        final snapshot = await ReadingStats.load();
        expect(comicsReadCount(snapshot), novel ? 1 : 0);
        expect(novelWordsReadCount(snapshot), novel ? 0 : 12345);
        expect(ReaderSettings().readingStatsEnabled, isTrue);
      },
    );
  }

  testWidgets('both domains stack at 320dp large text and fit wide screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _seedBothStats(novelWords: 123456789);
    await tester.runAsync(
      () => ReaderSettings().setNovelReadingStatsChartStyle(1),
    );
    await tester.pumpWidget(_buildTestApp(const StatsPage()));
    await tester.pumpAndSettle();
    final comicTop = tester.getTopLeft(_domain('comic')).dy;
    final scroll = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const PageStorageKey('reading-stats')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await _showPageItem(
      tester,
      find.byKey(const ValueKey('stats-novel-activity')),
    );
    await tester.pumpAndSettle();
    expect(_within('novel', find.text('123,456,789')), findsOneWidget);
    expect(
      tester.getTopLeft(_domain('novel')).dy + scroll.position.pixels,
      greaterThan(comicTop),
    );
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1200, 900);
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(_domain('novel')).dx,
      greaterThan(tester.getTopLeft(_domain('comic')).dx),
    );
    expect(
      tester.getTopLeft(_domain('novel')).dy,
      tester.getTopLeft(_domain('comic')).dy,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'settings tabs switch only panel contents and keep independent values',
    (tester) async {
      await _seedBothStats();
      await tester.pumpWidget(_buildTestApp(const StatsPage()));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.byIcon(Icons.tune_rounded));
      expect(
        tester
            .widget<SegmentedButton<bool>>(
              find.byKey(const ValueKey('stats-settings-tabs')),
            )
            .selected,
        {false},
      );
      expect(find.byKey(const ValueKey('stats-comic-visible')), findsOneWidget);
      expect(find.byKey(const ValueKey('stats-novel-visible')), findsNothing);
      await _selectSettingsTab(tester, isNovel: true);
      expect(find.byKey(const ValueKey('stats-novel-visible')), findsOneWidget);
      expect(find.byKey(const ValueKey('stats-comic-visible')), findsNothing);
      final radio = find
          .descendant(
            of: find.byKey(const ValueKey('stats-novel-chart-settings-card')),
            matching: find.byType(RadioListTile<int>),
          )
          .last;
      await _tapVisible(tester, radio);
      expect(ReaderSettings().novelReadingStatsChartStyle, 1);
      await _selectSettingsTab(tester, isNovel: false);
      expect(ReaderSettings().readingStatsChartStyle, 0);
      expect(
        tester
            .widget<RadioGroup<int>>(
              find.descendant(
                of: find.byKey(const ValueKey('stats-chart-settings-card')),
                matching: find.byType(RadioGroup<int>),
              ),
            )
            .groupValue,
        0,
      );
      await _selectSettingsTab(tester, isNovel: true);
      expect(
        tester
            .widget<RadioGroup<int>>(
              find.descendant(
                of: find.byKey(
                  const ValueKey('stats-novel-chart-settings-card'),
                ),
                matching: find.byType(RadioGroup<int>),
              ),
            )
            .groupValue,
        1,
      );
      expect(find.text('统计功能'), findsOneWidget);
      Navigator.of(tester.element(find.byType(AppSheet))).pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('stats-settings-tabs')), findsNothing);
      expect(_domain('comic'), findsOneWidget);
      await _showPageItem(tester, _domain('novel'));
      expect(_domain('novel'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('settings cards remain scrollable at narrow large-text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await ReaderSettings().setReadingStatsEnabled(true);
    await tester.pumpWidget(_buildTestApp(const StatsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsSection), findsNWidgets(4));
    expect(
      tester.getSize(find.byType(AppSheet)).height,
      lessThanOrEqualTo(448),
    );
    for (final isNovel in [false, true]) {
      await _selectSettingsTab(tester, isNovel: isNovel);
      final clear = find.byKey(
        ValueKey('stats-${isNovel ? 'novel' : 'comic'}-clear'),
      );
      await tester.ensureVisible(clear);
      await tester.pumpAndSettle();
      expect(clear.hitTestable(), findsOneWidget);
      expect(find.byType(SettingsSection), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'enabled state shows FAB; tapping opens settings sheet with 关闭/清除',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'reader_reading_stats_enabled': true,
        'reading_stats_v1':
            '{"comicMeta":{"comic-a":{"name":"漫画A","tags":[],"chapterImages":{"ch-1":1}}},"daily":{}}',
      });
      ReaderSettings().resetPrefsCache();
      await ReaderSettings().initFromPrefs(
        await SharedPreferences.getInstance(),
      );
      ReadingStats.reloadFromPrefs();

      await tester.pumpWidget(_buildTestApp(const StatsPage()));
      await tester.pumpAndSettle();

      // 右下角设置 FAB 存在；未开启态不应有 FAB
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);

      // 内联的关闭/清除按钮已移除，不应在主页直接可见
      expect(find.text('关闭'), findsNothing);
      expect(find.text('清除'), findsNothing);

      // 点击 FAB 弹出底部抽屉，里面有开关与清除操作
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();
      expect(find.text('阅读统计设置'), findsOneWidget);
      expect(find.text('统计功能'), findsOneWidget);
      expect(find.text('清除'), findsOneWidget);
      expect(find.byType(AppSheet), findsOneWidget);
      expect(find.byType(SettingsSection), findsNWidgets(4));
      expect(find.byKey(const ValueKey('stats-settings-tabs')), findsOneWidget);
      expect(find.byKey(const ValueKey('stats-novel-visible')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('stats-chart-settings-card')),
          matching: find.byType(RadioGroup<int>),
        ),
        findsOneWidget,
      );
      final clear = find.byKey(const ValueKey('stats-comic-clear'));
      await tester.ensureVisible(clear);
      await tester.pumpAndSettle();
      expect(clear.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
