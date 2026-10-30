import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/api/novel/novel_api.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/models/novel.dart';
import 'package:kira/models/novel_reading_progress.dart';
import 'package:kira/pages/novel_reader/novel_reader_contents_sheet.dart';
import 'package:kira/pages/novel_reader/novel_reader_illustrations.dart';
import 'package:kira/pages/novel_reader/novel_reader_viewport.dart';
import 'package:kira/pages/novel_reader_page.dart';
import 'package:kira/pages/reader/reader_image_viewer.dart';
import 'package:kira/pages/reader/reader_long_press_zoom.dart';
import 'package:kira/providers/novel_providers.dart';
import 'package:kira/repositories/novel_repository.dart';
import 'package:kira/utils/novel_reading_store.dart';
import 'package:kira/widgets/app_sheet.dart';
import 'package:kira/widgets/error_retry_view.dart';
import 'package:kira/widgets/pinch_zoomable.dart';
import 'package:kira/widgets/select_tile.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

const _text = NovelContentEntry(name: '正文一', contentType: 1);
const _imageA = NovelContentEntry(
  name: '彩图 A',
  contentType: 2,
  content: 'https://images.invalid/a.png',
);
const _imageB = NovelContentEntry(
  name: '彩图 B',
  contentType: 2,
  content: 'https://images.invalid/b.png',
);

class _Api implements NovelApi {
  final imageRequests = <String>[];
  int failures = 0;

  @override
  bool get hasCopyToken => false;

  @override
  Future<List<int>> getContentBytes(String url) async {
    imageRequests.add(url);
    if (failures > 0) {
      --failures;
      throw const NovelApiException('offline');
    }
    return base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected API access: ${invocation.memberName}');
}

class _Repository implements NovelRepository {
  _Repository(this.details);

  final Map<String, NovelVolumeDetail> details;
  final contentLoads = <String>[];
  final detailErrors = <String, Object>{};

  @override
  final _Api api = _Api();

  @override
  Future<List<NovelVolume>> loadVolumes(
    String pathWord, {
    bool refresh = false,
  }) async => details.values.map((detail) => detail.volume).toList();

  @override
  Future<NovelVolumeDetail> loadVolumeDetail(
    String pathWord,
    String volumeId, {
    bool refresh = false,
  }) async {
    if (detailErrors[volumeId] case final error?) throw error;
    return details[volumeId]!;
  }

  @override
  Future<NovelVolumeContent> loadVolumeContent(
    String pathWord,
    String volumeId, {
    bool refresh = false,
  }) async {
    contentLoads.add(volumeId);
    final detail = details[volumeId]!;
    return NovelVolumeContent(
      detail: detail,
      entries: [
        for (final (index, entry) in detail.volume.contents.indexed)
          NovelReaderEntry(
            entryIndex: index,
            entry: entry,
            paragraphs: entry.isText
                ? List.generate(100, (line) => '正文 $index 段落 $line')
                : const [],
          ),
      ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected repository access: ${invocation.memberName}',
  );
}

class _Store implements NovelReadingStore {
  _Store(this.progress);

  NovelReadingProgress progress;
  final writes = <NovelReadingProgress>[];

  @override
  Future<NovelReadingProgress?> readProgress(String pathWord) async => progress;

  @override
  Future<void> saveProgress(NovelReadingProgress progress) async {
    this.progress = progress;
    writes.add(progress);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected store access: ${invocation.memberName}');
}

NovelVolumeDetail _detail(
  List<NovelContentEntry> entries, {
  String id = 'v1',
  bool locked = false,
}) => NovelVolumeDetail(
  book: const NovelBook(pathWord: 'book', name: '测试小说'),
  volume: NovelVolume(id: id, name: '$id 卷', contents: entries),
  isLocked: locked,
);

class _SheetResult {
  bool closed = false;
  (String, int)? selection;
}

Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 20));
  }
  // Memory-image decoding runs outside FakeAsync; finish the native codecs
  // before requiring every loading animation (including cached rows) to settle.
  for (final element in find.byType(Image).evaluate()) {
    final image = element.widget as Image;
    await tester.runAsync(() => precacheImage(image.image, element));
  }
  await tester.pumpAndSettle(
    const Duration(milliseconds: 20),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 3),
  );
}

