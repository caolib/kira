import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/general_page.dart';
import 'package:kira/widgets/setting_action_tile.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'user_token': 'token',
      'saved_username': 'alice',
      'saved_password': 'secret',
      'auto_login': true,
    });
  });

  testWidgets('reset app requires exact confirmation text', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await UserManager().init();

    await tester.pumpWidget(
      wrapWithApp(const GeneralPage(), wrapInScaffold: false),
    );
    await tester.pumpAndSettle();

    // 重置应用入口从红色卡片按钮改为普通 ListTile，点击弹出确认对话框。
    final resetTile = find.text('重置应用').first;
    await tester.scrollUntilVisible(resetTile, 100);
    await tester.tap(resetTile);
    await tester.pumpAndSettle();

    FilledButton button() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '确认重置'));

    expect(button().onPressed, isNull);

    await tester.enterText(find.byType(TextField).last, '重置');
    await tester.pump();
    expect(button().onPressed, isNull);

    await tester.enterText(find.byType(TextField).last, '重置应用');
    await tester.pump();
    expect(button().onPressed, isNotNull);
  });

  testWidgets('export and import sit on the same row', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await UserManager().init();

    await tester.pumpWidget(
      wrapWithApp(const GeneralPage(), wrapInScaffold: false),
    );
    await tester.pumpAndSettle();

    final exportTile = find.ancestor(
      of: find.text('导出设置'),
      matching: find.byType(SettingActionTile),
    );
    final importTile = find.ancestor(
      of: find.text('导入设置'),
      matching: find.byType(SettingActionTile),
    );
    expect(exportTile, findsOneWidget);
    expect(importTile, findsOneWidget);

    final exportRect = tester.getRect(exportTile);
    final importRect = tester.getRect(importTile);

    // 同一行并排:纵向对齐、横向不重叠,且导出在导入左侧。
    expect(exportRect.top, closeTo(importRect.top, 0.01));
    expect(exportRect.height, closeTo(importRect.height, 0.01));
    expect(exportRect.right, lessThanOrEqualTo(importRect.left + 0.01));

    // 两项不再作为带副标题的 ListTile 各占一行。
    expect(
      find.ancestor(of: find.text('导出设置'), matching: find.byType(ListTile)),
      findsNothing,
    );
  });
}
