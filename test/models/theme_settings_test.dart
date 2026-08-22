import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/theme_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ThemeSettings settings;

  setUp(() async {
    settings = ThemeSettings();
    settings.resetPrefsCache();
  });

  test(
    'defaults to selectedOnly when no bottom-nav preference exists',
    () async {
      SharedPreferences.setMockInitialValues({});
      await settings.initFromPrefs(await SharedPreferences.getInstance());
      expect(settings.bottomNavLabelMode, BottomNavLabelMode.selectedOnly);
      expect(settings.bottomNavShowLabels, isTrue);
    },
  );

  test('migrates legacy true bool to selectedOnly mode', () async {
    SharedPreferences.setMockInitialValues({'bottom_nav_show_labels': true});
    await settings.initFromPrefs(await SharedPreferences.getInstance());
    expect(settings.bottomNavLabelMode, BottomNavLabelMode.selectedOnly);
    expect(settings.bottomNavShowLabels, isTrue);
  });

  test('migrates legacy false bool to hidden mode', () async {
    SharedPreferences.setMockInitialValues({'bottom_nav_show_labels': false});
    await settings.initFromPrefs(await SharedPreferences.getInstance());
    expect(settings.bottomNavLabelMode, BottomNavLabelMode.hidden);
    expect(settings.bottomNavShowLabels, isFalse);
  });

  test('prefers explicit label mode over legacy bool', () async {
    SharedPreferences.setMockInitialValues({
      'bottom_nav_show_labels': false,
      'bottom_nav_label_mode': BottomNavLabelMode.selectedOnly.name,
    });
    await settings.initFromPrefs(await SharedPreferences.getInstance());
    expect(settings.bottomNavLabelMode, BottomNavLabelMode.selectedOnly);
  });

  test('setBottomNavLabelMode writes mode and legacy bool', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await settings.initFromPrefs(prefs);

    await settings.setBottomNavLabelMode(BottomNavLabelMode.hidden);
    expect(settings.bottomNavLabelMode, BottomNavLabelMode.hidden);
    expect(prefs.getString('bottom_nav_label_mode'), 'hidden');
    expect(prefs.getBool('bottom_nav_show_labels'), isFalse);

    await settings.setBottomNavLabelMode(BottomNavLabelMode.always);
    expect(settings.bottomNavLabelMode, BottomNavLabelMode.always);
    expect(prefs.getString('bottom_nav_label_mode'), 'always');
    expect(prefs.getBool('bottom_nav_show_labels'), isTrue);
  });

  test('nav swipe defaults to enabled and persists when toggled', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await settings.initFromPrefs(prefs);

    expect(settings.navSwipeEnabled, isTrue);

    await settings.setNavSwipeEnabled(false);
    expect(settings.navSwipeEnabled, isFalse);
    expect(prefs.getBool('nav_swipe_enabled'), isFalse);

    await settings.initFromPrefs(prefs);
    expect(settings.navSwipeEnabled, isFalse);
  });

  test('back exit confirm defaults to enabled and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await settings.initFromPrefs(prefs);

    expect(settings.backExitConfirm, isTrue);

    await settings.setBackExitConfirm(false);
    expect(settings.backExitConfirm, isFalse);
    expect(prefs.getBool('back_exit_confirm'), isFalse);

    await settings.initFromPrefs(prefs);
    expect(settings.backExitConfirm, isFalse);
  });

  test('uses default appearance sizing preferences', () async {
    SharedPreferences.setMockInitialValues({});
    await settings.initFromPrefs(await SharedPreferences.getInstance());

    expect(settings.defaultFontSize, ThemeSettings.defaultAppFontSize);
    expect(settings.cardShadowElevation, 2.0);
  });

  test('keeps a saved zero card shadow elevation', () async {
    SharedPreferences.setMockInitialValues({'card_shadow_elevation': 0.0});
    await settings.initFromPrefs(await SharedPreferences.getInstance());

    expect(settings.cardShadowElevation, 0.0);
  });

  test('persists and clamps appearance sizing preferences', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await settings.initFromPrefs(prefs);

    await settings.setDefaultFontSize(16);
    await settings.setCardShadowElevation(2.5);

    expect(prefs.getDouble('default_font_size'), 16);
    expect(prefs.getDouble('card_shadow_elevation'), 2.5);

    await settings.setDefaultFontSize(100);
    await settings.setCardShadowElevation(100);

    expect(settings.defaultFontSize, ThemeSettings.maxDefaultFontSize);
    expect(settings.cardShadowElevation, ThemeSettings.maxCardShadowElevation);
    await settings.setCardShadowElevation(-1);
    expect(settings.cardShadowElevation, ThemeSettings.minCardShadowElevation);
  });

  test(
    'loads a clamped card shadow elevation and notifies on change',
    () async {
      SharedPreferences.setMockInitialValues({'card_shadow_elevation': 99.0});
      await settings.initFromPrefs(await SharedPreferences.getInstance());

      expect(
        settings.cardShadowElevation,
        ThemeSettings.maxCardShadowElevation,
      );

      var notifications = 0;
      void listener() => notifications++;
      settings.addListener(listener);

      await settings.setCardShadowElevation(1.5);

      expect(settings.cardShadowElevation, 1.5);
      expect(notifications, 1);
      settings.removeListener(listener);
    },
  );
}
