import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kira/main.dart';
import 'package:kira/models/secure_credential_store.dart';
import 'package:kira/pages/general_page.dart';
import 'package:kira/utils/app_icon_switcher.dart';
import 'package:kira/utils/app_logger.dart';
import 'package:kira/utils/download_manager.dart';
import 'package:kira/utils/novel_download_manager.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Runs on the iOS simulator with actual plugins, not host-channel mocks.
/// Runs the shared production startup with offline prefs and the /general route.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'iOS native initialization, persistence, WebView and app frame',
    (tester) async {
      expect(Platform.isIOS, isTrue);
      final errors = <Object>[];
      final previousHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        errors.add(details.exception);
        previousHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = previousHandler);

      final info = await PackageInfo.fromPlatform().timeout(
        const Duration(seconds: 15),
      );
      expect(info.packageName, 'io.github.caolib.kira');
      expect(info.version, isNotEmpty);
      final documents = await getApplicationDocumentsDirectory();
      final support = await getApplicationSupportDirectory();
      final temporary = await getTemporaryDirectory();
      expect(documents.path, isNotEmpty);
      expect(support.path, isNotEmpty);
      expect(temporary.path, isNotEmpty);
      final probe = File('${temporary.path}/kira-ios-smoke.txt');
      try {
        await probe.writeAsString('native filesystem', flush: true);
        expect(await probe.readAsString(), 'native filesystem');
      } finally {
        if (await probe.exists()) await probe.delete();
      }

      const preferenceKey = 'ios_integration_smoke';
      final prefs = await SharedPreferences.getInstance();
      expect(await prefs.setString(preferenceKey, 'persisted'), isTrue);
      await prefs.reload();
      expect(prefs.getString(preferenceKey), 'persisted');
      expect(await prefs.remove(preferenceKey), isTrue);
      // Exercise the default credential backend as well as plain prefs.
      final credentials = SecureCredentialStore();
      final oldToken = await credentials.readToken();
      try {
        await credentials.writeToken('ios-smoke-local-token');
        SecureCredentialStore.resetInstance();
        expect(
          await SecureCredentialStore().readToken(),
          'ios-smoke-local-token',
        );
      } finally {
        await credentials.writeToken(oldToken);
      }
      expect(await AppIconSwitcher.getAppIconIndex(), anyOf(0, 1));

      // The WebView uses a local document and a JavaScript handler, like login,
      // without sending credentials or requests to an upstream website.
      final webLoaded = Completer<void>();
      Object? webError;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InAppWebView(
              initialData: InAppWebViewInitialData(
                data: '<html><body>offline iOS smoke</body></html>',
              ),
              onWebViewCreated: (controller) {
                controller.addJavaScriptHandler(
                  handlerName: 'iosSmoke',
                  callback: (_) {
                    if (!webLoaded.isCompleted) webLoaded.complete();
                    return true;
                  },
                );
              },
              onLoadStop: (controller, _) async {
                try {
                  await controller.evaluateJavascript(
                    source:
                        'window.flutter_inappwebview.callHandler("iosSmoke");',
                  );
                } catch (error) {
                  webError = error;
                  if (!webLoaded.isCompleted) webLoaded.complete();
                }
              },
              onReceivedError: (_, _, error) {
                webError = error;
                if (!webLoaded.isCompleted) webLoaded.complete();
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await webLoaded.future.timeout(const Duration(seconds: 30));
      expect(webError, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      // Use normal preferences to keep this simulator offline. The startup
      // implementation is shared with production, not copied into the test.
      const offlineSettings = <String, Object>{
        'copy_auto_update': false,
        'network_auto_test_enabled': false,
        'backup_auto_enabled': false,
        'auto_check_update_frequency': 'never',
        'auto_check_clipboard_shared_links': false,
        'app_font_family': '',
        'app_logging_enabled': true,
        'app_logging_minimum_level': 'error',
      };
      final savedSettings = {
        for (final key in offlineSettings.keys) key: prefs.get(key),
      };
      addTearDown(() async {
        for (final entry in savedSettings.entries) {
          final value = entry.value;
          if (value == null) {
            await prefs.remove(entry.key);
          } else if (value is bool) {
            await prefs.setBool(entry.key, value);
          } else if (value is String) {
            await prefs.setString(entry.key, value);
          } else {
            throw StateError('Unexpected smoke preference type: ${entry.key}');
          }
        }
      });
      for (final entry in offlineSettings.entries) {
        final value = entry.value;
        if (value is bool) {
          expect(await prefs.setBool(entry.key, value), isTrue);
        } else if (value is String) {
          expect(await prefs.setString(entry.key, value), isTrue);
        }
      }
      binding.platformDispatcher.defaultRouteNameTestValue = '/general';
      addTearDown(binding.platformDispatcher.clearDefaultRouteNameTestValue);
      await startKira().timeout(const Duration(seconds: 30));
      for (
        var i = 0;
        i < 100 && find.byType(GeneralPage).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byType(GeneralPage), findsOneWidget);
      expect(find.byType(MaterialApp), findsOneWidget);
      // Production starts novel initialization concurrently with the first
      // frame. Join it afterwards so a plugin failure cannot be missed.
      await NovelDownloadManager().init().timeout(const Duration(seconds: 30));
      expect(DownloadManager().customSaveDirectory, isNull);
      expect(NovelDownloadManager().customSaveDirectory, isNull);
      expect(AppLogger.instance.isUnavailable, isFalse);
      final startupErrors = await AppLogger.instance.readEntries();
      expect(
        startupErrors,
        isEmpty,
        reason: 'Fallback startup must not hide plugin errors',
      );
      expect(tester.takeException(), isNull);
      expect(errors, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
