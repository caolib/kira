import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/widgets/app_sheet.dart';

import '../test_helpers.dart';

Future<void> _openSheet(
  WidgetTester tester, {
  required Widget child,
  double? heightFactor,
  double? maxHeightFactor,
  EdgeInsets padding = EdgeInsets.zero,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 800);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    wrapWithApp(
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showAppSheet<void>(
            context,
            heightFactor: heightFactor,
            maxHeightFactor: maxHeightFactor,
            child: child,
          ),
          child: const Text('打开'),
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(padding: padding),
        child: child!,
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(setupSecureCredentialStoreForTest);
  tearDown(teardownSecureCredentialStoreForTest);

  testWidgets('弹层打开后随窗口调整宽度，宽屏限宽并居中', (tester) async {
    await _openSheet(
      tester,
      child: const SizedBox(width: double.infinity, height: 80),
    );
    final sheet = find.byType(AppSheet);
    expect(tester.getRect(sheet).width, closeTo(400, 0.01));

    tester.view.physicalSize = const Size(1000, 800);
    await tester.pumpAndSettle();
    final wideRect = tester.getRect(sheet);
    expect(wideRect.width, closeTo(640, 0.01));
    expect(wideRect.center.dx, closeTo(500, 0.01));
    expect(wideRect.bottom, closeTo(800, 0.01));

    tester.view.physicalSize = const Size(375, 800);
    await tester.pumpAndSettle();
    expect(tester.getRect(sheet).width, closeTo(375, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('最大高度包含把手和底部安全区，长内容可以滚动', (tester) async {
    await _openSheet(
      tester,
      maxHeightFactor: 0.7,
      padding: const EdgeInsets.only(top: 24, bottom: 32),
      child: SingleChildScrollView(
        child: Column(
          children: [
            for (var index = 0; index < 30; index++)
              SizedBox(height: 64, child: Text('设置 $index')),
          ],
        ),
      ),
    );
    final rect = tester.getRect(find.byType(AppSheet));
    expect(rect.height, closeTo(560, 0.01));
    expect(rect.bottom, closeTo(800, 0.01));
    await tester.ensureVisible(find.text('设置 29'));
    await tester.pumpAndSettle();
    expect(find.text('设置 29').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('最大高度不是固定高度，短内容依然按内容收缩', (tester) async {
    await _openSheet(
      tester,
      maxHeightFactor: 0.7,
      padding: const EdgeInsets.only(bottom: 32),
      child: const SizedBox(height: 80, width: 400),
    );
    final rect = tester.getRect(find.byType(AppSheet));
    expect(rect.height, closeTo(80 + 16 + 32, 0.01));
    expect(rect.bottom, closeTo(800, 0.01));
  });

  testWidgets('未指定上限时保持既有按内容布局', (tester) async {
    await _openSheet(tester, child: const SizedBox(height: 640, width: 400));
    expect(tester.getSize(find.byType(AppSheet)).height, closeTo(656, 0.01));
  });

  testWidgets('既有固定高度参数仍然扩展到指定比例', (tester) async {
    await _openSheet(
      tester,
      heightFactor: 0.85,
      child: const SizedBox(height: 80, width: 400),
    );
    final sheet = find.descendant(
      of: find.byType(AppSheet),
      matching: find.byWidgetPredicate(
        (widget) => widget is Material && widget.clipBehavior == Clip.antiAlias,
      ),
    );
    expect(tester.getSize(sheet).height, closeTo(680, 0.01));
  });

  testWidgets('reduced motion opens and closes a sheet without a transition', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapWithApp(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAppSheet<void>(
                  context,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump();
    final route = ModalRoute.of(tester.element(find.text('关闭')))!;
    expect(route.animation!.value, 1);
    expect(route.animation!.isAnimating, isFalse);
    await tester.tap(find.text('关闭'));
    await tester.pump();
    await tester.pump();
    expect(find.text('关闭'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
