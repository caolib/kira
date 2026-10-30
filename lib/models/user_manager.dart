import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/api_transport.dart';
import '../api/user/user_api.dart';
import '../utils/app_logger.dart';
import '../utils/copy_web_login.dart' show CopyWebLoginForm, canApplyLoginForm;
import 'account_identity.dart';
import 'api_ordering.dart';
import 'app_theme_option.dart';
import 'comment_settings.dart';
import 'copy_account_store.dart';
import 'network_proxy_types.dart';
import 'network_settings.dart';
import 'novel_reader_status_settings.dart';
import 'reader_settings.dart';
import 'secure_credential_store.dart';
import 'theme_settings.dart';

export 'network_proxy_types.dart';
export 'network_settings.dart' show NetworkSelectionMode;
export 'theme_settings.dart' show BottomNavLabelMode;

part 'user_manager_parts/account_reconciliation.dart';
part 'user_manager_parts/app_settings.dart';
part 'user_manager_parts/comment.dart';
part 'user_manager_parts/credentials.dart';
part 'user_manager_parts/init.dart';
part 'user_manager_parts/reader.dart';
part 'user_manager_parts/theme_nav.dart';

class UserManager extends ChangeNotifier {
  static final UserManager _instance = UserManager._();
  factory UserManager() => _instance;
  UserManager._();

  // ── Domain-specific sub-stores ─────────────────────────────────────
  // Each store is an independent ChangeNotifier.  Callers that only
  // need reader / comment / theme / network settings should
  // import the specific store directly and skip the facade entirely.

  final reader = ReaderSettings();
  final novelStatus = NovelReaderStatusSettings();
  final comment = CommentSettings();
  final theme = ThemeSettings();
  final network = NetworkSettings();
  final CopyAccountStore _copyAccount = CopyAccountStore();

  CopyAccountStore get copyAccount => _copyAccount;
  String? get copyToken => copyAccount.token;
  bool get isCopyLoggedIn => copyAccount.isLoggedIn;

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

  /// GitHub 下载镜像默认前缀，也用于提示条等处的「默认值」语义。
  static const defaultUpdateMirrorPrefix = 'https://gh-proxy.org/';

  /// 镜像源下拉里内置的可选项，第一项即默认；其余为备选。
  static const updateMirrorPrefixOptions = <String>[
    defaultUpdateMirrorPrefix,
    'https://ghproxy.net/',
  ];

  /// 应用内下载的镜像兜底顺序：选中的镜像优先，内置与自定义镜像依次尝试。
  /// 选中的值不在列表里（如备份恢复的旧值）时也排在最前。
  static List<String> updateMirrorFallbackChain(
    String selected, [
    List<String> custom = const [],
  ]) {
    final first = normalizeUpdateMirrorPrefix(selected);
    final chain = <String>[first];
    for (final option in [...updateMirrorPrefixOptions, ...custom]) {
      final normalized = normalizeUpdateMirrorPrefix(option);
      if (!chain.contains(normalized)) chain.add(normalized);
    }
    return chain;
  }

  static const appLogoPaths = ThemeSettings.appLogoPaths;

  static const _keyToken = 'user_token';
  static const _keyUsername = 'user_username';
  static const _keyNickname = 'user_nickname';
  static const _keyAvatar = 'user_avatar';
  static const _keyUserId = 'user_id';
  static const _keyAccountId = 'user_account_id';
  static const _keySavedUsername = 'saved_username';
  static const _keySavedPassword = 'saved_password';
  static const _keySavedCredentials = 'saved_credentials';
  static const _keyDesktopFontFamily = 'desktop_font_family';
  static const _keyBookshelfOrdering = 'bookshelf_ordering';
  static const _keyReaderHorizontalImageScale = 'reader_horizontal_image_scale';
  static const _keyAutoCheckUpdate = 'auto_check_update';
  static const _keySkippedUpdateVersion = 'skipped_update_version';
  static const _keyUpdateMirrorPrefix = 'update_mirror_prefix';
  static const _keyUpdateMirrorCustomPrefixes = 'update_mirror_custom_prefixes';
  static const _keyUpdateChannel = 'update_channel'; // stable | beta
  static const _keyUseUpdateMirror = 'use_update_mirror';
  static const _keyDisclaimerAccepted = 'disclaimer_accepted';
  static const _keyLoginSource = 'login_source';
  static const _keyRemoteNoticeEnabled = 'remote_notice_enabled';
  static const _keyLocale = 'locale';
  static const _keyMangaHomeSource = 'manga_home_source';
  static const _keyDiscoverSource = 'discover_source';
  static const _keySearchTabIndex = 'search_tab_index';
  static const _keyCopyApiHost = 'copy_api_host';
  static const _keyCopyLoginHost = 'copy_login_host';
  static const _keyCustomCopyLoginHosts = 'copy_login_custom_hosts';
  static const _keyCopyAppVersion = 'copy_app_version';
  static const _keyCopyVersionCode = 'copy_version_code';
  static const _keyCopyAutoUpdate = 'copy_auto_update';
  static const _keyCopySettingsUpdatedAt = 'copy_settings_updated_at';
  static const _keyCopyHomeSectionCollapsed = 'copy_home_section_collapsed';
  static const _keyCommentBlockedUsers = 'comment_blocked_users';
  static const _keyCommentBlockNoRemind = 'comment_block_no_remind';
  static const _keyCommentBlockwords = 'comment_blockwords';
  static const _keyCommentBlockGroupSpam = 'comment_block_group_spam';

