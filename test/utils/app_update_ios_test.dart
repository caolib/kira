import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/utils/app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

Map<String, Object?> _release(String tag, List<String> names) => {
  'tag_name': tag,
  'name': 'Release $tag',
  'body': 'Release notes',
  'html_url': 'https://example.com/releases/$tag',
  'assets': [
    for (final name in names)
      {
        'name': name,
        'browser_download_url': 'https://example.com/$name',
        'size': 1024,
        'created_at': '2026-11-15T00:00:00Z',
      },
  ],
};

void _setInstalledBuild(String version, String build) {
  PackageInfo.setMockInitialValues(
    appName: 'Kira',
    packageName: 'io.github.caolib.kira',
    version: version,
    buildNumber: build,
    buildSignature: '',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ios = TargetPlatformVariant({TargetPlatform.iOS});
  late Interceptor interceptor;
  late Map<String, Object?> response;
  final requests = <RequestOptions>[];

  setUp(() async {
    setupSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({});
    await UserManager().init();
    _setInstalledBuild('1.7.7', '656');
    AppUpdateService.state.value = const AppUpdateState.idle();
    AppUpdateService.hasUnseenUpdate.value = false;
    requests.clear();
    response = _release('v1.7.8', ['kira-1.7.8+657-ios-unsigned.ipa']);
    interceptor = InterceptorsWrapper(
      onRequest: (options, handler) {
        requests.add(options);
        handler.resolve(
          Response<Object?>(
            requestOptions: options,
            statusCode: 200,
            data: response,
          ),
        );
      },
    );
    AppUpdateService.dioForTesting.interceptors.insert(0, interceptor);
  });

  tearDown(() {
    AppUpdateService.dioForTesting.interceptors.remove(interceptor);
    AppUpdateService.state.value = const AppUpdateState.idle();
    AppUpdateService.hasUnseenUpdate.value = false;
    teardownSecureCredentialStoreForTest();
  });

  Future<AppUpdateInfo?> checkUpdate(
    WidgetTester tester, {
    bool respectSkippedVersion = true,
  }) => tester.runAsync<AppUpdateInfo?>(
    () => AppUpdateService.checkForUpdate(
      respectSkippedVersion: respectSkippedVersion,
    ).timeout(const Duration(seconds: 5)),
  );

  testWidgets('iOS stable uses latest Release and only returns IPA assets', (
    tester,
  ) async {
    response = _release('v1.7.8', [
      'kira-9.9.9+999-arm64-v8a.apk',
      'kira-1.7.8+657-ios-unsigned.ipa.sha256',
      'kira-1.7.8+657-ios-unsigned.ipa',
      'kira-1.7.8+657-darwin.IPA',
      'release.json',
    ]);
    final info = (await checkUpdate(tester))!;
    expect(requests.single.uri.path, '/repos/caolib/kira/releases/latest');
    expect(info.isBetaChannel, isFalse);
    expect(info.isCurrentVersion, isFalse);
    expect(info.latestVersion, '1.7.8');
    expect(info.assets.map((asset) => asset.name), [
      'kira-1.7.8+657-ios-unsigned.ipa',
      'kira-1.7.8+657-darwin.IPA',
    ]);
    expect(
      info.assets.every((asset) => asset.platform == AssetPlatform.ios),
      isTrue,
    );
  }, variant: ios);

  testWidgets(
    'iOS beta uses ios-build and orders IPA builds including prerelease names',
    (tester) async {
      await UserManager().setUpdateChannel('beta');
      response = _release('ios-build', [
        'kira-1.7.7+655-ios-unsigned.ipa',
        'kira-9.9.9+999-ios-unsigned.ipa.sha256',
        'kira-9.9.9+999-arm64-v8a.apk',
        'kira-1.7.8+657-ios-unsigned.ipa',
        'kira-1.7.8-beta.2+658-ios-unsigned.ipa',
      ]);
      final info = (await checkUpdate(tester))!;
      expect(
        requests.single.uri.path,
        '/repos/caolib/kira/releases/tags/ios-build',
      );
      expect(isBetaChannelSupported(), isTrue);
      expect(info.isBetaChannel, isTrue);
      expect(info.isCurrentVersion, isFalse);
      expect(info.assets.map((asset) => asset.name), [
        'kira-1.7.8-beta.2+658-ios-unsigned.ipa',
        'kira-1.7.8+657-ios-unsigned.ipa',
        'kira-1.7.7+655-ios-unsigned.ipa',
      ]);
      expect(info.assets.first.versionParts, [1, 7, 8, 658]);
    },
    variant: ios,
  );

  testWidgets('iOS beta remains available until the IPA build is installed', (
    tester,
  ) async {
    await UserManager().setUpdateChannel('beta');
    response = _release('ios-build', [
      'kira-1.7.8-beta.2+658-ios-unsigned.ipa',
    ]);
    for (var check = 0; check < 2; check++) {
      expect((await checkUpdate(tester))!.isCurrentVersion, isFalse);
    }
    _setInstalledBuild('1.7.8', '658');
    expect((await checkUpdate(tester))!.isCurrentVersion, isTrue);
    _setInstalledBuild('1.7.8', '659');
    expect((await checkUpdate(tester))!.isCurrentVersion, isTrue);
  }, variant: ios);

  for (final channel in ['stable', 'beta']) {
    testWidgets(
      'iOS $channel never offers APK or checksum-only releases as an update',
      (tester) async {
        await UserManager().setUpdateChannel(channel);
        response = _release(channel == 'beta' ? 'ios-build' : 'v1.7.8', [
          'kira-9.9.9+999-arm64-v8a.apk',
          'kira-9.9.9+999-ios-unsigned.ipa.sha256',
        ]);
        final info = (await checkUpdate(tester))!;
        expect(info.noAssetForPlatform, isTrue);
        expect(info.assets, isEmpty);
        const host = ValueKey('ios-update-host');
        await tester.pumpWidget(wrapWithApp(const SizedBox(key: host)));
        await tester.runAsync(
          () => AppUpdateService.checkAndPrompt(
            tester.element(find.byKey(host)),
            auto: true,
          ).timeout(const Duration(seconds: 5)),
        );
        expect(AppUpdateService.state.value.status, AppUpdateStatus.latest);
        expect(AppUpdateService.hasUnseenUpdate.value, isFalse);
      },
      variant: ios,
    );
  }

  testWidgets('iOS stable keeps skipped-version and already-latest behavior', (
    tester,
  ) async {
    await UserManager().setSkippedUpdateVersion('1.7.8');
    expect(await checkUpdate(tester), isNull);
    expect(
      (await checkUpdate(tester, respectSkippedVersion: false))!.latestVersion,
      '1.7.8',
    );
    _setInstalledBuild('1.7.8', '657');
    expect((await checkUpdate(tester))!.isCurrentVersion, isTrue);
  }, variant: ios);

  for (final channel in ['stable', 'beta']) {
    testWidgets(
      'iOS $channel startup still checks, records success and lights the badge',
      (tester) async {
        final user = UserManager();
        await user.setUpdateChannel(channel);
        await user.setUpdateCheckFrequency(UpdateCheckFrequency.daily);
        response = _release(channel == 'beta' ? 'ios-build' : 'v1.7.8', [
          'kira-1.7.8+657-ios-unsigned.ipa',
        ]);
        const host = ValueKey('ios-startup-update-host');
        await tester.pumpWidget(wrapWithApp(const SizedBox(key: host)));
        final context = tester.element(find.byKey(host));
        await tester.runAsync(
          () => AppUpdateService.checkOnStartup(
            context,
          ).timeout(const Duration(seconds: 5)),
        );
        expect(AppUpdateService.state.value.status, AppUpdateStatus.available);
        expect(AppUpdateService.hasUnseenUpdate.value, isTrue);
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getInt('auto_check_update_last_success_$channel'),
          isNotNull,
        );
        await tester.runAsync(
          () => AppUpdateService.checkOnStartup(
            context,
          ).timeout(const Duration(seconds: 5)),
        );
        expect(requests, hasLength(1));
        AppUpdateService.markUpdateBadgeSeen();
        await tester.pump();
        expect(AppUpdateService.hasUnseenUpdate.value, isFalse);
      },
      variant: ios,
    );
  }

  testWidgets(
    'Android beta continues using the CI tag',
    (tester) async {
      await UserManager().setUpdateChannel('beta');
      response = _release('CI', ['kira-1.7.8+657-arm64-v8a.apk']);
      await checkUpdate(tester);
      expect(requests.single.uri.path, '/repos/caolib/kira/releases/tags/CI');
    },
    variant: const TargetPlatformVariant({TargetPlatform.android}),
  );
}
