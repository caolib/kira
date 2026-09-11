import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/general_page.dart';

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
}
