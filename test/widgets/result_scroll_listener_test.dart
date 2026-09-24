import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/widgets/result_scroll_listener.dart';
import 'package:kira/widgets/shimmer_skeleton.dart';
import 'package:kira/widgets/sliver_comic_grid_skeleton.dart';

void main() {
  testWidgets('vertical result scroll controls back-to-top and pagination', (
    tester,
  ) async {
    var canScrollUp = false;
    var loads = 0;
    const target = ValueKey('scroll-target');
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => ResultScrollListener(
            canScrollUp: canScrollUp,
            onCanScrollUpChanged: (value) {
              setState(() => canScrollUp = value);
            },
            onLoadMore: () => loads++,
            child: const SizedBox.expand(key: target),
          ),
        ),
      ),
    );
    final context = tester.element(find.byKey(target));
    ScrollUpdateNotification(
      metrics: _metrics(pixels: 750),
      context: context,
      scrollDelta: 50,
    ).dispatch(context);
    await tester.pump();
    expect(canScrollUp, isTrue);
    expect(loads, 1);

    ScrollMetricsNotification(
      metrics: _metrics(pixels: 0, maxScrollExtent: 0),
      context: context,
    ).dispatch(context);
    await tester.pump();
    expect(canScrollUp, isFalse);
    expect(loads, 1);
  });

  testWidgets('same-frame scroll reversal reports the final position', (
    tester,
  ) async {
    var canScrollUp = false;
    const target = ValueKey('scroll-target');
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => ResultScrollListener(
            canScrollUp: canScrollUp,
            onCanScrollUpChanged: (value) {
              setState(() => canScrollUp = value);
            },
            child: const SizedBox.expand(key: target),
          ),
        ),
      ),
    );
    final context = tester.element(find.byKey(target));
    for (final pixels in [100.0, 0.0]) {
      ScrollUpdateNotification(
        metrics: _metrics(pixels: pixels),
        context: context,
        scrollDelta: pixels == 0 ? -100 : 100,
      ).dispatch(context);
    }
    await tester.pump();
    expect(canScrollUp, isFalse);
  });

  testWidgets('horizontal notifications do not paginate or show back-to-top', (
    tester,
  ) async {
    var changes = 0;
    var loads = 0;
    const target = ValueKey('scroll-target');
    await tester.pumpWidget(
      MaterialApp(
        home: ResultScrollListener(
          canScrollUp: false,
          onCanScrollUpChanged: (_) => changes++,
          onLoadMore: () => loads++,
          child: const SizedBox.expand(key: target),
        ),
      ),
    );
    final context = tester.element(find.byKey(target));
    final metrics = _metrics(pixels: 950, axis: AxisDirection.right);
    ScrollUpdateNotification(
      metrics: metrics,
      context: context,
      scrollDelta: 50,
    ).dispatch(context);
    ScrollMetricsNotification(
      metrics: metrics,
      context: context,
    ).dispatch(context);
    expect(changes, 0);
    expect(loads, 0);
  });

  testWidgets('inner vertical scroll notifications are ignored', (
    tester,
  ) async {
    var changes = 0;
    var loads = 0;
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ResultScrollListener(
          canScrollUp: false,
          onCanScrollUpChanged: (_) => changes++,
          onLoadMore: () => loads++,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 200,
                  child: ListView.builder(
                    controller: controller,
                    itemExtent: 50,
                    itemCount: 20,
                    itemBuilder: (_, index) => Text('$index'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expect(changes, 0);
    expect(loads, 0);
  });

  testWidgets('skeleton retains the responsive result grid geometry', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CustomScrollView(
          slivers: [
            SliverComicGridSkeleton(horizontalPadding: 16, cardExtent: 160),
          ],
        ),
      ),
    );
    final skeleton = tester.widget<ComicCoverSkeletonGrid>(
      find.byType(ComicCoverSkeletonGrid),
    );
    expect(skeleton.count, 20);
    expect(
      skeleton.gridDelegate,
      isA<SliverGridDelegateWithMaxCrossAxisExtent>(),
    );
    final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
    expect(grid.gridDelegate, same(skeleton.gridDelegate));
    expect(find.byType(ShimmerShell), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

FixedScrollMetrics _metrics({
  required double pixels,
  double maxScrollExtent = 1000,
  AxisDirection axis = AxisDirection.down,
}) {
  return FixedScrollMetrics(
    minScrollExtent: 0,
    maxScrollExtent: maxScrollExtent,
    pixels: pixels,
    viewportDimension: 500,
    axisDirection: axis,
    devicePixelRatio: 1,
  );
}