Future<_SheetResult> _openSheet(
  WidgetTester tester,
  _Repository repository, {
  int entryIndex = 0,
  double textScale = 1,
  String volumeId = 'v1',
}) async {
  final result = _SheetResult();
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result.selection = await showAppSheet<(String, int)>(
                context,
                heightFactor: 0.85,
                child: NovelReaderContentsSheet(
                  repository: repository,
                  pathWord: 'book',
                  volumeId: volumeId,
                  entryIndex: entryIndex,
                  detail: repository.details[volumeId],
                ),
              );
              result.closed = true;
            },
            child: const Text('打开目录'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开目录'));
  await _settle(tester);
  return result;
}

Future<void> _changeVolume(WidgetTester tester, String id) async {
  tester
      .widget<SelectTile<String>>(find.byType(SelectTile<String>))
      .onChanged(id);
  await _settle(tester);
}

void _closeSheet(WidgetTester tester) {
  Navigator.of(tester.element(find.byType(NovelReaderContentsSheet))).pop();
}

Finder get _illustrationList =>
    find.byKey(const ValueKey('novel-illustrations-list'));

Finder _illustration(String name) => find.descendant(
  of: find.byType(NovelReaderIllustrations),
  matching: find.byWidgetPredicate(
    (widget) => widget is Image && widget.semanticLabel == name,
  ),
);

ScrollableState _illustrationScroll(WidgetTester tester) =>
    tester.state<ScrollableState>(
      find.descendant(of: _illustrationList, matching: find.byType(Scrollable)),
    );

Future<void> _pinchIllustrations(
  WidgetTester tester, {
  required bool zoomIn,
}) async {
  final viewport = find.descendant(
    of: find.byType(NovelReaderIllustrations),
    matching: find.byType(PinchZoomable),
  );
  final center = tester.getCenter(viewport);
  final width = tester.getSize(viewport).width;
  final start = Offset(width / (zoomIn ? 8 : 4), 0);
  final end = Offset(width / (zoomIn ? 4 : 16), 0);
  final left = await tester.startGesture(center - start);
  final right = await tester.startGesture(center + start);
  await tester.pump();
  for (var step = 1; step <= 10; step++) {
    final spread = Offset.lerp(start, end, step / 10)!;
    await left.moveTo(center - spread);
    await right.moveTo(center + spread);
    await tester.pump(const Duration(milliseconds: 16));
  }
  // Let release velocity settle, so panning inertia does not affect assertions.
  await tester.pump(const Duration(milliseconds: 100));
  await left.up();
  await right.up();
  await _settle(tester);
}

