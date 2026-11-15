import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/api/novel/novel_api.dart';
import 'package:kira/models/novel.dart';
import 'package:kira/models/novel_reader_settings.dart';
import 'package:kira/models/novel_reading_progress.dart';
import 'package:kira/models/reader_settings.dart';
import 'package:kira/pages/novel_reader/novel_reader_document.dart';
import 'package:kira/pages/novel_reader/novel_reader_page_view.dart';
import 'package:kira/pages/novel_reader/novel_reader_settings_sheet.dart';
import 'package:kira/pages/novel_reader/novel_reader_viewport.dart';
import 'package:kira/pages/novel_reader/novel_visible_text_range.dart';
import 'package:kira/pages/novel_reader_page.dart';
import 'package:kira/providers/novel_providers.dart';
import 'package:kira/repositories/novel_reader_source.dart';
import 'package:kira/repositories/novel_repository.dart';
import 'package:kira/theme/novel_reader_theme.dart';
import 'package:kira/utils/novel_bookmark_store.dart';
import 'package:kira/utils/novel_reading_store.dart';
import 'package:kira/utils/reading_stats.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

class _Api implements NovelApi {
  @override
  bool get hasCopyToken => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected network access: ${invocation.memberName}');
}

class _Repository implements NovelRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected repository access: ${invocation.memberName}',
  );
}

class _History implements NovelReadingStore {
  final writes = <NovelReadingProgress>[];
  NovelReadingProgress? saved;

  @override
  Future<NovelReadingProgress?> readProgress(String pathWord) async => saved;

  @override
  Future<void> saveProgress(NovelReadingProgress progress) async {
    writes.add(progress);
    saved = progress;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Source implements NovelReaderSource {
  _Source(this.contents, {this.localOnly = false, this.imageBytes});

  final Future<List<int>>? imageBytes;

  final Map<String, NovelVolumeContent> contents;
  final loads = <String>[];
  @override
  final bool localOnly;

  @override
  Future<List<NovelVolume>> loadVolumes(String pathWord) async =>
      contents.values.map((content) => content.detail.volume).toList();

  @override
  Future<NovelVolumeDetail> loadVolumeDetail(
    String pathWord,
    String volumeId,
  ) async => contents[volumeId]!.detail;

  @override
  Future<NovelVolumeContent?> loadContent(
    String pathWord,
    String volumeId, {
    bool refresh = false,
    bool cachedOnly = false,
  }) async {
    loads.add(volumeId);
    return contents[volumeId];
  }

  @override
  Future<List<int>> loadImageBytes(
    String pathWord,
    String volumeId,
    String url,
  ) async {
    if (imageBytes case final pending?) return pending;
    return base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=',
    );
  }
}

NovelReaderEntry _entry(
  int index,
  List<String> paragraphs, {
  String name = '',
}) => NovelReaderEntry(
  entryIndex: index,
  entry: NovelContentEntry(name: name, contentType: 1),
  paragraphs: paragraphs,
);

NovelVolumeContent _content(
  List<NovelReaderEntry> entries, {
  String id = 'v1',
  String? next,
}) => NovelVolumeContent(
  detail: NovelVolumeDetail(
    book: const NovelBook(
      pathWord: 'book',
      name: '本地小说',
      themes: [NovelTag(name: '幻想', pathWord: 'fantasy')],
    ),
    volume: NovelVolume(
      id: id,
      name: id,
      bookPathWord: 'book',
      next: next,
      contents: entries.map((entry) => entry.entry).toList(),
    ),
  ),
  entries: entries,
);

Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 25));
  }
  await tester.pumpAndSettle(const Duration(milliseconds: 25));
}

Future<ReadingStatsSnapshot> _stats(WidgetTester tester) async {
  await _settle(tester);
  return (await tester.runAsync(ReadingStats.load))!;
}

