import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/download_manager.dart';
import 'package:kira/utils/novel_download_manager.dart';
import 'package:kira/widgets/app_sheet.dart';
import 'package:kira/widgets/download_settings_sheet.dart';
import 'package:kira/widgets/settings_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

class _Novels extends Fake implements NovelDownloadManager {
  @override
  int concurrency = 2;
  final concurrencyWrites = <int>[];

  @override
  String? get customSaveDirectory => null;

  @override
  Future<int> setConcurrency(int value) async {
    concurrencyWrites.add(value);
    return concurrency = value;
  }
}

void main() {
  setUp(() {
    setupSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(teardownSecureCredentialStoreForTest);

  for (final size in [
    const Size(375, 812),
    const Size(320, 640),
    const Size(812, 375),
  ]) {
    testWidgets('download settings group and scroll at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.view.reset);
      final downloads = DownloadManager.forTesting(
        rootDirectory: Directory.systemTemp,
      );
      await tester.runAsync(downloads.reloadScalarSettings);
      final novels = _Novels();
      await tester.pumpWidget(
        wrapWithApp(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDownloadSettingsSheet(
                    context,
                    downloads: downloads,
                    novelDownloads: novels,
                  ),
                  child: const Text('打开设置'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开设置'));
      await tester.pumpAndSettle();
      expect(find.byType(AppSheet), findsOneWidget);
      expect(find.byType(SettingsSection), findsNWidgets(2));
      final comicCard = find.byKey(
        const ValueKey('comic-download-settings-card'),
      );
      final novelCard = find.byKey(
        const ValueKey('novel-download-settings-card'),
      );
      expect(
        find.descendant(of: comicCard, matching: find.byType(SwitchListTile)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: novelCard, matching: find.byType(SwitchListTile)),
        findsNothing,
      );

      final prefs = await SharedPreferences.getInstance();
      for (final card in [comicCard, novelCard]) {
        final slider = find.descendant(of: card, matching: find.byType(Slider));
        await tester.ensureVisible(slider);
        await tester.pumpAndSettle();
        expect(slider.hitTestable(), findsOneWidget);
        tester.widget<Slider>(slider).onChanged!(16);
        await tester.pump();
        expect(
          prefs.getInt('download_image_concurrency'),
          card == comicCard ? isNull : 16,
        );
        expect(novels.concurrencyWrites, isEmpty);
        tester.widget<Slider>(slider).onChangeEnd!(16);
        await tester.pump();
        if (card == comicCard) {
          expect(prefs.getInt('download_image_concurrency'), 16);
        } else {
          expect(novels.concurrencyWrites, [16]);
        }
      }
      final toggle = find.descendant(
        of: comicCard,
        matching: find.byType(SwitchListTile),
      );
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: toggle, matching: find.byType(Switch)),
      );
      await tester.pump();
      expect(downloads.downloadCommentsEnabled, isFalse);
      expect(prefs.getBool('download_chapter_comments'), isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
