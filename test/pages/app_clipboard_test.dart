import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/main.dart';
import 'package:kira/models/user_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> clipboardCalls;

  setUp(() {
    setupSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({});
    clipboardCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method.startsWith('Clipboard.')) {
            clipboardCalls.add(call.method);
          }
          if (call.method == 'Clipboard.hasStrings') {
            return {'value': true};
          }
          if (call.method == 'Clipboard.getData') {
            return {'text': '普通文本'};
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    teardownSecureCredentialStoreForTest();
  });

  Future<void> launchApp(WidgetTester tester) async {
    // 直接启动通用设置页，避免无关首页数据加载。
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/general';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    await UserManager().init();
    await tester.pumpWidget(const ProviderScope(child: KiraApp()));
    await tester.pumpAndSettle();
  }

  Future<void> resumeApp(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  }

  testWidgets('默认启动和回前台均不访问剪贴板', (tester) async {
    await launchApp(tester);
    expect(clipboardCalls, isEmpty);
    await resumeApp(tester);
    expect(clipboardCalls, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('开启后启动读取，关闭后回前台停止读取', (tester) async {
    SharedPreferences.setMockInitialValues({
      'auto_check_clipboard_shared_links': true,
    });
    await launchApp(tester);
    expect(clipboardCalls, contains('Clipboard.getData'));

    clipboardCalls.clear();
    await resumeApp(tester);
    expect(clipboardCalls, contains('Clipboard.getData'));

    await UserManager().general.setAutoCheckClipboardSharedLinks(false);
    clipboardCalls.clear();
    await resumeApp(tester);
    expect(clipboardCalls, isEmpty);

    await UserManager().general.setAutoCheckClipboardSharedLinks(true);
    await resumeApp(tester);
    expect(clipboardCalls, contains('Clipboard.getData'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
