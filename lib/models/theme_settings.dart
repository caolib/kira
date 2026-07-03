import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme_option.dart';
import 'prefs_store.dart';

/// Theme and appearance settings, extracted from UserManager.
class ThemeSettings extends PrefsStore {
  static final ThemeSettings _instance = ThemeSettings._();
  factory ThemeSettings() => _instance;
  ThemeSettings._();

  // ── Shared constants (moved from UserManager) ──────────────────────

  static const defaultNavKey = 'comic';
  static const defaultNavOrder = [
    'comic',
    'anime',
    'search',
    'bookshelf',
    'profile',
  ];
  static const defaultDisplayModeRefreshRate = 0;

  static const appLogoPaths = [
    'assets/ic_launcher.png',
    'assets/ic_launcher_1.png',
  ];

  // ── Defaults ───────────────────────────────────────────────────────

  static const double minDarkModeCoverBrightness = 0.10;
  static const double maxDarkModeCoverBrightness = 1.0;
  static const double defaultDarkModeCoverBrightness = 0.85;

  // ── Preference keys ────────────────────────────────────────────────

  static const _keyThemeMode = 'theme_mode';
  static const _keyThemeColor = 'theme_color';
  static const _keyThemeVariant = 'theme_variant';
  static const _keyCustomThemeColor = 'custom_theme_color';
  static const _keyDarkModeCoverBrightness = 'dark_mode_cover_brightness';
  static const _keyBottomNavShowLabels = 'bottom_nav_show_labels';
  static const _keyNavOrder = 'nav_order';
  static const _keyLastNavKey = 'last_nav_key';
  static const _keyDesktopFontFamily = 'desktop_font_family';
  static const _keyDisplayModeRefreshRate = 'pref_display_mode_refresh_rate';
  static const _keyLogoIndex = 'logo_index';
  static const _keyBannerVisible = 'banner_visible';

  // ── Fields ─────────────────────────────────────────────────────────

  ThemeMode _themeMode = ThemeMode.system;
  String _themeColor = appThemeOptions.first.id;
  DynamicSchemeVariant _themeVariant = appThemeVariantOptions.first.variant;
  int _customThemeColorValue = defaultCustomThemeColor.toARGB32();
  double _darkModeCoverBrightness = defaultDarkModeCoverBrightness;
  bool _bottomNavShowLabels = true;
  List<String> _navOrder = defaultNavOrder;
  String _lastNavKey = defaultNavKey;
  String _desktopFontFamily = '';
  int _displayModeRefreshRate = defaultDisplayModeRefreshRate;
  int _logoIndex = 1;
  bool _bannerVisible = true;

  // ── Getters ────────────────────────────────────────────────────────

  ThemeMode get themeMode => _themeMode;
  String get themeColor => _themeColor;
  DynamicSchemeVariant get themeVariant => _themeVariant;
  Color get customThemeColor => Color(_customThemeColorValue);
  double get darkModeCoverBrightness => _darkModeCoverBrightness;
  bool get bottomNavShowLabels => _bottomNavShowLabels;
  List<String> get navOrder => _navOrder;
  String get lastNavKey => _lastNavKey;
  String get desktopFontFamily => _desktopFontFamily;
  int get displayModeRefreshRate => _displayModeRefreshRate;
  int get logoIndex => _logoIndex;
  bool get bannerVisible => _bannerVisible;

  AppThemeOption get themeOption {
    if (_themeColor == customThemeOptionId) {
      return AppThemeOption(
        id: customThemeOptionId,
        label: '自定',
        seedColor: customThemeColor,
      );
    }
    return resolveAppThemeOption(_themeColor);
  }

  AppThemeVariantOption get themeVariantOption =>
      resolveAppThemeVariantOption(_themeVariant.name);

  // ── Init ───────────────────────────────────────────────────────────

  Future<void> initFromPrefs(SharedPreferences prefs) async {
    _themeMode = ThemeMode.values[prefs.getInt(_keyThemeMode) ?? 0];
    final savedThemeColor = prefs.getString(_keyThemeColor);
    _themeColor = savedThemeColor == customThemeOptionId
        ? customThemeOptionId
        : resolveAppThemeOption(savedThemeColor).id;
    _themeVariant = resolveAppThemeVariantOption(
      prefs.getString(_keyThemeVariant),
    ).variant;
    _customThemeColorValue =
        prefs.getInt(_keyCustomThemeColor) ??
        defaultCustomThemeColor.toARGB32();
    _darkModeCoverBrightness = _normalizeDarkModeCoverBrightness(
      prefs.getDouble(_keyDarkModeCoverBrightness) ??
          defaultDarkModeCoverBrightness,
    );
    _bottomNavShowLabels = prefs.getBool(_keyBottomNavShowLabels) ?? true;
    final savedNavOrder = prefs.getStringList(_keyNavOrder);
    _navOrder = _normalizeNavOrder(savedNavOrder);
    if (savedNavOrder != null &&
        savedNavOrder.join('\u0000') != _navOrder.join('\u0000')) {
      await prefs.setStringList(_keyNavOrder, _navOrder);
    }
    final savedLastNavKey = prefs.getString(_keyLastNavKey);
    _lastNavKey = _normalizeNavKey(savedLastNavKey);
    if (savedLastNavKey != null && savedLastNavKey != _lastNavKey) {
      await prefs.setString(_keyLastNavKey, _lastNavKey);
    }
    _desktopFontFamily = prefs.getString(_keyDesktopFontFamily) ?? '';
    _displayModeRefreshRate = _normalizeDisplayModeRefreshRate(
      prefs.getInt(_keyDisplayModeRefreshRate),
    );
    _logoIndex = (prefs.getInt(_keyLogoIndex) ?? 1).clamp(
      0,
      appLogoPaths.length - 1,
    );
    _bannerVisible = prefs.getBool(_keyBannerVisible) ?? true;
  }

