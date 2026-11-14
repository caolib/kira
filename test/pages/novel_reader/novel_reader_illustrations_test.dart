import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/novel.dart';
import 'package:kira/models/reader_settings.dart';
import 'package:kira/pages/novel_reader/novel_reader_illustrations.dart';
import 'package:kira/pages/reader/reader_image_viewer.dart';
import 'package:kira/widgets/app_sheet.dart';
import 'package:kira/widgets/error_retry_view.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_helpers.dart';

Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.green, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Finder _row(int index) => find.byKey(ValueKey('novel-illustration-$index'));

Future<void> _settleImages(WidgetTester tester) async {
  for (var attempt = 0; attempt < 12; attempt++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
      for (final element in find.byType(Image).evaluate().toList()) {
        final image = element.widget as Image;
        await precacheImage(image.image, element);
      }
    });
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  final platformCalls = <MethodCall>[];

  setUp(() async {
    platformCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          platformCalls.add(call);
          return null;
        });
    setupSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({});
    await ReaderSettings().initFromPrefs(await SharedPreferences.getInstance());
    await ReaderSettings().setImageGap(0);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    teardownSecureCredentialStoreForTest();
  });

  testWidgets('loading indicator follows theme primary, not white', (
    tester,
  ) async {
    final pending = Completer<List<int>>();
    await tester.pumpWidget(
      wrapWithApp(
        Theme(
          data: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.green,
            ).copyWith(primary: Colors.green),
          ),
          child: NovelReaderIllustrations(
            volumeName: '测试卷',
            illustrations: const [
              NovelContentEntry(name: '插图', contentType: 2, content: 'image'),
            ],
            loadBytes: (_) => pending.future,
          ),
        ),
        wrapInScaffold: false,
      ),
    );
    expect(
      tester
          .widget<ExpressiveLoadingIndicator>(
            find.byType(ExpressiveLoadingIndicator),
          )
          .color,
      Colors.green,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    final bytes = await tester.runAsync(() => _png(40, 80));
    pending.complete(bytes!);
    await _settleImages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'scroll hides chrome without resizing, tap and viewer restore it',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bytes = await tester.runAsync(() => _png(40, 80));
      var hostRestores = 0;
      await tester.pumpWidget(
        wrapWithApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                useSafeArea: false,
                builder: (_) => NovelReaderIllustrations(
                  volumeName: '测试卷',
                  illustrations: List.generate(
                    8,
                    (i) => NovelContentEntry(
                      name: '插图 $i',
                      contentType: 2,
                      content: 'image-$i',
                    ),
                  ),
                  loadBytes: (_) async => bytes!,
                  onClosed: () => hostRestores++,
                ),
              ),
              child: const Text('打开插图'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开插图'));
      await _settleImages(tester);
      final gallery = find.byKey(const ValueKey('novel-illustrations-list'));
      final scrollable = find.descendant(
        of: gallery,
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      final close = find.byKey(const ValueKey('novel-illustrations-back'));
      final size = tester.getSize(gallery);
      expect(close.hitTestable(), findsOneWidget);

      // Programmatic positioning (including async image size updates) isn't a
      // user scroll and must not hide the toolbar.
      position.jumpTo(200);
      await _settleImages(tester);
      expect(close.hitTestable(), findsOneWidget);
      await tester.drag(gallery, const Offset(0, -200));
      await _settleImages(tester);
      expect(close.hitTestable(), findsNothing);
      expect(tester.getSize(gallery), size);
      expect(
        platformCalls.any(
          (call) =>
              call.method == 'SystemChrome.setEnabledSystemUIMode' &&
              call.arguments == 'SystemUiMode.immersiveSticky',
        ),
        isTrue,
      );

      final hiddenOffset = position.pixels;
      await tester.tapAt(tester.getCenter(gallery));
      await tester.pump(const Duration(milliseconds: 350));
      await _settleImages(tester);
      expect(close.hitTestable(), findsOneWidget);
      expect(tester.getSize(gallery), size);
      expect(position.pixels, closeTo(hiddenOffset, 0.01));
      expect(
        platformCalls
            .lastWhere(
              (call) =>
                  call.method == 'SystemChrome.setEnabledSystemUIOverlays' ||
                  call.method == 'SystemChrome.setEnabledSystemUIMode',
            )
            .method,
        'SystemChrome.setEnabledSystemUIOverlays',
      );

      // A double tap opens the shared viewer, without triggering the single-tap
      // toolbar toggle; returning keeps the gallery's previous chrome state.
      final point = tester.getCenter(gallery);
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(point);
      await _settleImages(tester);
      expect(find.byType(ReaderImageViewer), findsOneWidget);
      final viewerContext = tester.element(find.byType(ReaderImageViewer));
      Navigator.of(viewerContext).pop();
      await _settleImages(tester);
      await tester.pumpAndSettle();
      expect(find.byType(ReaderImageViewer), findsNothing);
      expect(close.hitTestable(), findsOneWidget);
      expect(
        platformCalls
            .lastWhere(
              (call) =>
                  call.method == 'SystemChrome.setEnabledSystemUIOverlays' ||
                  call.method == 'SystemChrome.setEnabledSystemUIMode',
            )
            .method,
        'SystemChrome.setEnabledSystemUIOverlays',
      );

      await tester.tap(close);
      await tester.pump();
      expect(
        hostRestores,
        1,
        reason: 'The close button must pop the gallery route',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await _settleImages(tester);
      expect(find.byType(NovelReaderIllustrations), findsNothing);
      expect(hostRestores, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  for (final direction in [0, 1, 2]) {
    testWidgets('settings select page direction $direction and fit landscape', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bytes = await tester.runAsync(() => _png(40, 80));
      final calls = <String, int>{};
      await tester.pumpWidget(
        wrapWithApp(
          NovelReaderIllustrations(
            volumeName: '测试卷',
            illustrations: List.generate(
              8,
              (index) => NovelContentEntry(
                name: '插图 $index',
                contentType: 2,
                content: 'image-$index',
              ),
            ),
            loadBytes: (url) async {
              calls.update(url, (count) => count + 1, ifAbsent: () => 1);
              return bytes!;
            },
          ),
          wrapInScaffold: false,
        ),
      );
      await _settleImages(tester);
      expect(find.byType(SegmentedButton<bool>), findsNothing);
      final back = find.byKey(const ValueKey('novel-illustrations-back'));
      final settings = find.byKey(
        const ValueKey('novel-illustrations-settings'),
      );
      expect(
        tester.getCenter(back).dx,
        lessThan(tester.getCenter(settings).dx),
      );
      final scrollable = find.descendant(
        of: find.byKey(const ValueKey('novel-illustrations-list')),
        matching: find.byType(Scrollable),
      );
      tester.state<ScrollableState>(scrollable).position.jumpTo(1900);
      await _settleImages(tester);

      await tester.tap(settings);
      await tester.pumpAndSettle();
      final mode = tester.widget<SegmentedButton<bool>>(
        find.byKey(const ValueKey('novel-illustrations-mode')),
      );
      mode.onSelectionChanged!({true});
      await _settleImages(tester);
      tester
          .widget<SegmentedButton<int>>(
            find.byKey(const ValueKey('novel-illustrations-direction')),
          )
          .onSelectionChanged!({direction});
      await _settleImages(tester);
      final sheet = find.byType(AppSheet);
      expect(tester.getSize(sheet).height, lessThanOrEqualTo(350));
      Navigator.of(tester.element(sheet)).pop();
      await tester.pumpAndSettle();
      await _settleImages(tester);

      var pages = tester.widget<PageView>(find.byType(PageView));
      expect(
        pages.scrollDirection,
        direction == 2 ? Axis.vertical : Axis.horizontal,
      );
      expect(pages.reverse, direction == 1);
      expect(
        pages.controller!.page,
        closeTo(1, 0.01),
        reason: 'Switching mode keeps the illustration in the viewport center',
      );
      final image = tester.widget<Image>(find.byType(Image).first);
      expect(image.fit, BoxFit.contain);
      final fitted = applyBoxFit(
        image.fit!,
        const Size(40, 80),
        const Size(900, 500),
      );
      expect(fitted.destination, const Size(250, 500));

      final delta = direction == 2
          ? const Offset(0, -350)
          : direction == 1
          ? const Offset(650, 0)
          : const Offset(-650, 0);
      await tester.drag(find.byType(PageView), delta);
      await _settleImages(tester);
      await tester.pumpAndSettle();
      pages = tester.widget<PageView>(find.byType(PageView));
      expect(pages.controller!.page, closeTo(2, 0.01));
      expect(back.hitTestable(), findsNothing);
      await tester.tapAt(const Offset(450, 250));
      await tester.pump(const Duration(milliseconds: 350));
      await _settleImages(tester);
      expect(back.hitTestable(), findsOneWidget);

      // All three directions can return to continuous scrolling, keeping the
      // current illustration and reusing the already loaded bytes.
      await tester.tap(settings);
      await tester.pumpAndSettle();
      tester
          .widget<SegmentedButton<bool>>(
            find.byKey(const ValueKey('novel-illustrations-mode')),
          )
          .onSelectionChanged!({false});
      await _settleImages(tester);
      Navigator.of(tester.element(find.byType(AppSheet))).pop();
      await tester.pumpAndSettle();
      await _settleImages(tester);
      final list = tester.widget<ListView>(find.byType(ListView));
      expect(
        list.scrollDirection,
        direction == 2 ? Axis.vertical : Axis.horizontal,
      );
      expect(list.reverse, direction == 1);
      expect(calls.values, everyElement(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('failed illustration can retry without changing other loads', (
    tester,
  ) async {
    final bytes = await tester.runAsync(() => _png(40, 80));
    var calls = 0;
    final retry = Completer<List<int>>();
    await tester.pumpWidget(
      wrapWithApp(
        NovelReaderIllustrations(
          volumeName: '测试卷',
          illustrations: const [
            NovelContentEntry(name: '插图', contentType: 2, content: 'image'),
          ],
          loadBytes: (_) {
            calls++;
            return calls == 1
                ? Future.error(StateError('image download failed'))
                : retry.future;
          },
        ),
        wrapInScaffold: false,
      ),
    );
    await _settleImages(tester);
    expect(find.byType(ErrorRetryView), findsOneWidget);
    expect(find.textContaining('image download failed'), findsOneWidget);
    expect(calls, 1);

    tester.widget<ErrorRetryView>(find.byType(ErrorRetryView)).onRetry();
    await tester.pump();
    expect(calls, 2);
    retry.complete(bytes!);
    await _settleImages(tester);
    expect(find.byType(ErrorRetryView), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    expect(calls, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'returning to recycled illustrations keeps their loaded heights',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final portrait = await tester.runAsync(() => _png(40, 80));
      final landscape = await tester.runAsync(() => _png(80, 40));
      final calls = <String, int>{};
      await tester.pumpWidget(
        wrapWithApp(
          NovelReaderIllustrations(
            volumeName: '测试卷',
            illustrations: List.generate(
              16,
              (index) => NovelContentEntry(
                name: '插图 $index',
                contentType: 2,
                content: 'image-$index',
              ),
            ),
            loadBytes: (url) async {
              calls.update(url, (count) => count + 1, ifAbsent: () => 1);
              final index = int.parse(url.substring('image-'.length));
              return index.isEven ? portrait! : landscape!;
            },
          ),
          wrapInScaffold: false,
        ),
      );
      await _settleImages(tester);
      expect(tester.getSize(_row(0)).height, closeTo(800, 0.01));

      final scrollable = find.descendant(
        of: find.byKey(const ValueKey('novel-illustrations-list')),
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable).position;

      // Load enough rows to recycle the first images, then return one row at a
      // time. A completed Future alone still produces a waiting frame when its
      // FutureBuilder is recreated, which used to restore a square placeholder.
      for (var step = 0; step < 18; step++) {
        position.jumpTo(position.pixels + 500);
        await tester.pump();
        await _settleImages(tester);
      }
      expect(_row(0), findsNothing);
      expect(calls, hasLength(16));
      // Stay away from the tail's overscroll spring while checking offsets.
      const downwardPosition = 4000.0;
      // Even decoded-image eviction must not restore the square placeholder.
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      position.jumpTo(0);
      await tester.pump();
      expect(
        tester.getSize(_row(0)).height,
        closeTo(800, 0.01),
        reason: 'A recycled portrait must not return to a square placeholder',
      );
      await _settleImages(tester);
      position.jumpTo(downwardPosition);
      await tester.pump();
      await _settleImages(tester);

      var checkedPortrait = false;
      var checkedLandscape = false;
      for (var step = 0; step < 24 && position.pixels > 0; step++) {
        final target = (position.pixels - 400).clamp(0.0, double.infinity);
        position.jumpTo(target);
        await tester.pump();
        for (var index = 0; index < 16; index++) {
          if (_row(index).evaluate().isEmpty ||
              !calls.containsKey('image-$index')) {
            continue;
          }
          final height = tester.getSize(_row(index)).height;
          expect(
            height,
            closeTo(index.isEven ? 800 : 200, 0.01),
            reason:
                'Recreated row $index must retain its aspect ratio immediately',
          );
          checkedPortrait |= index.isEven;
          checkedLandscape |= index.isOdd;
        }
        await _settleImages(tester);
        expect(position.pixels, closeTo(target, 0.01));
      }
      expect(position.pixels, lessThan(downwardPosition));
      expect(checkedPortrait, isTrue);
      expect(checkedLandscape, isTrue);
      expect(calls.values, everyElement(1));

      // Reproduce the reported gesture after every illustration has loaded:
      // repeated upward scrolling must never be corrected back downwards.
      position.jumpTo(4000);
      await tester.pump();
      await _settleImages(tester);
      final gesture = await tester.startGesture(tester.getCenter(scrollable));
      var previousPixels = position.pixels;
      for (var step = 0; step < 10; step++) {
        await gesture.moveBy(const Offset(0, 40));
        await tester.pump(const Duration(milliseconds: 16));
        expect(position.pixels, lessThanOrEqualTo(previousPixels));
        previousPixels = position.pixels;
      }
      await gesture.up();
      await _settleImages(tester);
      expect(position.pixels, lessThan(4000));
      expect(calls.values, everyElement(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
