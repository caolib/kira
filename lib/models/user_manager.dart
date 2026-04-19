import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme_option.dart';
import '../api/api_client.dart';

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
  }) =>
      SavedCredential(
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
  static const _keyCustomThemeColor = 'custom_theme_color';
  static const _keyBookshelfOrdering = 'bookshelf_ordering';
  static const _keyReaderMode = 'reader_mode';
  static const _keyReaderScrollDirection = 'reader_scroll_direction';
  static const _keyReaderImageGap = 'reader_image_gap';
  static const _keyReaderVolumeKey = 'reader_volume_key';
  static const _keyReaderPageRTL = 'reader_page_rtl';
  static const _keyReaderPageVertical = 'reader_page_vertical';
  static const _keyReaderDimming = 'reader_dimming';
  static const _keyImageLoadTimeout = 'image_load_timeout';
  static const _keyImageRetryCount = 'image_retry_count';
  static const _keyCommentCompactLayout = 'comment_compact_layout';
  static const _keyCommentShowAvatar = 'comment_show_avatar';
  static const _keyCommentShowUserName = 'comment_show_user_name';
  static const _keyCommentShowTime = 'comment_show_time';
  static const _keyCommentFontScale = 'comment_font_scale';
  static const _keyAutoCheckUpdate = 'auto_check_update';
  static const _keySkippedUpdateVersion = 'skipped_update_version';
  static const _keyAutoLogin = 'auto_login';
  static const _keyDisclaimerAccepted = 'disclaimer_accepted';
  static const _keyLoginSource = 'login_source';
  static const _keyApiRoute = 'api_route';

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
  int _customThemeColorValue = defaultCustomThemeColor.toARGB32();
  String _bookshelfOrdering = '-datetime_updated';
  int _readerMode = 0;
  int _readerScrollDirection = 2;
  double _readerImageGap = 0.0;
  bool _readerVolumeKey = true;
  bool _readerPageRTL = false;
  bool _readerPageVertical = false;
  double _readerDimming = 0.3;
  int _imageLoadTimeout = 15; // 秒
  int _imageRetryCount = 1;
  bool _commentCompactLayout = true;
  bool _commentShowAvatar = true;
  bool _commentShowUserName = true;
  bool _commentShowTime = true;
  double _commentFontScale = 1.0;
  bool _autoCheckUpdate = true;
  String? _skippedUpdateVersion;
  bool _autoLogin = false;
  bool _disclaimerAccepted = false;
  String _loginSource = 'hotmanga';
  int _apiRoute = 0; // 0=线路1(默认), 1=线路2

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
  Color get customThemeColor => Color(_customThemeColorValue);
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

  String get bookshelfOrdering => _bookshelfOrdering;
  int get readerMode => _readerMode;
  int get readerScrollDirection => _readerScrollDirection;
  double get readerImageGap => _readerImageGap;
  bool get readerVolumeKey => _readerVolumeKey;
  bool get readerPageRTL => _readerPageRTL;
  bool get readerPageVertical => _readerPageVertical;
  double get readerDimming => _readerDimming;
  int get imageLoadTimeout => _imageLoadTimeout;
  int get imageRetryCount => _imageRetryCount;
  bool get commentCompactLayout => _commentCompactLayout;
  bool get commentShowAvatar => _commentShowAvatar;
  bool get commentShowUserName => _commentShowUserName;
  bool get commentShowTime => _commentShowTime;
  double get commentFontScale => _commentFontScale;
  bool get autoCheckUpdate => _autoCheckUpdate;
  String? get skippedUpdateVersion => _skippedUpdateVersion;
  bool get autoLogin => _autoLogin;
  bool get disclaimerAccepted => _disclaimerAccepted;
  String get loginSource => _loginSource;
  int get apiRoute => _apiRoute;
  bool get isLoggedIn => _token != null && _token!.isNotEmpty;

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
    _customThemeColorValue =
        prefs.getInt(_keyCustomThemeColor) ??
        defaultCustomThemeColor.toARGB32();
    _bookshelfOrdering =
        prefs.getString(_keyBookshelfOrdering) ?? '-datetime_updated';
    _readerMode = prefs.getInt(_keyReaderMode) ?? 0;
    _readerScrollDirection = prefs.getInt(_keyReaderScrollDirection) ?? 2;
    _readerImageGap = prefs.getDouble(_keyReaderImageGap) ?? 0.0;
    _readerVolumeKey = prefs.getBool(_keyReaderVolumeKey) ?? true;
    _readerPageRTL = prefs.getBool(_keyReaderPageRTL) ?? false;
    _readerPageVertical = prefs.getBool(_keyReaderPageVertical) ?? false;
    _readerDimming = prefs.getDouble(_keyReaderDimming) ?? 0.3;
    _imageLoadTimeout = prefs.getInt(_keyImageLoadTimeout) ?? 15;
    _imageRetryCount = prefs.getInt(_keyImageRetryCount) ?? 1;
    _commentCompactLayout = prefs.getBool(_keyCommentCompactLayout) ?? true;
    _commentShowAvatar = prefs.getBool(_keyCommentShowAvatar) ?? true;
    _commentShowUserName = prefs.getBool(_keyCommentShowUserName) ?? true;
    _commentShowTime = prefs.getBool(_keyCommentShowTime) ?? true;
    _commentFontScale = prefs.getDouble(_keyCommentFontScale) ?? 1.0;
    _autoCheckUpdate = prefs.getBool(_keyAutoCheckUpdate) ?? true;
    _skippedUpdateVersion = prefs.getString(_keySkippedUpdateVersion);
    _autoLogin = prefs.getBool(_keyAutoLogin) ?? false;
    _disclaimerAccepted = prefs.getBool(_keyDisclaimerAccepted) ?? false;
    _loginSource = prefs.getString(_keyLoginSource) ?? 'hotmanga';
    _apiRoute = prefs.getInt(_keyApiRoute) ?? 0;
    notifyListeners();
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
    ApiClient().clearAuthState();
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
    } catch (_) {}
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

  Future<void> refreshUserInfo() async {
    if (!isLoggedIn) return;
    final info = await ApiClient().getUserInfo();
    await saveLogin(
      token: _token!,
      userId: info['user_id']?.toString() ?? _userId ?? '',
      username: info['username']?.toString() ?? _username ?? '',
      nickname: info['nickname']?.toString() ?? _nickname ?? '',
      avatar: info['avatar']?.toString() ?? _avatar ?? '',
    );
  }
}
