import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/reader/reader_image_viewer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_helpers.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('gal');
  final messenger = binding.defaultBinaryMessenger;
  late Future<bool> Function() checkAccess;
  Object? saveError;
  var accessChecks = 0;
  var writes = 0;

  setUp(() async {
    setupSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({});
    final reader = UserManager().reader..resetPrefsCache();
    await reader.initFromPrefs(await SharedPreferences.getInstance());
    checkAccess = () async => true;
    saveError = null;
    accessChecks = 0;
    writes = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'hasAccess':
          accessChecks++;
          expect(call.arguments, {'toAlbum': false});
          return checkAccess();
        case 'requestAccess':
          expect(call.arguments, {'toAlbum': false});
          return true;
        case 'putImageBytes':
          writes++;
          expect(call.arguments, containsPair('album', null));
          if (saveError case final error?) throw error;
          return null;
        default:
          fail('Unexpected photo method: ${call.method}');
      }
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    teardownSecureCredentialStoreForTest();
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        ReaderImageViewer(
          imageBytes: base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=',
          ),
          pageNumber: 1,
          pageCount: 1,
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  final saveButton = find.widgetWithIcon(IconButton, Icons.save_alt);

  testWidgets(
    'iOS saving rejects repeated taps and restores the button after completion',
    (tester) async {
      await mount(tester);
      final callback = tester.widget<IconButton>(saveButton).onPressed!;
      if (callback is! Future<void> Function()) {
        fail('The save action must expose its asynchronous completion');
      }
      late Completer<bool> permission;
      late Future<void> saving;
      await tester.runAsync(() async {
        permission = Completer<bool>();
        checkAccess = () => permission.future;
        saving = callback();
        await callback();
      });
      await tester.pump();
      expect(accessChecks, 1);
      expect(writes, 0);
      expect(tester.widget<IconButton>(saveButton).onPressed, isNull);
      // Await the actual save in the real async zone, including image codecs.
      await tester.runAsync(() async {
        permission.complete(true);
        await saving.timeout(const Duration(seconds: 5));
      });
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(tester.widget<IconButton>(saveButton).onPressed, isNotNull);
      expect(find.text('图片已保存到相册'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(wrapWithApp(const SizedBox.shrink()));
    },
    variant: const TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets(
    'leaving the iOS viewer while permission is pending does not save or set state',
    (tester) async {
      await mount(tester);
      final callback = tester.widget<IconButton>(saveButton).onPressed!;
      if (callback is! Future<void> Function()) {
        fail('The save action must expose its asynchronous completion');
      }
      late Completer<bool> permission;
      late Future<void> saving;
      await tester.runAsync(() async {
        permission = Completer<bool>();
        checkAccess = () => permission.future;
        saving = callback();
      });
      await tester.pump();
      expect(accessChecks, 1);
      await tester.pumpWidget(wrapWithApp(const SizedBox.shrink()));
      await tester.runAsync(() async {
        permission.complete(true);
        await saving.timeout(const Duration(seconds: 5));
      });
      await tester.pumpAndSettle();
      expect(writes, 0);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets(
    'iOS save failure displays the native reason and allows retry',
    (tester) async {
      saveError = PlatformException(
        code: 'UNEXPECTED',
        message: 'PhotoKit write failed',
      );
      await mount(tester);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(find.textContaining('PhotoKit write failed'), findsOneWidget);
      expect(tester.widget<IconButton>(saveButton).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(wrapWithApp(const SizedBox.shrink()));
    },
    variant: const TargetPlatformVariant({TargetPlatform.iOS}),
  );
}
