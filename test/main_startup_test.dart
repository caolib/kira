import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/main.dart';
import 'package:kira/models/secure_credential_store.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/general_page.dart';
import 'package:kira/utils/app_logger.dart';
import 'package:kira/utils/download_manager.dart';
import 'package:kira/utils/novel_download_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

class _StartupPaths extends PathProviderPlatform {
  _StartupPaths(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async =>
      p.join(root, 'Documents');

  @override
  Future<String?> getApplicationSupportPath() async => p.join(root, 'Support');

  @override
  Future<String?> getTemporaryPath() async => p.join(root, 'Temporary');
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform oldPaths;
  late HttpOverrides? oldHttpOverrides;

  setUp(() async {
    setupSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({
      'copy_auto_update': false,
      'app_font_family': '',
      'app_logging_enabled': true,
      'app_logging_minimum_level': 'error',
      'auto_check_update_frequency': 'never',
      'secure_mirror_user_token': 'local-startup-token',
    });
    // This regression deliberately checks the default persistent backend.
    SecureCredentialStore.resetInstance();
    directory = await Directory.systemTemp.createTemp('kira_startup_test_');
    oldPaths = PathProviderPlatform.instance;
    oldHttpOverrides = HttpOverrides.current;
    PathProviderPlatform.instance = _StartupPaths(directory.path);
  });

  tearDown(() async {
    binding.platformDispatcher.clearDefaultRouteNameTestValue();
    PathProviderPlatform.instance = oldPaths;
    HttpOverrides.global = oldHttpOverrides;
    await directory.delete(recursive: true);
    teardownSecureCredentialStoreForTest();
  });

  testWidgets(
    'shared production startup mounts the app and retains binding error handlers',
    (tester) async {
      final errorHandler = FlutterError.onError;
      binding.platformDispatcher.defaultRouteNameTestValue = '/general';
      await tester.runAsync(
        () => startKira().timeout(const Duration(seconds: 15)),
      );
      for (
        var i = 0;
        i < 100 && find.byType(GeneralPage).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      // KiraApp itself owns the localized MaterialApp; do not wrap that app twice.
      expect(find.byType(KiraApp), findsOneWidget);
      expect(
        find.byType(GeneralPage),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data)
            .join('; '),
      );
      expect(find.byType(MaterialApp), findsOneWidget);
      expect(FlutterError.onError, same(errorHandler));
      final persistedToken = (await SharedPreferences.getInstance()).getString(
        'secure_mirror_user_token',
      );
      expect(persistedToken, isNotEmpty);
      expect(UserManager().token, persistedToken);
      await tester.runAsync(() async {
        await NovelDownloadManager().init().timeout(const Duration(seconds: 5));
        expect(
          DownloadManager().rootPath,
          p.join(directory.path, 'Documents', 'comic_downloads'),
        );
        expect(
          NovelDownloadManager().rootPath,
          p.join(directory.path, 'Documents', 'novel_downloads'),
        );
        expect(AppLogger.instance.isUnavailable, isFalse);
        expect(await AppLogger.instance.readEntries(), isEmpty);
      });
      expect(tester.takeException(), isNull);
      binding.platformDispatcher.clearDefaultRouteNameTestValue();
      await tester.pumpWidget(wrapWithApp(const SizedBox.shrink()));
      await tester.pump();
      // Let the existing one-shot expired-cache cleanup finish before teardown.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 6)),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
