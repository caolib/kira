import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/widgets/pinch_zoomable.dart';

void main() {
  Matrix4 transformOf(WidgetTester tester) =>
      tester.widget<Transform>(find.byType(Transform)).transform;

  Future<void> pinch(
    WidgetTester tester, {
    required Offset finger1,
    required Offset finger2,
    required Offset delta1,
    required Offset delta2,
  }) async {
    final g1 = await tester.startGesture(finger1);
    final g2 = await tester.startGesture(finger2);
    await tester.pump();
    const steps = 10.0;
    for (var i = 0; i < steps; i++) {
      await g1.moveBy(delta1 / steps);
      await g2.moveBy(delta2 / steps);
      await tester.pump(const Duration(milliseconds: 16));
    }
    // 停顿再抬手，避免抬手速度触发惯性动画干扰断言。
    await tester.pump(const Duration(milliseconds: 100));
    await g1.up();
    await g2.up();
    await tester.pumpAndSettle();
  }

  Future<void> drag(
    WidgetTester tester, {
    required Offset from,
    required Offset delta,
  }) async {
    final gesture = await tester.startGesture(from);
    await tester.pump();
    const steps = 10.0;
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(delta / steps);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('双指捏合扩大可放大视图', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: PinchZoomable(child: ColoredBox(color: Colors.white)),
      ),
    );

    await pinch(
      tester,
      finger1: const Offset(200, 200),
      finger2: const Offset(600, 400),
      delta1: const Offset(-90, -90),
      delta2: const Offset(90, 90),
    );

    expect(transformOf(tester).getMaxScaleOnAxis(), greaterThan(1.5));
  });

  testWidgets('非对称捏合不被父级滚动手势抢先', (tester) async {
    // 复现真实场景：父级是可滚动列表（拖动阈值 18px 小于缩放阈值 36px），
    // 一根手指基本不动、另一根大幅移动的捏合会被识别成滚动。
    var scrolled = false;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (_) => scrolled = true,
          child: const PinchZoomable(child: ColoredBox(color: Colors.white)),
        ),
      ),
    );

    final g1 = await tester.startGesture(const Offset(400, 300));
    await tester.pump();
    final g2 = await tester.startGesture(const Offset(500, 300));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await g2.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 100));
    await g1.up();
    await g2.up();
    await tester.pumpAndSettle();

    expect(transformOf(tester).getMaxScaleOnAxis(), greaterThan(1.5));
    expect(scrolled, isFalse);
  });

  testWidgets('缩放不超过上限', (tester) async {
    final controller = PinchZoomController(maxScale: 2.0);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PinchZoomable(
          controller: controller,
          child: const ColoredBox(color: Colors.white),
        ),
      ),
    );

    await pinch(
      tester,
      finger1: const Offset(200, 200),
      finger2: const Offset(600, 400),
      delta1: const Offset(-300, -300),
      delta2: const Offset(300, 300),
    );

    expect(controller.scale, closeTo(2.0, 0.01));
  });

  testWidgets('未放大时单指拖动不平移视图', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: PinchZoomable(child: ColoredBox(color: Colors.white)),
      ),
    );

    await drag(
      tester,
      from: const Offset(400, 300),
      delta: const Offset(80, 0),
    );

    expect(transformOf(tester), equals(Matrix4.identity()));
  });

  testWidgets('放大后单指拖动平移视图', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: PinchZoomable(child: ColoredBox(color: Colors.white)),
      ),
    );

    await pinch(
      tester,
      finger1: const Offset(200, 200),
      finger2: const Offset(600, 400),
      delta1: const Offset(-60, -60),
      delta2: const Offset(60, 60),
    );
    final before = transformOf(tester);

    await drag(
      tester,
      from: const Offset(400, 300),
      delta: const Offset(80, 0),
    );

    expect(transformOf(tester), isNot(equals(before)));
    expect(
      transformOf(tester).getMaxScaleOnAxis(),
      closeTo(before.getMaxScaleOnAxis(), 0.01),
    );
  });

  testWidgets('双指收拢后回到最小缩放', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: PinchZoomable(child: ColoredBox(color: Colors.white)),
      ),
    );

    await pinch(
      tester,
      finger1: const Offset(200, 200),
      finger2: const Offset(600, 400),
      delta1: const Offset(-60, -60),
      delta2: const Offset(60, 60),
    );
    // 反向捏合：双指收拢回到原位。
    await pinch(
      tester,
      finger1: const Offset(110, 110),
      finger2: const Offset(690, 490),
      delta1: const Offset(90, 90),
      delta2: const Offset(-90, -90),
    );

    final value = transformOf(tester);
    expect(value.getMaxScaleOnAxis(), closeTo(1.0, 0.01));
    // 允许浮点残差。
    expect(value.getTranslation().length, lessThan(0.01));
  });

  testWidgets('单击手势穿透到子组件', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PinchZoomable(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const ColoredBox(color: Colors.white),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(GestureDetector).last);
    await tester.pumpAndSettle();

    expect(taps, 1);
  });

  testWidgets('onZoomChanged 在放大/复原时各回调一次', (tester) async {
    final zoomStates = <bool>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PinchZoomable(
          onZoomChanged: zoomStates.add,
          child: const ColoredBox(color: Colors.white),
        ),
      ),
    );

    await pinch(
      tester,
      finger1: const Offset(200, 200),
      finger2: const Offset(600, 400),
      delta1: const Offset(-90, -90),
      delta2: const Offset(90, 90),
    );
    expect(zoomStates, [true]);

    await pinch(
      tester,
      finger1: const Offset(110, 110),
      finger2: const Offset(690, 490),
      delta1: const Offset(90, 90),
      delta2: const Offset(-90, -90),
    );
    expect(zoomStates, [true, false]);
  });

  testWidgets('外部 pan：未放大时无效，放大后平移视野', (tester) async {
    final controller = PinchZoomController();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PinchZoomable(
          controller: controller,
          child: const ColoredBox(color: Colors.white),
        ),
      ),
    );

    controller.pan(const Offset(50, 0));
    await tester.pump();
    expect(controller.zoomed, isFalse);
    expect(controller.transform, equals(Matrix4.identity()));

    await pinch(
      tester,
      finger1: const Offset(200, 200),
      finger2: const Offset(600, 400),
      delta1: const Offset(-90, -90),
      delta2: const Offset(90, 90),
    );
    expect(controller.zoomed, isTrue);
    final before = controller.transform;

    controller.pan(const Offset(50, 0));
    await tester.pump();
    expect(controller.transform, isNot(equals(before)));
  });

  testWidgets('单指拖动松手后按速度启动惯性（手势结束驱动）', (tester) async {
    final controller = PinchZoomController();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PinchZoomable(
          controller: controller,
          child: const ColoredBox(color: Colors.white),
        ),
      ),
    );

    await pinch(
      tester,
      finger1: const Offset(200, 200),
      finger2: const Offset(600, 400),
      delta1: const Offset(-90, -90),
      delta2: const Offset(90, 90),
    );
    expect(controller.zoomed, isTrue);
    // 单指快速向上拖后松手：松手速度应驱动惯性继续向上滑行。
    // 合成事件需显式递增时间戳，否则识别器算出的速度为零。
    final pointer = TestPointer();
    await tester.sendEventToBinding(
      pointer.down(
        const Offset(400, 300),
        timeStamp: const Duration(milliseconds: 1000),
      ),
    );
    await tester.pump();
    for (var i = 1; i <= 5; i++) {
      await tester.sendEventToBinding(
        pointer.move(
          Offset(400, 300 - 20.0 * i),
          timeStamp: Duration(milliseconds: 1000 + 16 * i),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.sendEventToBinding(
      pointer.up(timeStamp: const Duration(milliseconds: 1090)),
    );
    await tester.pump();
    final atRelease = controller.offset;
    await tester.pump(const Duration(milliseconds: 120));
    expect(controller.offset.dy, lessThan(atRelease.dy));
    controller.stopFling();
  });

  testWidgets('beginFling 惯性滑行：沿速度方向衰减滑行', (tester) async {
    final controller = PinchZoomController();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PinchZoomable(
          controller: controller,
          child: const ColoredBox(color: Colors.white),
        ),
      ),
    );

    await pinch(
      tester,
      finger1: const Offset(200, 200),
      finger2: const Offset(600, 400),
      delta1: const Offset(-90, -90),
      delta2: const Offset(90, 90),
    );
    expect(controller.zoomed, isTrue);

    // 向左甩（负 dx）：视野应继续向左滑行（offset 减小）。
    controller.beginFling(const Offset(-600, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(controller.offset.dx, lessThan(0));

    controller.stopFling();
    final stopped = controller.offset.dx;
    await tester.pump(const Duration(milliseconds: 120));
    expect(controller.offset.dx, equals(stopped));
  });

  testWidgets('beginFling 顶到边界即停', (tester) async {
    final controller = PinchZoomController();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PinchZoomable(
          controller: controller,
          child: const ColoredBox(color: Colors.white),
        ),
      ),
    );

    await pinch(
      tester,
      finger1: const Offset(200, 200),
      finger2: const Offset(600, 400),
      delta1: const Offset(-90, -90),
      delta2: const Offset(90, 90),
    );

    // 先把视野平移到右边界（offset 上限 0），再正向甩：应立即被夹紧不动。
    controller.pan(const Offset(400, 0));
    expect(controller.offset.dx, equals(0.0));

    controller.beginFling(const Offset(600, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(controller.offset.dx, equals(0.0));
  });

  testWidgets('active 变为 false 时自动复位缩放', (tester) async {
    Widget buildSubject(bool active) => Directionality(
      textDirection: TextDirection.ltr,
      child: PinchZoomable(
        active: active,
        child: const ColoredBox(color: Colors.white),
      ),
    );

    await tester.pumpWidget(buildSubject(true));
    await pinch(
      tester,
      finger1: const Offset(200, 200),
      finger2: const Offset(600, 400),
      delta1: const Offset(-90, -90),
      delta2: const Offset(90, 90),
    );
    expect(transformOf(tester).getMaxScaleOnAxis(), greaterThan(1.5));

    await tester.pumpWidget(buildSubject(false));
    final value = transformOf(tester);
    expect(value.getMaxScaleOnAxis(), closeTo(1.0, 0.01));
    expect(value.getTranslation().length, lessThan(0.01));
  });

  testWidgets('捏合中途抬指：滑行延迟到全部抬起后启动', (tester) async {
    final controller = PinchZoomController();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PinchZoomable(
          controller: controller,
          child: const ColoredBox(color: Colors.white),
        ),
      ),
    );

    await pinch(
      tester,
      finger1: const Offset(200, 200),
      finger2: const Offset(600, 400),
      delta1: const Offset(-90, -90),
      delta2: const Offset(90, 90),
    );
    expect(controller.zoomed, isTrue);

    // 双指快速上滑后先抬一指，另一指仍按在屏上。
    // 合成事件需显式递增时间戳，否则识别器算出的速度为零。
    final g1 = await tester.startGesture(const Offset(300, 400));
    final g2 = await tester.startGesture(const Offset(500, 400));
    await tester.pump();
    for (var i = 1; i <= 5; i++) {
      await g1.moveBy(
        const Offset(0, -20),
        timeStamp: Duration(milliseconds: 16 * i),
      );
      await g2.moveBy(
        const Offset(0, -20),
        timeStamp: Duration(milliseconds: 16 * i),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    final atLift = controller.offset;
    await g1.up(timeStamp: const Duration(milliseconds: 96));
    await tester.pump();
    // 剩余手指仍在屏上：不得立即启动惯性滑行（否则与后续操控叠加）。
    expect(controller.offset, atLift);

    await g2.up(timeStamp: const Duration(milliseconds: 100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    // 全部抬起后才按抬指速度启动滑行。
    expect(controller.offset.dy, lessThan(atLift.dy));
    controller.stopFling();
  });

  testWidgets('快速双指同帧抬起仍按松手速度滑行', (tester) async {
    final controller = PinchZoomController();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PinchZoomable(
          controller: controller,
          child: const ColoredBox(color: Colors.white),
        ),
      ),
    );

    await pinch(
      tester,
      finger1: const Offset(200, 200),
      finger2: const Offset(600, 400),
      delta1: const Offset(-90, -90),
      delta2: const Offset(90, 90),
    );
    expect(controller.zoomed, isTrue);

    // 双指快速上滑后同帧抬起（onEnd 只触发一次，pointerCount 仍大于 0）。
    final g1 = await tester.startGesture(const Offset(300, 400));
    final g2 = await tester.startGesture(const Offset(500, 400));
    await tester.pump();
    for (var i = 1; i <= 5; i++) {
      await g1.moveBy(
        const Offset(0, -20),
        timeStamp: Duration(milliseconds: 16 * i),
      );
      await g2.moveBy(
        const Offset(0, -20),
        timeStamp: Duration(milliseconds: 16 * i),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    final atRelease = controller.offset;
    await g1.up(timeStamp: const Duration(milliseconds: 96));
    await g2.up(timeStamp: const Duration(milliseconds: 96));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(controller.offset.dy, lessThan(atRelease.dy));
    controller.stopFling();
  });

  testWidgets('isScaleGestureActive 标记缩放手势占用区间', (tester) async {
    var dragged = false;
    final controller = PinchZoomController();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (_) => dragged = true,
          child: PinchZoomable(
            controller: controller,
            child: const ColoredBox(color: Colors.white),
          ),
        ),
      ),
    );

    // 单指拖动：父级拖动手势（pan slop 36px）抢先赢下竞技场，缩放识别器未接管。
    final g1 = await tester.startGesture(const Offset(400, 300));
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await g1.moveBy(const Offset(0, 30));
      await tester.pump();
    }
    expect(dragged, isTrue);
    expect(controller.isScaleGestureActive, isFalse);
    await g1.up();
    await tester.pumpAndSettle();

    // 双指捏合（第二指落下立即接管）：onStart 置位，全部抬起后经
    // onGestureEnded 复位。
    final g2 = await tester.startGesture(const Offset(400, 300));
    final g3 = await tester.startGesture(const Offset(500, 300));
    await tester.pump();
    expect(controller.isScaleGestureActive, isTrue);

    await g2.up();
    await g3.up();
    await tester.pumpAndSettle();
    expect(controller.isScaleGestureActive, isFalse);
  });
}
