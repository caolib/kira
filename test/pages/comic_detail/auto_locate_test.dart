import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kira/api/api_client.dart';
import 'package:kira/api/manga/manga_api.dart';
import 'package:kira/models/chapter.dart';
import 'package:kira/models/comic.dart' hide Theme;
import 'package:kira/models/reader_settings.dart';
import 'package:kira/pages/comic_detail_page.dart';
import 'package:kira/routing/app_router.dart';
import 'package:kira/utils/download_manager.dart';
import 'package:kira/utils/reading_history.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_helpers.dart';
import '../search_page_test_support.dart' show installSearchImageCache;

const _pathWord = 'test-comic';
const _downloadedPathWord = 'downloaded-test-comic';
const _enable = '开启自动定位上次阅读章节';
const _backToTop = '回到顶部';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

class _Manga extends Fake implements MangaApi {
  _Manga({this.total = 200, this.hasGroup = true, this.brief});

  final int total;
  final bool hasGroup;
  final String? brief;
  final offsets = <int>[];

  @override
  Future<Comic> getComicDetail(String pathWord) async => Comic(
    pathWord: pathWord,
    name: '测试漫画',
    cover: '',
    brief: brief,
    groups: hasGroup
        ? {'default': ComicGroup(pathWord: 'default', count: total, name: '默认')}
        : null,
  );

  @override
  Future<Map<String, dynamic>> getComicQuery(String pathWord) async => {};

  @override
  Future<({List<Chapter> list, int total})> getChapterList(
    String pathWord, {
    String group = 'default',
    int limit = 100,
    int offset = 0,
  }) async {
    offsets.add(offset);
    return (
      list: [
        for (var i = offset; i < total && i < offset + limit; i++)
          Chapter(uuid: 'chapter-$i', index: i, name: '章节 $i'),
      ],
      total: total,
    );
  }
}

class _Client extends Fake implements ApiClient {
  _Client(this.manga);

  @override
  final MangaApi manga;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ApiClient originalApi;
  final settings = ReaderSettings();

  setUpAll(() async {
    final originalPaths = PathProviderPlatform.instance;
    final directory = await Directory.systemTemp.createTemp('chapter-locate-');
    addTearDown(() async {
      PathProviderPlatform.instance = originalPaths;
      await directory.delete(recursive: true);
    });
    PathProviderPlatform.instance = _Paths(directory.path);
    SharedPreferences.setMockInitialValues({});
    final downloads = await DownloadManager.resolveRootDirectory(
      customPath: null,
      defaultParentPath: directory.path,
    );
    await downloads.create(recursive: true);
    await File('${downloads.path}/manifest.json').writeAsString(
      jsonEncode({
        'comics': {
          _downloadedPathWord: {
            'chapter-0': DownloadedChapterSummary(
              chapterUuid: 'chapter-0',
              chapterName: '章节 0',
              pageCount: 1,
              savedAt: DateTime.utc(2026),
            ).toJson(),
          },
        },
      }),
    );
    await DownloadManager().init();
    installSearchImageCache();
  });

  setUp(() async {
    setupSecureCredentialStoreForTest();
    originalApi = ApiClient();
    SharedPreferences.setMockInitialValues({});
    await settings.initFromPrefs(await SharedPreferences.getInstance());
  });

  tearDown(() {
    ApiClient.setTestInstance(originalApi);
    settings.resetPrefsCache();
    teardownSecureCredentialStoreForTest();
  });

  Future<void> readChapter(int index, {int listPage = 0}) =>
      ReadingHistory.save(
        pathWord: _pathWord,
        chapterUuid: 'chapter-$index',
        chapterName: '章节 $index',
        chapterListPage: listPage,
      );

  Finder card(int index) => find.widgetWithText(ChapterCard, '章节 $index');

  void expectHighlight(WidgetTester tester, int index) {
    final item = card(index);
    expect(item.hitTestable(), findsOneWidget);
    final chapter = tester.widget<ChapterCard>(item);
    expect(chapter.isLastRead, isTrue);
    expect(chapter.isLocateHighlighted, isTrue);
  }

