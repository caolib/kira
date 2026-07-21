import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/api_transport.dart';
import '../utils/app_icon_switcher.dart';
import '../utils/app_logger.dart';
import 'api_ordering.dart';
import 'app_theme_option.dart';
import 'comment_settings.dart';
import 'danmaku_settings.dart';
import 'network_proxy_types.dart';
import 'network_settings.dart';
import 'reader_settings.dart';
import 'theme_settings.dart';

export 'network_proxy_types.dart';
export 'network_settings.dart' show NetworkSelectionMode;
export 'theme_settings.dart' show BottomNavLabelMode;

class SavedCredential {
  final String username;
  final String password;
  final String? token;
  final String? loginSource;
  final String? userId;
  final String? nickname;
  final String? avatar;

  const SavedCredential({
    required this.username,
    required this.password,
    this.token,
    this.loginSource,
    this.userId,
    this.nickname,
    this.avatar,
  });

  factory SavedCredential.fromJson(Map<String, dynamic> json) =>
      SavedCredential(
        username: json['username']?.toString() ?? '',
        password: json['password']?.toString() ?? '',
        token: json['token']?.toString(),
        loginSource: json['login_source']?.toString(),
        userId: json['user_id']?.toString(),
        nickname: json['nickname']?.toString(),
        avatar: json['avatar']?.toString(),
      );

  Map<String, dynamic> toJson() => {
    'username': username,
    'password': password,
    if (token != null) 'token': token,
    if (loginSource != null) 'login_source': loginSource,
    if (userId != null) 'user_id': userId,
    if (nickname != null) 'nickname': nickname,
    if (avatar != null) 'avatar': avatar,
  };

  SavedCredential copyWith({
    String? token,
    String? loginSource,
    String? userId,
    String? nickname,
    String? avatar,
  }) => SavedCredential(
    username: username,
    password: password,
    token: token ?? this.token,
    loginSource: loginSource ?? this.loginSource,
    userId: userId ?? this.userId,
    nickname: nickname ?? this.nickname,
    avatar: avatar ?? this.avatar,
  );
}

class UserManager extends ChangeNotifier {
  static final UserManager _instance = UserManager._();
  factory UserManager() => _instance;
  UserManager._();

  // ── Domain-specific sub-stores ─────────────────────────────────────
  // Each store is an independent ChangeNotifier.  Callers that only
  // need reader / danmaku / comment / theme / network settings should
  // import the specific store directly and skip the facade entirely.

  final reader = ReaderSettings();
  final danmaku = DanmakuSettings();
  final comment = CommentSettings();
  final theme = ThemeSettings();
  final network = NetworkSettings();

  // ── Backward-compat constant re-exports ────────────────────────────
  // These delegate to the canonical definitions in each sub-store so
  // existing callers that reference UserManager.defaultXxx keep working.

  static const double minDarkModeCoverBrightness =
      ThemeSettings.minDarkModeCoverBrightness;
  static const double maxDarkModeCoverBrightness =
      ThemeSettings.maxDarkModeCoverBrightness;
  static const double defaultDarkModeCoverBrightness =
      ThemeSettings.defaultDarkModeCoverBrightness;
  static const defaultNavKey = ThemeSettings.defaultNavKey;
  static const defaultNavOrder = ThemeSettings.defaultNavOrder;
  static const defaultDisplayModeRefreshRate =
      ThemeSettings.defaultDisplayModeRefreshRate;
  static const defaultUpdateMirrorPrefix = 'https://ghproxy.net/';

  static const appLogoPaths = ThemeSettings.appLogoPaths;

  static const _keyToken = 'user_token';
  static const _keyUsername = 'user_username';
  static const _keyNickname = 'user_nickname';
  static const _keyAvatar = 'user_avatar';
  static const _keyUserId = 'user_id';
  static const _keySavedUsername = 'saved_username';
  static const _keySavedPassword = 'saved_password';
  static const _keySavedCredentials = 'saved_credentials';
  static const _keyThemeMode = 'theme_mode';
  static const _keyThemeColor = 'theme_color';
  static const _keyThemeVariant = 'theme_variant';
  static const _keyCustomThemeColor = 'custom_theme_color';
  static const _keyDarkModeCoverBrightness = 'dark_mode_cover_brightness';
  static const _keyBottomNavShowLabels = 'bottom_nav_show_labels';
  static const _keyBottomNavLabelMode = 'bottom_nav_label_mode';
  static const _keyNavOrder = 'nav_order';
  static const _keyLastNavKey = 'last_nav_key';
  static const _keyDesktopFontFamily = 'desktop_font_family';
  static const _keyDisplayModeRefreshRate = 'pref_display_mode_refresh_rate';
  static const _keyBookshelfOrdering = 'bookshelf_ordering';
  static const _keyReaderMode = 'reader_mode';
  static const _keyReaderScrollDirection = 'reader_scroll_direction';
  static const _keyReaderImageGap = 'reader_image_gap';
  static const _keyReaderVolumeKey = 'reader_volume_key';
  static const _keyReaderInstantPageTurn = 'reader_instant_page_turn';
  static const _keyReaderPageRTL = 'reader_page_rtl';
  static const _keyReaderPageVertical = 'reader_page_vertical';
  static const _keyReaderDimming = 'reader_dimming';
  static const _keyReaderAutoScrollEnabled = 'reader_auto_scroll_enabled';
  static const _keyReaderAutoScrollPause = 'reader_auto_scroll_pause';
  static const _keyReaderAutoScrollResume = 'reader_auto_scroll_resume';
  static const _keyReaderAutoScrollResumeDelay =
      'reader_auto_scroll_resume_delay';
  static const _keyReaderAutoScrollDistance = 'reader_auto_scroll_distance';
  static const _keyReaderContinuousReading = 'reader_continuous_reading';
  static const _keyImageViewerAutoRotateLandscape =
      'image_viewer_auto_rotate_landscape';
  static const _keyImageViewerLandscapeRotation =
      'image_viewer_landscape_rotation';
  static const _keyImageLoadTimeout = 'image_load_timeout';
  static const _keyImageRetryCount = 'image_retry_count';
  static const _keyCommentCompactLayout = 'comment_compact_layout';
  static const _keyCommentShowAvatar = 'comment_show_avatar';
  static const _keyCommentShowUserName = 'comment_show_user_name';
  static const _keyCommentShowTime = 'comment_show_time';
  static const _keyCommentFontScale = 'comment_font_scale';
  static const _keyCommentPreload = 'comment_preload';
  static const _keyCommentAutoLoadAll = 'comment_auto_load_all';
  static const _keyAutoCheckUpdate = 'auto_check_update';
  static const _keySkippedUpdateVersion = 'skipped_update_version';
  static const _keyUpdateMirrorPrefix = 'update_mirror_prefix';
  static const _keyUpdateChannel = 'update_channel'; // stable | beta
  static const _keyLastBetaAssetName = 'last_beta_asset_name';
  static const _keyUseUpdateMirror = 'use_update_mirror';
  static const _keyAutoLogin = 'auto_login';
  static const _keyDisclaimerAccepted = 'disclaimer_accepted';
  static const _keyLoginSource = 'login_source';
  static const _keyApiRoute = 'api_route';
  static const _keyNetworkProxyMode = 'network_proxy_mode';
  static const _keyNetworkProxyType = 'network_proxy_type';
  static const _keyNetworkProxyHost = 'network_proxy_host';
  static const _keyNetworkProxyPort = 'network_proxy_port';
  static const _keyAnimeFeatureEnabled = 'anime_feature_enabled';
  static const _keyRemoteNoticeEnabled = 'remote_notice_enabled';
  static const _keyLocale = 'locale';
  static const _keyBannerVisible = 'banner_visible';
  static const _keyMangaHomeSource = 'manga_home_source';
  static const _keyCopyApiHost = 'copy_api_host';
  static const _keyCopyAppVersion = 'copy_app_version';
  static const _keyCopyAutoUpdate = 'copy_auto_update';
  static const _keyCopySettingsUpdatedAt = 'copy_settings_updated_at';
  static const _keyCopyHomeSectionCollapsed = 'copy_home_section_collapsed';
  static const _keyAnimeHomeBannerCollapsed = 'anime_home_banner_collapsed';
  static const _keyAnimeSkipSeconds = 'anime_skip_seconds';
  static const _keyAnimePlaybackProgressEnabled =
      'anime_playback_progress_enabled';
  static const _keyDanmakuEnabled = 'danmaku_enabled';
  static const _keyDanmakuFontSize = 'danmaku_font_size';
  static const _keyDanmakuArea = 'danmaku_area';
  static const _keyDanmakuOpacity = 'danmaku_opacity';
  static const _keyDanmakuHideScroll = 'danmaku_hide_scroll';
  static const _keyDanmakuHideTop = 'danmaku_hide_top';
  static const _keyDanmakuHideBottom = 'danmaku_hide_bottom';
  static const _keyDanmakuBlocklist = 'danmaku_blocklist';
  static const _keyDanmakuFontFamily = 'danmaku_font_family';
  static const _keyCommentBlockedUsers = 'comment_blocked_users';
  static const _keyCommentBlockNoRemind = 'comment_block_no_remind';
  static const _keyLogoIndex = 'logo_index';

