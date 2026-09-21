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

  /// 记住搜索页停留的标签，下次冷启动直接回到这一页。
  ///
  /// 不调 [_notifyListeners]：这个值只被 [SearchPage] 初次建
  /// [TabController] 时读一次，切 tab 时通知全体监听者重建没有意义。
  Future<void> setSearchTabIndex(int index) async {
    final next = index.clamp(0, 1);
    if (_searchTabIndex == next) return;
    _searchTabIndex = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(UserManager._keySearchTabIndex, next);
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

  Future<void> _persistCustomCopyLoginHosts(SharedPreferences prefs) =>
      prefs.setStringList(
        UserManager._keyCustomCopyLoginHosts,
        _customCopyLoginHosts,
      );

  /// 添加自定义登录域名（不做合法性校验，由用户自己负责）。
  /// 空值或与现有条目重复（含内置）返回 false。
  Future<bool> addCustomCopyLoginHost(String value) async {
    final host = value.trim();
    if (host.isEmpty || copyLoginHostChoices.contains(host)) return false;

    _customCopyLoginHosts = [..._customCopyLoginHosts, host];
    final prefs = await SharedPreferences.getInstance();
    await _persistCustomCopyLoginHosts(prefs);
    _notifyListeners();
    return true;
  }

  /// 删除自定义登录域名。若删的是当前启用域名，回落到内置默认。
  Future<void> removeCustomCopyLoginHost(String host) async {
    if (!_customCopyLoginHosts.contains(host)) return;

    _customCopyLoginHosts = _customCopyLoginHosts
        .where((e) => e != host)
        .toList(growable: true);
    final prefs = await SharedPreferences.getInstance();
    await _persistCustomCopyLoginHosts(prefs);
    if (_copyLoginHost == host) {
      _copyLoginHost = defaultCopyLoginHost;
      await prefs.setString(
        UserManager._keyCopyLoginHost,
        defaultCopyLoginHost,
      );
    }
    _notifyListeners();
  }

  /// 修改自定义登录域名（不做合法性校验，由用户自己负责）。
  /// 新值为空或与现有条目重复（含内置）返回 false；
  /// 若旧值是当前启用域名，修改后同步切换到新值。
  Future<bool> updateCustomCopyLoginHost(String oldHost, String next) async {
    if (!_customCopyLoginHosts.contains(oldHost)) return false;
    final host = next.trim();
    if (host.isEmpty) return false;
    if (host == oldHost) return true;
    if (copyLoginHostChoices.where((e) => e != oldHost).contains(host)) {
      return false;
    }

    _customCopyLoginHosts = [
      for (final h in _customCopyLoginHosts)
        if (h == oldHost) host else h,
    ];
    final prefs = await SharedPreferences.getInstance();
    await _persistCustomCopyLoginHosts(prefs);
    if (_copyLoginHost == oldHost) {
      _copyLoginHost = host;
      await prefs.setString(UserManager._keyCopyLoginHost, host);
    }
    _notifyListeners();
    return true;
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
