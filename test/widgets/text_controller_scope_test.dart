import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/widgets/text_controller_scope.dart';

import '../test_helpers.dart';

void main() {
  group('TextControllerScope', () {
    late ValueNotifier<int> rebuild;
    late TextEditingController controller;

    setUp(() => rebuild = ValueNotifier<int>(0));
    tearDown(() => rebuild.dispose());

    /// 打开一个含 TextField 的弹窗；[rebuild] 自增即可重建弹窗子树。
    Future<void> openDialog(WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => TextControllerScope(
                  initialText: '初始文本',
                  builder: (dialogContext, c) {
                    controller = c;
                    return ValueListenableBuilder<int>(
                      valueListenable: rebuild,
                      builder: (context, _, _) =>
                          AlertDialog(content: TextField(controller: c)),
                    );
                  },
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
    }

    testWidgets('provides a controller seeded with initialText', (
      tester,
    ) async {
      await openDialog(tester);

      expect(controller.text, '初始文本');
      expect(find.text('初始文本'), findsOneWidget);
    });

    testWidgets('controller survives a rebuild during the exit transition', (
      tester,
    ) async {
      await openDialog(tester);
      await tester.enterText(find.byType(TextField), '评论内容');

      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pump();

      // 发表成功后弹 toast / 撒花会插入 OverlayEntry，退出动画期间弹窗子树因此重建，
      // TextField 随之重新订阅 controller —— 控制器若已提前释放就会抛断言。
      rebuild.value++;
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('disposes the controller once the route is gone', (
      tester,
    ) async {
      await openDialog(tester);

      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      expect(() => controller.addListener(() {}), throwsFlutterError);
    });
  });
}