  String? _token;
  String? _username;
  String? _nickname;
  String? _avatar;
  String? _userId;
  String? _savedUsername;
  String? _savedPassword;
  List<SavedCredential> _savedCredentials = [];
  ThemeMode _themeMode = ThemeMode.system;
  String _themeColor = appThemeOptions.first.id;
  DynamicSchemeVariant _themeVariant = appThemeVariantOptions.first.variant;
  int _customThemeColorValue = defaultCustomThemeColor.toARGB32();
  double _darkModeCoverBrightness = defaultDarkModeCoverBrightness;
  BottomNavLabelMode _bottomNavLabelMode = BottomNavLabelMode.selectedOnly;
  List<String> _navOrder = defaultNavOrder;
  String _lastNavKey = defaultNavKey;
  String _desktopFontFamily = '';
  int _displayModeRefreshRate = defaultDisplayModeRefreshRate;
  String _bookshelfOrdering = ApiOrdering.datetimeUpdated;
  int _readerMode = 0;
  int _readerScrollDirection = 2;
  double _readerImageGap = 0.0;
  bool _readerVolumeKey = true;
  bool _readerInstantPageTurn = false;
  bool _readerPageRTL = false;
  bool _readerPageVertical = false;
  double _readerDimming = 0.3;
  bool _readerAutoScrollEnabled = false;
  double _readerAutoScrollPause = 3.0;
  bool _readerAutoScrollResume = false;
  double _readerAutoScrollResumeDelay = 2.0;
  double _readerAutoScrollDistance = 0.8;
  bool _readerContinuousReading = true;
  bool _imageViewerAutoRotateLandscape = false;
  int _imageViewerLandscapeRotation = 1;
  int _imageLoadTimeout = 15; // 秒
  int _imageRetryCount = 1;
  bool _commentCompactLayout = true;
  bool _commentShowAvatar = true;
  bool _commentShowUserName = true;
  bool _commentShowTime = true;
  double _commentFontScale = 1.0;
  bool _commentPreload = true;
  bool _commentAutoLoadAll = false;
  bool _autoCheckUpdate = true;
  String? _skippedUpdateVersion;
  String _updateMirrorPrefix = defaultUpdateMirrorPrefix;
  String _updateChannel = 'stable'; // stable | beta
  String? _lastBetaAssetName;
  bool _useUpdateMirror = false;
  bool _autoLogin = false;
  bool _disclaimerAccepted = false;
  String _loginSource = 'hotmanga';
  int _apiRoute = 0; // 0=线路1(默认), 1=线路2
  NetworkProxyMode _networkProxyMode = NetworkProxyMode.system;
  NetworkProxyType _networkProxyType = NetworkProxyType.http;
  String _networkProxyHost = '';
  int _networkProxyPort = 0;
  bool _animeFeatureEnabled = true;
  bool _remoteNoticeEnabled = true;
  String _locale = ''; // '' = follow system, 'zh' = 简体, 'zh-Hant' = 繁体
  bool _bannerVisible = true;
  String _mangaHomeSource = 'hot';
  String _copyApiHost = defaultCopyApiHost;
  String _copyAppVersion = defaultCopyAppVersion;
  bool _copyAutoUpdate = true;
  int? _copySettingsUpdatedAt;
  Map<String, bool> _copyHomeSectionCollapsed = {};
  bool _animeHomeBannerCollapsed = false;
  int _animeSkipSeconds = 86;
  bool _animePlaybackProgressEnabled = true;
  bool _danmakuEnabled = true;
  double _danmakuFontSize = 16;
  double _danmakuArea = 0.25;
  double _danmakuOpacity = 1.0;
  bool _danmakuHideScroll = false;
  bool _danmakuHideTop = false;
  bool _danmakuHideBottom = false;
  List<String> _danmakuBlocklist = [];
  String _danmakuFontFamily = '';

