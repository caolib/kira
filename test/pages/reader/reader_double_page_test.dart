import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/api/api_client.dart';
import 'package:kira/api/manga/manga_api.dart';
import 'package:kira/models/chapter.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/reader_page.dart';
import 'package:kira/utils/bookmark_store.dart';
import 'package:kira/utils/double_page_layout.dart';
import 'package:kira/utils/reading_history.dart';
import 'package:kira/widgets/pinch_zoomable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_helpers.dart';

class _ReaderApi extends Fake implements ApiClient {
  _ReaderApi(this.manga);

  @override
  final MangaApi manga;
}

class _ReaderMangaApi extends Fake implements MangaApi {
  _ReaderMangaApi(this.chapters, {this.failing = const {}});

  final Map<String, ChapterDetail> chapters;
  final Set<String> failing;
  final requestedChapters = <String>[];

  @override
  Future<ChapterDetail> getChapterDetail(
    String pathWord,
    String chapterUuid, {
    bool forceRefresh = false,
  }) async {
    requestedChapters.add(chapterUuid);
    if (failing.contains(chapterUuid)) {
      throw Exception('boom');
    }
    return chapters[chapterUuid]!;
  }
}

ChapterDetail _chapter(
  String uuid, {
  String? prev,
  String? next,
  int pages = 1,
  bool downloaded = true,
}) {
  return ChapterDetail(
    uuid: uuid,
    index: 0,
    name: uuid,
    prev: prev,
    next: next,
    contents: List.filled(pages, File('assets/ic_launcher.png').absolute.path),
    isDownloaded: downloaded,
  );
}

/// 当前上屏的 PageView 控制器（分组变化时会换新控制器，必须每次重新取）。
PageController _controller(WidgetTester tester) {
  return tester.widget<PageView>(find.byType(PageView)).controller!;
}

Future<void> _pumpUntilPageView(WidgetTester tester) async {
  for (var attempt = 0; attempt < 10; attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    if (find.byType(PageView).evaluate().isNotEmpty) return;
  }
  fail('阅读器没有进入翻页模式');
}

