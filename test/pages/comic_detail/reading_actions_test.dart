import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/pages/comic_detail/reading_actions.dart';

import '../../test_helpers.dart';

void main() {
  setUp(setupSecureCredentialStoreForTest);
  tearDown(teardownSecureCredentialStoreForTest);

  Future<void> pumpActions(
    WidgetTester tester, {
    double width = 288,
    double textScale = 1,
    VoidCallback? onContinue,
    VoidCallback? onNext,
    VoidCallback? onBackToTop,
    bool showBackToTop = true,
  }) => tester.pumpWidget(
    wrapWithApp(
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Align(
            alignment: Alignment.bottomRight,
            child: SizedBox(
              width: width,
              child: ComicDetailReadingActions(
                continueLabel: '第123话 很长的章节名 · 20/30',
                onContinue: onContinue ?? () {},
                nextLabel: '第124话 下一章节名称',
                onNext: onNext ?? () {},
                onBackToTop: showBackToTop ? onBackToTop ?? () {} : null,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  for (final scale in [1.0, 1.35, 2.0, 3.0]) {
    testWidgets('详情 FAB 在 ${scale}x 字号下保留同行顺序且不溢出', (tester) async {
      await pumpActions(tester, textScale: scale);
      expect(tester.takeException(), isNull);
      final continuing = tester.getRect(
        find.byKey(const ValueKey('comic_continue_action')),
      );
      final next = tester.getRect(
        find.byKey(const ValueKey('comic_next_action')),
      );
      final backToTop = tester.getRect(
        find.byKey(const ValueKey('comic_back_to_top_action')),
      );
      final row = tester.getRect(find.byType(ComicDetailReadingActions));
      expect(backToTop.center.dy, closeTo(continuing.center.dy, 0.01));
      expect(next.center.dy, closeTo(continuing.center.dy, 0.01));
      expect(backToTop.right, lessThan(next.left));
      expect(next.right, lessThan(continuing.left));
      expect(backToTop.left, closeTo(row.left, 0.01));
      expect(continuing.right, closeTo(row.right, 0.01));
    });
  }

  testWidgets('悬浮 FAB 没有共用的不透明底板', (tester) async {
    await pumpActions(tester);
    final subject = find.byType(ComicDetailReadingActions);
    final materials = find.descendant(
      of: subject,
      matching: find.byType(Material),
    );
    for (final action in ['continue', 'next', 'back_to_top']) {
      expect(
        find.ancestor(
          of: find.byKey(ValueKey('comic_${action}_action')),
          matching: materials,
        ),
        findsNothing,
      );
    }
  });

  testWidgets('下一话使用主色，继续阅读和回顶使用次色', (tester) async {
    await pumpActions(tester);
    final cs = Theme.of(
      tester.element(find.byType(ComicDetailReadingActions)),
    ).colorScheme;
    final next = tester.widget<FloatingActionButton>(
      find.byKey(const ValueKey('comic_next_action')),
    );
    final continuing = tester.widget<FloatingActionButton>(
      find.byKey(const ValueKey('comic_continue_action')),
    );
    final backToTop = tester.widget<FloatingActionButton>(
      find.byKey(const ValueKey('comic_back_to_top_action')),
    );
    expect(next.backgroundColor, cs.primaryContainer);
    expect(next.foregroundColor, cs.onPrimaryContainer);
    for (final secondary in [continuing, backToTop]) {
      expect(secondary.backgroundColor, cs.secondaryContainer);
      expect(secondary.foregroundColor, cs.onSecondaryContainer);
    }
  });

  testWidgets('没有下一话时继续阅读使用主色', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        ComicDetailReadingActions(continueLabel: '继续阅读', onContinue: () {}),
      ),
    );
    final cs = Theme.of(
      tester.element(find.byType(ComicDetailReadingActions)),
    ).colorScheme;
    final continuing = tester.widget<FloatingActionButton>(
      find.byKey(const ValueKey('comic_continue_action')),
    );
    expect(continuing.backgroundColor, cs.primaryContainer);
    expect(continuing.foregroundColor, cs.onPrimaryContainer);
  });

  testWidgets('继续阅读、下一话、回顶保留各自回调', (tester) async {
    final calls = <String>[];
    await pumpActions(
      tester,
      onContinue: () => calls.add('continue'),
      onNext: () => calls.add('next'),
      onBackToTop: () => calls.add('back_to_top'),
    );
    for (final action in ['continue', 'next', 'back_to_top']) {
      await tester.tap(find.byKey(ValueKey('comic_${action}_action')));
    }
    final backToTop = find.byTooltip('回到顶部');
    expect(calls, ['continue', 'next', 'back_to_top']);
    expect(tester.getSize(backToTop).shortestSide, greaterThanOrEqualTo(48));
    expect(find.byIcon(Icons.vertical_align_top), findsOneWidget);
  });

  testWidgets('回顶的显隐不改变右侧阅读按钮的位置', (tester) async {
    final next = find.byKey(const ValueKey('comic_next_action'));
    final continuing = find.byKey(const ValueKey('comic_continue_action'));
    await pumpActions(tester, textScale: 2, showBackToTop: false);
    final nextRect = tester.getRect(next);
    final continueRect = tester.getRect(continuing);
    expect(find.byTooltip('回到顶部'), findsNothing);

    await pumpActions(tester, textScale: 2);
    expect(find.byTooltip('回到顶部'), findsOneWidget);
    expect(tester.getRect(next), nextRect);
    expect(tester.getRect(continuing), continueRect);
  });

  testWidgets('没有阅读历史时也能单独显示回顶按钮', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        ComicDetailReadingActions(
          continueLabel: '',
          onContinue: null,
          onBackToTop: () {},
        ),
      ),
    );
    expect(find.byKey(const ValueKey('comic_continue_action')), findsNothing);
    expect(find.byKey(const ValueKey('comic_next_action')), findsNothing);
    final backToTop = find.byType(FloatingActionButton);
    expect(backToTop, findsOneWidget);
    expect(
      tester.getTopLeft(backToTop).dx,
      tester.getTopLeft(find.byType(ComicDetailReadingActions)).dx,
    );
  });
}
