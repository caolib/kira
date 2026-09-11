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
import 'network_proxy_types.dart';
import 'network_settings.dart';
import 'reader_settings.dart';
import 'theme_settings.dart';

export 'network_proxy_types.dart';
export 'network_settings.dart' show NetworkSelectionMode;
export 'theme_settings.dart' show BottomNavLabelMode;

part 'user_manager_parts/app_settings.dart';
part 'user_manager_parts/comment.dart';
part 'user_manager_parts/init.dart';
part 'user_manager_parts/reader.dart';
part 'user_manager_parts/theme_nav.dart';

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
  // need reader / comment / theme / network settings should
  // import the specific store directly and skip the facade entirely.

  final reader = ReaderSettings();
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
  static const _keyReaderHorizontalImageScale = 'reader_horizontal_image_scale';
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
  static const _keyRemoteNoticeEnabled = 'remote_notice_enabled';
  static const _keyLocale = 'locale';
  static const _keyBannerVisible = 'banner_visible';
  static const _keyMangaHomeSource = 'manga_home_source';
  static const _keyCopyApiHost = 'copy_api_host';
  static const _keyCopyLoginHost = 'copy_login_host';
  static const _keyCustomCopyLoginHosts = 'copy_login_custom_hosts';
  static const _keyCopyAppVersion = 'copy_app_version';
  static const _keyCopyAutoUpdate = 'copy_auto_update';
  static const _keyCopySettingsUpdatedAt = 'copy_settings_updated_at';
  static const _keyCopyHomeSectionCollapsed = 'copy_home_section_collapsed';
  static const _keyCommentBlockedUsers = 'comment_blocked_users';
  static const _keyCommentBlockNoRemind = 'comment_block_no_remind';
  static const _keyCommentBlockwords = 'comment_blockwords';
  static const _keyCommentBlockGroupSpam = 'comment_block_group_spam';
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
  // 横向滚动模式下图片相对视口高度的缩放档位，1.0 = 填满高度。
  double _readerHorizontalImageScale = 1.0;
  bool _imageViewerAutoRotateLandscape = false;
  int _imageViewerLandscapeRotation = 1;
  int _imageLoadTimeout = 15; // 秒
  int _imageRetryCount = 1;
  bool _commentCompactLayout = true;
  bool _commentShowAvatar = true;
  bool _commentShowUserName = true;
  bool _commentShowTime = true;
  bool _commentPreload = true;
  bool _commentAutoLoadAll = false;
  bool _autoCheckUpdate = true;
  String? _skippedUpdateVersion;
  String _updateMirrorPrefix = defaultUpdateMirrorPrefix;
  String _updateChannel = 'stable'; // stable | beta
  String? _lastBetaAssetName;
  bool _useUpdateMirror = true;
  bool _autoLogin = false;
  bool _disclaimerAccepted = false;
  String _loginSource = 'hotmanga';
  int _apiRoute = 0; // 0=线路1(默认), 1=线路2
  bool _remoteNoticeEnabled = true;

  /// '' = follow system, 'zh' = Simplified, 'zh-Hant' = Traditional.
  String _locale = '';
  bool _bannerVisible = true;
  String _mangaHomeSource = 'hot';
  String _copyApiHost = defaultCopyApiHost;
  String _copyLoginHost = defaultCopyLoginHost;

  /// 用户自定义的拷贝登录域名（内置 [copyLoginHostOptions] 之外）。
  List<String> _customCopyLoginHosts = [];
  String _copyAppVersion = defaultCopyAppVersion;
  bool _copyAutoUpdate = true;
  int? _copySettingsUpdatedAt;
  Map<String, bool> _copyHomeSectionCollapsed = {};

  /// 评论屏蔽用户黑名单，元素为 `userId|userName` 形式
  List<String> _commentBlockedUsers = [];
  bool _commentBlockNoRemind = false;

  /// 评论屏蔽词列表，评论内容包含任一屏蔽词即被过滤
  List<String> _commentBlockwords = [];

  /// 群广告屏蔽预设：同时包含「群」与 8~12 位数字的评论将被过滤。默认关闭。
  bool _commentBlockGroupSpam = false;
  int _logoIndex = 1;

  /// extension part 文件里的成员不是 UserManager 自身的成员，不能直接调用受
  /// 保护的 [notifyListeners]，统一经由这个转发方法。
  void _notifyListeners() => notifyListeners();

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

  /// 委托给 [reader]：两边曾各自缓存 'reader_mode'，
  /// 经此处修改不会同步到子 store，反之亦然。
  int get readerMode => reader.mode;
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
  double get readerHorizontalImageScale => _readerHorizontalImageScale;
  bool get imageViewerAutoRotateLandscape => _imageViewerAutoRotateLandscape;
  int get imageViewerLandscapeRotation => _imageViewerLandscapeRotation;
  int get imageLoadTimeout => _imageLoadTimeout;
  int get imageRetryCount => _imageRetryCount;
  bool get commentCompactLayout => _commentCompactLayout;
  bool get commentShowAvatar => _commentShowAvatar;
  bool get commentShowUserName => _commentShowUserName;
  bool get commentShowTime => _commentShowTime;

  /// 委托给 [comment]。子 store 的 notifyListeners 会经
  /// _onSubStoreChanged 转发到本 facade 的监听者。
  double get commentFontScale => comment.fontScale;
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
  NetworkProxyMode get networkProxyMode => network.proxyMode;
  NetworkProxyType get networkProxyType => network.proxyType;
  String get networkProxyHost => network.proxyHost;
  int get networkProxyPort => network.proxyPort;
  bool get hasManualProxy => network.hasManualProxy;
  bool get remoteNoticeEnabled => _remoteNoticeEnabled;

  /// '' = follow system, 'zh' = 简体中文, 'zh-Hant' = 繁體中文
  String get locale => _locale;
  bool get bannerVisible => _bannerVisible;
  String get mangaHomeSource => _mangaHomeSource;
  String get copyApiHost => _copyApiHost;
  String get copyLoginHost => _copyLoginHost;
  List<String> get customCopyLoginHosts =>
      List.unmodifiable(_customCopyLoginHosts);

  /// 高级设置中可选的全部登录域名：内置 + 自定义，去重保序。
  List<String> get copyLoginHostChoices => List.unmodifiable([
    ...copyLoginHostOptions,
    ..._customCopyLoginHosts.where((h) => !copyLoginHostOptions.contains(h)),
  ]);
  String get copyAppVersion => _copyAppVersion;
  bool get copyAutoUpdate => _copyAutoUpdate;
  int? get copySettingsUpdatedAt => _copySettingsUpdatedAt;
  bool isCopyHomeSectionCollapsed(String key) =>
      _copyHomeSectionCollapsed[key] ?? false;
  List<String> get commentBlockedUsers =>
      List.unmodifiable(_commentBlockedUsers);
  bool get commentBlockNoRemind => _commentBlockNoRemind;
  List<String> get commentBlockwords => List.unmodifiable(_commentBlockwords);
  bool get commentBlockGroupSpam => _commentBlockGroupSpam;
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

  static String normalizeCopyApiHost(String? value) =>
      _normalizeHost(value, defaultCopyApiHost);

  /// 登录域名不做合法性校验（填什么由用户自己负责），仅去两端空白；
  /// 空值回落内置默认。
  static String normalizeCopyLoginHost(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? defaultCopyLoginHost : trimmed;
  }

  static String _normalizeHost(String? value, String fallback) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return fallback;

    final rawUri = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(rawUri);
    if (uri == null || uri.host.isEmpty) return fallback;

    final host = uri.host.trim().toLowerCase();
    if (host.isEmpty || host.contains(' ')) return fallback;

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

  void _onSubStoreChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    reader.removeListener(_onSubStoreChanged);
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

  Future<void> setLoginSource(String source) async {
    _loginSource = source;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLoginSource, source);
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

  static int _normalizeDisplayModeRefreshRate(int? refreshRate) {
    if (refreshRate == null || refreshRate < 0) {
      return defaultDisplayModeRefreshRate;
    }
    return refreshRate;
  }
}