  String? _token;
  String? _username;
  String? _nickname;
  String? _avatar;
  String? _userId;
  String? _accountId;
  String? _savedUsername;
  String? _savedPassword;
  List<SavedCredential> _savedCredentials = [];

  /// Free-form note attached to the COPY account the next login creates
  /// (「这是谁的账号」). Not a credential: safe to persist in the record.
  String _copyAccountLabel = '';
  String _desktopFontFamily = '';
  String _bookshelfOrdering = ApiOrdering.datetimeUpdated;
  // 横向滚动模式下图片相对视口高度的缩放档位，1.0 = 填满高度。
  double _readerHorizontalImageScale = 1.0;
  bool _autoCheckUpdate = true;
  String? _skippedUpdateVersion;
  String _updateMirrorPrefix = defaultUpdateMirrorPrefix;

  /// 用户自定义的更新镜像源（内置 [updateMirrorPrefixOptions] 之外）。
  List<String> _customUpdateMirrorPrefixes = [];
  String _updateChannel = 'stable'; // stable | beta
  bool _useUpdateMirror = true;
  bool _disclaimerAccepted = false;
  String _loginSource = 'hotmanga';
  bool _remoteNoticeEnabled = true;

  /// '' = follow system, 'zh' = Simplified, 'zh-Hant' = Traditional.
  String _locale = '';
  String _mangaHomeSource = 'hot';

  /// 「发现」页自己的数据源，与首页互不影响。
  String _discoverSource = 'hot';

  /// 搜索页当前标签：0 = 搜索，1 = 发现。与 [lastNavKey] 同理，冷启动恢复。
  int _searchTabIndex = 0;
  String _copyApiHost = defaultCopyApiHost;
  String _copyLoginHost = defaultCopyLoginHost;

  /// 用户自定义的拷贝登录域名（内置 [copyLoginHostOptions] 之外）。
  List<String> _customCopyLoginHosts = [];
  String _copyAppVersion = defaultCopyAppVersion;
  String _copyVersionCode = defaultCopyVersionCode;
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
  ThemeMode get themeMode => theme.themeMode;
  String get themeColor => theme.themeColor;
  DynamicSchemeVariant get themeVariant => theme.themeVariant;
  Color get customThemeColor => theme.customThemeColor;
  double get darkModeCoverBrightness => theme.darkModeCoverBrightness;
  BottomNavLabelMode get bottomNavLabelMode => theme.bottomNavLabelMode;

  /// Compatibility: true when labels are not fully hidden.
  bool get bottomNavShowLabels => theme.bottomNavShowLabels;
  List<String> get navOrder => theme.navOrder;
  bool get showNovel => theme.showNovel;
  String get lastNavKey => theme.lastNavKey;
  String get desktopFontFamily => _desktopFontFamily;
  int get displayModeRefreshRate => theme.displayModeRefreshRate;
  AppThemeOption get themeOption => theme.themeOption;
  AppThemeVariantOption get themeVariantOption => theme.themeVariantOption;

  String get bookshelfOrdering => _bookshelfOrdering;

