import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/pages/reader/reader_long_press_zoom.dart';

const _surfaceKey = ValueKey('reader-long-press-zoom-surface');
const _transformKey = ValueKey('reader-long-press-zoom-transform');

Widget _buildSubject({
  bool enabled = true,
  double panSensitivity = 2.0,
  Axis? contentScrollAxis,
  bool Function()? canStart,
  VoidCallback? onZoomStarted,
  VoidCallback? onZoomEnded,
  Widget? child,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 300,
          height: 500,
          child: ReaderLongPressZoomSurface(
            key: _surfaceKey,
            enabled: enabled,
            panSensitivity: panSensitivity,
            contentScrollAxis: contentScrollAxis,
            canStart: canStart,
            onZoomStarted: onZoomStarted,
            onZoomEnded: onZoomEnded,
            child: child ?? const ColoredBox(color: Colors.blue),
          ),
        ),
      ),
    ),
  );
}

Widget _buildPageViewSubject({
  required PageController controller,
  VoidCallback? onTap,
  VoidCallback? onDoubleTap,
}) {
  return MaterialApp(
    home: PageView(
      controller: controller,
      children: [
        ReaderLongPressZoomSurface(
          key: _surfaceKey,
          enabled: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            onDoubleTap: onDoubleTap,
            child: const ColoredBox(color: Colors.blue),
          ),
        ),
        const ColoredBox(color: Colors.green),
      ],
    ),
  );
}

Transform _transform(WidgetTester tester) {
  return tester.widget<Transform>(find.byKey(_transformKey));
}

Future<TestGesture> _startLongPress(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(_surfaceKey)),
  );
  await tester.pump(const Duration(milliseconds: 251));
  await tester.pump(const Duration(milliseconds: 370));
  return gesture;
}

Future<void> _finishAnimation(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 370));
}

