import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/about_page.dart' show AboutPage;
import 'package:kira/pages/profile_page.dart';
import 'package:kira/utils/remote_notice_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
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

  Future<void> pumpProfilePage(WidgetTester tester) async {
    RemoteNoticeService.unreadActiveCount.value = 0;
    SharedPreferences.setMockInitialValues({
      'user_token': 'current-token',
      'user_user_id': '1',
      'user_username': 'alice',
      'user_nickname': 'Alice',
      'user_avatar': '',
      'saved_username': 'alice',
      'saved_password': 'alice-pass',
      'saved_credentials': jsonEncode([
        {
          'username': 'alice',
          'password': 'alice-pass',
          'token': 'current-token',
          'user_id': '1',
          'nickname': 'Alice',
          'avatar': '',
        },
        {
          'username': 'bob',
          'password': 'bob-pass',
          'token': 'bob-token',
          'user_id': '2',
          'nickname': 'Bob',
          'avatar': '',
        },
      ]),
    });
    await UserManager().init();

    await tester.pumpWidget(_buildTestApp(const ProfilePage()));
    await tester.pumpAndSettle();
  }

  testWidgets('switch account sheet shows add account button', (tester) async {
    await pumpProfilePage(tester);

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('切换账号'));
    await tester.pumpAndSettle();

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('添加账号'), findsOneWidget);
    expect(find.byIcon(Icons.person_add_alt_1), findsOneWidget);
  });

  testWidgets('profile page shows general settings entry', (tester) async {
    await pumpProfilePage(tester);

    expect(find.text('通用'), findsOneWidget);
  });

  testWidgets('notice center is below AI config in the first settings group', (
    tester,
  ) async {
    // 断言的是单列纵向排布（通知中心在 AI 配置与下载中心之间）。
    // 测试默认表面逻辑宽 800 越过宽屏断点 720，会切成左右双列，
    // 下载中心（右列顶部）反而排在通知中心（左列第 5 行）上方。
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(600 * 3, 1000 * 3);
    addTearDown(tester.view.reset);

    await pumpProfilePage(tester);

    final aiTop = tester.getTopLeft(find.text('AI配置')).dy;
    final noticeTop = tester.getTopLeft(find.text('通知中心')).dy;
    final downloadTop = tester.getTopLeft(find.text('下载中心')).dy;

    expect(noticeTop, greaterThan(aiTop));
    expect(noticeTop, lessThan(downloadTop));
  });

  testWidgets('notice red dot uses notice icon color', (tester) async {
    await pumpProfilePage(tester);

    RemoteNoticeService.unreadActiveCount.value = 1;
    await tester.pump();

    expect(
      find.byWidgetPredicate((widget) {
        final decoration = widget is Container ? widget.decoration : null;
        return widget is Container &&
            decoration is BoxDecoration &&
            decoration.color == const Color(0xFFEB6F92);
      }),
      findsOneWidget,
    );
  });

  testWidgets('about page shows error log entry', (tester) async {
    SharedPreferences.setMockInitialValues({'app_logging_enabled': true});
    PackageInfo.setMockInitialValues(
      appName: 'Kira',
      packageName: 'com.example.kira',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    await UserManager().init();

    await tester.pumpWidget(_buildTestApp(const AboutPage()));
    // AboutPage 的更新检查指示器常驻动画会让 pumpAndSettle 永不结束，
    // 用固定 pump 等首帧与异步初始化完成。
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('日志'), findsOneWidget);
    expect(find.byIcon(Icons.bug_report_outlined), findsOneWidget);
  });
}
