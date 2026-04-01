import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';

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
  static const _keyThemeMode = 'theme_mode';
  static const _keyBookshelfOrdering = 'bookshelf_ordering';
  static const _keyReaderMode = 'reader_mode';
  static const _keyReaderImageGap = 'reader_image_gap';
  static const _keyReaderVolumeKey = 'reader_volume_key';
  static const _keyReaderPageRTL = 'reader_page_rtl';
  static const _keyReaderPageVertical = 'reader_page_vertical';
  static const _keyReaderDimming = 'reader_dimming';
  static const _keyAutoCheckUpdate = 'auto_check_update';
  static const _keySkippedUpdateVersion = 'skipped_update_version';

  String? _token;
  String? _username;
  String? _nickname;
  String? _avatar;
  String? _userId;
  String? _savedUsername;
  String? _savedPassword;
  ThemeMode _themeMode = ThemeMode.system;
  String _bookshelfOrdering = '-datetime_updated';
  int _readerMode = 0;
  double _readerImageGap = 0.0;
  bool _readerVolumeKey = true;
  bool _readerPageRTL = false;
  bool _readerPageVertical = false;
  double _readerDimming = 0.3;
  bool _autoCheckUpdate = true;
  String? _skippedUpdateVersion;

  String? get token => _token;
  String? get username => _username;
  String? get nickname => _nickname;
  String? get avatar => _avatar;
  String? get userId => _userId;
  String? get savedUsername => _savedUsername;
  String? get savedPassword => _savedPassword;
  ThemeMode get themeMode => _themeMode;
  String get bookshelfOrdering => _bookshelfOrdering;
  int get readerMode => _readerMode;
  double get readerImageGap => _readerImageGap;
  bool get readerVolumeKey => _readerVolumeKey;
  bool get readerPageRTL => _readerPageRTL;
  bool get readerPageVertical => _readerPageVertical;
  double get readerDimming => _readerDimming;
  bool get autoCheckUpdate => _autoCheckUpdate;
  String? get skippedUpdateVersion => _skippedUpdateVersion;
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
    _themeMode = ThemeMode.values[prefs.getInt(_keyThemeMode) ?? 0];
    _bookshelfOrdering =
        prefs.getString(_keyBookshelfOrdering) ?? '-datetime_updated';
    _readerMode = prefs.getInt(_keyReaderMode) ?? 0;
    _readerImageGap = prefs.getDouble(_keyReaderImageGap) ?? 0.0;
    _readerVolumeKey = prefs.getBool(_keyReaderVolumeKey) ?? true;
    _readerPageRTL = prefs.getBool(_keyReaderPageRTL) ?? false;
    _readerPageVertical = prefs.getBool(_keyReaderPageVertical) ?? false;
    _readerDimming = prefs.getDouble(_keyReaderDimming) ?? 0.3;
    _autoCheckUpdate = prefs.getBool(_keyAutoCheckUpdate) ?? true;
    _skippedUpdateVersion = prefs.getString(_keySkippedUpdateVersion);
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
    notifyListeners();
  }

  Future<void> logout() async {
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySavedUsername, username);
    await prefs.setString(_keySavedPassword, password);
  }

  Future<void> clearCredentials() async {
    _savedUsername = null;
    _savedPassword = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySavedUsername);
    await prefs.remove(_keySavedPassword);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyThemeMode, mode.index);
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
