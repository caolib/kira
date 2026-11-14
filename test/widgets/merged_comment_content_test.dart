import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/widgets/merged_comment_content.dart';

import '../test_helpers.dart';

void main() {
  setUp(setupSecureCredentialStoreForTest);
  tearDown(teardownSecureCredentialStoreForTest);

  Widget content({bool reduced = false, bool dark = false, double scale = 1}) =>
      wrapWithApp(
        Theme(
          data: ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
          child: MediaQuery(
            data: MediaQueryData(
              disableAnimations: reduced,
              textScaler: TextScaler.linear(scale),
            ),
            child: const Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 280,
                child: MergedCommentContent(
                  count: 10,
                  names: ['甲读者', '乙读者'],
                  avatars: [
                    CircleAvatar(),
                    CircleAvatar(),
                    CircleAvatar(),
                    CircleAvatar(),
                    CircleAvatar(),
                  ],
                  body: Text('合并评论正文'),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('定时轮播并在销毁时清理计时器', (tester) async {
    await tester.pumpWidget(content());
    expect(find.text('甲读者'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('乙读者'), findsOneWidget);
    await tester.pumpWidget(wrapWithApp(const SizedBox()));
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('减少动画停止轮播，切换偏好和成员数量不会越界', (tester) async {
    await tester.pumpWidget(content());
    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(content(reduced: true));
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('甲读者'), findsOneWidget);
    expect(find.text('乙读者'), findsNothing);
    await tester.pumpWidget(
      wrapWithApp(
        const MergedCommentContent(
          count: 2,
          names: ['唯一用户'],
          avatars: [],
          body: Text('正文'),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('${dark ? '深色' : '浅色'}窄屏大字叠放头像与热度人数不溢出', (tester) async {
      await tester.pumpWidget(content(reduced: true, dark: dark, scale: 2));
      await tester.pumpAndSettle();
      expect(find.byType(CircleAvatar), findsNWidgets(5));
      expect(find.text('10'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
