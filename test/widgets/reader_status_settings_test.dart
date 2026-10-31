import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/models/reader_settings.dart';
import 'package:kira/widgets/reader_status_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

void main() {
  setUp(setupSecureCredentialStoreForTest);
  tearDown(teardownSecureCredentialStoreForTest);

  testWidgets(
    'dragging the first status segment to the end persists its final index',
    (tester) async {
      SharedPreferences.setMockInitialValues({'reader_status_overlay': true});
      final prefs = await SharedPreferences.getInstance();
      final reader = ReaderSettings()..resetPrefsCache();
      await reader.initFromPrefs(prefs);
      var changes = 0;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ReaderStatusSettingsSection(onChanged: () => changes++),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('reader-status-details-toggle')),
      );
      await tester.pumpAndSettle();
      final handles = find.byType(ReorderableDragStartListener);
      final first = tester.getCenter(handles.first);
      final last = tester.getCenter(handles.last);
      final gesture = await tester.startGesture(first);
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.moveTo(last + const Offset(0, 100));
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.moveBy(const Offset(0, 1));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      const expected = ['network', 'battery', 'page', 'fps', 'time'];
      expect(reader.statusOverlayOrder, expected);
      expect(prefs.getStringList('reader_status_overlay_order'), expected);
      expect(changes, 1);
      expect(tester.takeException(), isNull);

      // 反向拖回首位，验证没有在新回调上重复做旧回调的索引补偿。
      final back = await tester.startGesture(tester.getCenter(handles.last));
      await tester.pump();
      await back.moveTo(tester.getCenter(handles.first) - const Offset(0, 100));
      await tester.pump(const Duration(milliseconds: 300));
      await back.up();
      await tester.pumpAndSettle();
      expect(
        reader.statusOverlayOrder,
        ReaderSettings.defaultStatusOverlayOrder,
      );
      expect(changes, 2);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('details collapse independently of the overlay preference', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'reader_status_overlay': true});
    final prefs = await SharedPreferences.getInstance();
    final reader = ReaderSettings()..resetPrefsCache();
    await reader.initFromPrefs(prefs);
    var changes = 0;
    await tester.pumpWidget(
      wrapWithApp(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: SingleChildScrollView(
              child: ReaderStatusSettingsSection(onChanged: () => changes++),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final toggle = find.byKey(const ValueKey('reader-status-details-toggle'));
    final slider = find.byType(Slider);
    expect(slider.hitTestable(), findsNothing);
    await tester.tap(find.text('状态显示'));
    await tester.pump();
    expect(slider.hitTestable(), findsOneWidget);
    await tester.tap(toggle);
    await tester.pump();
    expect(slider.hitTestable(), findsNothing);
    expect(reader.statusOverlay, isTrue);
    expect(changes, 0);
    await tester.tap(
      find.byKey(const ValueKey('reader-status-overlay-switch')),
    );
    await tester.pump();
    expect(reader.statusOverlay, isFalse);
    expect(toggle, findsOneWidget);
    expect(changes, 1);
    await tester.tap(find.text('状态显示'));
    await tester.pump();
    expect(slider.hitTestable(), findsOneWidget);
    expect(reader.statusOverlay, isFalse);
    expect(changes, 1);
    await tester.tap(
      find.byKey(const ValueKey('reader-status-overlay-switch')),
    );
    await tester.pump();
    expect(reader.statusOverlay, isTrue);
    expect(slider.hitTestable(), findsOneWidget);
    expect(changes, 2);
    expect(tester.takeException(), isNull);
  });
}
