import 'package:shared_preferences/shared_preferences.dart';

import 'prefs_store.dart';

/// Danmaku-specific settings, extracted from UserManager.
class DanmakuSettings extends PrefsStore {
  static final DanmakuSettings _instance = DanmakuSettings._();
  factory DanmakuSettings() => _instance;
  DanmakuSettings._();

  // ── Preference keys ────────────────────────────────────────────────

  static const _keyEnabled = 'danmaku_enabled';
  static const _keyFontSize = 'danmaku_font_size';
  static const _keyArea = 'danmaku_area';
  static const _keyOpacity = 'danmaku_opacity';
  static const _keyHideScroll = 'danmaku_hide_scroll';
  static const _keyHideTop = 'danmaku_hide_top';
  static const _keyHideBottom = 'danmaku_hide_bottom';
  static const _keyBlocklist = 'danmaku_blocklist';
  static const _keyFontFamily = 'danmaku_font_family';

  // ── Fields ─────────────────────────────────────────────────────────

  bool _enabled = true;
  double _fontSize = 16;
  double _area = 0.25;
  double _opacity = 1.0;
  bool _hideScroll = false;
  bool _hideTop = false;
  bool _hideBottom = false;
  List<String> _blocklist = [];
  String _fontFamily = '';

  // ── Getters ────────────────────────────────────────────────────────

  bool get enabled => _enabled;
  double get fontSize => _fontSize;
  double get area => _area;
  double get opacity => _opacity;
  bool get hideScroll => _hideScroll;
  bool get hideTop => _hideTop;
  bool get hideBottom => _hideBottom;
  List<String> get blocklist => List.unmodifiable(_blocklist);
  String get fontFamily => _fontFamily;

  // ── Init ───────────────────────────────────────────────────────────

  Future<void> initFromPrefs(SharedPreferences prefs) async {
    _enabled = prefs.getBool(_keyEnabled) ?? true;
    _fontSize = prefs.getDouble(_keyFontSize) ?? 16;
    _area = prefs.getDouble(_keyArea) ?? 0.25;
    _opacity = prefs.getDouble(_keyOpacity) ?? 1.0;
    _hideScroll = prefs.getBool(_keyHideScroll) ?? false;
    _hideTop = prefs.getBool(_keyHideTop) ?? false;
    _hideBottom = prefs.getBool(_keyHideBottom) ?? false;
    _blocklist = prefs.getStringList(_keyBlocklist) ?? [];
    _fontFamily = prefs.getString(_keyFontFamily) ?? '';
  }

  // ── Setters ────────────────────────────────────────────────────────

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    await setBool(_keyEnabled, value);
  }

  Future<void> setFontSize(double value) async {
    if (_fontSize == value) return;
    _fontSize = value;
    await setDouble(_keyFontSize, value);
  }

  Future<void> setArea(double value) async {
    if (_area == value) return;
    _area = value;
    await setDouble(_keyArea, value);
  }

  Future<void> setOpacity(double value) async {
    if (_opacity == value) return;
    _opacity = value;
    await setDouble(_keyOpacity, value);
  }

  Future<void> setHideScroll(bool value) async {
    if (_hideScroll == value) return;
    _hideScroll = value;
    await setBool(_keyHideScroll, value);
  }

  Future<void> setHideTop(bool value) async {
    if (_hideTop == value) return;
    _hideTop = value;
    await setBool(_keyHideTop, value);
  }

  Future<void> setHideBottom(bool value) async {
    if (_hideBottom == value) return;
    _hideBottom = value;
    await setBool(_keyHideBottom, value);
  }

  Future<void> setBlocklist(List<String> list) async {
    _blocklist = List.from(list);
    await setStringList(_keyBlocklist, list);
  }

  Future<void> setFontFamily(String value) async {
    if (_fontFamily == value) return;
    _fontFamily = value;
    await setString(_keyFontFamily, value);
  }
}
