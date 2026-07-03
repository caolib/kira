import 'package:shared_preferences/shared_preferences.dart';

import 'prefs_store.dart';

/// Comment display settings, extracted from UserManager.
class CommentSettings extends PrefsStore {
  static final CommentSettings _instance = CommentSettings._();
  factory CommentSettings() => _instance;
  CommentSettings._();

  // ── Preference keys ────────────────────────────────────────────────

  static const _keyCompactLayout = 'comment_compact_layout';
  static const _keyShowAvatar = 'comment_show_avatar';
  static const _keyShowUserName = 'comment_show_user_name';
  static const _keyShowTime = 'comment_show_time';
  static const _keyFontScale = 'comment_font_scale';
  static const _keyPreload = 'comment_preload';
  static const _keyAutoLoadAll = 'comment_auto_load_all';

  // ── Fields ─────────────────────────────────────────────────────────

  bool _compactLayout = true;
  bool _showAvatar = true;
  bool _showUserName = true;
  bool _showTime = true;
  double _fontScale = 1.0;
  bool _preload = true;
  bool _autoLoadAll = false;

  // ── Getters ────────────────────────────────────────────────────────

  bool get compactLayout => _compactLayout;
  bool get showAvatar => _showAvatar;
  bool get showUserName => _showUserName;
  bool get showTime => _showTime;
  double get fontScale => _fontScale;
  bool get preload => _preload;
  bool get autoLoadAll => _autoLoadAll;

  // ── Init ───────────────────────────────────────────────────────────

  Future<void> initFromPrefs(SharedPreferences prefs) async {
    _compactLayout = prefs.getBool(_keyCompactLayout) ?? true;
    _showAvatar = prefs.getBool(_keyShowAvatar) ?? true;
    _showUserName = prefs.getBool(_keyShowUserName) ?? true;
    _showTime = prefs.getBool(_keyShowTime) ?? true;
    _fontScale = prefs.getDouble(_keyFontScale) ?? 1.0;
    _preload = prefs.getBool(_keyPreload) ?? true;
    _autoLoadAll = prefs.getBool(_keyAutoLoadAll) ?? false;
  }

  // ── Setters ────────────────────────────────────────────────────────

  Future<void> setCompactLayout(bool value) async {
    _compactLayout = value;
    await setBool(_keyCompactLayout, value);
  }

  Future<void> setShowAvatar(bool value) async {
    _showAvatar = value;
    await setBool(_keyShowAvatar, value);
  }

  Future<void> setShowUserName(bool value) async {
    _showUserName = value;
    await setBool(_keyShowUserName, value);
  }

  Future<void> setShowTime(bool value) async {
    _showTime = value;
    await setBool(_keyShowTime, value);
  }

  Future<void> setFontScale(double value) async {
    _fontScale = value;
    await setDouble(_keyFontScale, value);
  }

  Future<void> setPreload(bool value) async {
    _preload = value;
    await setBool(_keyPreload, value);
  }

  Future<void> setAutoLoadAll(bool value) async {
    _autoLoadAll = value;
    await setBool(_keyAutoLoadAll, value);
  }
}
