part of '../user_manager.dart';

extension UserManagerAppSettingsPart on UserManager {
  Future<void> setAutoCheckUpdate(bool enabled) async {
    _autoCheckUpdate = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(UserManager._keyAutoCheckUpdate, enabled);
    _notifyListeners();
  }

  Future<void> setSkippedUpdateVersion(String? version) async {
    _skippedUpdateVersion = version;
    final prefs = await SharedPreferences.getInstance();
    if (version == null || version.isEmpty) {
      await prefs.remove(UserManager._keySkippedUpdateVersion);
    } else {
      await prefs.setString(UserManager._keySkippedUpdateVersion, version);
    }
    _notifyListeners();
  }

  Future<void> setUpdateMirrorPrefix(String value) async {
    final normalized = UserManager.normalizeUpdateMirrorPrefix(value);
    if (_updateMirrorPrefix == normalized) return;

    _updateMirrorPrefix = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(UserManager._keyUpdateMirrorPrefix, normalized);
    _notifyListeners();
  }

  Future<void> setUpdateChannel(String value) async {
    final next = value == 'beta' ? 'beta' : 'stable';
    if (_updateChannel == next) return;
    _updateChannel = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(UserManager._keyUpdateChannel, next);
    _notifyListeners();
  }

  Future<void> setLastBetaAssetName(String? name) async {
    if (_lastBetaAssetName == name) return;
    _lastBetaAssetName = name;
    final prefs = await SharedPreferences.getInstance();
    if (name == null || name.isEmpty) {
      await prefs.remove(UserManager._keyLastBetaAssetName);
    } else {
      await prefs.setString(UserManager._keyLastBetaAssetName, name);
    }
    _notifyListeners();
  }

  Future<void> setUseUpdateMirror(bool value) async {
    if (_useUpdateMirror == value) return;
    _useUpdateMirror = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(UserManager._keyUseUpdateMirror, value);
    _notifyListeners();
  }

  Future<void> setAutoLogin(bool enabled) async {
    _autoLogin = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(UserManager._keyAutoLogin, enabled);
    _notifyListeners();
  }

  Future<void> setDisclaimerAccepted(bool accepted) async {
    _disclaimerAccepted = accepted;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(UserManager._keyDisclaimerAccepted, accepted);
    _notifyListeners();
  }

  Future<void> setApiRoute(int route) async {
    _apiRoute = route;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(UserManager._keyApiRoute, route);
    _notifyListeners();
  }

  Future<void> setNetworkSelectionMode(NetworkSelectionMode mode) async {
    await network.setSelectionMode(mode);
    _notifyListeners();
  }

  Future<void> setFixedNodeHost(String? host) async {
    await network.setFixedNodeHost(host);
    _notifyListeners();
  }

  Future<void> setNetworkProxyMode(NetworkProxyMode mode) =>
      network.setProxyMode(mode);

  Future<void> setManualProxy({
    required String host,
    required int port,
    required NetworkProxyType type,
    bool enable = true,
  }) => network.setManualProxy(
    host: host,
    port: port,
    type: type,
    enable: enable,
  );

  Future<void> setRemoteNoticeEnabled(bool enabled) async {
    if (_remoteNoticeEnabled == enabled) return;
    _remoteNoticeEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(UserManager._keyRemoteNoticeEnabled, enabled);
    _notifyListeners();
  }

  Future<void> setLocale(String locale) async {
    if (_locale == locale) return;
    _locale = locale;
    final prefs = await SharedPreferences.getInstance();
    if (locale.isEmpty) {
      await prefs.remove(UserManager._keyLocale);
    } else {
      await prefs.setString(UserManager._keyLocale, locale);
    }
    _notifyListeners();
  }

  Future<void> setBannerVisible(bool visible) async {
    if (_bannerVisible == visible) return;
    _bannerVisible = visible;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(UserManager._keyBannerVisible, visible);
    _notifyListeners();
  }

  Future<void> setMangaHomeSource(String source) async {
    if (_mangaHomeSource == source) return;
    _mangaHomeSource = source;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(UserManager._keyMangaHomeSource, source);
    _notifyListeners();
  }

  Future<void> setCopyApiHost(String value) async {
    final normalized = UserManager.normalizeCopyApiHost(value);
    if (_copyApiHost == normalized) return;

    _copyApiHost = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(UserManager._keyCopyApiHost, normalized);
    _notifyListeners();
  }

  Future<void> setCopyLoginHost(String value) async {
    final normalized = UserManager.normalizeCopyLoginHost(value);
    if (_copyLoginHost == normalized) return;

    _copyLoginHost = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(UserManager._keyCopyLoginHost, normalized);
    _notifyListeners();
  }

  Future<void> setCopyAppVersion(String value) async {
    final normalized = UserManager.normalizeCopyAppVersion(value);
    if (_copyAppVersion == normalized) return;

    _copyAppVersion = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(UserManager._keyCopyAppVersion, normalized);
    _notifyListeners();
  }

  Future<void> setCopyAutoUpdate(bool enabled) async {
    if (_copyAutoUpdate == enabled) return;
    _copyAutoUpdate = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(UserManager._keyCopyAutoUpdate, enabled);
    _notifyListeners();
  }

  /// 记录「本次启动已尝试自动更新 COPY 高级设置」，内部调用。
  Future<void> markCopySettingsUpdated() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    _copySettingsUpdatedAt = now;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(UserManager._keyCopySettingsUpdatedAt, now);
    _notifyListeners();
  }

  Future<void> setCopyHomeSectionCollapsed(String key, bool collapsed) async {
    if (_copyHomeSectionCollapsed[key] == collapsed) return;
    _copyHomeSectionCollapsed = {..._copyHomeSectionCollapsed, key: collapsed};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      UserManager._keyCopyHomeSectionCollapsed,
      jsonEncode(_copyHomeSectionCollapsed),
    );
  }
}