Future<void> _mount(
  WidgetTester tester,
  _Source source, {
  NovelReaderSettings settings = const NovelReaderSettings(keepScreenOn: false),
  String volume = 'v1',
  int initialEntry = 0,
  int initialParagraph = 0,
  double alignment = 0,
  bool enabled = true,
  _History? history,
  bool resume = false,
}) async {
  await tester.runAsync(() async {
    await ReaderSettings().setReadingStatsEnabled(enabled);
    await settings.save();
  });
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        novelApiProvider.overrideWithValue(_Api()),
        novelRepositoryProvider.overrideWithValue(_Repository()),
        novelReadingStoreProvider.overrideWithValue(history ?? _History()),
        novelBookmarkStoreProvider.overrideWithValue(
          NovelBookmarkStore.forTesting(prefs: Future.value(prefs)),
        ),
      ],
      child: wrapWithApp(
        NovelReaderPage(
          pathWord: 'book',
          volumeId: volume,
          initialEntryIndex: initialEntry,
          initialParagraphIndex: initialParagraph,
          initialParagraphAlignment: alignment,
          source: source,
          resume: resume,
        ),
        wrapInScaffold: false,
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _remove(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await _settle(tester);
  await tester.runAsync(ReadingStats.flush);
}

Future<void> _jump(WidgetTester tester, double item) async {
  final slider = tester.widget<Slider>(
    find.byKey(const ValueKey('novel-reader-progress')),
  );
  slider.onChanged!(item);
  slider.onChangeEnd!(item);
  await _settle(tester);
}

Future<void> _changeSettings(
  WidgetTester tester,
  NovelReaderSettings settings,
) async {
  final button = tester.widget<IconButton>(
    find.byKey(const ValueKey('novel-reader-settings')),
  );
  button.onPressed!();
  await _settle(tester);
  tester
      .widget<NovelReaderSettingsSheet>(find.byType(NovelReaderSettingsSheet))
      .onChanged(settings);
  await _settle(tester);
  Navigator.of(tester.element(find.byType(NovelReaderSettingsSheet))).pop();
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    setupSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({});
    await ReaderSettings().initFromPrefs(await SharedPreferences.getInstance());
    ReadingStats.reloadFromPrefs();
    ReadingStats.setEnabledGate(() => ReaderSettings().readingStatsEnabled);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('io.github.caolib.kira/volume'),
          (_) async => null,
        );
  });

  tearDown(() async {
    await ReadingStats.flush();
    ReadingStats.reloadFromPrefs();
    teardownSecureCredentialStoreForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('io.github.caolib.kira/volume'),
          null,
        );
  });

  for (final mode in NovelReaderMode.values) {
    testWidgets('$mode 首屏只统计可见正文，跳章不计中间章', (tester) async {
      final source = _Source({
        'v1': _content([
          for (var chapter = 0; chapter < 3; chapter++)
            _entry(chapter, List.filled(40, '甲乙丙丁戊己庚辛壬癸')),
        ]),
      });
      await _mount(
        tester,
        source,
        settings: NovelReaderSettings(mode: mode, keepScreenOn: false),
      );
      final first = await _stats(tester);
      final novel = first.novelMeta['book']!;
      expect(novel.totalWords, greaterThan(0));
      expect(novel.totalWords, lessThan(400));
      expect(novel.chapters['v1']!.keys, ['0']);
      // 翻页定位到章首可能同屏显示上章尾段，选章中避免把可见尾段误判为跳过。
      await _jump(tester, 100);
      final after = await _stats(tester);
      expect(
        after.novelMeta['book']!.chapters['v1']!.keys,
        unorderedEquals(['0', '2']),
      );
      expect(tester.takeException(), isNull);
      await _remove(tester);
    });

    testWidgets('$mode 离线短正文回看、改字号与切换模式不重复', (tester) async {
      final source = _Source({
        'v1': _content([
          _entry(3, ['甲乙丙丁', '戊己庚辛']),
        ]),
      }, localOnly: true);
      var settings = NovelReaderSettings(mode: mode, keepScreenOn: false);
      await _mount(tester, source, settings: settings);
      expect((await _stats(tester)).novelMeta['book']!.totalWords, 8);
      await _jump(tester, 0);
      settings = settings.copyWith(fontSize: 24);
      await _changeSettings(tester, settings);
      settings = settings.copyWith(
        mode: mode == NovelReaderMode.paged
            ? NovelReaderMode.scroll
            : NovelReaderMode.paged,
      );
      await _changeSettings(tester, settings);
      final novel = (await _stats(tester)).novelMeta['book']!;
      expect(novel.totalWords, 8);
      expect(novel.name, '本地小说');
      expect(novel.tags, ['幻想']);
      expect(source.loads, ['v1']);
      await _remove(tester);
    });

    testWidgets('$mode 空章节、空白与图片没有阅读量', (tester) async {
      await _mount(
        tester,
        _Source({
          'v1': _content([
            _entry(0, [], name: '空章节标题不统计'),
            _entry(1, [' ', '\t', '　']),
            const NovelReaderEntry(
              entryIndex: 2,
              entry: NovelContentEntry(
                name: '插图',
                contentType: 2,
                content: 'local.png',
              ),
            ),
          ]),
        }),
        settings: NovelReaderSettings(mode: mode, keepScreenOn: false),
      );
      expect((await _stats(tester)).novelMeta, isEmpty);
      await _remove(tester);
    });
  }

  testWidgets('首次启用先初始化旧小说，再采集新书的可见正文', (tester) async {
    await tester.runAsync(
      () => NovelReadingStore().saveProgress(
        NovelReadingProgress(
          pathWord: 'old-book',
          name: '旧小说',
          cover: '',
          volumeId: 'old-v2',
          volumeName: '第二卷',
          chapterName: '旧章节',
          entryIndex: 5,
          updatedAt: DateTime(2026, 8, 3),
          readVolumeIds: const {'old-v1'},
        ),
      ),
    );
    await _mount(
      tester,
      _Source({
        'v1': _content([
          _entry(0, ['甲乙丙丁']),
        ]),
      }),
    );
    final snapshot = await _stats(tester);
    expect(snapshot.novelMeta.keys, unorderedEquals(['old-book', 'book']));
    expect(snapshot.novelMeta['old-book']!.totalWords, 0);
    expect(snapshot.novelMeta['book']!.totalWords, 4);
    expect(novelVolumesReadCount(snapshot), 3);
    expect(snapshot.novelDaily.values.single, 4);
    await _remove(tester);
  });

  testWidgets('禁用不包裹正文，启用补采当前屏', (tester) async {
    await _mount(
      tester,
      _Source({
        'v1': _content([
          _entry(0, ['甲乙丙丁']),
        ]),
      }),
      enabled: false,
    );
    expect(find.byType(NovelTextRangeProbe), findsNothing);
    expect((await _stats(tester)).novelMeta, isEmpty);
    await tester.runAsync(() => ReaderSettings().setReadingStatsEnabled(true));
    await _settle(tester);
    expect(find.byType(NovelTextRangeProbe), findsOneWidget);
    expect((await _stats(tester)).novelMeta['book']!.totalWords, 4);
    await _remove(tester);
  });

  testWidgets('分页恢复只计目标页，不计前缀分页或后台生成页', (tester) async {
    final history = _History()
      ..saved = NovelReadingProgress(
        pathWord: 'book',
        name: '小说',
        cover: '',
        volumeId: 'v1',
        volumeName: 'v1',
        chapterName: '',
        entryIndex: 2,
        paragraphIndex: 20,
        updatedAt: DateTime(2025),
      );
    await _mount(
      tester,
      _Source({
        'v1': _content([
          for (var i = 0; i < 4; i++) _entry(i, List.filled(45, '甲乙丙丁')),
        ]),
      }),
      settings: const NovelReaderSettings(
        mode: NovelReaderMode.paged,
        keepScreenOn: false,
      ),
      history: history,
      resume: true,
    );
    final novel = (await _stats(tester)).novelMeta['book']!;
    expect(novel.chapters['v1']!.keys, ['2']);
    expect(novel.totalWords, lessThan(180));
    await tester.pump(const Duration(seconds: 2));
    expect(
      (await _stats(tester)).novelMeta['book']!.totalWords,
      novel.totalWords,
    );
    expect(history.writes.every((p) => p.entryIndex == 2), isTrue);
    await _remove(tester);
  });

  testWidgets('跨卷同索引独立记录，预取下一卷不算阅读', (tester) async {
    final source = _Source({
      'v1': _content([
        _entry(0, ['甲乙丙丁']),
      ], next: 'v2'),
      'v2': _content([
        _entry(0, ['戊己庚辛']),
      ], id: 'v2'),
    });
    await _mount(tester, source);
    expect((await _stats(tester)).novelMeta['book']!.chapters.keys, ['v1']);
    final viewport = tester.widget<NovelReaderViewport>(
      find.byType(NovelReaderViewport),
    );
    viewport.onApproachEnd!();
    await _settle(tester);
    expect(source.loads, contains('v2'));
    expect((await _stats(tester)).novelMeta['book']!.totalWords, 4);
    final next = tester.widget<IconButton>(
      find.byKey(const ValueKey('novel-reader-next')),
    );
    next.onPressed!();
    await _settle(tester);
    final novel = (await _stats(tester)).novelMeta['book']!;
    expect(novel.totalWords, 8);
    expect(novel.chapters.keys, unorderedEquals(['v1', 'v2']));
    await _remove(tester);
  });

  testWidgets('退后台后跳转不计，恢复补采并保留历史写入', (tester) async {
    final history = _History();
    await _mount(
      tester,
      _Source({
        'v1': _content([
          _entry(0, List.filled(40, '甲乙丙丁')),
          _entry(1, List.filled(40, '戊己庚辛')),
        ]),
      }),
      history: history,
    );
    final before = (await _stats(tester)).novelMeta['book']!.totalWords;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await _settle(tester);
    expect(history.writes, isNotEmpty);
    await _jump(tester, 40);
    expect((await _stats(tester)).novelMeta['book']!.totalWords, before);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);
    expect(
      (await _stats(tester)).novelMeta['book']!.chapters['v1']!.keys,
      unorderedEquals(['0', '1']),
    );
    await _remove(tester);
  });

  testWidgets('其他路由覆盖时不计底层跳转，返回后补采', (tester) async {
    await _mount(
      tester,
      _Source({
        'v1': _content([
          _entry(0, List.filled(40, '甲乙丙丁')),
          _entry(1, List.filled(40, '戊己庚辛')),
        ]),
      }),
    );
    final initial = (await _stats(tester)).novelMeta['book']!.totalWords;
    final viewport = tester.widget<NovelReaderViewport>(
      find.byType(NovelReaderViewport),
    );
    final navigator = Navigator.of(
      tester.element(find.byType(NovelReaderPage)),
    );
    unawaited(
      navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold())),
    );
    await _settle(tester);
    // 手动触发一个迟到的可见回调，宿主仍须以实时 route.isCurrent 拦住。
    viewport.onVisibleText!([
      NovelVisibleTextRange(
        paragraph: viewport.document.paragraphAt(40),
        itemIndex: 40,
        start: 0,
        end: 4,
      ),
    ]);
    expect((await _stats(tester)).novelMeta['book']!.totalWords, initial);
    navigator.pop();
    await _settle(tester);
    expect((await _stats(tester)).novelMeta['book']!.totalWords, initial);
    await _remove(tester);
  });

  testWidgets('分页后台翻页与未绘制瞬时跳页不计，恢复只补当前页', (tester) async {
    await _mount(
      tester,
      _Source({
        'v1': _content([
          _entry(0, [List.filled(600, '甲乙丙丁').join()]),
        ]),
      }),
      settings: const NovelReaderSettings(
        mode: NovelReaderMode.paged,
        instantPageTurn: true,
        keepScreenOn: false,
      ),
    );
    final state = tester.state<NovelReaderPageViewState>(
      find.byType(NovelReaderPageView),
    );
    final initial = (await _stats(tester)).novelMeta['book']!.totalWords;
    // 同帧前翻再返回，目标页从未绘制，不能记账。
    state.nextPage();
    state.prevPage();
    await _settle(tester);
    expect((await _stats(tester)).novelMeta['book']!.totalWords, initial);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await _settle(tester);
    state.nextPage();
    await _settle(tester);
    expect((await _stats(tester)).novelMeta['book']!.totalWords, initial);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);
    expect(
      (await _stats(tester)).novelMeta['book']!.totalWords,
      greaterThan(initial),
    );
    await _remove(tester);
  });

  testWidgets('全屏插图层覆盖期间不记正文，关闭不改变统计', (tester) async {
    // 保持插图加载中，明确验证覆盖层；不依赖原生图片解码与无限 loading 动画收敛。
    final imageBytes = Completer<List<int>>();
    await _mount(
      tester,
      _Source({
        'v1': _content([
          _entry(0, List.filled(40, '甲乙丙丁')),
          const NovelReaderEntry(
            entryIndex: 1,
            entry: NovelContentEntry(
              name: '插图',
              contentType: 2,
              content: 'local.png',
            ),
          ),
        ]),
      }, imageBytes: imageBytes.future),
    );
    final initial = (await _stats(tester)).novelMeta['book']!.totalWords;
    final viewport = tester.widget<NovelReaderViewport>(
      find.byType(NovelReaderViewport),
    );
    tester
        .widget<IconButton>(
          find.byKey(const ValueKey('novel-reader-illustrations')),
        )
        .onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    viewport.onVisibleText!([
      NovelVisibleTextRange(
        paragraph: viewport.document.paragraphAt(35),
        itemIndex: 35,
        start: 0,
        end: 4,
      ),
    ]);
    final covered = (await tester.runAsync(ReadingStats.load))!;
    expect(covered.novelMeta['book']!.totalWords, initial);
    Navigator.of(tester.element(find.byType(NovelReaderPage))).pop();
    await _settle(tester);
    expect((await _stats(tester)).novelMeta['book']!.totalWords, initial);
    await _remove(tester);
  });

  testWidgets('对白富文本沿用原始字符范围，不将标题算入', (tester) async {
    const settings = NovelReaderSettings(
      dialogueEnabled: true,
      keepScreenOn: false,
    );
    await _mount(
      tester,
      _Source({
        'v1': _content([
          _entry(0, ['「甲乙」丙丁'], name: '不应计数的章节标题'),
        ]),
      }),
      settings: settings,
    );
    // 引号保留在原始范围，字符计数口径由主存储统一处理。
    final collected = <NovelVisibleTextRange>[];
    final view = tester.widget<NovelReaderViewport>(
      find.byType(NovelReaderViewport),
    );
    for (final element in find.byType(NovelTextRangeProbe).evaluate()) {
      final probe = element.findRenderObject()! as RenderNovelTextRangeProbe;
      final range = probe.visibleRange(
        tester.renderObject<RenderBox>(find.byType(NovelReaderViewport)),
      );
      if (range != null) collected.add(range);
    }
    expect(collected.single.start, 0);
    expect(collected.single.end, 6);
    expect(collected.single.paragraph.text, '「甲乙」丙丁');
    expect(view.onVisibleText, isNotNull);
    expect(
      (await _stats(tester)).novelMeta['book']!.totalWords,
      greaterThan(0),
    );
    await _remove(tester);
  });

  testWidgets('分页只在绘制后计当前切片，来回翻页当天不重复', (tester) async {
    await _mount(
      tester,
      _Source({
        'v1': _content([
          _entry(0, [List.filled(400, '甲乙丙丁').join()]),
        ]),
      }),
      settings: const NovelReaderSettings(
        mode: NovelReaderMode.paged,
        instantPageTurn: true,
        keepScreenOn: false,
      ),
    );
    final state = tester.state<NovelReaderPageViewState>(
      find.byType(NovelReaderPageView),
    );
    final first = (await _stats(tester)).novelMeta['book']!.totalWords;
    state.nextPage();
    await _settle(tester);
    final second = (await _stats(tester)).novelMeta['book']!.totalWords;
    expect(second, greaterThan(first));
    expect(second, lessThan(1600));
    state.prevPage();
    await _settle(tester);
    expect((await _stats(tester)).novelMeta['book']!.totalWords, second);
    state.nextPage();
    await _settle(tester);
    expect((await _stats(tester)).novelMeta['book']!.totalWords, second);
    await _remove(tester);
  });

  testWidgets('只露章节标题而正文在屏外时不记录', (tester) async {
    final ranges = <NovelVisibleTextRange>[];
    await tester.pumpWidget(
      ProviderScope(
        child: wrapWithApp(
          SizedBox(
            height: 30,
            child: NovelReaderViewport(
              document: NovelReaderDocument([
                _entry(0, ['甲乙丙丁'], name: '标题'),
              ]),
              settings: const NovelReaderSettings(),
              palette: NovelReaderPalette.resolve(
                const NovelReaderSettings(),
                Brightness.light,
              ),
              target: const NovelReaderAnchor(entryIndex: 0),
              jumpRevision: 0,
              onPosition: (_) {},
              onTap: () {},
              onVisibleText: ranges.addAll,
            ),
          ),
        ),
      ),
    );
    await _settle(tester);
    expect(ranges, isEmpty);
    await _remove(tester);
  });

  testWidgets('行距空隙不误计下一行，几何查询不会重新布局', (tester) async {
    final paragraph = NovelReaderParagraph(_entry(0, ['甲乙丙丁戊己庚辛']), 0);
    final probes = <RenderNovelTextRangeProbe>[];
    final viewportKey = GlobalKey();
    final textKey = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        child: wrapWithApp(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              key: viewportKey,
              width: 80,
              height: 25,
              child: OverflowBox(
                alignment: Alignment.topLeft,
                maxHeight: double.infinity,
                child: NovelTextRangeProbe(
                  paragraph: paragraph,
                  itemIndex: 0,
                  onAttach: probes.add,
                  onDetach: probes.remove,
                  child: RichText(
                    key: textKey,
                    text: TextSpan(
                      text: paragraph.text,
                      style: const TextStyle(
                        fontFamily: 'Ahem',
                        fontSize: 20,
                        height: 3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final renderText =
        textKey.currentContext!.findRenderObject()! as RenderParagraph;
    final viewport =
        viewportKey.currentContext!.findRenderObject()! as RenderBox;
    final boxes = renderText.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: 4),
    );
    final sampled = probes.single.visibleRange(viewport);
    if (boxes.every((box) => box.top >= 25)) {
      expect(sampled, isNull);
    } else {
      expect(sampled!.end, 4);
    }
    expect(renderText.debugNeedsLayout, isFalse);
    expect(tester.takeException(), isNull);
    await _remove(tester);
  });

  testWidgets('长段滚动仅上报可见行，不扫描或复制整段', (tester) async {
    final text = List.filled(200, '甲乙丙丁戊己庚辛壬癸').join();
    final document = NovelReaderDocument([
      _entry(0, [text]),
    ]);
    final ranges = <NovelVisibleTextRange>[];
    final key = GlobalKey<NovelReaderViewportState>();
    // 20px Ahem 方块字，宽252px每行12字，30px行高，视口刚好6行。
    const expectedPerScreen = 12 * 6;
    await tester.pumpWidget(
      ProviderScope(
        child: wrapWithApp(
          Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 300,
              height: 180,
              child: NovelReaderViewport(
                key: key,
                document: document,
                settings: const NovelReaderSettings(lineHeight: 1.5),
                palette: NovelReaderPalette.resolve(
                  const NovelReaderSettings(),
                  Brightness.light,
                ),
                target: const NovelReaderAnchor(entryIndex: 0),
                jumpRevision: 0,
                onPosition: (_) {},
                onTap: () {},
                onVisibleText: ranges.addAll,
              ),
            ),
          ),
        ),
      ),
    );
    await _settle(tester);
    expect(ranges, isNotEmpty);
    expect(ranges.first.start, 0);
    expect(ranges.first.end, expectedPerScreen);
    expect(identical(ranges.first.paragraph.text, text), isTrue);
    ranges.clear();
    await tester.drag(find.byType(NovelReaderViewport), const Offset(0, -120));
    await _settle(tester);
    key.currentState!.sampleVisibleText();
    expect(ranges.last.start, greaterThan(0));
    expect(
      ranges.last.end - ranges.last.start,
      lessThanOrEqualTo(expectedPerScreen + 12),
    );
    final visibleItems = ranges.last.itemIndex;
    ranges.clear();
    const iterations = 500;
    final clock = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      key.currentState!.sampleVisibleText();
    }
    clock.stop();
    debugPrint(
      'reader-visible-range microbenchmark Windows flutter_test debug: '
      '$iterations samples, visible paragraphs=1 (item=$visibleItems), '
      'source UTF16=${text.length}, total=${clock.elapsedMicroseconds}us, '
      'mean=${(clock.elapsedMicroseconds / iterations).toStringAsFixed(1)}us',
    );
    expect(ranges.length, iterations);
    expect(tester.takeException(), isNull);
    await _remove(tester);
  });
}