  /// 共有的阅读器设置由 [reader] 保存，横向图片缩放仍由 facade 独占。
  int get readerMode => reader.mode;
  int get readerScrollDirection => reader.scrollDirection;
  double get readerImageGap => reader.imageGap;
  bool get readerVolumeKey => reader.volumeKey;
  bool get readerInstantPageTurn => reader.instantPageTurn;
  bool get readerPageRTL => reader.pageRTL;
  bool get readerPageVertical => reader.pageVertical;
  double get readerDimming => reader.dimming;
  bool get readerAutoScrollEnabled => reader.autoScrollEnabled;
  double get readerAutoScrollPause => reader.autoScrollPause;
  bool get readerAutoScrollResume => reader.autoScrollResume;
  double get readerAutoScrollResumeDelay => reader.autoScrollResumeDelay;
  double get readerAutoScrollDistance => reader.autoScrollDistance;
  bool get readerContinuousReading => reader.continuousReading;
  double get readerHorizontalImageScale => _readerHorizontalImageScale;
  bool get imageViewerAutoRotateLandscape => reader.viewerAutoRotateLandscape;
  int get imageViewerLandscapeRotation => reader.viewerLandscapeRotation;
  int get imageLoadTimeout => reader.imageLoadTimeout;
  int get imageRetryCount => reader.imageRetryCount;
  bool get commentCompactLayout => comment.compactLayout;
  bool get commentShowAvatar => comment.showAvatar;
  bool get commentShowUserName => comment.showUserName;
  bool get commentShowTime => comment.showTime;

  /// 委托给 [comment]。子 store 的 notifyListeners 会经
  /// _onSubStoreChanged 转发到本 facade 的监听者。
  double get commentFontScale => comment.fontScale;
  bool get commentPreload => comment.preload;
  int get commentInitialPages => comment.initialPages;
  bool get autoCheckUpdate => _autoCheckUpdate;
  String? get skippedUpdateVersion => _skippedUpdateVersion;
  String get updateMirrorPrefix => _updateMirrorPrefix;

  /// 用户自定义的更新镜像源（内置 [updateMirrorPrefixOptions] 之外）。
  List<String> get customUpdateMirrorPrefixes =>
      List.unmodifiable(_customUpdateMirrorPrefixes);
  String get updateChannel => _updateChannel;
  bool get isBetaUpdateChannel => _updateChannel == 'beta';
  bool get useUpdateMirror => _useUpdateMirror;
  bool get disclaimerAccepted => _disclaimerAccepted;
  String get loginSource => _loginSource;
  int get apiRoute => network.apiRoute;
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
  bool get bannerVisible => theme.bannerVisible;
  String get mangaHomeSource => _mangaHomeSource;

  /// 「发现」页当前数据源，独立于 [mangaHomeSource]。
  String get discoverSource => _discoverSource;

  /// 搜索页上次停留的标签（0 = 搜索，1 = 发现）。
  int get searchTabIndex => _searchTabIndex;
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
  String get copyVersionCode => _copyVersionCode;
  bool get copyAutoUpdate => _copyAutoUpdate;
  int? get copySettingsUpdatedAt => _copySettingsUpdatedAt;
  bool isCopyHomeSectionCollapsed(String key) =>
      _copyHomeSectionCollapsed[key] ?? false;
  List<String> get commentBlockedUsers =>
      List.unmodifiable(_commentBlockedUsers);
  bool get commentBlockNoRemind => _commentBlockNoRemind;
  List<String> get commentBlockwords => List.unmodifiable(_commentBlockwords);
  bool get commentBlockGroupSpam => _commentBlockGroupSpam;