  /// 评论屏蔽用户黑名单，元素为 `userId|userName` 形式
  List<String> _commentBlockedUsers = [];
  bool _commentBlockNoRemind = false;
  int _logoIndex = 1;

  String? get token => _token;
  String? get username => _username;
  String? get nickname => _nickname;
  String? get avatar => _avatar;
  String? get userId => _userId;
  String? get savedUsername => _savedUsername;
  String? get savedPassword => _savedPassword;
  List<SavedCredential> get savedCredentials =>
      List.unmodifiable(_savedCredentials);
  ThemeMode get themeMode => _themeMode;
  String get themeColor => _themeColor;
  DynamicSchemeVariant get themeVariant => _themeVariant;
  Color get customThemeColor => Color(_customThemeColorValue);
  double get darkModeCoverBrightness => _darkModeCoverBrightness;
  BottomNavLabelMode get bottomNavLabelMode => _bottomNavLabelMode;

  /// Compatibility: true when labels are not fully hidden.
  bool get bottomNavShowLabels =>
      _bottomNavLabelMode != BottomNavLabelMode.hidden;
  List<String> get navOrder => _navOrder;
  String get lastNavKey => _lastNavKey;
  String get desktopFontFamily => _desktopFontFamily;
  int get displayModeRefreshRate => _displayModeRefreshRate;
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

  String get bookshelfOrdering => _bookshelfOrdering;
  int get readerMode => _readerMode;
  int get readerScrollDirection => _readerScrollDirection;
  double get readerImageGap => _readerImageGap;
  bool get readerVolumeKey => _readerVolumeKey;
  bool get readerInstantPageTurn => _readerInstantPageTurn;
  bool get readerPageRTL => _readerPageRTL;
  bool get readerPageVertical => _readerPageVertical;
  double get readerDimming => _readerDimming;
  bool get readerAutoScrollEnabled => _readerAutoScrollEnabled;
  double get readerAutoScrollPause => _readerAutoScrollPause;
  bool get readerAutoScrollResume => _readerAutoScrollResume;
  double get readerAutoScrollResumeDelay => _readerAutoScrollResumeDelay;
  double get readerAutoScrollDistance => _readerAutoScrollDistance;
  bool get readerContinuousReading => _readerContinuousReading;
  bool get imageViewerAutoRotateLandscape => _imageViewerAutoRotateLandscape;
  int get imageViewerLandscapeRotation => _imageViewerLandscapeRotation;
  int get imageLoadTimeout => _imageLoadTimeout;
  int get imageRetryCount => _imageRetryCount;
  bool get commentCompactLayout => _commentCompactLayout;
  bool get commentShowAvatar => _commentShowAvatar;
  bool get commentShowUserName => _commentShowUserName;
  bool get commentShowTime => _commentShowTime;
  double get commentFontScale => _commentFontScale;
  bool get commentPreload => _commentPreload;
  bool get commentAutoLoadAll => _commentAutoLoadAll;
  bool get autoCheckUpdate => _autoCheckUpdate;
  String? get skippedUpdateVersion => _skippedUpdateVersion;
  String get updateMirrorPrefix => _updateMirrorPrefix;
  String get updateChannel => _updateChannel;
  bool get isBetaUpdateChannel => _updateChannel == 'beta';
  String? get lastBetaAssetName => _lastBetaAssetName;
  bool get useUpdateMirror => _useUpdateMirror;
  bool get autoLogin => _autoLogin;
  bool get disclaimerAccepted => _disclaimerAccepted;
  String get loginSource => _loginSource;
  int get apiRoute => _apiRoute;
  NetworkSelectionMode get networkSelectionMode => network.selectionMode;
  String? get fixedNodeHost => network.fixedNodeHost;
  NetworkProxyMode get networkProxyMode => _networkProxyMode;
  NetworkProxyType get networkProxyType => _networkProxyType;
  String get networkProxyHost => _networkProxyHost;
  int get networkProxyPort => _networkProxyPort;
  bool get hasManualProxy =>
      _networkProxyHost.isNotEmpty && _networkProxyPort > 0;
  bool get animeFeatureEnabled => _animeFeatureEnabled;
  bool get remoteNoticeEnabled => _remoteNoticeEnabled;

  /// '' = follow system, 'zh' = 简体中文, 'zh-Hant' = 繁體中文
  String get locale => _locale;
  bool get bannerVisible => _bannerVisible;
  String get mangaHomeSource => _mangaHomeSource;
  String get copyApiHost => _copyApiHost;
  String get copyAppVersion => _copyAppVersion;
  bool get copyAutoUpdate => _copyAutoUpdate;
  int? get copySettingsUpdatedAt => _copySettingsUpdatedAt;
  bool isCopyHomeSectionCollapsed(String key) =>
      _copyHomeSectionCollapsed[key] ?? false;
  bool get animeHomeBannerCollapsed => _animeHomeBannerCollapsed;
  int get animeSkipSeconds => _animeSkipSeconds;
  bool get animePlaybackProgressEnabled => _animePlaybackProgressEnabled;
  bool get danmakuEnabled => _danmakuEnabled;
  double get danmakuFontSize => _danmakuFontSize;
  double get danmakuArea => _danmakuArea;
  double get danmakuOpacity => _danmakuOpacity;
  bool get danmakuHideScroll => _danmakuHideScroll;
  bool get danmakuHideTop => _danmakuHideTop;
  bool get danmakuHideBottom => _danmakuHideBottom;
  List<String> get danmakuBlocklist => List.unmodifiable(_danmakuBlocklist);
  String get danmakuFontFamily => _danmakuFontFamily;
  List<String> get commentBlockedUsers =>
      List.unmodifiable(_commentBlockedUsers);
  bool get commentBlockNoRemind => _commentBlockNoRemind;
  int get logoIndex => _logoIndex;
  String get appLogoPath =>
      appLogoPaths[_logoIndex.clamp(0, appLogoPaths.length - 1)];
  bool get isLoggedIn => _token != null && _token!.isNotEmpty;

  static String normalizeUpdateMirrorPrefix(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return defaultUpdateMirrorPrefix;

    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return defaultUpdateMirrorPrefix;
    }