void main() {
  setUp(() {
    setupSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    teardownSecureCredentialStoreForTest();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets('groups images without changing original chapter indices', (
    tester,
  ) async {
    final source = [
      _text,
      _imageA,
      const NovelContentEntry(name: '未知条目', contentType: 9),
      _imageB,
      const NovelContentEntry(name: '', contentType: 1),
    ];
    final repository = _Repository({'v1': _detail(source)});
    final result = await _openSheet(tester, repository, entryIndex: 4);

    expect(find.text('插图'), findsOneWidget);
    expect(find.text('彩图 A'), findsNothing);
    expect(find.text('彩图 B'), findsNothing);
    expect(find.byKey(const ValueKey('novel-toc-entry-1')), findsNothing);
    expect(find.byKey(const ValueKey('novel-toc-entry-3')), findsNothing);
    expect(find.byKey(const ValueKey('novel-toc-entry-2')), findsOneWidget);
    final chapter = find.byKey(const ValueKey('novel-toc-entry-4'));
    expect(tester.widget<ListTile>(chapter).selected, isTrue);
    expect(find.text('章节 5'), findsOneWidget);
    expect(repository.details['v1']!.volume.contents, same(source));
    expect(source.length, 5);

    await tester.tap(chapter);
    await _settle(tester);
    expect(result.closed, isTrue);
    expect(result.selection, ('v1', 4));
    expect(repository.api.imageRequests, isEmpty);
  });

  testWidgets('chapter names with the volume prefix deduplicate in the list', (
    tester,
  ) async {
    // API 章节名自带卷名前缀：卷名「第一卷」，章节名「第一卷 序」。
    const source = [
      NovelContentEntry(name: '  第一卷 序  ', contentType: 1),
      NovelContentEntry(name: '第一卷 特典', contentType: 1),
      NovelContentEntry(name: '与卷名无关的章节', contentType: 1),
    ];
    final repository = _Repository({
      'v1': const NovelVolumeDetail(
        book: NovelBook(pathWord: 'book', name: '测试小说'),
        volume: NovelVolume(id: 'v1', name: '第一卷', contents: source),
      ),
    });
    await _openSheet(tester, repository);

    // 前缀被去掉，不出现「第一卷 第一卷 序」式重复。
    expect(find.text('序'), findsOneWidget);
    expect(find.text('第一卷 序'), findsNothing);
    expect(find.text('特典'), findsOneWidget);
    // 与卷名无关的章节名原样保留。
    expect(find.text('与卷名无关的章节'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('continuous images scroll and zoom without selecting text', (
    tester,
  ) async {
    final repository = _Repository({
      'v1': _detail(const [_text, _imageA, _imageB]),
    });
    final result = await _openSheet(tester, repository);
    await tester.tap(find.byKey(const ValueKey('novel-toc-illustrations-v1')));
    await _settle(tester);

    final gallery = find.byType(NovelReaderIllustrations);
    expect(gallery, findsOneWidget);
    expect(
      find.descendant(of: gallery, matching: find.byType(PageView)),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('novel-illustrations-count')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('novel-illustrations-next')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('novel-illustrations-previous')),
      findsNothing,
    );
    expect(find.text('彩图 A'), findsNothing);
    expect(find.text('彩图 B'), findsNothing);
    expect(
      find.descendant(of: gallery, matching: find.text('v1 卷')),
      findsOneWidget,
    );
    expect(result.closed, isFalse);

    expect(
      find.descendant(
        of: gallery,
        matching: find.byType(ReaderLongPressZoomSurface),
      ),
      findsOneWidget,
    );

    final zoom = find.descendant(
      of: gallery,
      matching: find.byType(PinchZoomable),
    );
    expect(zoom, findsOneWidget);
    expect(tester.getSize(zoom), tester.getSize(_illustrationList));
    expect(tester.getSize(zoom).height.isFinite, isTrue);
    expect(
      tester.widget<ListView>(_illustrationList).scrollDirection,
      Axis.vertical,
    );
    await tester.drag(
      _illustrationList,
      Offset(0, -tester.getSize(_illustrationList).width * 0.65),
    );
    await _settle(tester);
    final scrollable = _illustrationScroll(tester);
    expect(scrollable.position.pixels, greaterThan(0));
    final first = tester.getRect(_illustration(_imageA.name));
    final second = tester.getRect(_illustration(_imageB.name));
    expect(second.top, closeTo(first.bottom, 0.01));
    expect(first.width, tester.getSize(_illustrationList).width);
    expect(second.width, first.width);
    // The square fixture keeps its ratio rather than fitting a paged viewport.
    expect(first.height, closeTo(first.width, 0.01));
    expect(second.height, closeTo(second.width, 0.01));
    expect(repository.api.imageRequests, [_imageA.content, _imageB.content]);

    final beforeZoom = scrollable.position.pixels;
    await _pinchIllustrations(tester, zoomIn: true);
    expect(
      tester.widget<ListView>(_illustrationList).physics,
      isA<NeverScrollableScrollPhysics>(),
    );
    await tester.drag(zoom, const Offset(50, -60));
    await _settle(tester);
    expect(scrollable.position.pixels, closeTo(beforeZoom, 0.01));
    await _pinchIllustrations(tester, zoomIn: false);
    expect(
      tester.widget<ListView>(_illustrationList).physics,
      isNot(isA<NeverScrollableScrollPhysics>()),
    );
    await tester.drag(_illustrationList, const Offset(0, 150));
    await _settle(tester);
    expect(scrollable.position.pixels, lessThan(beforeZoom));
    expect(find.text('彩图 A'), findsNothing);
    expect(find.text('彩图 B'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('novel-illustrations-close')));
    await _settle(tester);

    expect(find.byType(NovelReaderIllustrations), findsNothing);
    expect(find.byType(NovelReaderContentsSheet), findsOneWidget);
    expect(result.closed, isFalse);
    expect(repository.contentLoads, isEmpty);
    _closeSheet(tester);
    await _settle(tester);
    expect(result.closed, isTrue);
    expect(result.selection, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('double tap opens the shared image viewer', (tester) async {
    final repository = _Repository({
      'v1': _detail(const [_text, _imageA, _imageB]),
    });
    final result = await _openSheet(tester, repository);
    await tester.tap(find.byKey(const ValueKey('novel-toc-illustrations-v1')));
    await _settle(tester);

    await tester.tap(_illustration(_imageA.name));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(_illustration(_imageA.name));
    await _settle(tester);

    expect(find.byType(ReaderImageViewer), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(ReaderImageViewer),
        matching: find.byIcon(Icons.close),
      ),
    );
    await _settle(tester);

    expect(find.byType(ReaderImageViewer), findsNothing);
    expect(find.byType(NovelReaderIllustrations), findsOneWidget);
    expect(result.closed, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('each volume has its own gallery and original text selections', (
    tester,
  ) async {
    final repository = _Repository({
      'v1': _detail(const [_text, _imageA, _imageB]),
      'v2': _detail(const [_imageB, _text], id: 'v2'),
    });
    final result = await _openSheet(tester, repository);
    await _changeVolume(tester, 'v2');
    expect(
      find.byKey(const ValueKey('novel-toc-illustrations-v1')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('novel-toc-illustrations-v2')));
    await _settle(tester);
    expect(_illustration(_imageB.name), findsOneWidget);
    expect(_illustration(_imageA.name), findsNothing);
    expect(find.text('彩图 B'), findsNothing);
    expect(repository.api.imageRequests, [_imageB.content]);
    // System back dismisses only the gallery, not the directory or reader.
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(result.closed, isFalse);
    await tester.tap(find.byKey(const ValueKey('novel-toc-entry-1')));
    await _settle(tester);
    expect(result.selection, ('v2', 1));
  });

  testWidgets(
    'image-only volumes have one entry; text-only volumes have none',
    (tester) async {
      final repository = _Repository({
        'v1': _detail(const [_imageA, _imageB]),
        'v2': _detail(const [_text], id: 'v2'),
      });
      final result = await _openSheet(tester, repository, entryIndex: 1);
      expect(find.byType(ListTile), findsOneWidget);
      expect(find.text('插图'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('novel-toc-illustrations-v1')),
      );
      await _settle(tester);
      expect(_illustrationList, findsOneWidget);
      expect(find.byKey(const ValueKey('novel-toc-entry-1')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('novel-illustrations-close')));
      await _settle(tester);
      expect(result.closed, isFalse);
      expect(result.selection, isNull);
      await _changeVolume(tester, 'v2');
      expect(find.text('插图'), findsNothing);
      expect(find.byKey(const ValueKey('novel-toc-entry-0')), findsOneWidget);
    },
  );

  testWidgets('locked illustrations cannot be opened through the gallery', (
    tester,
  ) async {
    final repository = _Repository({
      'v1': _detail(const [_imageA], locked: true),
    });
    await _openSheet(tester, repository);
    final entry = find.byKey(const ValueKey('novel-toc-illustrations-v1'));
    expect(tester.widget<ListTile>(entry).enabled, isFalse);
    await tester.tap(entry);
    await _settle(tester);
    expect(find.byType(NovelReaderIllustrations), findsNothing);
    expect(repository.api.imageRequests, isEmpty);
  });

  testWidgets('failed image retries without changing the selected chapter', (
    tester,
  ) async {
    final repository = _Repository({
      'v1': _detail(const [_text, _imageA]),
    });
    repository.api.failures = 1;
    final result = await _openSheet(tester, repository);
    await tester.tap(find.byKey(const ValueKey('novel-toc-illustrations-v1')));
    await _settle(tester);
    expect(find.text('插图加载失败：offline'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(ErrorRetryView),
        matching: find.byType(FilledButton),
      ),
    );
    await _settle(tester);
    expect(find.byType(ErrorRetryView), findsNothing);
    expect(_illustration(_imageA.name), findsOneWidget);
    expect(find.text('彩图 A'), findsNothing);
    expect(repository.api.imageRequests, [_imageA.content, _imageA.content]);
    expect(result.closed, isFalse);
    expect(repository.contentLoads, isEmpty);
    await tester.tap(find.byKey(const ValueKey('novel-illustrations-close')));
    await _settle(tester);
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('novel-toc-entry-0')))
          .selected,
      isTrue,
    );
    expect(result.selection, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'detail failure remains scrollable on a short large-text screen',
    (tester) async {
      tester.view.physicalSize = const Size(700, 460);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _Repository({
        'v1': _detail(const [_text]),
        'v2': _detail(const [_text, _imageA], id: 'v2'),
      });
      repository.detailErrors['v2'] = const NovelApiException('offline');
      await _openSheet(tester, repository, textScale: 2);
      await _changeVolume(tester, 'v2');
      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorRetryView), findsOneWidget);
      final retry = find.descendant(
        of: find.byType(ErrorRetryView),
        matching: find.byType(FilledButton),
      );
      await tester.ensureVisible(retry);
      await _settle(tester);
      repository.detailErrors.clear();
      await tester.tap(retry);
      await _settle(tester);
      expect(find.byType(ErrorRetryView), findsNothing);
      expect(
        find.byKey(const ValueKey('novel-toc-illustrations-v2')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing image URL stays in gallery without requesting bytes', (
    tester,
  ) async {
    final repository = _Repository({
      'v1': _detail(const [NovelContentEntry(name: '', contentType: 2)]),
    });
    final result = await _openSheet(tester, repository);
    await tester.tap(find.byKey(const ValueKey('novel-toc-illustrations-v1')));
    await _settle(tester);
    expect(find.textContaining('插图加载失败'), findsOneWidget);
    expect(_illustrationList, findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(ErrorRetryView),
        matching: find.byType(FilledButton),
      ),
    );
    await _settle(tester);
    expect(find.textContaining('插图加载失败'), findsOneWidget);
    expect(repository.api.imageRequests, isEmpty);
    expect(result.closed, isFalse);
    await tester.tap(find.byKey(const ValueKey('novel-illustrations-close')));
    await _settle(tester);
    expect(result.closed, isFalse);
    expect(result.selection, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'viewing another volume illustrations preserves mid-text progress',
    (tester) async {
      final repository = _Repository({
        'v1': _detail(const [_text, _imageA, _imageB]),
        'v2': _detail(const [_text, _imageB, _imageA], id: 'v2'),
      });
      final store = _Store(
        NovelReadingProgress(
          pathWord: 'book',
          name: '测试小说',
          cover: '',
          volumeId: 'v1',
          volumeName: 'v1 卷',
          chapterName: '正文一',
          paragraphIndex: 40,
          paragraphAlignment: -0.04,
          updatedAt: DateTime(2025),
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            novelRepositoryProvider.overrideWithValue(repository),
            novelApiProvider.overrideWithValue(repository.api),
            novelReadingStoreProvider.overrideWithValue(store),
          ],
          child: const MaterialApp(
            locale: Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: NovelReaderPage(
              pathWord: 'book',
              volumeId: 'v1',
              resume: true,
            ),
          ),
        ),
      );
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await _settle(tester);
      final viewport = tester.state<NovelReaderViewportState>(
        find.byType(NovelReaderViewport),
      );
      final before = viewport.currentLocation!.anchor;
      expect(before.paragraphIndex, 40);

      await tester.tapAt(tester.getCenter(find.byType(NovelReaderViewport)));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('novel-reader-contents')));
      await _settle(tester);
      await _changeVolume(tester, 'v2');
      store.writes.clear();
      final progressBefore = store.progress;
      await tester.tap(
        find.byKey(const ValueKey('novel-toc-illustrations-v2')),
      );
      await _settle(tester);
      await tester.drag(
        _illustrationList,
        Offset(0, -tester.getSize(_illustrationList).width * 0.65),
      );
      await _settle(tester);
      expect(_illustrationScroll(tester).position.pixels, greaterThan(0));
      expect(
        tester.getRect(_illustration(_imageA.name)).top,
        closeTo(tester.getRect(_illustration(_imageB.name)).bottom, 0.01),
      );
      expect(find.text('彩图 A'), findsNothing);
      expect(find.text('彩图 B'), findsNothing);
      expect(store.writes, isEmpty);
      await tester.tap(find.byKey(const ValueKey('novel-illustrations-close')));
      await _settle(tester);
      expect(store.writes, isEmpty);
      _closeSheet(tester);
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await _settle(tester);
      expect(store.writes, isEmpty);
      expect(store.progress, same(progressBefore));

      final after = viewport.currentLocation!.anchor;
      expect(after.entryIndex, before.entryIndex);
      expect(after.paragraphIndex, before.paragraphIndex);
      expect(after.alignment, closeTo(before.alignment, 0.005));
      expect(repository.contentLoads, ['v1']);
      expect(store.progress.volumeId, 'v1');
      expect(store.progress.entryIndex, 0);
      expect(store.progress.paragraphIndex, 40);
      expect(store.progress.paragraphAlignment, closeTo(-0.04, 0.005));
      await tester.pumpWidget(const SizedBox());
      await _settle(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('header stays bare and chapter names stay single-line', (
    tester,
  ) async {
    final repository = _Repository({
      'v1': _detail(const [_text]),
    });
    await _openSheet(tester, repository);

    // 目录本身就是目录，不再重复标题、定位按钮或阅读状态说明。
    expect(find.text('目录'), findsNothing);
    expect(
      find.byKey(const ValueKey('novel-toc-locate-current')),
      findsNothing,
    );
    expect(find.text('正在阅读'), findsNothing);
    expect(find.byKey(const ValueKey('novel-toc-close')), findsOneWidget);
    expect(find.byKey(const ValueKey('novel-toc-catalog')), findsOneWidget);

    final title = tester.widget<Text>(find.text('正文一'));
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('catalog footer sits below the list instead of covering it', (
    tester,
  ) async {
    final repository = _Repository({
      'v1': _detail(const [_text, _text, _text]),
    });
    await _openSheet(tester, repository);

    final footer = tester.getRect(
      find.byKey(const ValueKey('novel-toc-catalog')),
    );
    final list = tester.getRect(find.byType(ScrollablePositionedList));
    expect(footer.top, greaterThanOrEqualTo(list.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'long names on a narrow large-text screen keep the layout intact',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const longVolume = '第二卷 转生之后我在异世界过起了慢生活';
      final entries = [
        for (var index = 0; index < 40; index++)
          NovelContentEntry(name: '第${index + 1}章 一个特别漫长的章节标题', contentType: 1),
      ];
      final repository = _Repository({
        'v1': const NovelVolumeDetail(
          book: NovelBook(pathWord: 'book', name: '测试小说'),
          volume: NovelVolume(
            id: 'v1',
            name: '第一卷 最初的约定',
            contents: [NovelContentEntry(name: '正文一', contentType: 1)],
          ),
        ),
        'v2': NovelVolumeDetail(
          book: const NovelBook(pathWord: 'book', name: '测试小说'),
          volume: NovelVolume(id: 'v2', name: longVolume, contents: entries),
        ),
      });
      await _openSheet(
        tester,
        repository,
        volumeId: 'v2',
        entryIndex: 30,
        textScale: 2,
      );

      final sheet = tester.getRect(find.byType(NovelReaderContentsSheet));
      final selected = tester.getRect(
        find.byKey(const ValueKey('novel-toc-entry-30')),
      );
      // 打开长卷时当前章节直接落在可视区，不需要先滚动。
      expect(selected.top, greaterThanOrEqualTo(sheet.top - 0.01));
      expect(selected.bottom, lessThanOrEqualTo(sheet.bottom + 0.01));

      final title = tester.widget<Text>(find.text('第31章 一个特别漫长的章节标题'));
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);

      // 卷名胶囊有硬上限，长卷名不会把顶部行撑破，也不会挤掉关闭入口。
      final pill = tester.getRect(find.byType(SelectTile<String>));
      final close = tester.getRect(
        find.byKey(const ValueKey('novel-toc-close')),
      );
      expect(pill.left, greaterThanOrEqualTo(sheet.left - 0.01));
      expect(pill.right, lessThanOrEqualTo(close.left + 0.01));
      expect(close.right, lessThanOrEqualTo(sheet.right + 0.01));
      expect(tester.takeException(), isNull);
    },
  );
}
