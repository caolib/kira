import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/widgets/expandable_comment_text.dart';

import '../test_helpers.dart';

const _longText = '第一行文字\n第二行文字\n第三行文字必须清晰\n第四行隐藏内容\n第五行完整内容';

void main() {
  setUp(setupSecureCredentialStoreForTest);
  tearDown(teardownSecureCredentialStoreForTest);

  Widget content({
    String text = _longText,
    bool reduced = true,
    bool dark = false,
    double scale = 1,
    double width = 300,
    VoidCallback? onTap,
  }) => wrapWithApp(
    Theme(
      data: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      child: MediaQuery(
        data: MediaQueryData(
          disableAnimations: reduced,
          textScaler: TextScaler.linear(scale),
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: GestureDetector(
              onTap: onTap,
              child: ExpandableCommentText(
                text: text,
                style: const TextStyle(fontSize: 16, height: 1.55),
                backgroundColor: dark ? Colors.black : Colors.white,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('三行清晰截断，无渐隐或分隔线，省略号加粗放大，展开后移除', (tester) async {
    await tester.pumpWidget(content());
    final body = find.text(_longText);
    final ellipsis = find.byKey(const ValueKey('comment-collapsed-ellipsis'));
    expect(tester.widget<Text>(body).maxLines, 3);
    expect(tester.widget<Text>(body).overflow, TextOverflow.ellipsis);
    expect(find.byKey(const ValueKey('comment-collapsed-edge')), findsNothing);
    expect(find.byType(Positioned), findsNothing);
    final style = tester.widget<Text>(ellipsis).style!;
    expect(style.fontWeight, FontWeight.w800);
    expect(
      style.fontSize,
      greaterThan(tester.widget<Text>(body).style!.fontSize!),
    );
    final closedHeight = tester
        .getSize(find.byType(ExpandableCommentText))
        .height;
    await tester.tap(find.text('展开全文'));
    await tester.pump();
    expect(tester.widget<Text>(body).maxLines, isNull);
    expect(ellipsis, findsNothing);
    expect(find.text('收起'), findsOneWidget);
    expect(
      tester.getSize(find.byType(ExpandableCommentText)).height,
      greaterThan(closedHeight),
    );
    expect(find.byType(AnimatedSize), findsNothing);
    await tester.tap(find.text('收起'));
    await tester.pump();
    expect(tester.widget<Text>(body).maxLines, 3);
    expect(ellipsis, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('短正文与恰好三行不折叠，点按保留父级回复操作', (tester) async {
    var taps = 0;
    for (final text in ['短正文', '第一行\n第二行\n第三行']) {
      await tester.pumpWidget(content(text: text, onTap: () => taps++));
      expect(find.text('展开全文'), findsNothing);
      expect(
        find.byKey(const ValueKey('comment-collapsed-edge')),
        findsNothing,
      );
      await tester.tap(find.text(text));
    }
    expect(taps, 2);
  });

  testWidgets('折叠与展开不触发父级回复，替换内容重置折叠状态', (tester) async {
    var taps = 0;
    await tester.pumpWidget(content(onTap: () => taps++));
    await tester.tap(find.text('展开全文'));
    await tester.pump();
    expect(taps, 0);
    await tester.pumpWidget(content(text: '新内容\n第二行\n第三行\n第四行'));
    expect(find.text('展开全文'), findsOneWidget);
    expect(tester.widget<Text>(find.text('新内容\n第二行\n第三行\n第四行')).maxLines, 3);
  });

  for (final dark in [false, true]) {
    testWidgets('${dark ? '深色' : '浅色'}大字体窄宽度换行正确折叠且不溢出', (tester) async {
      const text = '这段没有手动换行的长评论在放大字体和较窄的屏幕上会自动换成超过三行，展开后需要显示全部内容。';
      await tester.pumpWidget(
        content(text: text, dark: dark, scale: 2, width: 240),
      );
      expect(find.text('展开全文'), findsOneWidget);
      await tester.tap(find.text('展开全文'));
      await tester.pump();
      expect(tester.widget<Text>(find.text(text)).maxLines, isNull);
      expect(tester.takeException(), isNull);
    });
  }
}