  // ── Setters ────────────────────────────────────────────────────────

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await setInt(_keyThemeMode, mode.index);
  }

  Future<void> setThemeColor(String themeColor) async {
    final nextThemeColor = themeColor == customThemeOptionId
        ? customThemeOptionId
        : resolveAppThemeOption(themeColor).id;
    if (_themeColor == nextThemeColor) return;

    _themeColor = nextThemeColor;
    await setString(_keyThemeColor, nextThemeColor);
  }

  Future<void> setThemeVariant(DynamicSchemeVariant variant) async {
    if (_themeVariant == variant) return;
    _themeVariant = variant;
    await setString(_keyThemeVariant, variant.name);
  }

  Future<void> setCustomThemeColor(Color color) async {
    final nextColorValue = color.toARGB32();
    final shouldNotify =
        _customThemeColorValue != nextColorValue ||
        _themeColor != customThemeOptionId;

    _customThemeColorValue = nextColorValue;
    _themeColor = customThemeOptionId;

    final p = await prefs;
    await p.setInt(_keyCustomThemeColor, nextColorValue);
    await p.setString(_keyThemeColor, customThemeOptionId);

    if (shouldNotify) notifyListeners();
  }

  Future<void> setDarkModeCoverBrightness(double value) async {
    final nextValue = _normalizeDarkModeCoverBrightness(value);
    if (_darkModeCoverBrightness == nextValue) return;

    _darkModeCoverBrightness = nextValue;
    await setDouble(_keyDarkModeCoverBrightness, nextValue);
  }

  Future<void> setBottomNavShowLabels(bool enabled) async {
    if (_bottomNavShowLabels == enabled) return;
    _bottomNavShowLabels = enabled;
    await setBool(_keyBottomNavShowLabels, enabled);
  }

  Future<void> setNavOrder(List<String> order) async {
    _navOrder = _normalizeNavOrder(order);
    await setStringList(_keyNavOrder, _navOrder);
  }

  Future<void> setLastNavKey(String key) async {
    final nextKey = _normalizeNavKey(key);
    if (_lastNavKey == nextKey && key == nextKey) return;
    _lastNavKey = nextKey;
    await setString(_keyLastNavKey, nextKey, notify: false);
  }

  Future<void> setDesktopFontFamily(String fontFamily) async {
    if (_desktopFontFamily == fontFamily) return;
    _desktopFontFamily = fontFamily;
    if (fontFamily.isEmpty) {
      await remove(_keyDesktopFontFamily);
    } else {
      await setString(_keyDesktopFontFamily, fontFamily);
    }
  }

  Future<void> setDisplayModeRefreshRate(int refreshRate) async {
    final nextRate = _normalizeDisplayModeRefreshRate(refreshRate);
    if (_displayModeRefreshRate == nextRate) return;
    _displayModeRefreshRate = nextRate;
    await setInt(_keyDisplayModeRefreshRate, nextRate);
  }

  Future<void> setBannerVisible(bool visible) async {
    if (_bannerVisible == visible) return;
    _bannerVisible = visible;
    await setBool(_keyBannerVisible, visible);
  }

  // ── Normalizers ────────────────────────────────────────────────────

  static double _normalizeDarkModeCoverBrightness(double value) {
    return value
        .clamp(minDarkModeCoverBrightness, maxDarkModeCoverBrightness)
        .toDouble();
  }

  static String _normalizeNavKey(String? key) {
    return defaultNavOrder.contains(key) ? key! : defaultNavKey;
  }

  static List<String> _normalizeNavOrder(List<String>? order) {
    final normalized = <String>[];
    for (final key in order ?? defaultNavOrder) {
      if (defaultNavOrder.contains(key) && !normalized.contains(key)) {
        normalized.add(key);
      }
    }
    for (final key in defaultNavOrder) {
      if (!normalized.contains(key)) {
        normalized.add(key);
      }
    }
    return normalized;
  }

  static int _normalizeDisplayModeRefreshRate(int? refreshRate) {
    if (refreshRate == null || refreshRate < 0) {
      return defaultDisplayModeRefreshRate;
    }
    return refreshRate;
  }
}
