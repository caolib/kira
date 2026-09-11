part of '../user_manager.dart';

extension UserManagerThemeNavPart on UserManager {
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(UserManager._keyThemeMode, mode.index);
    _notifyListeners();
  }

  Future<void> setThemeColor(String themeColor) async {
    final nextThemeColor = themeColor == customThemeOptionId
        ? customThemeOptionId
        : resolveAppThemeOption(themeColor).id;
    if (_themeColor == nextThemeColor) return;

    _themeColor = nextThemeColor;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(UserManager._keyThemeColor, nextThemeColor);
    _notifyListeners();
  }

  Future<void> setThemeVariant(DynamicSchemeVariant variant) async {
    if (_themeVariant == variant) return;

    _themeVariant = variant;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(UserManager._keyThemeVariant, variant.name);
    _notifyListeners();
  }

  Future<void> setCustomThemeColor(Color color) async {
    final nextColorValue = color.toARGB32();
    final shouldNotify =
        _customThemeColorValue != nextColorValue ||
        _themeColor != customThemeOptionId;

    _customThemeColorValue = nextColorValue;
    _themeColor = customThemeOptionId;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(UserManager._keyCustomThemeColor, nextColorValue);
    await prefs.setString(UserManager._keyThemeColor, customThemeOptionId);

    if (shouldNotify) _notifyListeners();
  }

  Future<void> setDarkModeCoverBrightness(
    double value, {
    bool persist = true,
  }) async {
    final nextValue = UserManager._normalizeDarkModeCoverBrightness(value);
    if (_darkModeCoverBrightness == nextValue) return;

    _darkModeCoverBrightness = nextValue;
    if (persist) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(UserManager._keyDarkModeCoverBrightness, nextValue);
    }
    _notifyListeners();
  }

  Future<void> setBottomNavShowLabels(bool enabled) async {
    await setBottomNavLabelMode(
      enabled ? BottomNavLabelMode.selectedOnly : BottomNavLabelMode.hidden,
    );
  }

  Future<void> setBottomNavLabelMode(BottomNavLabelMode mode) async {
    if (_bottomNavLabelMode == mode) return;

    _bottomNavLabelMode = mode;
    // ThemeSettings is the canonical store for appearance prefs; keep it
    // aligned so direct ThemeSettings readers see the same mode.
    await theme.setBottomNavLabelMode(mode);
    _notifyListeners();
  }

  Future<void> setNavOrder(List<String> order) async {
    _navOrder = UserManager._normalizeNavOrder(order);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(UserManager._keyNavOrder, _navOrder);
    _notifyListeners();
  }

  Future<void> setLastNavKey(String key) async {
    final nextKey = UserManager._normalizeNavKey(key);
    if (_lastNavKey == nextKey && key == nextKey) return;

    _lastNavKey = nextKey;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(UserManager._keyLastNavKey, nextKey);
  }

  Future<void> setDesktopFontFamily(String fontFamily) async {
    if (_desktopFontFamily == fontFamily) return;
    _desktopFontFamily = fontFamily;
    final prefs = await SharedPreferences.getInstance();
    if (fontFamily.isEmpty) {
      await prefs.remove(UserManager._keyDesktopFontFamily);
    } else {
      await prefs.setString(UserManager._keyDesktopFontFamily, fontFamily);
    }
    _notifyListeners();
  }

  Future<void> setDisplayModeRefreshRate(int refreshRate) async {
    final nextRate = UserManager._normalizeDisplayModeRefreshRate(refreshRate);
    if (_displayModeRefreshRate == nextRate) return;

    _displayModeRefreshRate = nextRate;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(UserManager._keyDisplayModeRefreshRate, nextRate);
    _notifyListeners();
  }

  Future<void> setBookshelfOrdering(String ordering) async {
    _bookshelfOrdering = ordering;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(UserManager._keyBookshelfOrdering, ordering);
    _notifyListeners();
  }

  Future<void> setLogoIndex(int index) async {
    final next = index.clamp(0, UserManager.appLogoPaths.length - 1);
    if (_logoIndex == next) return;
    _logoIndex = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(UserManager._keyLogoIndex, next);
    _notifyListeners();
    if (Platform.isAndroid || Platform.isIOS) {
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
}
