import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/reader/reader_image_viewer.dart';
import 'package:kira/widgets/app_sheet.dart';
import 'package:kira/widgets/settings_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_helpers.dart';

void main() {
  setUp(() async {
    setupSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({});
    final reader = UserManager().reader..resetPrefsCache();
    await reader.initFromPrefs(await SharedPreferences.getInstance());
  });
  tearDown(teardownSecureCredentialStoreForTest);

  for (final size in [
    const Size(375, 812),
    const Size(320, 850),
    const Size(812, 375),
  ]) {
    testWidgets(
      'image rotation settings share a card and remain usable at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          wrapWithApp(
            Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: ReaderImageViewer(
                  imageBytes: Uint8List.fromList(
                    base64Decode(
                      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=',
                    ),
                  ),
                  pageNumber: 1,
                  pageCount: 1,
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('查看器设置'));
        await tester.pumpAndSettle();
        expect(find.byType(AppSheet), findsOneWidget);
        final card = find.byKey(const ValueKey('reader-image-rotation-card'));
        expect(find.byType(SettingsSection), findsOneWidget);
        expect(
          find.descendant(of: card, matching: find.text('横向图片自动旋转')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: card, matching: find.text('旋转方向')),
          findsOneWidget,
        );
        final toggle = find.descendant(
          of: card,
          matching: find.byType(SwitchListTile),
        );
        await tester.ensureVisible(toggle);
        await tester.pumpAndSettle();
        final before = tester.widget<SwitchListTile>(toggle).value;
        await tester.tap(
          find.descendant(of: toggle, matching: find.byType(Switch)),
        );
        await tester.pumpAndSettle();
        expect(UserManager().imageViewerAutoRotateLandscape, !before);
        // 普通开关仍可点击标题启停。
        await tester.ensureVisible(toggle);
        await tester.pumpAndSettle();
        await tester.tap(find.text('横向图片自动旋转'));
        await tester.pumpAndSettle();
        expect(UserManager().imageViewerAutoRotateLandscape, before);
        final directions = find.descendant(
          of: card,
          matching: find.byType(SegmentedButton<int>),
        );
        await tester.ensureVisible(directions);
        await tester.pumpAndSettle();
        expect(
          directions.hitTestable(),
          before ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
