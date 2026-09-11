part of '../user_manager.dart';

extension UserManagerInitPart on UserManager {
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(UserManager._keyToken);
    _username = prefs.getString(UserManager._keyUsername);
    _nickname = prefs.getString(UserManager._keyNickname);
    _avatar = prefs.getString(UserManager._keyAvatar);
    _userId = prefs.getString(UserManager._keyUserId);
    _savedUsername = prefs.getString(UserManager._keySavedUsername);
    _savedPassword = prefs.getString(UserManager._keySavedPassword);
    final savedCredentialsRaw = prefs.getString(
      UserManager._keySavedCredentials,
    );
    if (savedCredentialsRaw != null && savedCredentialsRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(savedCredentialsRaw);
        if (decoded is List) {
          _savedCredentials = decoded
              .whereType<Map>()
              .map(
                (e) => SavedCredential.fromJson(Map<String, dynamic>.from(e)),
              )
              .where((e) => e.username.isNotEmpty)
              .toList();
        }
      } catch (_) {
        _savedCredentials = [];
      }
    }
    if (_savedCredentials.isEmpty &&
        _savedUsername != null &&
        _savedUsername!.isNotEmpty &&
        _savedPassword != null) {
      _savedCredentials = [
        SavedCredential(username: _savedUsername!, password: _savedPassword!),
      ];
      await prefs.setString(
        UserManager._keySavedCredentials,
        jsonEncode(_savedCredentials.map((e) => e.toJson()).toList()),
      );
    }
    _themeMode = ThemeMode.values[prefs.getInt(UserManager._keyThemeMode) ?? 0];
    final savedThemeColor = prefs.getString(UserManager._keyThemeColor);
    _themeColor = savedThemeColor == customThemeOptionId
        ? customThemeOptionId
        : resolveAppThemeOption(savedThemeColor).id;
    _themeVariant = resolveAppThemeVariantOption(
      prefs.getString(UserManager._keyThemeVariant),
    ).variant;
    _customThemeColorValue =
        prefs.getInt(UserManager._keyCustomThemeColor) ??
        defaultCustomThemeColor.toARGB32();
    _darkModeCoverBrightness = UserManager._normalizeDarkModeCoverBrightness(
      prefs.getDouble(UserManager._keyDarkModeCoverBrightness) ??
          UserManager.defaultDarkModeCoverBrightness,
    );
    _bottomNavLabelMode = UserManager._loadBottomNavLabelMode(prefs);
    final savedNavOrder = prefs.getStringList(UserManager._keyNavOrder);
    _navOrder = UserManager._normalizeNavOrder(savedNavOrder);
    if (savedNavOrder != null &&
        savedNavOrder.join('\u0000') != _navOrder.join('\u0000')) {
      await prefs.setStringList(UserManager._keyNavOrder, _navOrder);
    }
    final savedLastNavKey = prefs.getString(UserManager._keyLastNavKey);
    _lastNavKey = UserManager._normalizeNavKey(savedLastNavKey);
    if (savedLastNavKey != null && savedLastNavKey != _lastNavKey) {
      await prefs.setString(UserManager._keyLastNavKey, _lastNavKey);
    }
    _desktopFontFamily =
        prefs.getString(UserManager._keyDesktopFontFamily) ?? '';
    _displayModeRefreshRate = UserManager._normalizeDisplayModeRefreshRate(
      prefs.getInt(UserManager._keyDisplayModeRefreshRate),
    );
    _bookshelfOrdering =
        prefs.getString(UserManager._keyBookshelfOrdering) ??
        ApiOrdering.datetimeUpdated;
    _readerScrollDirection =
        prefs.getInt(UserManager._keyReaderScrollDirection) ?? 2;
    _readerImageGap = prefs.getDouble(UserManager._keyReaderImageGap) ?? 0.0;
    _readerVolumeKey = prefs.getBool(UserManager._keyReaderVolumeKey) ?? true;
    _readerInstantPageTurn =
        prefs.getBool(UserManager._keyReaderInstantPageTurn) ?? false;
    _readerPageRTL = prefs.getBool(UserManager._keyReaderPageRTL) ?? false;
    _readerPageVertical =
        prefs.getBool(UserManager._keyReaderPageVertical) ?? false;
    _readerDimming = prefs.getDouble(UserManager._keyReaderDimming) ?? 0.3;
    _readerAutoScrollEnabled =
        prefs.getBool(UserManager._keyReaderAutoScrollEnabled) ?? false;
    _readerAutoScrollPause =
        (prefs.getDouble(UserManager._keyReaderAutoScrollPause) ?? 3.0).clamp(
          0.5,
          8.0,
        );
    _readerAutoScrollResume =
        prefs.getBool(UserManager._keyReaderAutoScrollResume) ?? false;
    _readerAutoScrollResumeDelay =
        (prefs.getDouble(UserManager._keyReaderAutoScrollResumeDelay) ?? 2.0)
            .clamp(1.0, 5.0);
    _readerAutoScrollDistance =
        (prefs.getDouble(UserManager._keyReaderAutoScrollDistance) ?? 0.8)
            .clamp(0.2, 1.0);
    _readerContinuousReading =
        prefs.getBool(UserManager._keyReaderContinuousReading) ?? true;
    _readerHorizontalImageScale =
        (prefs.getDouble(UserManager._keyReaderHorizontalImageScale) ?? 1.0)
            .clamp(0.7, 1.0);
    _imageViewerAutoRotateLandscape =
        prefs.getBool(UserManager._keyImageViewerAutoRotateLandscape) ?? false;
    final savedImageViewerLandscapeRotation =
        prefs.getInt(UserManager._keyImageViewerLandscapeRotation) ?? 1;
    _imageViewerLandscapeRotation = savedImageViewerLandscapeRotation < 0
        ? -1
        : 1;
    _imageLoadTimeout = prefs.getInt(UserManager._keyImageLoadTimeout) ?? 15;
    _imageRetryCount = prefs.getInt(UserManager._keyImageRetryCount) ?? 1;
    _commentCompactLayout =
        prefs.getBool(UserManager._keyCommentCompactLayout) ?? true;
    _commentShowAvatar =
        prefs.getBool(UserManager._keyCommentShowAvatar) ?? true;
    _commentShowUserName =
        prefs.getBool(UserManager._keyCommentShowUserName) ?? true;
    _commentShowTime = prefs.getBool(UserManager._keyCommentShowTime) ?? true;
    _commentPreload = prefs.getBool(UserManager._keyCommentPreload) ?? true;
    _commentAutoLoadAll =
        prefs.getBool(UserManager._keyCommentAutoLoadAll) ?? false;
    _autoCheckUpdate = prefs.getBool(UserManager._keyAutoCheckUpdate) ?? true;
    _skippedUpdateVersion = prefs.getString(
      UserManager._keySkippedUpdateVersion,
    );
    _updateMirrorPrefix = UserManager.normalizeUpdateMirrorPrefix(
      prefs.getString(UserManager._keyUpdateMirrorPrefix),
    );
    _updateChannel = prefs.getString(UserManager._keyUpdateChannel) == 'beta'
        ? 'beta'
        : 'stable';
    _lastBetaAssetName = prefs.getString(UserManager._keyLastBetaAssetName);
    _useUpdateMirror = prefs.getBool(UserManager._keyUseUpdateMirror) ?? true;
    _autoLogin = prefs.getBool(UserManager._keyAutoLogin) ?? false;
    _disclaimerAccepted =
        prefs.getBool(UserManager._keyDisclaimerAccepted) ?? false;
    _loginSource = prefs.getString(UserManager._keyLoginSource) ?? 'hotmanga';
    _apiRoute = prefs.getInt(UserManager._keyApiRoute) ?? 0;
    _remoteNoticeEnabled =
        prefs.getBool(UserManager._keyRemoteNoticeEnabled) ?? true;
    _locale = prefs.getString(UserManager._keyLocale) ?? '';
    _bannerVisible = prefs.getBool(UserManager._keyBannerVisible) ?? true;
    _mangaHomeSource =
        prefs.getString(UserManager._keyMangaHomeSource) ?? 'hot';
    _copyApiHost = UserManager.normalizeCopyApiHost(
      prefs.getString(UserManager._keyCopyApiHost),
    );
    _copyLoginHost = UserManager.normalizeCopyLoginHost(
      prefs.getString(UserManager._keyCopyLoginHost),
    );
    {
      // 自定义登录域名：仅去空白、去重（含与内置重复），不校验合法性。
      final custom = <String>[];
      for (final raw
          in prefs.getStringList(UserManager._keyCustomCopyLoginHosts) ??
              const <String>[]) {
        final host = raw.trim();
        if (host.isEmpty ||
            custom.contains(host) ||
            copyLoginHostOptions.contains(host)) {
          continue;
        }
        custom.add(host);
      }
      _customCopyLoginHosts = custom;
      // 历史内置域名（如 www.mangacopy.com）曾被选为当前域名，内置列表
      // 收窄后不再包含它们——并入自定义列表，保持可见、可切换、可删除。
      // 仅内存合并即可：copyLoginHost 持久不变，下次 init 会重新推导。
      if (!copyLoginHostOptions.contains(_copyLoginHost) &&
          !_customCopyLoginHosts.contains(_copyLoginHost)) {
        _customCopyLoginHosts = [..._customCopyLoginHosts, _copyLoginHost];
      }
    }
    _copyAppVersion = UserManager.normalizeCopyAppVersion(
      prefs.getString(UserManager._keyCopyAppVersion),
    );
    _copyAutoUpdate = prefs.getBool(UserManager._keyCopyAutoUpdate) ?? true;
    _copySettingsUpdatedAt = prefs.getInt(
      UserManager._keyCopySettingsUpdatedAt,
    );
    _copyHomeSectionCollapsed = UserManager._decodeBoolMap(
      prefs.getString(UserManager._keyCopyHomeSectionCollapsed),
    );
    _commentBlockedUsers =
        prefs.getStringList(UserManager._keyCommentBlockedUsers) ?? [];
    _commentBlockNoRemind =
        prefs.getBool(UserManager._keyCommentBlockNoRemind) ?? false;
    _commentBlockwords =
        prefs.getStringList(UserManager._keyCommentBlockwords) ?? [];
    _commentBlockGroupSpam =
        prefs.getBool(UserManager._keyCommentBlockGroupSpam) ?? false;
    _logoIndex = (prefs.getInt(UserManager._keyLogoIndex) ?? 1).clamp(
      0,
      UserManager.appLogoPaths.length - 1,
    );
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final platformIndex = await AppIconSwitcher.getAppIconIndex();
        _logoIndex = platformIndex.clamp(
          0,
          UserManager.appLogoPaths.length - 1,
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
    // Initialize domain-specific sub-stores with the same prefs instance.
    await reader.initFromPrefs(prefs);
    await comment.initFromPrefs(prefs);
    await theme.initFromPrefs(prefs);
    await network.initFromPrefs(prefs);

    // Forward sub-store notifications so legacy listeners on UserManager
    // still rebuild when domain settings change.
    reader.addListener(_onSubStoreChanged);
    comment.addListener(_onSubStoreChanged);
    theme.addListener(_onSubStoreChanged);
    network.addListener(_onSubStoreChanged);

    _notifyListeners();
  }
}