  // ── 屏蔽判定与屏蔽用户写入 ────────────────────────────────────────────
  // 这几个成员留在类体（而非 UserManagerCommentPart 扩展）是因为扩展成员
  // 静态解析、无法被测试假体覆写；各评论区对其有真实的多态需求。

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
    await prefs.setStringList(
      UserManager._keyCommentBlockedUsers,
      _commentBlockedUsers,
    );
    _notifyListeners();
  }

  /// 评论内容是否命中任一屏蔽词（大小写不敏感）。
  bool isCommentBlockedByWord(String content) {
    if (_commentBlockwords.isEmpty || content.isEmpty) return false;
    final lower = content.toLowerCase();
    for (final word in _commentBlockwords) {
      if (word.isEmpty) continue;
      if (lower.contains(word.toLowerCase())) return true;
    }
    return false;
  }

  /// 群广告预设正则：内容含「群」且含 8~12 位连续数字。
  static final _groupSpamRegex = RegExp(r'\d{8,12}');

  bool isCommentGroupSpam(String content) {
    if (!_commentBlockGroupSpam || content.isEmpty) return false;
    if (!content.contains('群')) return false;
    return _groupSpamRegex.hasMatch(content);
  }

  Future<void> setCommentBlockNoRemind(bool value) async {
    _commentBlockNoRemind = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(UserManager._keyCommentBlockNoRemind, value);
    _notifyListeners();
  }

  int get logoIndex => theme.logoIndex;
  String get appLogoPath => appLogoPaths[theme.logoIndex];
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

  /// versioncode 只允许数字(服务端收到非数字会直接判无效);空值回落默认。
  static String normalizeCopyVersionCode(String? value) {
    final digits = (value ?? '').trim().replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty ? defaultCopyVersionCode : digits;
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

  int _suppressCopyAccountNotification = 0;
  bool _copyNotificationSuppressed = false;

  void _onCopyAccountChanged() {
    if (_suppressCopyAccountNotification > 0) {
      // A COPY change (e.g. the user picking another novel account) can land
      // while a login transaction is mid-flight. It must still reach facade
      // listeners even if that transaction later rolls back and publishes
      // nothing of its own.
      _copyNotificationSuppressed = true;
      return;
    }
    notifyListeners();
  }

  void _beginCopyAccountSuppression() => _suppressCopyAccountNotification++;

  /// Releases one suppression level, forwarding a COPY change that was
  /// swallowed while a transaction held the flag. Nested transactions release
  /// their own level; only the outermost one can actually notify.
  void _endCopyAccountSuppression() {
    if (_suppressCopyAccountNotification > 0) {
      _suppressCopyAccountNotification--;
    }
    if (_suppressCopyAccountNotification > 0) return;
    final pending = _copyNotificationSuppressed;
    _copyNotificationSuppressed = false;
    if (pending) notifyListeners();
  }

  /// Publishes a committed transaction while suppression is active. The state
  /// is already consistent, so releasing the flag later must not notify again.
  void _notifySuppressedCommit() {
    _copyNotificationSuppressed = false;
    notifyListeners();
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
    copyAccount.removeListener(_onCopyAccountChanged);
    super.dispose();
  }

  int _accountRevision = 0;
  Future<void>? _pendingAccountMutation;
  bool _accountsPausedForRestore = false;

  /// Keep backup snapshots outside partially written account transactions.
  Future<T> readAccountStorage<T>(Future<T> Function() read) =>
      _serializeAccounts(read, allowDuringRestore: true);

  Future<void> pauseAccountMutationsForRestore() async {
    _accountsPausedForRestore = true;
    ++_accountRevision;
    await _pendingAccountMutation;
  }

  void resumeAccountMutationsAfterRestore() {
    _accountsPausedForRestore = false;
  }

  Future<T> _serializeAccounts<T>(
    Future<T> Function() action, {
    bool allowDuringRestore = false,
  }) {
    if (_accountsPausedForRestore && !allowDuringRestore) {
      return Future.error(const CopyAccountStorageException());
    }
    final previous = _pendingAccountMutation;
    final barrier = Completer<void>();
    _pendingAccountMutation = barrier.future;
    Future<T> run() async {
      try {
        return await action();
      } finally {
        if (identical(_pendingAccountMutation, barrier.future)) {
          _pendingAccountMutation = null;
        }
        barrier.complete();
      }
    }

    return previous == null ? run() : previous.then((_) => run());
  }

  SavedCredential? get currentCredential => !isLoggedIn
      ? null
      : SavedCredential(
          username: _username ?? '',
          password: '',
          token: _token,
          loginSource: _loginSource,
          userId: _userId,
          nickname: _nickname,
          avatar: _avatar,
          accountId: _accountId,
        );

  SavedCredential? get _currentWithPassword {
    final current = currentCredential;
    if (current == null) return null;
    return current.copyWith(
      password: current.username == _savedUsername ? _savedPassword : null,
    );
  }

  static const _profileKeys = [
    _keyAccountId,
    _keyUserId,
    _keyUsername,
    _keyNickname,
    _keyAvatar,
    _keyLoginSource,
  ];

  Future<void> _requireAccountWrite(Future<bool> write) async {
    if (!await write) throw const CopyAccountStorageException();
  }

  Future<void> _persistProfile(SavedCredential credential) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in {
      _keyUserId: credential.userId ?? '',
      _keyAccountId: credential.accountId ?? '',
      _keyUsername: credential.username,
      _keyNickname: credential.nickname ?? '',
      _keyAvatar: credential.avatar ?? '',
      _keyLoginSource: credential.source,
    }.entries) {
      await _requireAccountWrite(prefs.setString(entry.key, entry.value));
    }
  }
}
