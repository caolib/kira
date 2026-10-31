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
    setupSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({
      'user_token': 'token',
      'saved_username': 'alice',
      'saved_password': 'secret',
      'auto_login': true,
    });
  });

  tearDown(teardownSecureCredentialStoreForTest);

  testWidgets('Banner 开关与子 store 双向同步并即时刷新', (tester) async {
    final user = UserManager();
    await user.init();
    await tester.pumpWidget(
      wrapWithApp(const GeneralPage(), wrapInScaffold: false),
    );
    await tester.pumpAndSettle();
    final tile = find.widgetWithText(SwitchListTile, '显示Banner');
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);

    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(user.bannerVisible, isFalse);
    expect(user.theme.bannerVisible, isFalse);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('banner_visible'), isFalse);

    await user.theme.setBannerVisible(true);
    await tester.pumpAndSettle();
    expect(user.bannerVisible, isTrue);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    expect(prefs.getBool('banner_visible'), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('剪贴板分享链接开关默认关闭、即时同步并持久化', (tester) async {
    final user = UserManager();
    await user.init();
    await tester.pumpWidget(
      wrapWithApp(const GeneralPage(), wrapInScaffold: false),
    );
    await tester.pumpAndSettle();
    final tile = find.widgetWithText(SwitchListTile, '自动识别剪贴板分享链接');
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);

    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(user.general.autoCheckClipboardSharedLinks, isTrue);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('auto_check_clipboard_shared_links'), isTrue);

    await user.init();
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);

    await user.general.setAutoCheckClipboardSharedLinks(false);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    expect(prefs.getBool('auto_check_clipboard_shared_links'), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
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

  // 「导出设置 / 导入设置」入口已由新的备份页（本地/WebDAV、加密与定时备份）取代，
  // 原并排一行的断言不再适用；这里改为确认通用页只剩备份入口、不再有旧的导入导出按钮。
  testWidgets('general page links to backup instead of legacy export tiles', (
    tester,
  ) async {
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

    expect(
      find.ancestor(of: find.text('导出设置'), matching: find.byType(ListTile)),
      findsNothing,
    );
    expect(
      find.ancestor(of: find.text('导入设置'), matching: find.byType(ListTile)),
      findsNothing,
    );
    expect(find.byType(SettingActionTile), findsNothing);
    expect(find.textContaining('备份'), findsWidgets);
  });

  testWidgets('wide screen puts backup and reset in the right column', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1200);
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

    final settings = tester.getTopLeft(find.text('显示Banner'));
    final backup = tester.getTopLeft(find.text('备份与同步'));
    final reset = tester.getTopLeft(find.text('重置应用'));

    // 左列设置组,右列备份在上、重置在下。
    expect(backup.dx, greaterThan(settings.dx));
    expect(reset.dx, backup.dx);
    expect(reset.dy, greaterThan(backup.dy));
  });
}