    return trimmed.endsWith('/') ? trimmed : '$trimmed/';
  }

  static String normalizeCopyApiHost(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return defaultCopyApiHost;

    final rawUri = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(rawUri);
    if (uri == null || uri.host.isEmpty) return defaultCopyApiHost;

    final host = uri.host.trim().toLowerCase();
    if (host.isEmpty || host.contains(' ')) return defaultCopyApiHost;

    final authorityHost = host.contains(':') && !host.startsWith('[')
        ? '[$host]'
        : host;
    return uri.hasPort ? '$authorityHost:${uri.port}' : authorityHost;
  }

  static String normalizeCopyAppVersion(String? value) {
    final version = value?.trim() ?? '';
    return version.isEmpty ? defaultCopyAppVersion : version;
  }

  static bool isValidProxyPort(int? port) =>
      port != null && port > 0 && port <= 65535;

  static Map<String, bool> _decodeBoolMap(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value == true),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_keyToken);
    _username = prefs.getString(_keyUsername);
    _nickname = prefs.getString(_keyNickname);
    _avatar = prefs.getString(_keyAvatar);
    _userId = prefs.getString(_keyUserId);
    _savedUsername = prefs.getString(_keySavedUsername);
    _savedPassword = prefs.getString(_keySavedPassword);
    final savedCredentialsRaw = prefs.getString(_keySavedCredentials);
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
        _keySavedCredentials,
        jsonEncode(_savedCredentials.map((e) => e.toJson()).toList()),
      );
    }
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
    _bottomNavLabelMode = _loadBottomNavLabelMode(prefs);
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
    _bookshelfOrdering =
        prefs.getString(_keyBookshelfOrdering) ?? ApiOrdering.datetimeUpdated;
    _readerMode = prefs.getInt(_keyReaderMode) ?? 0;
    _readerScrollDirection = prefs.getInt(_keyReaderScrollDirection) ?? 2;
    _readerImageGap = prefs.getDouble(_keyReaderImageGap) ?? 0.0;
    _readerVolumeKey = prefs.getBool(_keyReaderVolumeKey) ?? true;
    _readerInstantPageTurn = prefs.getBool(_keyReaderInstantPageTurn) ?? false;
    _readerPageRTL = prefs.getBool(_keyReaderPageRTL) ?? false;
    _readerPageVertical = prefs.getBool(_keyReaderPageVertical) ?? false;
    _readerDimming = prefs.getDouble(_keyReaderDimming) ?? 0.3;
    _readerAutoScrollEnabled =
        prefs.getBool(_keyReaderAutoScrollEnabled) ?? false;
    _readerAutoScrollPause = (prefs.getDouble(_keyReaderAutoScrollPause) ?? 3.0)
        .clamp(0.5, 8.0);
    _readerAutoScrollResume =
        prefs.getBool(_keyReaderAutoScrollResume) ?? false;
    _readerAutoScrollResumeDelay =
        (prefs.getDouble(_keyReaderAutoScrollResumeDelay) ?? 2.0).clamp(
          1.0,
          5.0,
        );
    _readerAutoScrollDistance =
        (prefs.getDouble(_keyReaderAutoScrollDistance) ?? 0.8).clamp(0.2, 1.0);
    _readerContinuousReading =
        prefs.getBool(_keyReaderContinuousReading) ?? true;
    _imageViewerAutoRotateLandscape =
        prefs.getBool(_keyImageViewerAutoRotateLandscape) ?? false;
    final savedImageViewerLandscapeRotation =
        prefs.getInt(_keyImageViewerLandscapeRotation) ?? 1;
    _imageViewerLandscapeRotation = savedImageViewerLandscapeRotation < 0
        ? -1
        : 1;
    _imageLoadTimeout = prefs.getInt(_keyImageLoadTimeout) ?? 15;
    _imageRetryCount = prefs.getInt(_keyImageRetryCount) ?? 1;
    _commentCompactLayout = prefs.getBool(_keyCommentCompactLayout) ?? true;
    _commentShowAvatar = prefs.getBool(_keyCommentShowAvatar) ?? true;
    _commentShowUserName = prefs.getBool(_keyCommentShowUserName) ?? true;
    _commentShowTime = prefs.getBool(_keyCommentShowTime) ?? true;
    _commentFontScale = prefs.getDouble(_keyCommentFontScale) ?? 1.0;
    _commentPreload = prefs.getBool(_keyCommentPreload) ?? true;
    _commentAutoLoadAll = prefs.getBool(_keyCommentAutoLoadAll) ?? false;
    _autoCheckUpdate = prefs.getBool(_keyAutoCheckUpdate) ?? true;
    _skippedUpdateVersion = prefs.getString(_keySkippedUpdateVersion);
    _updateMirrorPrefix = normalizeUpdateMirrorPrefix(
      prefs.getString(_keyUpdateMirrorPrefix),
    );
    _updateChannel = prefs.getString(_keyUpdateChannel) == 'beta'
        ? 'beta'
        : 'stable';
    _lastBetaAssetName = prefs.getString(_keyLastBetaAssetName);
    _useUpdateMirror = prefs.getBool(_keyUseUpdateMirror) ?? false;
    _autoLogin = prefs.getBool(_keyAutoLogin) ?? false;
    _disclaimerAccepted = prefs.getBool(_keyDisclaimerAccepted) ?? false;
    _loginSource = prefs.getString(_keyLoginSource) ?? 'hotmanga';
    _apiRoute = prefs.getInt(_keyApiRoute) ?? 0;
    _networkProxyMode = _normalizeNetworkProxyMode(
      prefs.getInt(_keyNetworkProxyMode),
    );
    _networkProxyType = _normalizeNetworkProxyType(
      prefs.getInt(_keyNetworkProxyType),
    );
    _networkProxyHost = prefs.getString(_keyNetworkProxyHost)?.trim() ?? '';
    _networkProxyPort = _normalizeProxyPort(prefs.getInt(_keyNetworkProxyPort));
    _animeFeatureEnabled = prefs.getBool(_keyAnimeFeatureEnabled) ?? true;
    _remoteNoticeEnabled = prefs.getBool(_keyRemoteNoticeEnabled) ?? true;
    _locale = prefs.getString(_keyLocale) ?? '';
    _bannerVisible = prefs.getBool(_keyBannerVisible) ?? true;
    _mangaHomeSource = prefs.getString(_keyMangaHomeSource) ?? 'hot';
    _copyApiHost = normalizeCopyApiHost(prefs.getString(_keyCopyApiHost));
    _copyAppVersion = normalizeCopyAppVersion(
      prefs.getString(_keyCopyAppVersion),
    );
    _copyAutoUpdate = prefs.getBool(_keyCopyAutoUpdate) ?? true;
    _copySettingsUpdatedAt = prefs.getInt(_keyCopySettingsUpdatedAt);
    _copyHomeSectionCollapsed = _decodeBoolMap(
      prefs.getString(_keyCopyHomeSectionCollapsed),
    );
    _animeHomeBannerCollapsed =
        prefs.getBool(_keyAnimeHomeBannerCollapsed) ?? false;
    _animeSkipSeconds = prefs.getInt(_keyAnimeSkipSeconds) ?? 86;
    _animePlaybackProgressEnabled =
        prefs.getBool(_keyAnimePlaybackProgressEnabled) ?? true;
    _danmakuEnabled = prefs.getBool(_keyDanmakuEnabled) ?? true;
    _danmakuFontSize = prefs.getDouble(_keyDanmakuFontSize) ?? 16;
    _danmakuArea = prefs.getDouble(_keyDanmakuArea) ?? 0.25;
    _danmakuOpacity = prefs.getDouble(_keyDanmakuOpacity) ?? 1.0;
    _danmakuHideScroll = prefs.getBool(_keyDanmakuHideScroll) ?? false;
    _danmakuHideTop = prefs.getBool(_keyDanmakuHideTop) ?? false;
    _danmakuHideBottom = prefs.getBool(_keyDanmakuHideBottom) ?? false;
    _danmakuBlocklist = prefs.getStringList(_keyDanmakuBlocklist) ?? [];
    _danmakuFontFamily = prefs.getString(_keyDanmakuFontFamily) ?? '';
    _commentBlockedUsers = prefs.getStringList(_keyCommentBlockedUsers) ?? [];
    _commentBlockNoRemind = prefs.getBool(_keyCommentBlockNoRemind) ?? false;
    _logoIndex = (prefs.getInt(_keyLogoIndex) ?? 1).clamp(
      0,
      appLogoPaths.length - 1,
    );
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final platformIndex = await AppIconSwitcher.getAppIconIndex();
        _logoIndex = platformIndex.clamp(0, appLogoPaths.length - 1);
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
    await danmaku.initFromPrefs(prefs);
    await comment.initFromPrefs(prefs);
    await theme.initFromPrefs(prefs);
    await network.initFromPrefs(prefs);

    // Forward sub-store notifications so legacy listeners on UserManager
    // still rebuild when domain settings change.
    reader.addListener(_onSubStoreChanged);
    danmaku.addListener(_onSubStoreChanged);
    comment.addListener(_onSubStoreChanged);
    theme.addListener(_onSubStoreChanged);
    network.addListener(_onSubStoreChanged);

    notifyListeners();
  }

  void _onSubStoreChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    reader.removeListener(_onSubStoreChanged);
    danmaku.removeListener(_onSubStoreChanged);
    comment.removeListener(_onSubStoreChanged);
    theme.removeListener(_onSubStoreChanged);
    network.removeListener(_onSubStoreChanged);
    super.dispose();
  }

  Future<void> saveLogin({
    required String token,
    required String userId,
    required String username,
    required String nickname,
    required String avatar,
  }) async {
    _token = token;
    _userId = userId;
    _username = username;
    _nickname = nickname;
    _avatar = avatar;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToken, token);
    await prefs.setString(_keyUserId, userId);
    await prefs.setString(_keyUsername, username);
    await prefs.setString(_keyNickname, nickname);
    await prefs.setString(_keyAvatar, avatar);

    // 同步更新对应凭证的令牌和用户信息
    final idx = _savedCredentials.indexWhere((e) => e.username == username);
    if (idx >= 0) {
      _savedCredentials[idx] = _savedCredentials[idx].copyWith(
        token: token,
        loginSource: _loginSource,
        userId: userId,
        nickname: nickname,
        avatar: avatar,
      );
      await prefs.setString(
        _keySavedCredentials,
        jsonEncode(_savedCredentials.map((e) => e.toJson()).toList()),
      );
    }
    notifyListeners();
  }

  Future<void> logout() async {
    ApiClient().user.clearAuthState();
    _token = null;
    _userId = null;
    _username = null;
    _nickname = null;
    _avatar = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyToken);
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyUsername);
    await prefs.remove(_keyNickname);
    await prefs.remove(_keyAvatar);
    notifyListeners();
  }

  Future<void> saveCredentials(String username, String password) async {
    _savedUsername = username;
    _savedPassword = password;
    _savedCredentials.removeWhere((e) => e.username == username);
    _savedCredentials.insert(
      0,
      SavedCredential(username: username, password: password),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySavedUsername, username);
    await prefs.setString(_keySavedPassword, password);
    await prefs.setString(
      _keySavedCredentials,
      jsonEncode(_savedCredentials.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> clearCredentials() async {
    _savedUsername = null;
    _savedPassword = null;
    _savedCredentials = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySavedUsername);
    await prefs.remove(_keySavedPassword);
    await prefs.remove(_keySavedCredentials);
  }

  /// 直接切换到已保存的凭证（无需重新登录）
  Future<bool> switchToCredential(SavedCredential credential) async {
    if (credential.token == null || credential.token!.isEmpty) return false;

    _token = credential.token;
    _username = credential.username;
    _nickname = credential.nickname;
    _avatar = credential.avatar;
    _userId = credential.userId;
    if (credential.loginSource != null) {
      _loginSource = credential.loginSource!;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToken, _token!);
    if (_userId != null) await prefs.setString(_keyUserId, _userId!);
    if (_username != null) await prefs.setString(_keyUsername, _username!);
    if (_nickname != null) await prefs.setString(_keyNickname, _nickname!);
    if (_avatar != null) await prefs.setString(_keyAvatar, _avatar!);
    if (credential.loginSource != null) {
      await prefs.setString(_keyLoginSource, credential.loginSource!);
    }

    // 更新凭证顺序，将选中的凭证移到最前
    _savedCredentials.removeWhere((e) => e.username == credential.username);
    _savedCredentials.insert(0, credential);
    _savedUsername = credential.username;
    _savedPassword = credential.password;
    await prefs.setString(_keySavedUsername, credential.username);
    await prefs.setString(_keySavedPassword, credential.password);
    await prefs.setString(
      _keySavedCredentials,
      jsonEncode(_savedCredentials.map((e) => e.toJson()).toList()),
    );

    notifyListeners();

    // 后台刷新用户信息
    try {
      await refreshUserInfo();
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'user_manager.refresh_user_info',
        ),
      );
    }
    return true;
  }

  Future<void> removeSavedCredential(String username) async {
    _savedCredentials.removeWhere((e) => e.username == username);
    if (_savedUsername == username) {
      if (_savedCredentials.isNotEmpty) {
        _savedUsername = _savedCredentials.first.username;
        _savedPassword = _savedCredentials.first.password;
      } else {
        _savedUsername = null;
        _savedPassword = null;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    if (_savedUsername == null) {
      await prefs.remove(_keySavedUsername);
      await prefs.remove(_keySavedPassword);
    } else {
      await prefs.setString(_keySavedUsername, _savedUsername!);
      await prefs.setString(_keySavedPassword, _savedPassword ?? '');
    }
    await prefs.setString(
      _keySavedCredentials,
      jsonEncode(_savedCredentials.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyThemeMode, mode.index);
    notifyListeners();
  }

  Future<void> setThemeColor(String themeColor) async {
    final nextThemeColor = themeColor == customThemeOptionId
        ? customThemeOptionId
        : resolveAppThemeOption(themeColor).id;
    if (_themeColor == nextThemeColor) return;

    _themeColor = nextThemeColor;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeColor, nextThemeColor);
    notifyListeners();
  }

  Future<void> setThemeVariant(DynamicSchemeVariant variant) async {
    if (_themeVariant == variant) return;

    _themeVariant = variant;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeVariant, variant.name);
    notifyListeners();
  }

  Future<void> setCustomThemeColor(Color color) async {
    final nextColorValue = color.toARGB32();
    final shouldNotify =
        _customThemeColorValue != nextColorValue ||
        _themeColor != customThemeOptionId;

    _customThemeColorValue = nextColorValue;
    _themeColor = customThemeOptionId;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyCustomThemeColor, nextColorValue);
    await prefs.setString(_keyThemeColor, customThemeOptionId);

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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyDarkModeCoverBrightness, nextValue);
    }
    notifyListeners();
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
    notifyListeners();
  }

  Future<void> setNavOrder(List<String> order) async {
    _navOrder = _normalizeNavOrder(order);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyNavOrder, _navOrder);
    notifyListeners();
  }

  Future<void> setLastNavKey(String key) async {
    final nextKey = _normalizeNavKey(key);
    if (_lastNavKey == nextKey && key == nextKey) return;

    _lastNavKey = nextKey;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastNavKey, nextKey);
  }

  Future<void> setDesktopFontFamily(String fontFamily) async {
    if (_desktopFontFamily == fontFamily) return;
    _desktopFontFamily = fontFamily;
    final prefs = await SharedPreferences.getInstance();
    if (fontFamily.isEmpty) {
      await prefs.remove(_keyDesktopFontFamily);
    } else {
      await prefs.setString(_keyDesktopFontFamily, fontFamily);
    }
    notifyListeners();
  }

  Future<void> setDisplayModeRefreshRate(int refreshRate) async {
    final nextRate = _normalizeDisplayModeRefreshRate(refreshRate);
    if (_displayModeRefreshRate == nextRate) return;

    _displayModeRefreshRate = nextRate;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyDisplayModeRefreshRate, nextRate);
    notifyListeners();
  }

  Future<void> setBookshelfOrdering(String ordering) async {
    _bookshelfOrdering = ordering;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBookshelfOrdering, ordering);
    notifyListeners();
  }

  Future<void> setReaderMode(int mode) async {
    _readerMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyReaderMode, mode);
    notifyListeners();
  }

  Future<void> setReaderScrollDirection(int direction) async {
    _readerScrollDirection = direction;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyReaderScrollDirection, direction);
    notifyListeners();
  }

  Future<void> setReaderImageGap(double gap) async {
    _readerImageGap = gap;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyReaderImageGap, gap);
    notifyListeners();
  }

  Future<void> setReaderVolumeKey(bool enabled) async {
    _readerVolumeKey = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyReaderVolumeKey, enabled);
    notifyListeners();
  }

  Future<void> setReaderInstantPageTurn(bool enabled) async {
    _readerInstantPageTurn = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyReaderInstantPageTurn, enabled);
    notifyListeners();
  }

  Future<void> setReaderPageRTL(bool rtl) async {
    _readerPageRTL = rtl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyReaderPageRTL, rtl);
    notifyListeners();
  }

  Future<void> setReaderPageVertical(bool vertical) async {
    _readerPageVertical = vertical;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyReaderPageVertical, vertical);
    notifyListeners();
  }

  Future<void> setReaderDimming(double value) async {
    _readerDimming = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyReaderDimming, value);
    notifyListeners();
  }

  Future<void> setReaderAutoScrollEnabled(bool enabled) async {
    _readerAutoScrollEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyReaderAutoScrollEnabled, enabled);
    notifyListeners();
  }

  Future<void> setReaderAutoScrollPause(double seconds) async {
    _readerAutoScrollPause = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyReaderAutoScrollPause, seconds);
    notifyListeners();
  }

  Future<void> setReaderAutoScrollResume(bool enabled) async {
    _readerAutoScrollResume = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyReaderAutoScrollResume, enabled);
    notifyListeners();
  }

  Future<void> setReaderAutoScrollResumeDelay(double seconds) async {
    _readerAutoScrollResumeDelay = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyReaderAutoScrollResumeDelay, seconds);
    notifyListeners();
  }

  Future<void> setReaderAutoScrollDistance(double factor) async {
    _readerAutoScrollDistance = factor;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyReaderAutoScrollDistance, factor);
    notifyListeners();
  }

  Future<void> setReaderContinuousReading(bool enabled) async {
    _readerContinuousReading = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyReaderContinuousReading, enabled);
    notifyListeners();
  }

  Future<void> setImageViewerAutoRotateLandscape(bool enabled) async {
    if (_imageViewerAutoRotateLandscape == enabled) return;
    _imageViewerAutoRotateLandscape = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyImageViewerAutoRotateLandscape, enabled);
    notifyListeners();
  }

  Future<void> setImageViewerLandscapeRotation(int rotation) async {
    final nextRotation = rotation < 0 ? -1 : 1;
    if (_imageViewerLandscapeRotation == nextRotation) return;
    _imageViewerLandscapeRotation = nextRotation;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyImageViewerLandscapeRotation, nextRotation);
    notifyListeners();
  }

  Future<void> setImageLoadTimeout(int seconds) async {
    _imageLoadTimeout = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyImageLoadTimeout, seconds);
    notifyListeners();
  }

  Future<void> setImageRetryCount(int count) async {
    _imageRetryCount = count;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyImageRetryCount, count);
    notifyListeners();
  }

  Future<void> setCommentCompactLayout(bool compact) async {
    _commentCompactLayout = compact;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCommentCompactLayout, compact);
    notifyListeners();
  }

  Future<void> setCommentShowAvatar(bool enabled) async {
    _commentShowAvatar = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCommentShowAvatar, enabled);
    notifyListeners();
  }

  Future<void> setCommentShowUserName(bool enabled) async {
    _commentShowUserName = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCommentShowUserName, enabled);
    notifyListeners();
  }

  Future<void> setCommentShowTime(bool enabled) async {
    _commentShowTime = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCommentShowTime, enabled);
    notifyListeners();
  }

  Future<void> setCommentFontScale(double scale) async {
    _commentFontScale = scale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyCommentFontScale, scale);
    notifyListeners();
  }

  Future<void> setCommentPreload(bool enabled) async {
    _commentPreload = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCommentPreload, enabled);
    notifyListeners();
  }

  Future<void> setCommentAutoLoadAll(bool enabled) async {
    _commentAutoLoadAll = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCommentAutoLoadAll, enabled);
    notifyListeners();
  }

  Future<void> setAutoCheckUpdate(bool enabled) async {
    _autoCheckUpdate = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoCheckUpdate, enabled);
    notifyListeners();
  }

  Future<void> setSkippedUpdateVersion(String? version) async {
    _skippedUpdateVersion = version;
    final prefs = await SharedPreferences.getInstance();
    if (version == null || version.isEmpty) {
      await prefs.remove(_keySkippedUpdateVersion);
    } else {
      await prefs.setString(_keySkippedUpdateVersion, version);
    }
    notifyListeners();
  }

  Future<void> setUpdateMirrorPrefix(String value) async {
    final normalized = normalizeUpdateMirrorPrefix(value);
    if (_updateMirrorPrefix == normalized) return;

    _updateMirrorPrefix = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUpdateMirrorPrefix, normalized);
    notifyListeners();
  }

  Future<void> setUpdateChannel(String value) async {
    final next = value == 'beta' ? 'beta' : 'stable';
    if (_updateChannel == next) return;
    _updateChannel = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUpdateChannel, next);
    notifyListeners();
  }

  Future<void> setLastBetaAssetName(String? name) async {
    if (_lastBetaAssetName == name) return;
    _lastBetaAssetName = name;
    final prefs = await SharedPreferences.getInstance();
    if (name == null || name.isEmpty) {
      await prefs.remove(_keyLastBetaAssetName);
    } else {
      await prefs.setString(_keyLastBetaAssetName, name);
    }
    notifyListeners();
  }

  Future<void> setUseUpdateMirror(bool value) async {
    if (_useUpdateMirror == value) return;
    _useUpdateMirror = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyUseUpdateMirror, value);
    notifyListeners();
  }

  Future<void> setAutoLogin(bool enabled) async {
    _autoLogin = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoLogin, enabled);
    notifyListeners();
  }

  Future<void> setDisclaimerAccepted(bool accepted) async {
    _disclaimerAccepted = accepted;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDisclaimerAccepted, accepted);
    notifyListeners();
  }

  Future<void> setLoginSource(String source) async {
    _loginSource = source;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLoginSource, source);
  }

  Future<void> setApiRoute(int route) async {
    _apiRoute = route;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyApiRoute, route);
    notifyListeners();
  }

  Future<void> setNetworkSelectionMode(NetworkSelectionMode mode) async {
    await network.setSelectionMode(mode);
    notifyListeners();
  }

  Future<void> setFixedNodeHost(String? host) async {
    await network.setFixedNodeHost(host);
    notifyListeners();
  }

  Future<void> setNetworkProxyMode(NetworkProxyMode mode) async {
    if (_networkProxyMode == mode) return;

    _networkProxyMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyNetworkProxyMode, mode.index);
    notifyListeners();
  }

  Future<void> setManualProxy({
    required String host,
    required int port,
    required NetworkProxyType type,
    bool enable = true,
  }) async {
    final nextHost = host.trim();
    final nextPort = _normalizeProxyPort(port);
    if (nextHost.isEmpty || nextPort == 0) return;

    final shouldNotify =
        _networkProxyHost != nextHost ||
        _networkProxyPort != nextPort ||
        _networkProxyType != type ||
        (enable && _networkProxyMode != NetworkProxyMode.manual);

    _networkProxyHost = nextHost;
    _networkProxyPort = nextPort;
    _networkProxyType = type;
    if (enable) {
      _networkProxyMode = NetworkProxyMode.manual;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyNetworkProxyHost, nextHost);
    await prefs.setInt(_keyNetworkProxyPort, nextPort);
    await prefs.setInt(_keyNetworkProxyType, type.index);
    if (enable) {
      await prefs.setInt(_keyNetworkProxyMode, NetworkProxyMode.manual.index);
    }

    if (shouldNotify) notifyListeners();
  }

  Future<void> setAnimeFeatureEnabled(bool enabled) async {
    if (_animeFeatureEnabled == enabled) return;
    _animeFeatureEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAnimeFeatureEnabled, enabled);
    notifyListeners();
  }

  Future<void> setRemoteNoticeEnabled(bool enabled) async {
    if (_remoteNoticeEnabled == enabled) return;
    _remoteNoticeEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyRemoteNoticeEnabled, enabled);
    notifyListeners();
  }

  Future<void> setLocale(String locale) async {
    if (_locale == locale) return;
    _locale = locale;
    final prefs = await SharedPreferences.getInstance();
    if (locale.isEmpty) {
      await prefs.remove(_keyLocale);
    } else {
      await prefs.setString(_keyLocale, locale);
    }
    notifyListeners();
  }

  Future<void> setBannerVisible(bool visible) async {
    if (_bannerVisible == visible) return;
    _bannerVisible = visible;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBannerVisible, visible);
    notifyListeners();
  }

  Future<void> setMangaHomeSource(String source) async {
    if (_mangaHomeSource == source) return;
    _mangaHomeSource = source;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMangaHomeSource, source);
    notifyListeners();
  }

  Future<void> setCopyApiHost(String value) async {
    final normalized = normalizeCopyApiHost(value);
    if (_copyApiHost == normalized) return;

    _copyApiHost = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCopyApiHost, normalized);
    notifyListeners();
  }

  Future<void> setCopyAppVersion(String value) async {
    final normalized = normalizeCopyAppVersion(value);
    if (_copyAppVersion == normalized) return;

    _copyAppVersion = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCopyAppVersion, normalized);
    notifyListeners();
  }

  Future<void> setCopyAutoUpdate(bool enabled) async {
    if (_copyAutoUpdate == enabled) return;
    _copyAutoUpdate = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCopyAutoUpdate, enabled);
    notifyListeners();
  }

  /// 记录「本次启动已尝试自动更新 COPY 高级设置」，内部调用。
  Future<void> markCopySettingsUpdated() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    _copySettingsUpdatedAt = now;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyCopySettingsUpdatedAt, now);
    notifyListeners();
  }

  Future<void> setCopyHomeSectionCollapsed(String key, bool collapsed) async {
    if (_copyHomeSectionCollapsed[key] == collapsed) return;
    _copyHomeSectionCollapsed = {..._copyHomeSectionCollapsed, key: collapsed};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyCopyHomeSectionCollapsed,
      jsonEncode(_copyHomeSectionCollapsed),
    );
  }

  Future<void> setAnimeHomeBannerCollapsed(bool collapsed) async {
    if (_animeHomeBannerCollapsed == collapsed) return;
    _animeHomeBannerCollapsed = collapsed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAnimeHomeBannerCollapsed, collapsed);
    notifyListeners();
  }

  Future<void> setAnimeSkipSeconds(int seconds) async {
    if (_animeSkipSeconds == seconds) return;
    _animeSkipSeconds = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyAnimeSkipSeconds, seconds);
    notifyListeners();
  }

  Future<void> setAnimePlaybackProgressEnabled(bool enabled) async {
    if (_animePlaybackProgressEnabled == enabled) return;
    _animePlaybackProgressEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAnimePlaybackProgressEnabled, enabled);
    notifyListeners();
  }

  Future<void> setDanmakuEnabled(bool value) async {
    if (_danmakuEnabled == value) return;
    _danmakuEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDanmakuEnabled, value);
    notifyListeners();
  }

  Future<void> setDanmakuFontSize(double value) async {
    if (_danmakuFontSize == value) return;
    _danmakuFontSize = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyDanmakuFontSize, value);
    notifyListeners();
  }

  Future<void> setDanmakuArea(double value) async {
    if (_danmakuArea == value) return;
    _danmakuArea = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyDanmakuArea, value);
    notifyListeners();
  }

  Future<void> setDanmakuOpacity(double value) async {
    if (_danmakuOpacity == value) return;
    _danmakuOpacity = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyDanmakuOpacity, value);
    notifyListeners();
  }

  Future<void> setDanmakuHideScroll(bool value) async {
    if (_danmakuHideScroll == value) return;
    _danmakuHideScroll = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDanmakuHideScroll, value);
    notifyListeners();
  }

  Future<void> setDanmakuHideTop(bool value) async {
    if (_danmakuHideTop == value) return;
    _danmakuHideTop = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDanmakuHideTop, value);
    notifyListeners();
  }

  Future<void> setDanmakuHideBottom(bool value) async {
    if (_danmakuHideBottom == value) return;
    _danmakuHideBottom = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDanmakuHideBottom, value);
    notifyListeners();
  }

  Future<void> setDanmakuBlocklist(List<String> list) async {
    _danmakuBlocklist = List.from(list);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyDanmakuBlocklist, list);
    notifyListeners();
  }

  Future<void> setDanmakuFontFamily(String value) async {
    if (_danmakuFontFamily == value) return;
    _danmakuFontFamily = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDanmakuFontFamily, value);
    notifyListeners();
  }

  /// `entry` 格式：`userId|userName`（userId 可为空字符串，userName 作为兜底标识）。
  bool isCommentUserBlocked(String userId, String userName) {
    if (userId.isEmpty && userName.isEmpty) return false;
    for (final raw in _commentBlockedUsers) {
      final sep = raw.indexOf('|');
      if (sep < 0) {
        if (userId.isNotEmpty && raw == userId) return true;
        continue;
      }
      final bId = raw.substring(0, sep);
      final bName = raw.substring(sep + 1);
      if (userId.isNotEmpty && bId == userId) return true;
      if (userId.isEmpty && userName.isNotEmpty && bName == userName) {
        return true;
      }
    }
    return false;
  }

  Future<void> blockCommentUser(String userId, String userName) async {
    final key = '$userId|$userName';
    if (_commentBlockedUsers.any((e) => e == key)) return;
    _commentBlockedUsers = [..._commentBlockedUsers, key];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyCommentBlockedUsers, _commentBlockedUsers);
    notifyListeners();
  }

  Future<void> unblockCommentUser(String rawKey) async {
    _commentBlockedUsers = _commentBlockedUsers
        .where((e) => e != rawKey)
        .toList(growable: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyCommentBlockedUsers, _commentBlockedUsers);
    notifyListeners();
  }

  Future<void> clearCommentBlockedUsers() async {
    _commentBlockedUsers = const [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCommentBlockedUsers);
    notifyListeners();
  }

  Future<void> setCommentBlockNoRemind(bool value) async {
    _commentBlockNoRemind = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCommentBlockNoRemind, value);
    notifyListeners();
  }

  Future<void> setLogoIndex(int index) async {
    final next = index.clamp(0, appLogoPaths.length - 1);
    if (_logoIndex == next) return;
    _logoIndex = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLogoIndex, next);
    notifyListeners();
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

  Future<void> refreshUserInfo() async {
    if (!isLoggedIn) return;
    final info = await ApiClient().user.getUserInfo();
    await saveLogin(
      token: _token!,
      userId: info['user_id']?.toString() ?? _userId ?? '',
      username: info['username']?.toString() ?? _username ?? '',
      nickname: info['nickname']?.toString() ?? _nickname ?? '',
      avatar: info['avatar']?.toString() ?? _avatar ?? '',
    );
  }

  static double _normalizeDarkModeCoverBrightness(double value) {
    return value
        .clamp(minDarkModeCoverBrightness, maxDarkModeCoverBrightness)
        .toDouble();
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

  static NetworkProxyMode _normalizeNetworkProxyMode(int? index) {
    if (index == null || index < 0 || index >= NetworkProxyMode.values.length) {
      return NetworkProxyMode.system;
    }
    return NetworkProxyMode.values[index];
  }

  static NetworkProxyType _normalizeNetworkProxyType(int? index) {
    if (index == null || index < 0 || index >= NetworkProxyType.values.length) {
      return NetworkProxyType.http;
    }
    return NetworkProxyType.values[index];
  }

  static int _normalizeProxyPort(int? port) {
    return isValidProxyPort(port) ? port! : 0;
  }

  static int _normalizeDisplayModeRefreshRate(int? refreshRate) {
    if (refreshRate == null || refreshRate < 0) {
      return defaultDisplayModeRefreshRate;
    }
    return refreshRate;
  }
}
