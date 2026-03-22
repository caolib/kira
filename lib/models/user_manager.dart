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

  String? _token;
  String? _username;
  String? _nickname;
  String? _avatar;
  String? _userId;
  String? _savedUsername;
  String? _savedPassword;
  ThemeMode _themeMode = ThemeMode.system;
  String _bookshelfOrdering = '-datetime_updated';

  String? get token => _token;
  String? get username => _username;
  String? get nickname => _nickname;
  String? get avatar => _avatar;
  String? get userId => _userId;
  String? get savedUsername => _savedUsername;
  String? get savedPassword => _savedPassword;
  ThemeMode get themeMode => _themeMode;
  String get bookshelfOrdering => _bookshelfOrdering;
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
    _bookshelfOrdering = prefs.getString(_keyBookshelfOrdering) ?? '-datetime_updated';
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
