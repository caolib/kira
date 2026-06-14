import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/general_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

    await tester.pumpWidget(const MaterialApp(home: GeneralPage()));
    await tester.pumpAndSettle();

    final resetButton = find.widgetWithText(FilledButton, '重置应用');
    await tester.scrollUntilVisible(resetButton, 100);
    await tester.tap(resetButton);
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

  testWidgets('anime feature switch updates setting', (tester) async {
    final user = UserManager();
    await user.init();

    await tester.pumpWidget(const MaterialApp(home: GeneralPage()));
    await tester.pumpAndSettle();

    expect(user.animeFeatureEnabled, isTrue);
    expect(find.text('动漫功能'), findsOneWidget);

    await tester.tap(find.text('动漫功能'));
    await tester.pumpAndSettle();

    expect(user.animeFeatureEnabled, isFalse);
  });
}
