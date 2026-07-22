import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/models/theme_settings.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/about_page.dart' show AboutPage;
import 'package:kira/pages/appearance_page.dart';
import 'package:kira/pages/profile_page.dart' show ProfilePage;
import 'package:kira/utils/app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _buildTestApp(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(cardTheme: const CardThemeData(elevation: 2.5)),
    home: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final user = UserManager();
    user.theme.resetPrefsCache();
    await user.init();
    AppUpdateService.state.value = const AppUpdateState.latest();
    PackageInfo.setMockInitialValues(
      appName: 'Kira',
      packageName: 'com.example.kira',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  test('user manager forwards unified shadow setting changes', () async {
    final user = UserManager();
    var notifications = 0;
    void listener() => notifications++;
    user.addListener(listener);

    await user.theme.setCardShadowElevation(1.5);

    expect(notifications, 1);
    user.removeListener(listener);
  });

  testWidgets('appearance page persists the unified card shadow size', (
    tester,
  ) async {
    await tester.pumpWidget(_buildTestApp(const AppearancePage()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('统一阴影大小'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    final sliderFinder = find.byWidgetPredicate(
      (widget) =>
          widget is Slider &&
          widget.min == ThemeSettings.minCardShadowElevation &&
          widget.max == ThemeSettings.maxCardShadowElevation,
    );
    final slider = tester.widget<Slider>(sliderFinder);

    expect(slider.value, 2.0);
    expect(slider.divisions, 8);

    slider.onChangeEnd!(2.5);
    await tester.pumpAndSettle();

    expect(UserManager().theme.cardShadowElevation, 2.5);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('card_shadow_elevation'), 2.5);
  });

  testWidgets('profile cards inherit the global card shadow', (tester) async {
    await tester.pumpWidget(_buildTestApp(const ProfilePage()));
    await tester.pumpAndSettle();

    final cards = tester.widgetList<Card>(find.byType(Card)).toList();
    expect(cards, isNotEmpty);
    expect(cards.every((card) => card.elevation == null), isTrue);
  });

  testWidgets('active about page cards inherit the global card shadow', (
    tester,
  ) async {
    await tester.pumpWidget(_buildTestApp(const AboutPage()));
    await tester.pumpAndSettle();

    final cards = tester.widgetList<Card>(find.byType(Card)).toList();
    expect(cards, isNotEmpty);
    expect(cards.every((card) => card.elevation == null), isTrue);
  });
}
