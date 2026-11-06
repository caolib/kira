import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/widgets/crossfade_carousel.dart';

import '../test_helpers.dart';

class _Harness {
  final options = ValueNotifier((count: 3, reduced: false, enabled: true));
  final pages = <int>[];
  final taps = <int>[];

  Future<void> mount(WidgetTester tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      options.dispose();
    });
    await tester.pumpWidget(
      wrapWithApp(
        Center(
          child: ValueListenableBuilder(
            valueListenable: options,
            builder: (context, value, _) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: value.reduced),
              child: TickerMode(
                enabled: value.enabled,
                child: SizedBox(
                  width: 320,
                  height: 180,
                  child: CrossfadeCarousel(
                    itemCount: value.count,
                    onPageChanged: pages.add,
                    itemBuilder: (context, index, imageScale) =>
                        GestureDetector(
                          onTap: () => taps.add(index),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Transform.scale(
                                key: ValueKey('image-$index'),
                                scale: imageScale,
                                child: ColoredBox(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                                ),
                              ),
                              Center(child: Text('图片$index')),
                            ],
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
  }

  Finder get carousel => find.byType(CrossfadeCarousel);

  void update({int? count, bool? reduced, bool? enabled}) {
    final current = options.value;
    options.value = (
      count: count ?? current.count,
      reduced: reduced ?? current.reduced,
      enabled: enabled ?? current.enabled,
    );
  }
}

Future<void> _advance(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

void main() {
  setUp(setupSecureCredentialStoreForTest);
  tearDown(teardownSecureCredentialStoreForTest);

  testWidgets('自动交叉淡化不平移外框，只对新图片微缩放', (tester) async {
    final h = _Harness();
    await h.mount(tester);
    final frame = tester.getRect(h.carousel);
    final titlePosition = tester.getCenter(find.text('图片0'));
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.getRect(h.carousel), frame);
    expect(tester.getCenter(find.text('图片1')), titlePosition);
    final opacity = tester.widget<Opacity>(find.byType(Opacity));
    expect(opacity.opacity, greaterThan(0));
    expect(opacity.opacity, lessThan(1));
    final image = tester.widget<Transform>(
      find.byKey(const ValueKey('image-1')),
    );
    expect(image.transform.storage[0], greaterThan(1));
    expect(image.transform.storage[0], lessThan(1.02));
    expect(h.pages, isEmpty);

    await tester.pumpAndSettle();
    expect(h.pages, [1]);
    expect(find.text('图片0'), findsNothing);
    expect(find.text('图片1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('自动轮播从最后一项无缝回到第一项', (tester) async {
    final h = _Harness();
    await h.mount(tester);
    await _advance(tester);
    await _advance(tester);
    await _advance(tester);
    expect(h.pages, [1, 2, 0]);
    expect(find.text('图片0'), findsOneWidget);
  });

  testWidgets('拖动跟手淡化，期间暂停自动轮播并在松手后重新计时', (tester) async {
    final h = _Harness();
    await h.mount(tester);
    await tester.pump(const Duration(seconds: 4));
    final gesture = await tester.startGesture(tester.getCenter(h.carousel));
    await gesture.moveBy(const Offset(-30, 0));
    await gesture.moveBy(const Offset(-100, 0));
    await tester.pump();
    expect(find.text('图片1'), findsOneWidget);
    expect(h.pages, isEmpty);
    await tester.pump(const Duration(seconds: 6));
    expect(h.pages, isEmpty);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(h.pages, [1]);
    await tester.pump(const Duration(seconds: 4));
    expect(h.pages, [1]);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(h.pages, [1, 2]);
  });

  testWidgets('短距离拖动与取消手势回退，右滑循环到最后一项', (tester) async {
    final h = _Harness();
    await h.mount(tester);
    final short = await tester.startGesture(tester.getCenter(h.carousel));
    await short.moveBy(const Offset(-30, 0));
    await short.moveBy(const Offset(-10, 0));
    await tester.pump(const Duration(milliseconds: 300));
    await short.up();
    await tester.pumpAndSettle();
    expect(h.pages, isEmpty);
    expect(find.text('图片0'), findsOneWidget);

    final canceled = await tester.startGesture(tester.getCenter(h.carousel));
    await canceled.moveBy(const Offset(-30, 0));
    await canceled.moveBy(const Offset(-150, 0));
    await tester.pump();
    await canceled.cancel();
    await tester.pumpAndSettle();
    expect(h.pages, isEmpty);

    await tester.drag(h.carousel, const Offset(130, 0));
    await tester.pumpAndSettle();
    expect(h.pages, [2]);
    expect(find.text('图片2'), findsOneWidget);
  });

  testWidgets('快速短滑也能切换，单次长拖动只翻一项', (tester) async {
    final h = _Harness();
    await h.mount(tester);
    await tester.fling(h.carousel, const Offset(-50, 0), 1500);
    await tester.pumpAndSettle();
    expect(h.pages, [1]);
    await tester.drag(h.carousel, const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(h.pages, [1, 2]);
  });

  testWidgets('拖动可以打断自动过渡并反向恢复原项', (tester) async {
    final h = _Harness();
    await h.mount(tester);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 80));
    final gesture = await tester.startGesture(tester.getCenter(h.carousel));
    await gesture.moveBy(const Offset(30, 0));
    await gesture.moveBy(const Offset(180, 0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(h.pages, isEmpty);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(h.pages, isEmpty);
    expect(find.text('图片0'), findsOneWidget);
  });

  testWidgets('交叠期间只有当前占主导的图片响应点击与无障碍', (tester) async {
    final h = _Harness();
    await h.mount(tester);
    final semantics = tester.ensureSemantics();
    try {
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 30));
      await tester.tap(h.carousel);
      expect(h.taps, [0]);
      expect(find.bySemanticsLabel('图片0'), findsOneWidget);
      expect(find.bySemanticsLabel('图片1'), findsNothing);
      await tester.pump(const Duration(milliseconds: 130));
      await tester.tap(h.carousel);
      expect(h.taps, [0, 1]);
      expect(find.bySemanticsLabel('图片0'), findsNothing);
      expect(find.bySemanticsLabel('图片1'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('减少动画关闭自动轮播，手动松手瞬时切换且不缩放', (tester) async {
    final h = _Harness();
    h.update(reduced: true);
    await h.mount(tester);
    await tester.pump(const Duration(seconds: 20));
    expect(h.pages, isEmpty);
    final gesture = await tester.startGesture(tester.getCenter(h.carousel));
    await gesture.moveBy(const Offset(-30, 0));
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump();
    expect(find.text('图片1'), findsNothing);
    await gesture.up();
    await tester.pump();
    expect(h.pages, [1]);
    expect(find.byType(Opacity), findsNothing);
    expect(
      tester
          .widget<Transform>(find.byKey(const ValueKey('image-1')))
          .transform
          .storage[0],
      1,
    );
    await tester.pump(const Duration(seconds: 20));
    expect(h.pages, [1]);
  });

  testWidgets('过渡中开启减少动画立即收尾，重新开启后恢复轮播', (tester) async {
    final h = _Harness();
    await h.mount(tester);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 160));
    h.update(reduced: true);
    await tester.pump();
    await tester.pump();
    expect(h.pages, [1]);
    expect(find.byType(Opacity), findsNothing);
    await tester.pump(const Duration(seconds: 20));
    expect(h.pages, [1]);
    h.update(reduced: false);
    await tester.pump();
    await _advance(tester);
    expect(h.pages, [1, 2]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('保留左右方向键切换并兼容减少动画', (tester) async {
    final h = _Harness();
    await h.mount(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(h.pages, [1]);
    h.update(reduced: true);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(h.pages, [1, 0]);
    expect(find.byType(Opacity), findsNothing);
  });

  testWidgets('隐藏分支不自动轮播，重新激活后恢复计时', (tester) async {
    final h = _Harness();
    await h.mount(tester);
    h.update(enabled: false);
    await tester.pump();
    await tester.pump(const Duration(seconds: 20));
    expect(h.pages, isEmpty);
    h.update(enabled: true);
    await tester.pump();
    await _advance(tester);
    expect(h.pages, [1]);
  });

  testWidgets('过渡中数据数量改变安全复位，空数据与单项不轮播', (tester) async {
    final h = _Harness();
    await h.mount(tester);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 160));
    h.update(count: 0);
    await tester.pump();
    expect(find.text('图片0'), findsNothing);
    await tester.pump(const Duration(seconds: 10));
    h.update(count: 1);
    await tester.pump();
    await tester.drag(h.carousel, const Offset(-150, 0));
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('图片0'), findsOneWidget);
    expect(find.text('图片1'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
