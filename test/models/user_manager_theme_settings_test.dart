import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/app_theme_option.dart';
import 'package:kira/models/network_settings.dart';
import 'package:kira/models/user_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final user = UserManager();

  setUp(() async {
    setupSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({});
    await user.init();
  });

  tearDown(teardownSecureCredentialStoreForTest);

  void testSharedSetting<T>({
    required String key,
    required T initial,
    required T changed,
    required T Function() readFacade,
    required T Function() readStore,
    required Future<void> Function(T) writeFacade,
    required Future<void> Function(T) writeStore,
    required Object Function(T) storedValue,
    bool skipsSameValue = true,
  }) {
    test('$key shares state, notifications and persistence', () async {
      expect(readFacade(), initial);
      expect(readStore(), initial);
      final snapshots = <(T, T)>[];
      void listener() => snapshots.add((readFacade(), readStore()));
      user.addListener(listener);
      addTearDown(() => user.removeListener(listener));
      final prefs = await SharedPreferences.getInstance();

      await writeFacade(changed);
      expect(readStore(), changed);
      expect(readFacade(), changed);
      expect(prefs.get(key), storedValue(changed));
      expect(snapshots, [(changed, changed)]);

      snapshots.clear();
      await writeStore(initial);
      expect(readFacade(), initial);
      expect(prefs.get(key), storedValue(initial));
      expect(snapshots, [(initial, initial)]);

      snapshots.clear();
      await writeFacade(initial);
      expect(snapshots, skipsSameValue ? isEmpty : [(initial, initial)]);

      await writeStore(changed);
      teardownSecureCredentialStoreForTest();
      for (var boot = 0; boot < 3; boot++) {
        user.theme.resetPrefsCache();
        user.network.resetPrefsCache();
        await user.init(persistMigrations: false);
        expect(readFacade(), changed);
        expect(readStore(), changed);
        expect(prefs.get(key), storedValue(changed));
      }

      await prefs.remove(key);
      await user.init(persistMigrations: false);
      expect(readFacade(), initial);
      expect(readStore(), initial);
    });
  }

  testSharedSetting(
    key: 'theme_mode',
    initial: ThemeMode.system,
    changed: ThemeMode.dark,
    readFacade: () => user.themeMode,
    readStore: () => user.theme.themeMode,
    writeFacade: user.setThemeMode,
    writeStore: user.theme.setThemeMode,
    storedValue: (value) => value.index,
    skipsSameValue: false,
  );
  testSharedSetting(
    key: 'theme_color',
    initial: defaultThemeOptionId,
    changed: 'teal',
    readFacade: () => user.themeColor,
    readStore: () => user.theme.themeColor,
    writeFacade: user.setThemeColor,
    writeStore: user.theme.setThemeColor,
    storedValue: (value) => value,
  );
  testSharedSetting(
    key: 'theme_variant',
    initial: defaultThemeVariant,
    changed: DynamicSchemeVariant.vibrant,
    readFacade: () => user.themeVariant,
    readStore: () => user.theme.themeVariant,
    writeFacade: user.setThemeVariant,
    writeStore: user.theme.setThemeVariant,
    storedValue: (value) => value.name,
  );
  testSharedSetting(
    key: 'custom_theme_color',
    initial: defaultCustomThemeColor,
    changed: Color(appThemeOptions[1].seedColor.toARGB32()),
    readFacade: () => user.customThemeColor,
    readStore: () => user.theme.customThemeColor,
    writeFacade: user.setCustomThemeColor,
    writeStore: user.theme.setCustomThemeColor,
    storedValue: (value) => value.toARGB32(),
  );
  testSharedSetting(
    key: 'dark_mode_cover_brightness',
    initial: UserManager.defaultDarkModeCoverBrightness,
    changed: 0.4,
    readFacade: () => user.darkModeCoverBrightness,
    readStore: () => user.theme.darkModeCoverBrightness,
    writeFacade: user.setDarkModeCoverBrightness,
    writeStore: user.theme.setDarkModeCoverBrightness,
    storedValue: (value) => value,
  );
  testSharedSetting(
    key: 'pref_display_mode_refresh_rate',
    initial: 0,
    changed: 120,
    readFacade: () => user.displayModeRefreshRate,
    readStore: () => user.theme.displayModeRefreshRate,
    writeFacade: user.setDisplayModeRefreshRate,
    writeStore: user.theme.setDisplayModeRefreshRate,
    storedValue: (value) => value,
  );
  testSharedSetting(
    key: 'api_route',
    initial: NetworkSettings.defaultApiRoute,
    changed: 0,
    readFacade: () => user.apiRoute,
    readStore: () => user.network.apiRoute,
    writeFacade: user.setApiRoute,
    writeStore: user.network.setApiRoute,
    storedValue: (value) => value,
    skipsSameValue: false,
  );

  test(
    'custom color publishes active theme and seed together in one notification',
    () async {
      final color = Color(appThemeOptions[1].seedColor.toARGB32());
      final snapshots = <(String, String, Color, Color)>[];
      void listener() => snapshots.add((
        user.themeColor,
        user.theme.themeColor,
        user.themeOption.seedColor,
        user.theme.themeOption.seedColor,
      ));
      user.addListener(listener);
      addTearDown(() => user.removeListener(listener));

      await user.theme.setCustomThemeColor(color);
      expect(snapshots, [
        (customThemeOptionId, customThemeOptionId, color, color),
      ]);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('theme_color'), customThemeOptionId);
      expect(prefs.getInt('custom_theme_color'), color.toARGB32());

      snapshots.clear();
      await user.setCustomThemeColor(color);
      expect(snapshots, isEmpty);
      await user.setThemeColor('teal');
      expect(user.themeOption.id, 'teal');
      expect(user.theme.themeOption.id, 'teal');
      snapshots.clear();
      await user.setCustomThemeColor(color);
      expect(snapshots, [
        (customThemeOptionId, customThemeOptionId, color, color),
      ]);
    },
  );

  test(
    'invalid theme identifiers retain fallback behavior without rewriting prefs',
    () async {
      SharedPreferences.setMockInitialValues({
        'theme_color': 'unknown-color',
        'theme_variant': 'unknown-variant',
        'dark_mode_cover_brightness': 0.01,
        'pref_display_mode_refresh_rate': -120,
      });
      await user.init(persistMigrations: false);
      expect(user.themeColor, defaultThemeOptionId);
      expect(user.themeVariantOption.variant, defaultThemeVariant);
      expect(
        user.darkModeCoverBrightness,
        UserManager.minDarkModeCoverBrightness,
      );
      expect(user.displayModeRefreshRate, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('theme_color'), 'unknown-color');
      expect(prefs.getString('theme_variant'), 'unknown-variant');
      expect(prefs.getDouble('dark_mode_cover_brightness'), 0.01);
      expect(prefs.getInt('pref_display_mode_refresh_rate'), -120);

      await user.theme.setThemeColor('teal');
      await user.setThemeColor('unknown-color');
      expect(user.theme.themeColor, defaultThemeOptionId);
      expect(prefs.getString('theme_color'), defaultThemeOptionId);
    },
  );

  test(
    'temporary cover brightness is shared, clamped and not persisted',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await user.setDarkModeCoverBrightness(0.4);
      var notifications = 0;
      void listener() => notifications++;
      user.addListener(listener);
      addTearDown(() => user.removeListener(listener));

      await user.setDarkModeCoverBrightness(0.01, persist: false);
      expect(
        user.theme.darkModeCoverBrightness,
        UserManager.minDarkModeCoverBrightness,
      );
      expect(
        user.darkModeCoverBrightness,
        UserManager.minDarkModeCoverBrightness,
      );
      expect(prefs.getDouble('dark_mode_cover_brightness'), 0.4);
      expect(notifications, 1);
      await user.theme.setDarkModeCoverBrightness(2.0, persist: false);
      expect(
        user.darkModeCoverBrightness,
        UserManager.maxDarkModeCoverBrightness,
      );
      expect(prefs.getDouble('dark_mode_cover_brightness'), 0.4);
      expect(notifications, 2);

      await user.init(persistMigrations: false);
      expect(user.darkModeCoverBrightness, 0.4);
    },
  );

  test('negative refresh rates normalize to auto through both paths', () async {
    await user.setDisplayModeRefreshRate(120);
    await user.theme.setDisplayModeRefreshRate(-1);
    expect(user.displayModeRefreshRate, 0);
    await user.theme.setDisplayModeRefreshRate(90);
    await user.setDisplayModeRefreshRate(-1);
    expect(user.theme.displayModeRefreshRate, 0);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('pref_display_mode_refresh_rate'), 0);
  });
}
