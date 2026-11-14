import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_icon_switcher.dart';
import '../utils/app_logger.dart';
import '../utils/font_manager.dart';
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
    'novel',
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
  static const double minDefaultFontSize = 8.0;
  static const double maxDefaultFontSize = 26.0;
  static const double defaultAppFontSize = 14.0;
  static const double minCardShadowElevation = 0.0;
  static const double maxCardShadowElevation = 4.0;
  static const double defaultCardShadowElevation = 2.0;

  // ── Preference keys ────────────────────────────────────────────────

  static const _keyThemeMode = 'theme_mode';
  static const _keyThemeColor = 'theme_color';
  static const _keyThemeVariant = 'theme_variant';
  static const _keyCustomThemeColor = 'custom_theme_color';
  static const _keyDarkModeCoverBrightness = 'dark_mode_cover_brightness';
  static const _keyDefaultFontSize = 'default_font_size';
  static const _keyCardShadowElevation = 'card_shadow_elevation';
  static const _keyBottomNavShowLabels = 'bottom_nav_show_labels';
  static const _keyBottomNavLabelMode = 'bottom_nav_label_mode';
  static const _keyNavOrder = 'nav_order';
  static const _keyNavSwipeEnabled = 'nav_swipe_enabled';
  static const _keyFloatingNavEnabled = 'nav_floating_enabled';
  static const _keyBackExitConfirm = 'back_exit_confirm';
  static const _keyShowNovel = 'nav_show_novel';
  static const _keyBrowseHistoryLocal = 'nav_browse_history_local';
  static const _keyLastNavKey = 'last_nav_key';
  static const _keyAppFontFamily = 'app_font_family';
  static const _keyDisplayModeRefreshRate = 'pref_display_mode_refresh_rate';
  static const _keyLogoIndex = 'logo_index';
  static const _keyBannerVisible = 'banner_visible';
  static const _keyUseDynamicColor = 'use_dynamic_color';
  static const _keyAmoledDark = 'amoled_dark';
  static const _keyReduceMotion = 'reduce_motion';

  // ── Fields ─────────────────────────────────────────────────────────

  ThemeMode _themeMode = ThemeMode.system;
  String _themeColor = defaultThemeOptionId;
  DynamicSchemeVariant _themeVariant = defaultThemeVariant;
  int _customThemeColorValue = defaultCustomThemeColor.toARGB32();
  double _darkModeCoverBrightness = defaultDarkModeCoverBrightness;
  double _defaultFontSize = defaultAppFontSize;
  double _cardShadowElevation = defaultCardShadowElevation;
  BottomNavLabelMode _bottomNavLabelMode = BottomNavLabelMode.selectedOnly;
  List<String> _navOrder = defaultNavOrder;
  bool _navSwipeEnabled = true;
  bool _floatingNavEnabled = true;
  bool _backExitConfirm = true;
  bool _showNovel = true;
  bool _browseHistoryLocal = false;
  Future<void>? _browseHistoryModeQueue;
  String _lastNavKey = defaultNavKey;
  String _appFontFamily = '';
  int _displayModeRefreshRate = defaultDisplayModeRefreshRate;
  int _logoIndex = 1;
  bool _bannerVisible = true;
  bool _useDynamicColor = false;
  bool _amoledDark = false;
  bool _reduceMotion = false;

  // ── Getters ────────────────────────────────────────────────────────

  ThemeMode get themeMode => _themeMode;
  String get themeColor => _themeColor;
  DynamicSchemeVariant get themeVariant => _themeVariant;
  Color get customThemeColor => Color(_customThemeColorValue);
  double get darkModeCoverBrightness => _darkModeCoverBrightness;
  double get defaultFontSize => _defaultFontSize;
  double get cardShadowElevation => _cardShadowElevation;
  BottomNavLabelMode get bottomNavLabelMode => _bottomNavLabelMode;

  /// Compatibility: any mode that still shows label text somewhere.
  bool get bottomNavShowLabels =>
      _bottomNavLabelMode != BottomNavLabelMode.hidden;
  List<String> get navOrder => _navOrder;

  /// Whether a horizontal swipe on the main shell switches bottom-nav tabs.
  bool get navSwipeEnabled => _navSwipeEnabled;

  /// Whether the bottom navigation bar floats above page content.
  ///
  /// 悬浮底栏浮在内容之上，经典模式（标签始终显示）的满宽不透明条撑在
  /// 内容外面会露出 Scaffold 背景色，只能切到胶囊样式；因此开启悬浮时
  /// 顺带把标签模式从 [BottomNavLabelMode.always] 降为
  /// [BottomNavLabelMode.selectedOnly]，无需提醒用户。
  bool get floatingNavEnabled => _floatingNavEnabled;

  /// Whether back on a bottom-nav root asks for a second press before exiting.
  bool get backExitConfirm => _backExitConfirm;

  /// 是否展示轻小说入口（底部导航、书架等 tab 与各处入口）。
  bool get showNovel => _showNovel;

  /// 浏览记录上次显示本机进度，默认显示在线历史。
  bool get browseHistoryLocal => _browseHistoryLocal;
  String get lastNavKey => _lastNavKey;
  String get appFontFamily => _appFontFamily;
  int get displayModeRefreshRate => _displayModeRefreshRate;
  int get logoIndex => _logoIndex;
  bool get bannerVisible => _bannerVisible;

  /// Android 12+ Monet dynamic color from system wallpaper.
  bool get useDynamicColor => _useDynamicColor;

  /// Pure-black background in dark mode for OLED screens.
  bool get amoledDark => _amoledDark;

  /// App-level "reduce motion" switch. It is OR-ed with the system setting so
  /// turning it on skips transitions even when the OS preference is off.
  bool get reduceMotion => _reduceMotion;

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

  Future<void> initFromPrefs(
    SharedPreferences prefs, {
    bool persistMigrations = true,
  }) async {
    syncPrefs(prefs);
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
    _defaultFontSize = _normalizeDefaultFontSize(
      prefs.getDouble(_keyDefaultFontSize) ?? defaultAppFontSize,
    );
    _cardShadowElevation = _normalizeCardShadowElevation(
      prefs.getDouble(_keyCardShadowElevation) ?? defaultCardShadowElevation,
    );
    _bottomNavLabelMode = _loadBottomNavLabelMode(prefs);
    final savedNavOrder = prefs.getStringList(_keyNavOrder);
    _navOrder = _normalizeNavOrder(savedNavOrder);
    if (persistMigrations &&
        savedNavOrder != null &&
        savedNavOrder.join('\u0000') != _navOrder.join('\u0000')) {
      await prefs.setStringList(_keyNavOrder, _navOrder);
    }
    _navSwipeEnabled = prefs.getBool(_keyNavSwipeEnabled) ?? true;
    _floatingNavEnabled = prefs.getBool(_keyFloatingNavEnabled) ?? true;
    // 旧数据可能同时留着悬浮 + 「始终显示文字」；沿用 setter 的互斥规则。
    if (_floatingNavEnabled &&
        _bottomNavLabelMode == BottomNavLabelMode.always) {
      _bottomNavLabelMode = BottomNavLabelMode.selectedOnly;
      if (persistMigrations) {
        await prefs.setString(_keyBottomNavLabelMode, _bottomNavLabelMode.name);
      }
    }
    _backExitConfirm = prefs.getBool(_keyBackExitConfirm) ?? true;
    _showNovel = prefs.getBool(_keyShowNovel) ?? true;
    _browseHistoryLocal = prefs.getBool(_keyBrowseHistoryLocal) ?? false;
    final savedLastNavKey = prefs.getString(_keyLastNavKey);
    _lastNavKey = _normalizeNavKey(savedLastNavKey);
    if (persistMigrations &&
        savedLastNavKey != null &&
        savedLastNavKey != _lastNavKey) {
      await prefs.setString(_keyLastNavKey, _lastNavKey);
    }
    _appFontFamily = prefs.getString(_keyAppFontFamily) ?? '';
    _displayModeRefreshRate = _normalizeDisplayModeRefreshRate(
      prefs.getInt(_keyDisplayModeRefreshRate),
    );
    _logoIndex = (prefs.getInt(_keyLogoIndex) ?? 1).clamp(
      0,
      appLogoPaths.length - 1,
    );
    // The launcher is authoritative on mobile; do not rewrite the saved value.
    if (AppIconSwitcher.isSupportedPlatform) {
      try {
        _logoIndex = (await AppIconSwitcher.getAppIconIndex()).clamp(
          0,
          appLogoPaths.length - 1,
        );
      } catch (e, stack) {
        unawaited(
          AppLogger.instance.recordWarning(
            e,
            stackTrace: stack,
            source: 'user_manager.get_app_icon',
          ),
        );
      }
    }
    _bannerVisible = prefs.getBool(_keyBannerVisible) ?? true;
    _useDynamicColor = prefs.getBool(_keyUseDynamicColor) ?? false;
    _amoledDark = prefs.getBool(_keyAmoledDark) ?? false;
    _reduceMotion = prefs.getBool(_keyReduceMotion) ?? false;
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

  Future<void> setDarkModeCoverBrightness(
    double value, {
    bool persist = true,
  }) async {
    final nextValue = _normalizeDarkModeCoverBrightness(value);
    if (_darkModeCoverBrightness == nextValue) return;

    _darkModeCoverBrightness = nextValue;
    if (persist) {
      await setDouble(_keyDarkModeCoverBrightness, nextValue);
    } else {
      notifyListeners();
    }
  }

  Future<void> setDefaultFontSize(double value) async {
    final nextValue = _normalizeDefaultFontSize(value);
    if (_defaultFontSize == nextValue) return;

    _defaultFontSize = nextValue;
    await setDouble(_keyDefaultFontSize, nextValue);
  }

  Future<void> setCardShadowElevation(double value) async {
    final nextValue = _normalizeCardShadowElevation(value);
    if (_cardShadowElevation == nextValue) return;

    _cardShadowElevation = nextValue;
    await setDouble(_keyCardShadowElevation, nextValue);
  }

  Future<void> setBottomNavShowLabels(bool enabled) async {
    await setBottomNavLabelMode(
      enabled ? BottomNavLabelMode.selectedOnly : BottomNavLabelMode.hidden,
    );
  }

  /// 「始终显示文字」只在非悬浮时可选：悬浮底栏是浮在内容上的胶囊，
  /// 满宽不透明条撑在内容外面会露出 Scaffold 背景色。悬浮开着时把它降为
  /// 选中项显示，用户不用被告知，也不会遇到那个错配的样式。
  Future<void> setBottomNavLabelMode(BottomNavLabelMode mode) async {
    final next = mode == BottomNavLabelMode.always && _floatingNavEnabled
        ? BottomNavLabelMode.selectedOnly
        : mode;
    if (_bottomNavLabelMode == next) return;
    _bottomNavLabelMode = next;
    final p = await prefs;
    await p.setString(_keyBottomNavLabelMode, next.name);
    // Keep legacy bool in sync for older builds / external readers.
    await p.setBool(_keyBottomNavShowLabels, next != BottomNavLabelMode.hidden);
    notifyListeners();
  }

  Future<void> setNavOrder(List<String> order) async {
    _navOrder = _normalizeNavOrder(order);
    await setStringList(_keyNavOrder, _navOrder);
  }

  Future<void> setNavSwipeEnabled(bool enabled) async {
    if (_navSwipeEnabled == enabled) return;
    _navSwipeEnabled = enabled;
    await setBool(_keyNavSwipeEnabled, enabled);
  }

  Future<void> setFloatingNavEnabled(bool enabled) async {
    if (_floatingNavEnabled == enabled) return;
    _floatingNavEnabled = enabled;
    await setBool(_keyFloatingNavEnabled, enabled, notify: false);
    // 悬浮与「始终显示文字」互斥，见 floatingNavEnabled 的说明。
    if (enabled && _bottomNavLabelMode == BottomNavLabelMode.always) {
      await setBottomNavLabelMode(BottomNavLabelMode.selectedOnly);
      return;
    }
    notifyListeners();
  }

  Future<void> setBackExitConfirm(bool enabled) async {
    if (_backExitConfirm == enabled) return;
    _backExitConfirm = enabled;
    await setBool(_keyBackExitConfirm, enabled);
  }

  Future<void> setShowNovel(bool value) async {
    if (_showNovel == value) return;
    _showNovel = value;
    await setBool(_keyShowNovel, value);
  }

  Future<void> setBrowseHistoryLocal(bool value) {
    final operation = (_browseHistoryModeQueue ?? Future<void>.value()).then((
      _,
    ) async {
      if (_browseHistoryLocal == value) return;
      final p = await prefs;
      final previous = p.getBool(_keyBrowseHistoryLocal);
      try {
        if (!await p.setBool(_keyBrowseHistoryLocal, value)) {
          throw StateError('Browse history mode persistence failed');
        }
      } catch (error, stack) {
        // SharedPreferences 写失败也可能已修改内存缓存，恢复旧值再重载。
        try {
          if (previous == null) {
            await p.remove(_keyBrowseHistoryLocal);
          } else {
            await p.setBool(_keyBrowseHistoryLocal, previous);
          }
          await p.reload();
        } catch (rollbackError, rollbackStack) {
          unawaited(
            AppLogger.instance.recordWarning(
              rollbackError,
              stackTrace: rollbackStack,
              source: 'theme_settings.browse_history_mode_rollback',
            ),
          );
        }
        Error.throwWithStackTrace(error, stack);
      }
      _browseHistoryLocal = value;
      notifyListeners();
    });
    late final Future<void> tail;
    void releaseIfIdle() {
      if (identical(_browseHistoryModeQueue, tail)) {
        _browseHistoryModeQueue = null;
      }
    }

    tail = operation.then<void>(
      (_) => releaseIfIdle(),
      onError: (Object error, StackTrace stack) {
        releaseIfIdle();
        unawaited(
          AppLogger.instance.recordWarning(
            error,
            stackTrace: stack,
            source: 'theme_settings.browse_history_mode',
          ),
        );
      },
    );
    _browseHistoryModeQueue = tail;
    return operation;
  }

  Future<void> setLastNavKey(String key) async {
    final nextKey = _normalizeNavKey(key);
    if (_lastNavKey == nextKey && key == nextKey) return;
    _lastNavKey = nextKey;
    await setString(_keyLastNavKey, nextKey, notify: false);
  }

  Future<void> setAppFontFamily(String fontFamily) async {
    final next = fontFamily == FontManager.defaultFontId ? '' : fontFamily;
    if (_appFontFamily == next) return;
    _appFontFamily = next;
    if (next.isEmpty) {
      await remove(_keyAppFontFamily);
    } else {
      await setString(_keyAppFontFamily, next);
    }
  }

  Future<void> setDisplayModeRefreshRate(int refreshRate) async {
    final nextRate = _normalizeDisplayModeRefreshRate(refreshRate);
    if (_displayModeRefreshRate == nextRate) return;
    _displayModeRefreshRate = nextRate;
    await setInt(_keyDisplayModeRefreshRate, nextRate);
  }

  Future<void> setLogoIndex(int index) async {
    final next = index.clamp(0, appLogoPaths.length - 1);
    if (_logoIndex == next) return;
    _logoIndex = next;
    await setInt(_keyLogoIndex, next);
    if (AppIconSwitcher.isSupportedPlatform) {
      try {
        await AppIconSwitcher.setAppIcon(next);
      } catch (e, stack) {
        unawaited(
          AppLogger.instance.recordWarning(
            e,
            stackTrace: stack,
            source: 'user_manager.set_app_icon',
          ),
        );
      }
    }
  }

  Future<void> setBannerVisible(bool visible) async {
    if (_bannerVisible == visible) return;
    _bannerVisible = visible;
    await setBool(_keyBannerVisible, visible);
  }

  Future<void> setUseDynamicColor(bool enabled) async {
    if (_useDynamicColor == enabled) return;
    _useDynamicColor = enabled;
    await setBool(_keyUseDynamicColor, enabled);
  }

  Future<void> setAmoledDark(bool enabled) async {
    if (_amoledDark == enabled) return;
    _amoledDark = enabled;
    await setBool(_keyAmoledDark, enabled);
  }

  Future<void> setReduceMotion(bool enabled) async {
    if (_reduceMotion == enabled) return;
    _reduceMotion = enabled;
    await setBool(_keyReduceMotion, enabled);
  }

  // ── Normalizers ────────────────────────────────────────────────────

  static double _normalizeDarkModeCoverBrightness(double value) {
    return value
        .clamp(minDarkModeCoverBrightness, maxDarkModeCoverBrightness)
        .toDouble();
  }

  static double _normalizeDefaultFontSize(double value) {
    return value.clamp(minDefaultFontSize, maxDefaultFontSize).toDouble();
  }

  static double _normalizeCardShadowElevation(double value) {
    return value
        .clamp(minCardShadowElevation, maxCardShadowElevation)
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
    // Add the new destination next to comics without reordering existing tabs.
    if (!normalized.contains('novel') && normalized.contains('comic')) {
      normalized.insert(normalized.indexOf('comic') + 1, 'novel');
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

  /// Prefer the new string key; fall back to the legacy bool for upgrades.
  static BottomNavLabelMode _loadBottomNavLabelMode(SharedPreferences prefs) {
    final saved = prefs.getString(_keyBottomNavLabelMode);
    if (saved != null) {
      for (final mode in BottomNavLabelMode.values) {
        if (mode.name == saved) return mode;
      }
    }
    // Upgrades: old "show labels" becomes the new capsule selected-only
    // mode so users pick up the new bar without staying on classic always.
    final legacy = prefs.getBool(_keyBottomNavShowLabels);
    if (legacy == false) return BottomNavLabelMode.hidden;
    return BottomNavLabelMode.selectedOnly;
  }
}

/// Bottom navigation label presentation.
///
/// - [selectedOnly]: capsule bar; label only on the selected tab (default)
/// - [hidden]: capsule bar; icons only
/// - [always]: classic Material bar; labels always under icons
enum BottomNavLabelMode { selectedOnly, hidden, always }
