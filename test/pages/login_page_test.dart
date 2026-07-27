import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/login_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _buildTestApp(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('saved accounts are filtered by the selected login source', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'login_source': 'hotmanga',
      'saved_username': 'hot_user',
      'saved_password': 'hot_password',
      'saved_credentials': jsonEncode([
        {
          'username': 'hot_user',
          'password': 'hot_password',
          'login_source': 'hotmanga',
        },
        {
          'username': 'copy_user',
          'password': 'copy_password',
          'login_source': 'copy',
        },
      ]),
    });
    await UserManager().init();

    await tester.pumpWidget(_buildTestApp(const LoginPage()));
    await tester.pumpAndSettle();

    expect(find.text('hot_user'), findsNWidgets(2));
    expect(find.text('copy_user'), findsNothing);
    expect(
      find.byKey(const ValueKey('official-register-hotmanga')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('official-register-copy')), findsNothing);

    await tester.tap(find.text('拷贝漫画'));
    await tester.pumpAndSettle();

    expect(find.text('hot_user'), findsNothing);
    expect(find.text('copy_user'), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey('official-register-hotmanga')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('official-register-copy')),
      findsOneWidget,
    );

    await tester.tap(find.text('热辣漫画'));
    await tester.pumpAndSettle();

    expect(find.text('hot_user'), findsNWidgets(2));
    expect(find.text('copy_user'), findsNothing);
    expect(
      find.byKey(const ValueKey('official-register-hotmanga')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('official-register-copy')), findsNothing);
  });

  testWidgets('token login opens from the top-right action', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await UserManager().init();

    await tester.pumpWidget(_buildTestApp(const LoginPage()));
    await tester.pumpAndSettle();

    expect(find.text('令牌 (Token)'), findsNothing);

    await tester.tap(find.byIcon(Icons.key));
    await tester.pumpAndSettle();

    expect(find.text('令牌登录'), findsOneWidget);
    expect(find.text('令牌 (Token)'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('令牌 (Token)'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
