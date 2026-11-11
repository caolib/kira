import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/about_page.dart';
import 'package:kira/theme/app_status_colors.dart';
import 'package:kira/utils/app_logger.dart';
import 'package:kira/utils/app_update.dart';
import 'package:kira/widgets/select_tile.dart';
import 'package:kira/widgets/setting_action_tile.dart';
import 'package:kira/widgets/setting_tile_group.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

Map<String, Object> _release({bool beta = false}) => {
  'tag_name': beta ? 'CI' : 'v1.1.0',
  'name': beta ? 'Beta build' : 'Stable release',
  'body': 'Release notes',
  'html_url': 'https://example.com/releases',
  'assets': [
    for (final suffix in [
      'windows.exe',
      'arm64-v8a.apk',
      'macos.dmg',
      'linux.AppImage',
      'ios.ipa',
    ])
      {
        'name': 'kira-1.1.0+2-$suffix',
        'browser_download_url': 'https://example.com/kira-1.1.0+2-$suffix',
        'size': 1024,
      },
  ],
};

void _setInstalledBuild(String build) {
  PackageInfo.setMockInitialValues(
    appName: 'Kira',
    packageName: 'com.example.kira',
    version: '1.0.0',
    buildNumber: build,
    buildSignature: '',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <(RequestOptions, RequestInterceptorHandler)>[];
  late Interceptor interceptor;

  setUp(() async {
    setupSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({});
    await UserManager().init();
    // Initialize platform-backed logging outside the widget test's fake clock.
    await AppLogger.instance.init();
    _setInstalledBuild('1');
    AppUpdateService.state.value = const AppUpdateState.idle();
    AppUpdateService.hasUnseenUpdate.value = false;
    requests.clear();
    interceptor = InterceptorsWrapper(
      onRequest: (options, handler) => requests.add((options, handler)),
    );
    AppUpdateService.dioForTesting.interceptors.insert(0, interceptor);
  });

  tearDown(() {
    AppUpdateService.dioForTesting.interceptors.remove(interceptor);
    AppUpdateService.state.value = const AppUpdateState.idle();
    AppUpdateService.hasUnseenUpdate.value = false;
    teardownSecureCredentialStoreForTest();
  });

  void respond(int index, {bool beta = false, Map<String, Object>? release}) {
    final (options, handler) = requests[index];
    handler.resolve(
      Response<Object?>(
        requestOptions: options,
        statusCode: 200,
        data: release ?? _release(beta: beta),
      ),
    );
  }

  /// checkForUpdate 先等 PackageInfo.fromPlatform() 再发请求，单次 pump
  /// 不足以让请求到达拦截器；有界轮询直到第 index 个请求被捕获。
  /// 轮询用的是普通 pump（不能用 pumpAndSettle：checking 状态的
  /// CircularProgressIndicator 是常驻动画）。
  Future<void> waitForRequest(WidgetTester tester, int index) async {
    var attempts = 0;
    while (requests.length <= index) {
      await tester.pump(const Duration(milliseconds: 10));
      if (attempts++ > 200) {
        fail('update request #$index never reached the interceptor');
      }
    }
  }

  Future<void> pumpAbout(WidgetTester tester, {double width = 800}) async {
    tester.view.physicalSize = Size(width, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      wrapWithApp(const AboutPage(), wrapInScaffold: false),
    );
    await tester.pump();
  }

  Future<BuildContext> pumpHost(WidgetTester tester) async {
    const key = ValueKey('update-host');
    await tester.pumpWidget(wrapWithApp(const SizedBox(key: key)));
    return tester.element(find.byKey(key));
  }

  group('关于页外链', () {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final calls = <MethodCall>[];
    Future<bool> Function() launch = () async => true;

    setUp(() {
      calls.clear();
      launch = () async => true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return launch();
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    for (final width in [320.0, 375.0, 800.0, 1200.0]) {
      testWidgets('官网保持三项快捷入口，源代码在许可下方：$width', (tester) async {
        await pumpAbout(tester, width: width);
        await tester.pumpAndSettle();

        expect(
          tester
              .widgetList<SettingActionTile>(find.byType(SettingActionTile))
              .map((tile) => tile.label),
          ['官网', '反馈', '日志'],
        );
        expect(find.text('仓库'), findsNothing);
        expect(find.byIcon(Icons.language), findsOneWidget);
        final source = find.widgetWithText(ListTile, '源代码');
        await tester.ensureVisible(source);
        await tester.pumpAndSettle();
        final group = find.ancestor(
          of: source,
          matching: find.byType(SettingTileGroup),
        );
        expect(group, findsOneWidget);
        expect(
          find.descendant(of: group, matching: find.text('开源许可')),
          findsOneWidget,
        );
        expect(
          tester.getTopLeft(source).dy,
          greaterThan(
            tester.getTopLeft(find.widgetWithText(ListTile, '开源许可')).dy,
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }

    for (final (label, url) in [
      ('官网', 'https://kira.caolib.qzz.io'),
      ('源代码', 'https://github.com/caolib/kira'),
      ('反馈', 'https://github.com/caolib/kira/issues/new/choose'),
    ]) {
      testWidgets('$label直接通过外部浏览器打开正确地址', (tester) async {
        await pumpAbout(tester, width: 375);
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();

        expect(calls, hasLength(1));
        expect(calls.single.method, 'launch');
        expect(calls.single.arguments, containsPair('url', url));
        expect(calls.single.arguments, containsPair('useWebView', false));
        expect(calls.single.arguments, containsPair('useSafariVC', false));
        expect(
          calls.single.arguments,
          containsPair('universalLinksOnly', false),
        );
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(AboutPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    for (final throwsError in [false, true]) {
      testWidgets('官网打开${throwsError ? '异常显示原始原因' : '返回失败时提示重试'}', (
        tester,
      ) async {
        launch = () async {
          if (throwsError) {
            throw PlatformException(code: 'launch_failed', message: '浏览器被系统限制');
          }
          return false;
        };
        await pumpAbout(tester);
        await tester.tap(find.text('官网'));
        await tester.pumpAndSettle();

        expect(
          throwsError
              ? find.textContaining('浏览器被系统限制')
              : find.text('无法打开链接，请稍后重试'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      });

      testWidgets('离开关于页后忽略迟到的${throwsError ? '异常' : '失败'}提示', (tester) async {
        final result = Completer<bool>();
        launch = () => result.future;
        await pumpAbout(tester);
        await tester.tap(find.text('官网'));
        await tester.pump();
        expect(calls, hasLength(1));
        await tester.pumpWidget(wrapWithApp(const SizedBox()));
        await tester.pumpAndSettle();

        if (throwsError) {
          result.completeError(
            PlatformException(code: 'launch_failed', message: '浏览器被系统限制'),
          );
        } else {
          result.complete(false);
        }
        await tester.pumpAndSettle();
        expect(find.textContaining('浏览器被系统限制'), findsNothing);
        expect(find.text('无法打开链接，请稍后重试'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  });

  for (final width in [375.0, 800.0]) {
    testWidgets('frequency dropdown saves without checking at width $width', (
      tester,
    ) async {
      await pumpAbout(tester, width: width);
      final select = find.byType(SelectTile<UpdateCheckFrequency>);
      await tester.ensureVisible(select);
      await tester.pumpAndSettle();
      expect(find.byType(SwitchListTile), findsNothing);
      const labels = ['从不检查', '启动时检查', '每天一次', '每周一次', '每月一次'];
      expect(
        tester
            .widget<SelectTile<UpdateCheckFrequency>>(select)
            .items
            .map((item) => item.label),
        labels,
      );
      for (final (index, frequency) in UpdateCheckFrequency.values.indexed) {
        await tester.tap(select);
        await tester.pumpAndSettle();
        await tester.tap(find.text(labels[index]).last);
        await tester.pumpAndSettle();
        expect(UserManager().updateCheckFrequency, frequency);
        expect(
          (await SharedPreferences.getInstance()).getString(
            'auto_check_update_frequency',
          ),
          frequency.name,
        );
        expect(requests, isEmpty);
        expect(tester.takeException(), isNull);
      }
      await UserManager().init();
      expect(UserManager().updateCheckFrequency, UpdateCheckFrequency.monthly);
    });
  }

  testWidgets('never and unexpired periods skip startup requests', (
    tester,
  ) async {
    final user = UserManager();
    final context = await pumpHost(tester);
    await user.setUpdateCheckFrequency(UpdateCheckFrequency.never);
    await AppUpdateService.checkOnStartup(context);
    for (final frequency in [
      UpdateCheckFrequency.daily,
      UpdateCheckFrequency.weekly,
      UpdateCheckFrequency.monthly,
    ]) {
      await user.setUpdateCheckFrequency(frequency);
      await user.recordUpdateCheckSuccess('stable');
      await AppUpdateService.checkOnStartup(context);
    }
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
    expect(AppUpdateService.state.value.status, AppUpdateStatus.idle);
  });

  testWidgets(
    'expired startup check records success and suppresses next startup',
    (tester) async {
      final user = UserManager();
      await user.setUpdateCheckFrequency(UpdateCheckFrequency.daily);
      await user.recordUpdateCheckSuccess(
        'stable',
        at: DateTime.now().subtract(const Duration(days: 2)),
      );
      final context = await pumpHost(tester);
      final check = AppUpdateService.checkOnStartup(context);
      await waitForRequest(tester, 0);
      await AppUpdateService.checkOnStartup(context);
      expect(
        requests,
        hasLength(1),
        reason: 'an in-flight check must not be duplicated',
      );
      respond(0);
      await check;
      expect(user.isUpdateCheckDue(), isFalse);
      expect(AppUpdateService.hasUnseenUpdate.value, isTrue);
      await user.init();
      AppUpdateService.state.value = const AppUpdateState.idle();
      await AppUpdateService.checkOnStartup(context);
      expect(requests, hasLength(1));
      expect(AppUpdateService.state.value.status, AppUpdateStatus.idle);
    },
  );

  for (final result in ['available', 'latest', 'skipped', 'no-assets']) {
    testWidgets('successful $result check advances frequency clock', (
      tester,
    ) async {
      final user = UserManager();
      await user.setUpdateCheckFrequency(UpdateCheckFrequency.monthly);
      if (result == 'skipped') await user.setSkippedUpdateVersion('1.1.0');
      final context = await pumpHost(tester);
      // Manual checks count too, while automatic checks respect skipped versions.
      final check = AppUpdateService.checkAndPrompt(
        context,
        auto: result == 'skipped',
      );
      await waitForRequest(tester, 0);
      final release = _release();
      if (result == 'latest') release['tag_name'] = 'v1.0.0';
      if (result == 'no-assets') release['assets'] = <Object>[];
      respond(0, release: release);
      await check;
      await tester.pumpAndSettle();
      expect(user.isUpdateCheckDue(), isFalse);
      expect(
        AppUpdateService.state.value.status,
        result == 'available'
            ? AppUpdateStatus.available
            : AppUpdateStatus.latest,
      );
      await AppUpdateService.checkOnStartup(context);
      expect(requests, hasLength(1));
      await tester.pump(const Duration(seconds: 5));
    });
  }

  testWidgets('startup frequency checks again after a successful check', (
    tester,
  ) async {
    final context = await pumpHost(tester);
    for (var i = 0; i < 2; i++) {
      final check = AppUpdateService.checkOnStartup(context);
      await waitForRequest(tester, i);
      respond(i);
      await check;
    }
    expect(requests, hasLength(2));
  });

  testWidgets('Beta cancel disables and persists startup checks', (
    tester,
  ) async {
    await UserManager().setUpdateChannel('beta');
    await UserManager().setUpdateCheckFrequency(UpdateCheckFrequency.weekly);
    await pumpAbout(tester);
    await tester.tap(find.text('检查更新'));
    await waitForRequest(tester, 0);
    respond(0, beta: true);
    await tester.pumpAndSettle();

    await tester.tap(find.text('取消自动检查更新'));
    await tester.pumpAndSettle();

    expect(UserManager().updateCheckFrequency, UpdateCheckFrequency.never);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('auto_check_update_frequency'), 'never');
    expect(prefs.getString('skipped_update_version'), isNull);
    expect(
      tester
          .widget<SelectTile<UpdateCheckFrequency>>(
            find.byType(SelectTile<UpdateCheckFrequency>),
          )
          .value,
      UpdateCheckFrequency.never,
    );

    // Turning off startup checks must not prevent an explicit manual check.
    await tester.tap(find.text('检查更新'));
    await waitForRequest(tester, 1);
    respond(1, beta: true);
    await tester.pumpAndSettle();
    expect(AppUpdateService.state.value.status, AppUpdateStatus.available);
    expect(UserManager().updateCheckFrequency, UpdateCheckFrequency.never);
    expect(AppUpdateService.hasUnseenUpdate.value, isFalse);
  });

  testWidgets('stable skip persists only the selected version', (tester) async {
    await pumpAbout(tester);
    await tester.tap(find.text('检查更新'));
    await waitForRequest(tester, 0);
    respond(0);
    await tester.pumpAndSettle();
    await tester.tap(find.text('跳过此版本'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('skipped_update_version'), '1.1.0');
    expect(UserManager().updateCheckFrequency, UpdateCheckFrequency.startup);
    expect(AppUpdateService.state.value.status, AppUpdateStatus.latest);

    // Auto checks stay quiet for the skipped version…
    final context = tester.element(find.byType(AboutPage));
    final autoCheck = AppUpdateService.checkAndPrompt(context, auto: true);
    await waitForRequest(tester, 1);
    respond(1);
    await autoCheck;
    await tester.pumpAndSettle();
    expect(AppUpdateService.state.value.status, AppUpdateStatus.latest);

    // …while a manual check still surfaces the update.
    await tester.tap(find.text('检查更新'));
    await waitForRequest(tester, 2);
    respond(2);
    await tester.pumpAndSettle();
    expect(AppUpdateService.state.value.status, AppUpdateStatus.available);
  });

  testWidgets('Beta remains available across restart with legacy seen record', (
    tester,
  ) async {
    await UserManager().setUpdateChannel('beta');
    final context = await pumpHost(tester);
    final firstCheck = AppUpdateService.checkAndPrompt(context, auto: true);
    await waitForRequest(tester, 0);
    respond(0, beta: true);
    await firstCheck;
    final info = AppUpdateService.state.value.info!;
    expect(AppUpdateService.state.value.status, AppUpdateStatus.available);
    expect(AppUpdateService.hasUnseenUpdate.value, isTrue);

    // An old installation may still carry a "seen build" record; merely
    // discovering the build must never hide it before it is installed.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_beta_asset_name', info.assets.first.name);
    await UserManager().init();
    AppUpdateService.state.value = const AppUpdateState.idle();
    AppUpdateService.hasUnseenUpdate.value = false;
    final secondCheck = AppUpdateService.checkAndPrompt(context, auto: true);
    await waitForRequest(tester, 1);
    respond(1, beta: true);
    await secondCheck;
    expect(AppUpdateService.state.value.status, AppUpdateStatus.available);
    expect(AppUpdateService.hasUnseenUpdate.value, isTrue);

    // Only installing the new build clears the update.
    _setInstalledBuild('2');
    final installedCheck = AppUpdateService.checkAndPrompt(context, auto: true);
    await waitForRequest(tester, 2);
    respond(2, beta: true);
    await installedCheck;
    expect(AppUpdateService.state.value.status, AppUpdateStatus.latest);
    expect(AppUpdateService.hasUnseenUpdate.value, isFalse);
  });

  testWidgets('About opens without checking and manual check keeps badge off', (
    tester,
  ) async {
    await UserManager().setUpdateCheckFrequency(UpdateCheckFrequency.never);
    await pumpAbout(tester);
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
    expect(AppUpdateService.state.value.status, AppUpdateStatus.idle);
    await tester.tap(find.text('检查更新'));
    await waitForRequest(tester, 0);
    expect(requests.single.$1.path, endsWith('/releases/latest'));
    respond(0);
    await tester.pumpAndSettle();

    expect(find.text('跳过此版本'), findsOneWidget);
    expect(AppUpdateService.state.value.status, AppUpdateStatus.available);
    expect(AppUpdateService.hasUnseenUpdate.value, isFalse);
    await tester.pumpWidget(wrapWithApp(const SizedBox()));
    await tester.pumpAndSettle();
    expect(AppUpdateService.hasUnseenUpdate.value, isFalse);
  });

  testWidgets('startup result arriving after About opens is marked seen', (
    tester,
  ) async {
    final context = await pumpHost(tester);
    final check = AppUpdateService.checkAndPrompt(context, auto: true);
    await waitForRequest(tester, 0);
    await pumpAbout(tester);
    expect(requests, hasLength(1));
    respond(0);
    await tester.pumpAndSettle();
    await check;

    expect(AppUpdateService.state.value.status, AppUpdateStatus.available);
    expect(AppUpdateService.hasUnseenUpdate.value, isFalse);
  });

  testWidgets('result arriving after leaving About still lights the badge', (
    tester,
  ) async {
    final context = await pumpHost(tester);
    final check = AppUpdateService.checkOnStartup(context);
    await waitForRequest(tester, 0);
    await pumpAbout(tester);
    await tester.pumpWidget(wrapWithApp(const SizedBox()));
    await tester.pumpAndSettle();
    respond(0);
    await tester.pumpAndSettle();
    await check;

    expect(AppUpdateService.state.value.status, AppUpdateStatus.available);
    expect(AppUpdateService.hasUnseenUpdate.value, isTrue);
  });

  for (final oldRequestFails in [false, true]) {
    testWidgets('channel switch refreshes immediately and ignores old '
        '${oldRequestFails ? 'failure' : 'success'}', (tester) async {
      await UserManager().setUpdateCheckFrequency(UpdateCheckFrequency.never);
      await pumpAbout(tester);
      await tester.tap(find.text('检查更新'));
      await waitForRequest(tester, 0);
      expect(requests.single.$1.path, endsWith('/releases/latest'));

      await tester.tap(find.text('稳定版'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('beta'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('是否切换?'), findsOneWidget);
      expect(find.text('预览版更新更快，问题也可能更多'), findsOneWidget);
      // 测试宿主是 Windows(非 Android arm64),arm64 提示应标成警告色。
      final danger = AppStatusColors.danger(
        Theme.of(tester.element(find.byType(AboutPage))).colorScheme,
      );
      expect(
        tester.widget<Text>(find.text('仅限 Android arm64 设备。')).style?.color,
        danger,
      );
      // 探测到设备环境时补一行「当前设备：...」,同样是警示色。
      final deviceLine = find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').startsWith('当前设备：'),
      );
      expect(deviceLine, findsOneWidget);
      expect(tester.widget<Text>(deviceLine).style?.color, danger);
      await tester.tap(find.text('确认'));
      await tester.pump(const Duration(milliseconds: 300));
      await waitForRequest(tester, 1);
      expect(requests.last.$1.path, endsWith('/releases/tags/CI'));
      respond(1, beta: true);
      await tester.pumpAndSettle();
      expect(AppUpdateService.state.value.info!.isBetaChannel, isTrue);
      await tester.pumpAndSettle();
      expect(AppUpdateService.state.value.info!.isBetaChannel, isTrue);
      // 不支持的设备上,Beta 徽标换成警告图标(与红色提示一致)。
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);

      // The stale stable-channel response completes late; it must not
      // replace the fresh beta result — success or failure alike.
      if (oldRequestFails) {
        final (options, handler) = requests.first;
        handler.reject(DioException(requestOptions: options, error: 'offline'));
      } else {
        respond(0);
      }
      await tester.pumpAndSettle();
      expect(AppUpdateService.state.value.status, AppUpdateStatus.available);
      expect(AppUpdateService.state.value.info!.isBetaChannel, isTrue);
      expect(AppUpdateService.hasUnseenUpdate.value, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('auto_check_update_last_success_beta'), isNotNull);
      expect(prefs.getInt('auto_check_update_last_success_stable'), isNull);

      // The reverse switch also replaces the old card and rechecks at once.
      await tester.tap(find.text('beta'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('稳定版'));
      await tester.pump(const Duration(milliseconds: 400));
      await waitForRequest(tester, 2);
      expect(AppUpdateService.state.value.status, AppUpdateStatus.checking);
      expect(AppUpdateService.state.value.info, isNull);
      respond(2);
      await tester.pumpAndSettle();
      expect(AppUpdateService.state.value.info!.isBetaChannel, isFalse);
      expect(find.text('跳过此版本'), findsOneWidget);
    });
  }

  group('更新镜像源', () {
    // 弹出菜单的收起动画比 300ms 长，多给一轮以确保菜单从树上移除。
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    testWidgets('自定义镜像在下拉里可删除，删除后回落默认', (tester) async {
      final user = UserManager();
      await user.addCustomUpdateMirrorPrefix('https://my.mirror');
      await user.setUpdateMirrorPrefix('https://my.mirror');

      await pumpAbout(tester);
      final mirrorRow = find.byTooltip('设置镜像源');
      await tester.ensureVisible(mirrorRow);
      await settle(tester);
      // 按钮上显示当前镜像的主机名。
      expect(find.text('my.mirror'), findsOneWidget);

      await tester.tap(mirrorRow);
      await settle(tester);
      expect(find.text('https://my.mirror/'), findsOneWidget);

      await tester.tap(find.byTooltip('删除'));
      await settle(tester);

      expect(user.customUpdateMirrorPrefixes, isEmpty);
      expect(user.updateMirrorPrefix, UserManager.defaultUpdateMirrorPrefix);
      // 删除后菜单立即收起，按钮回落到默认镜像主机名。
      expect(find.byType(AboutPage), findsOneWidget, reason: 'about 页不应被 pop');
      expect(find.byType(PopupMenuItem<String>), findsNothing);
      expect(find.text('gh-proxy.org'), findsOneWidget);
      // 再打开下拉，已删除的自定义项不再出现。
      await tester.tap(mirrorRow);
      await settle(tester);
      expect(find.text('https://my.mirror/'), findsNothing);
    });

    testWidgets('切换内置镜像后自定义项仍留在下拉里', (tester) async {
      final user = UserManager();
      await user.addCustomUpdateMirrorPrefix('https://my.mirror');

      await pumpAbout(tester);
      final mirrorRow = find.byTooltip('设置镜像源');
      await tester.ensureVisible(mirrorRow);
      await settle(tester);

      await tester.tap(mirrorRow);
      await settle(tester);
      await tester.tap(find.text('https://my.mirror/'));
      await settle(tester);
      expect(user.updateMirrorPrefix, 'https://my.mirror/');

      await tester.tap(mirrorRow);
      await settle(tester);
      await tester.tap(find.text('https://ghproxy.net/'));
      await settle(tester);

      expect(user.updateMirrorPrefix, 'https://ghproxy.net/');
      expect(user.customUpdateMirrorPrefixes, ['https://my.mirror/']);
      await tester.tap(mirrorRow);
      await settle(tester);
      expect(find.text('https://my.mirror/'), findsOneWidget);
    });
  });
}