  void screen(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> openDetail(
    WidgetTester tester,
    _Manga manga, {
    bool reduceMotion = false,
    Brightness brightness = Brightness.light,
    Widget child = const ComicDetailPage(pathWord: _pathWord),
  }) async {
    ApiClient.setTestInstance(_Client(manga));
    await tester.pumpWidget(
      wrapWithApp(
        child,
        wrapInScaffold: false,
        theme: ThemeData(brightness: brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('默认关闭，开启后按当前倒序定位离屏章节，高亮 1.5 秒', (tester) async {
    screen(tester, const Size(375, 667));
    final manga = _Manga(total: 100);
    await readChapter(2);
    await openDetail(tester, manga);
    expect(find.byTooltip(_enable), findsOneWidget);
    expect(tester.widget<ChapterCard>(card(2)).isLocateHighlighted, isFalse);

    await tester.tap(find.byTooltip('正序（旧→新）'));
    await tester.pumpAndSettle();
    expect(card(2), findsNothing);
    await tester.tap(find.byTooltip(_enable));
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 16));

    expect(settings.autoLocateLastReadChapter, isTrue);
    expectHighlight(tester, 2);
    expect(manga.offsets, [0]);
    await tester.pump(const Duration(seconds: 1));
    expectHighlight(tester, 2);
    await tester.pump(const Duration(milliseconds: 500));
    final chapter = tester.widget<ChapterCard>(card(2));
    expect(chapter.isLocateHighlighted, isFalse);
    expect(chapter.isLastRead, isTrue);
  });

  testWidgets('进入横屏详情，仅滚动右侧章节栏并保留历史分页', (tester) async {
    screen(tester, const Size(640, 360));
    final manga = _Manga();
    await settings.setAutoLocateLastReadChapter(true);
    await readChapter(199, listPage: 1);
    await openDetail(
      tester,
      manga,
      reduceMotion: true,
      brightness: Brightness.dark,
    );

    expectHighlight(tester, 199);
    final scrollables = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .where((state) => state.position.axis == Axis.vertical)
        .toList();
    expect(scrollables, hasLength(2));
    expect(scrollables.first.position.pixels, 0);
    expect(scrollables.last.position.pixels, greaterThan(0));
    expect(find.byTooltip(_backToTop), findsNothing);
    expect(manga.offsets, [100]);
  });

  testWidgets('从阅读器返回定位当前页，跨页则不滚动、不请求', (tester) async {
    screen(tester, const Size(375, 667));
    final manga = _Manga();
    await settings.setAutoLocateLastReadChapter(true);
    await readChapter(0);
    var nextRead = 90;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const ComicDetailPage(pathWord: _pathWord),
        ),
        GoRoute(
          path: '/reader/:pathWord/:chapterUuid',
          name: AppRoutes.reader,
          builder: (context, _) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () {
                  readChapter(nextRead, listPage: nextRead ~/ 100);
                  context.pop();
                },
                child: const Text('返回详情'),
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await openDetail(tester, manga, child: Router.withConfig(config: router));

    await tester.tap(card(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('返回详情'));
    await tester.pumpAndSettle();
    expectHighlight(tester, 90);
    expect(manga.offsets, [0]);

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    final before = position.pixels;
    nextRead = 101;
    await tester.tap(card(90));
    await tester.pumpAndSettle();
    await tester.tap(find.text('返回详情'));
    await tester.pumpAndSettle();
    expect(position.pixels, before);
    expect(card(101), findsNothing);
    expect(tester.widget<ChapterCard>(card(90)).isLocateHighlighted, isFalse);
    expect(manga.offsets, [0]);
  });

  testWidgets('竖屏拖动章节即收起封面简介，章节工具栏吸顶且不自动翻页', (tester) async {
    screen(tester, const Size(375, 667));
    const brief = '测试漫画简介';
    final manga = _Manga(brief: brief);
    await openDetail(tester, manga);

    final view = find.byType(CustomScrollView);
    expect(view, findsOneWidget);
    final groups = find.byType(SegmentedButton<String>);
    expect(tester.getSize(groups).width, tester.getSize(view).width - 32);
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    final scrollbar = tester.widget<RawScrollbar>(find.byType(RawScrollbar));
    expect(scrollbar.thumbVisibility, isNot(true));
    expect(scrollbar.thickness, 3);
    final controls = find.byTooltip(_enable);
    final initialControlsTop = tester.getTopLeft(controls).dy;
    final initialBriefTop = tester.getTopLeft(find.text(brief)).dy;

    await tester.timedDrag(
      card(0),
      const Offset(0, -65),
      const Duration(milliseconds: 400),
    );
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
    expect(tester.getTopLeft(find.text(brief)).dy, lessThan(initialBriefTop));
    expect(tester.getTopLeft(controls).dy, lessThan(initialControlsTop));
    expect(manga.offsets, [0]);

    await tester.timedDrag(
      card(2),
      const Offset(0, -460),
      const Duration(milliseconds: 500),
    );
    await tester.pumpAndSettle();
    expect(find.text(brief).hitTestable(), findsNothing);
    expect(controls.hitTestable(), findsOneWidget);
    expect(card(0).hitTestable(), findsNothing);
    expect(manga.offsets, [0]);
    final pinnedTop = tester.getTopLeft(controls).dy;

    await tester.tap(find.widgetWithText(FilledButton, '2'));
    await tester.pumpAndSettle();
    expect(card(100).hitTestable(), findsOneWidget);
    expect(tester.getTopLeft(controls).dy, closeTo(pinnedTop, 0.01));
    expect(manga.offsets, [0, 100]);
  });

  for (final mouseWheel in [false, true]) {
    testWidgets('反向${mouseWheel ? '滚轮' : '拖动'}时漫画信息不提前显示', (tester) async {
      screen(tester, const Size(375, 667));
      const brief = '测试漫画简介';
      final manga = _Manga(brief: brief);
      await openDetail(tester, manga);
      final view = find.byType(CustomScrollView);
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      position.jumpTo(550);
      await tester.pumpAndSettle();
      final synopsis = find.text(brief);
      expect(synopsis.hitTestable(), findsNothing);

      final start = tester.getCenter(view) + const Offset(0, 80);
      if (mouseWheel) {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: start,
            scrollDelta: const Offset(0, -60),
          ),
        );
      } else {
        final drag = await tester.startGesture(start);
        await drag.moveBy(const Offset(0, 30));
        await drag.moveBy(const Offset(0, 55));
        await tester.pump();
        expect(synopsis.hitTestable(), findsNothing);
        await drag.up();
      }
      await tester.pumpAndSettle();
      expect(position.pixels, inExclusiveRange(300, 550));
      expect(synopsis.hitTestable(), findsNothing);

      position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(synopsis.hitTestable(), findsOneWidget);
      expect(manga.offsets, [0]);
    });
  }

  for (final reduceMotion in [false, true]) {
    testWidgets('封面简介滚出后可回顶（减少动画：$reduceMotion）', (tester) async {
      screen(tester, const Size(375, 667));
      const brief = '测试漫画简介';
      final manga = _Manga(brief: brief);
      await openDetail(tester, manga, reduceMotion: reduceMotion);

      final backToTop = find.byTooltip(_backToTop);
      final synopsis = find.text(brief);
      final view = find.byType(CustomScrollView);
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      final infoEnd =
          tester.getBottomLeft(synopsis).dy - tester.getTopLeft(view).dy;
      expect(backToTop, findsNothing);

      position.jumpTo(infoEnd - 8);
      await tester.pumpAndSettle();
      expect(backToTop, findsNothing);

      position.jumpTo(infoEnd + 300);
      await tester.pumpAndSettle();
      expect(synopsis.hitTestable(), findsNothing);
      expect(backToTop.hitTestable(), findsOneWidget);
      expect(find.byTooltip('下载中心'), findsNothing);

      await tester.tap(backToTop);
      if (reduceMotion) {
        expect(position.pixels, position.minScrollExtent);
      }
      await tester.pumpAndSettle();
      expect(position.pixels, position.minScrollExtent);
      expect(synopsis.hitTestable(), findsOneWidget);
      expect(backToTop, findsNothing);
      expect(manga.offsets, [0]);
    });
  }

  testWidgets('已有下载时标题栏可打开下载中心，底部不再显示下载入口', (tester) async {
    screen(tester, const Size(375, 667));
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) =>
              const ComicDetailPage(pathWord: _downloadedPathWord),
        ),
        GoRoute(
          path: '/download-center',
          name: AppRoutes.downloadCenter,
          builder: (_, _) => const Scaffold(body: Text('下载中心测试页')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await openDetail(
      tester,
      _Manga(),
      child: Router.withConfig(config: router),
    );

    final downloads = find.byTooltip('下载中心');
    expect(downloads, findsOneWidget);
    expect(
      find.ancestor(of: downloads, matching: find.byType(AppBar)),
      findsOneWidget,
    );
    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.tap(downloads);
    await tester.pumpAndSettle();
    expect(find.text('下载中心测试页'), findsOneWidget);
  });

  testWidgets('短目录不产生额外滚动，无分组且不分页时隐藏两种按钮', (tester) async {
    screen(tester, const Size(375, 667));
    await openDetail(tester, _Manga(total: 1, hasGroup: false));
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    expect(position.maxScrollExtent, 0);
    expect(tester.getSize(card(0)).height, chapterTileExtent(1));
    expect(find.byTooltip(_backToTop), findsNothing);
    expect(find.byTooltip('正序（旧→新）'), findsNothing);
    expect(find.byTooltip(_enable), findsNothing);
  });
}