Future<UserManager> _openDoublePageReader(
  WidgetTester tester, {
  required Map<String, ChapterDetail> chapters,
  String chapterUuid = 'only',
  int initialPage = 1,
  bool coverAlone = true,
  int direction = 0,
  Set<String> failing = const {},
  bool doublePage = true,
  _ReaderMangaApi? manga,
}) async {
  ApiClient.setTestInstance(
    _ReaderApi(manga ?? _ReaderMangaApi(chapters, failing: failing)),
  );
  final user = UserManager();
  await user.init();
  await user.setReaderMode(1);
  await user.setReaderScrollDirection(direction);
  await user.setReaderContinuousReading(true);
  await user.setReaderDoublePage(doublePage);
  await user.setReaderDoublePageCoverAlone(coverAlone);

  await tester.pumpWidget(
    wrapWithApp(
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ReaderPage(
                pathWord: 'reader-double-test',
                comicName: '测试漫画',
                group: 'default',
                chapterUuid: chapterUuid,
                chapterName: chapterUuid,
                initialPage: initialPage,
              ),
            ),
          ),
          child: const Text('打开阅读器'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开阅读器'));
  await _pumpUntilPageView(tester);
  expect(find.byType(ReaderPage), findsOneWidget);
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pumpAndSettle();
  return user;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient originalApi;
  late Directory tempDirectory;
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');

  setUpAll(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'kira-reader-double-',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (_) async => tempDirectory.path,
        );
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await tempDirectory.delete(recursive: true);
  });

  setUp(() async {
    await ReadingHistory.flush();
    SharedPreferences.setMockInitialValues({});
    setupSecureCredentialStoreForTest();
    BookmarkStore().debugReset();
    originalApi = ApiClient();
    UserManager().reader.resetPrefsCache();
    await UserManager().reader.initFromPrefs(
      await SharedPreferences.getInstance(),
    );
  });

  tearDown(() async {
    await ReadingHistory.flush();
    BookmarkStore().debugReset();
    ApiClient.setTestInstance(originalApi);
    teardownSecureCredentialStoreForTest();
  });

  testWidgets('非首页续读：initialPage 定位到所属跨页（首图单页）', (tester) async {
    // 20 页 + 首图单页 → 跨页分组 [0] [1,2] [3,4] [5,6] [7,8] [9,10] …；
    // 第 11 页（下标 10）属于跨页 5，跨页首页是第 10 页。
    await _openDoublePageReader(
      tester,
      chapters: {'only': _chapter('only', pages: 20)},
      initialPage: 11,
    );

    expect(_controller(tester).page, 5);
    final slider = tester.widget<Slider>(find.byType(Slider));
    // 页码、进度条与书签口径统一取跨页首页：11 → 10。
    expect(slider.value, 10);
  });

  testWidgets('关闭「首图单独成页」后画面与页码同步重定位', (tester) async {
    // 20 页 + 首图单页，第 4 页（下标 3）在 [3,4] → 跨页 2。
    final user = await _openDoublePageReader(
      tester,
      chapters: {'only': _chapter('only', pages: 20)},
      initialPage: 4,
    );
    expect(_controller(tester).page, 2);

    // 取消首图单页后 [0,1] [2,3]：同一个第 4 页落在跨页 1，跨页首页是第 3 页。
    await user.setReaderDoublePageCoverAlone(false);
    await tester.pumpAndSettle();

    expect(_controller(tester).page, 1);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('滑块选择同一跨页第二页时按跨页首页记录页码', (tester) async {
    await _openDoublePageReader(
      tester,
      chapters: {'only': _chapter('only', pages: 20)},
      coverAlone: false,
    );
    expect(tester.widget<Slider>(find.byType(Slider)).value, 1);

    // 无首图单页：跨页是 [0,1] [2,3] …。滑到第 4 页（下标 3）仍属跨页 1，
    // 页码、书签与历史都必须记成跨页首页的第 3 页，而不是 4。
    tester.widget<Slider>(find.byType(Slider)).onChanged!(4);
    await tester.pumpAndSettle();

    expect(_controller(tester).page, 1);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 3);
  });

  test('横向大图独占跨页，不影响前后单页配对', () {
    // 5 页，第 2 页（下标 1）本身已是横向跨页大图。
    final layout = DoublePageLayout.fromPageCounts([5], widePages: {(0, 1)});

    expect(layout.spreadCount, 4);
    expect(layout.pagesInSpread(0).single.imageIndex, 0);
    expect(layout.pagesInSpread(1).single.imageIndex, 1);
    // 大图之后的单页继续两两配对，不会因为大图插入而错位。
    expect(
      [for (final page in layout.pagesInSpread(2)) page.imageIndex],
      [2, 3],
    );
    expect(layout.pagesInSpread(3).single.imageIndex, 4);
    expect(layout.spreadIndexOf(0, 4), 3);
  });

  testWidgets('刷新章节后仍停在原跨页', (tester) async {
    await _openDoublePageReader(
      tester,
      chapters: {'only': _chapter('only', pages: 20)},
      initialPage: 11,
    );
    expect(_controller(tester).page, 5);

    // 轻点屏幕中间唤出工具栏（单击要等双击超时后才回调）。
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    // 刷新沿用 previousPage，双页下必须换算回同一个跨页。
    expect(_controller(tester).page, 5);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 10);
  });

  testWidgets('跨页内两根手指可以捏合缩放并锁定翻页', (tester) async {
    await _openDoublePageReader(
      tester,
      chapters: {'only': _chapter('only', pages: 20)},
    );
    // 两页并排时整组共用一个缩放手势容器，否则左右页各拿一根指针、无法识别。
    final pinch = find.byType(PinchZoomable);
    expect(pinch, findsWidgets);

    final center = tester.getCenter(find.byType(PinchZoomable).first);
    final left = await tester.startGesture(
      center + const Offset(-60, 0),
      pointer: 1,
    );
    final right = await tester.startGesture(
      center + const Offset(60, 0),
      pointer: 2,
    );
    await left.moveBy(const Offset(-60, 0));
    await right.moveBy(const Offset(60, 0));
    await tester.pump();
    await left.up();
    await right.up();
    await tester.pumpAndSettle();

    // 放大后翻页手势被锁住，避免缩放过程中滑走。
    expect(
      tester.widget<PageView>(find.byType(PageView)).physics,
      isA<NeverScrollableScrollPhysics>(),
    );
  });

  testWidgets('下一话加载失败时停留在当前跨页', (tester) async {
    final manga = _ReaderMangaApi(
      {
        'only': _chapter('only', next: 'boom', pages: 2),
        'boom': _chapter('boom', pages: 2, downloaded: false),
      },
      failing: {'boom'},
    );
    await _openDoublePageReader(
      tester,
      chapters: const {},
      manga: manga,
      failing: {'boom'},
    );

    final pageViewSize = tester.getSize(find.byType(PageView));
    final rightTap = Offset(
      pageViewSize.width * 0.9,
      pageViewSize.height * 0.5,
    );
    // 图片手势同时注册了双击，单击要等双击超时后才回调，须显式推进时间。
    await tester.tapAt(rightTap);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(_controller(tester).page, 1);

    // 再往前翻：加载下一话失败，必须留在原跨页，不能跳回本章首页。
    await tester.tapAt(rightTap);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(manga.requestedChapters, contains('boom'));
    expect(_controller(tester).page, 1);
    expect(find.byType(ReaderPage), findsOneWidget);
  });
}