void main() {
  testWidgets('sensitivity control commits only after the drag ends', (
    tester,
  ) async {
    final committed = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderLongPressZoomSensitivityControl(
            title: 'Drag sensitivity',
            value: 2.0,
            onCommitted: committed.add,
          ),
        ),
      ),
    );

    var slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(2.5);
    await tester.pump();

    slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, 2.5);
    expect(find.text('2.5×'), findsOneWidget);
    expect(committed, isEmpty);

    slider.onChangeEnd!(2.5);
    await tester.pump();
    expect(committed, [2.5]);
  });

  testWidgets('long press zooms to 1.75 and release resets to 1.0', (
    tester,
  ) async {
    await tester.pumpWidget(_buildSubject());

    final gesture = await _startLongPress(tester);
    expect(
      _transform(tester).transform.getMaxScaleOnAxis(),
      closeTo(1.75, 0.01),
    );

    await gesture.up();
    await _finishAnimation(tester);
    expect(
      _transform(tester).transform.getMaxScaleOnAxis(),
      closeTo(1.0, 0.01),
    );
  });

  testWidgets(
    'zoom-in uses a soft spring tail instead of a 120ms linear ramp',
    (tester) async {
      await tester.pumpWidget(_buildSubject());
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_surfaceKey)),
      );

      await tester.pump(const Duration(milliseconds: 251));
      await tester.pump(const Duration(milliseconds: 120));
      final scaleDuringTail = _transform(tester).transform.getMaxScaleOnAxis();

      expect(scaleDuringTail, greaterThan(1.5));
      expect(scaleDuringTail, lessThan(1.7));

      await tester.pump(const Duration(milliseconds: 250));
      expect(
        _transform(tester).transform.getMaxScaleOnAxis(),
        closeTo(1.75, 0.01),
      );
      await gesture.up();
    },
  );

  testWidgets('zoom-out uses the same soft spring tail', (tester) async {
    await tester.pumpWidget(_buildSubject());
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_surfaceKey)),
    );
    await tester.pump(const Duration(milliseconds: 251));
    await tester.pump(const Duration(milliseconds: 370));

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final scaleDuringTail = _transform(tester).transform.getMaxScaleOnAxis();

    expect(scaleDuringTail, greaterThan(1.1));
    expect(scaleDuringTail, lessThan(1.25));

    await tester.pump(const Duration(milliseconds: 250));
    expect(
      _transform(tester).transform.getMaxScaleOnAxis(),
      closeTo(1.0, 0.01),
    );
  });

  testWidgets(
    'releasing during zoom-in reverses continuously from its current scale',
    (tester) async {
      await tester.pumpWidget(_buildSubject());
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_surfaceKey)),
      );
      await tester.pump(const Duration(milliseconds: 251));
      await tester.pump(const Duration(milliseconds: 120));
      final beforeRelease = _transform(tester).transform.getMaxScaleOnAxis();

      await gesture.up();
      await tester.pump();
      final atRelease = _transform(tester).transform.getMaxScaleOnAxis();

      expect(atRelease, closeTo(beforeRelease, 0.02));
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        _transform(tester).transform.getMaxScaleOnAxis(),
        lessThan(beforeRelease),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        _transform(tester).transform.getMaxScaleOnAxis(),
        closeTo(1.0, 0.01),
      );
    },
  );

  testWidgets('moving while held changes the matrix translation', (
    tester,
  ) async {
    await tester.pumpWidget(_buildSubject());
    final gesture = await _startLongPress(tester);
    final before = _transform(tester).transform.storage.toList();

    await gesture.moveBy(const Offset(36, -24));
    await tester.pump();
    final after = _transform(tester).transform.storage;

    expect(after[12], isNot(closeTo(before[12], 0.01)));
    expect(after[13], isNot(closeTo(before[13], 0.01)));
    await gesture.up();
  });

  testWidgets('pan sensitivity multiplies movement while held', (tester) async {
    await tester.pumpWidget(_buildSubject(panSensitivity: 2.5));
    final gesture = await _startLongPress(tester);
    final before = _transform(tester).transform.storage.toList();

    await gesture.moveBy(const Offset(20, -10));
    await tester.pump();
    final after = _transform(tester).transform.storage;

    expect(after[12] - before[12], closeTo(50, 0.01));
    expect(after[13] - before[13], closeTo(-25, 0.01));
    await gesture.up();
  });

  testWidgets(
    'panning is clamped so scaled content always covers the viewport',
    (tester) async {
      await tester.pumpWidget(_buildSubject());
      final gesture = await _startLongPress(tester);

      await gesture.moveBy(const Offset(1000, 1000));
      await tester.pump();
      final transformedRect = MatrixUtils.transformRect(
        _transform(tester).transform,
        const Rect.fromLTWH(0, 0, 300, 500),
      );

      expect(transformedRect.left, lessThanOrEqualTo(0.01));
      expect(transformedRect.top, lessThanOrEqualTo(0.01));
      expect(transformedRect.right, greaterThanOrEqualTo(299.99));
      expect(transformedRect.bottom, greaterThanOrEqualTo(499.99));

      await gesture.moveBy(const Offset(-2000, -2000));
      await tester.pump();
      final oppositeRect = MatrixUtils.transformRect(
        _transform(tester).transform,
        const Rect.fromLTWH(0, 0, 300, 500),
      );

      expect(oppositeRect.left, lessThanOrEqualTo(0.01));
      expect(oppositeRect.top, lessThanOrEqualTo(0.01));
      expect(oppositeRect.right, greaterThanOrEqualTo(299.99));
      expect(oppositeRect.bottom, greaterThanOrEqualTo(499.99));
      await gesture.up();
    },
  );

  testWidgets('scroll viewport keeps native scrolling active while zoomed', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _buildSubject(
        contentScrollAxis: Axis.vertical,
        child: ListView(
          controller: controller,
          children: const [
            SizedBox(height: 500, child: ColoredBox(color: Colors.blue)),
            SizedBox(
              key: ValueKey('next-page'),
              height: 500,
              child: ColoredBox(color: Colors.green),
            ),
            SizedBox(height: 500, child: ColoredBox(color: Colors.orange)),
          ],
        ),
      ),
    );
    final gesture = await _startLongPress(tester);
    final transformBeforeMove = _transform(tester).transform.storage.toList();

    await gesture.moveBy(const Offset(0, -110));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -110));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -110));
    await tester.pump();
    final transformAfterMove = _transform(tester).transform.storage;

    expect(controller.offset, greaterThan(0));
    expect(transformAfterMove[13], closeTo(transformBeforeMove[13], 0.01));
    expect(
      tester.getRect(find.byKey(const ValueKey('next-page'))).top,
      lessThan(500),
    );
    await gesture.up();
  });

  testWidgets('scroll viewport blocks the child tap after a stationary hold', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _buildSubject(
        contentScrollAxis: Axis.vertical,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => taps++,
          child: const ColoredBox(color: Colors.blue),
        ),
      ),
    );
    final gesture = await _startLongPress(tester);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));

    expect(taps, 0);

    await tester.tap(find.byKey(_surfaceKey));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('a rejected scroll viewport hold still blocks the child tap', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _buildSubject(
        contentScrollAxis: Axis.vertical,
        canStart: () => false,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => taps++,
          child: const ColoredBox(color: Colors.blue),
        ),
      ),
    );
    final gesture = await _startLongPress(tester);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));

    expect(taps, 0);
  });

  test(
    'uses one viewport target for scroll mode and page target otherwise',
    () {
      expect(
        readerLongPressZoomTargetForMode(isPageMode: false),
        ReaderLongPressZoomTarget.viewport,
      );
      expect(
        readerLongPressZoomTargetForMode(isPageMode: true),
        ReaderLongPressZoomTarget.page,
      );
    },
  );

  testWidgets('pointer cancel resets the zoom', (tester) async {
    await tester.pumpWidget(_buildSubject());
    final gesture = await _startLongPress(tester);

    await gesture.cancel();
    await _finishAnimation(tester);

    expect(
      _transform(tester).transform.getMaxScaleOnAxis(),
      closeTo(1.0, 0.01),
    );
  });

  testWidgets('disabled surface passes a long stationary tap to its child', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _buildSubject(
        enabled: false,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => taps++,
          child: const ColoredBox(color: Colors.blue),
        ),
      ),
    );
    final gesture = await _startLongPress(tester);

    expect(
      _transform(tester).transform.getMaxScaleOnAxis(),
      closeTo(1.0, 0.01),
    );
    await gesture.up();
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('canStart can reject the zoom', (tester) async {
    await tester.pumpWidget(_buildSubject(canStart: () => false));
    final gesture = await _startLongPress(tester);

    expect(
      _transform(tester).transform.getMaxScaleOnAxis(),
      closeTo(1.0, 0.01),
    );
    await gesture.up();
  });

  testWidgets('quick drag before the hold deadline never zooms', (
    tester,
  ) async {
    await tester.pumpWidget(_buildSubject());
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(_surfaceKey)),
    );

    await gesture.moveBy(const Offset(0, 40));
    await tester.pump(const Duration(milliseconds: 371));

    expect(
      _transform(tester).transform.getMaxScaleOnAxis(),
      closeTo(1.0, 0.01),
    );
    await gesture.up();
  });

  testWidgets('disabling an active surface resets it', (tester) async {
    var ended = 0;
    await tester.pumpWidget(_buildSubject(onZoomEnded: () => ended++));
    final gesture = await _startLongPress(tester);

    await tester.pumpWidget(
      _buildSubject(enabled: false, onZoomEnded: () => ended++),
    );
    await tester.pump(const Duration(milliseconds: 370));

    expect(
      _transform(tester).transform.getMaxScaleOnAxis(),
      closeTo(1.0, 0.01),
    );
    expect(ended, 1);
    await gesture.up();
  });

  testWidgets('a second pointer prevents the zoom', (tester) async {
    await tester.pumpWidget(_buildSubject());
    final center = tester.getCenter(find.byKey(_surfaceKey));
    final first = await tester.startGesture(center, pointer: 1);
    final second = await tester.startGesture(
      center + const Offset(20, 20),
      pointer: 2,
    );

    await tester.pump(const Duration(milliseconds: 371));

    expect(
      _transform(tester).transform.getMaxScaleOnAxis(),
      closeTo(1.0, 0.01),
    );
    await second.up();
    await first.up();
  });

  testWidgets('a transient second pointer disqualifies the gesture', (
    tester,
  ) async {
    await tester.pumpWidget(_buildSubject());
    final center = tester.getCenter(find.byKey(_surfaceKey));
    final first = await tester.startGesture(center, pointer: 1);
    await tester.pump(const Duration(milliseconds: 100));
    final second = await tester.startGesture(
      center + const Offset(20, 20),
      pointer: 2,
    );
    await tester.pump(const Duration(milliseconds: 20));
    await second.up();

    await tester.pump(const Duration(milliseconds: 251));
    await tester.pump(const Duration(milliseconds: 120));

    expect(
      _transform(tester).transform.getMaxScaleOnAxis(),
      closeTo(1.0, 0.01),
    );
    await first.up();
  });

  testWidgets('a second pointer cancels an active zoom', (tester) async {
    var started = 0;
    var ended = 0;
    await tester.pumpWidget(
      _buildSubject(onZoomStarted: () => started++, onZoomEnded: () => ended++),
    );
    final first = await _startLongPress(tester);
    final second = await tester.startGesture(
      tester.getCenter(find.byKey(_surfaceKey)) + const Offset(20, 20),
      pointer: 2,
    );
    await _finishAnimation(tester);

    expect(
      _transform(tester).transform.getMaxScaleOnAxis(),
      closeTo(1.0, 0.01),
    );
    expect(started, 1);
    expect(ended, 1);

    await second.up();
    await first.up();
    expect(ended, 1);
  });

  testWidgets('unmounting an active surface ends the zoom', (tester) async {
    var ended = 0;
    await tester.pumpWidget(_buildSubject(onZoomEnded: () => ended++));
    await _startLongPress(tester);

    await tester.pumpWidget(const SizedBox());

    expect(ended, 1);
  });

  testWidgets('long press owns movement inside a PageView', (tester) async {
    final controller = PageController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_buildPageViewSubject(controller: controller));

    final gesture = await _startLongPress(tester);
    await gesture.moveBy(const Offset(-220, 0));
    await tester.pump();

    expect(controller.page, closeTo(0, 0.01));
    expect(
      _transform(tester).transform.getMaxScaleOnAxis(),
      closeTo(1.75, 0.01),
    );
    await gesture.up();
  });

  testWidgets('quick drag still turns a PageView page', (tester) async {
    final controller = PageController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_buildPageViewSubject(controller: controller));

    await tester.drag(find.byKey(_surfaceKey), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(controller.page, closeTo(1, 0.01));
  });

  testWidgets('single and double tap callbacks remain available', (
    tester,
  ) async {
    final controller = PageController();
    addTearDown(controller.dispose);
    var taps = 0;
    var doubleTaps = 0;
    await tester.pumpWidget(
      _buildPageViewSubject(
        controller: controller,
        onTap: () => taps++,
        onDoubleTap: () => doubleTaps++,
      ),
    );

    await tester.tap(find.byKey(_surfaceKey));
    await tester.pump(const Duration(milliseconds: 400));
    expect(taps, 1);
    expect(doubleTaps, 0);

    await tester.tap(find.byKey(_surfaceKey));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(_surfaceKey));
    await tester.pump(const Duration(milliseconds: 400));
    expect(taps, 1);
    expect(doubleTaps, 1);
  });
}
