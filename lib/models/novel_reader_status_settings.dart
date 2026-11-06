import 'package:shared_preferences/shared_preferences.dart';

import 'prefs_store.dart';
import 'reader_settings.dart';
import 'reader_status_prefs.dart';

/// 轻小说状态组件（时间/网络/电量/章节名/进度/帧率浮层）的独立配置，
/// 与漫画侧 `ReaderSettings` 的 `reader_status_overlay*` 互不影响。
///
/// 首次初始化（prefs 中无任何 `novel_status_overlay*` 键）时，一次性继承
/// 漫画侧现值并固化（只读初始化仅继承到内存）——老用户升级后两侧
/// 初始一致，之后各自独立演化。
class NovelReaderStatusSettings extends PrefsStore
    implements ReaderStatusPrefs {
  static final NovelReaderStatusSettings _instance =
      NovelReaderStatusSettings._();
  factory NovelReaderStatusSettings() => _instance;
  NovelReaderStatusSettings._();

  // ── Preference keys ────────────────────────────────────────────────

  static const _keyOverlay = 'novel_status_overlay';
  static const _keyTime = 'novel_status_overlay_time';
  static const _keyBattery = 'novel_status_overlay_battery';
  static const _keyNetwork = 'novel_status_overlay_network';
  static const _keyChapter = 'novel_status_overlay_chapter';
  static const _keyPage = 'novel_status_overlay_page';
  static const _keyFps = 'novel_status_overlay_fps';
  static const _keyOrder = 'novel_status_overlay_order';
  static const _keyPosition = 'novel_status_overlay_position';
  static const _keyOpacity = 'novel_status_overlay_opacity';
  static const _keyForeground = 'novel_status_overlay_foreground';
  static const _keyBackground = 'novel_status_overlay_background';
  static const _keyFollowTheme = 'novel_status_overlay_follow_theme';

  /// 迁移哨兵：写入后不再从漫画侧继承。
  static const _keySeeded = 'novel_status_overlay_seeded';

  /// 轻小说侧段位集合与默认顺序：`chapter` 排第一（一眼可扫读当前章节，
  /// 时间/网络等系统状态靠后；顺序仅是默认值，用户可拖动调整）。
  static const List<String> defaultNovelStatusOverlayOrder = [
    'chapter',
    'time',
    'network',
    'battery',
    'page',
    'fps',
  ];

  static const List<String> _allKeys = [
    _keyOverlay,
    _keyTime,
    _keyBattery,
    _keyNetwork,
    _keyChapter,
    _keyPage,
    _keyFps,
    _keyOrder,
    _keyPosition,
    _keyOpacity,
    _keyForeground,
    _keyBackground,
    _keyFollowTheme,
  ];

  // ── Fields ─────────────────────────────────────────────────────────

  bool _overlay = false;
  bool _time = true;
  bool _battery = true;
  bool _network = true;
  bool _chapter = false;
  bool _page = false;
  bool _fps = false;
  List<String> _order = List.of(defaultNovelStatusOverlayOrder);
  // 0=左上 1=顶部中间 2=右上(默认) 3=右下 4=底部中间 5=左下
  int _position = 2;
  // 0.0(透明)~1.0(不透明)，作用于背景色。
  double _opacity = 0.7;

  /// null=未手动指定颜色（跟随主题时忽略）。
  int? _foreground;
  int? _background;

  /// 配色跟随阅读主题（palette 前景/背景）；关闭后用手动颜色（未设则
  /// 黑底白字）。默认跟随。
  bool _followTheme = true;

  // ── ReaderStatusPrefs ──────────────────────────────────────────────

  @override
  bool get statusOverlay => _overlay;
  @override
  bool get statusOverlayTime => _time;
  @override
  bool get statusOverlayBattery => _battery;
  @override
  bool get statusOverlayNetwork => _network;
  @override
  bool get statusOverlayChapter => _chapter;
  @override
  bool get statusOverlayPage => _page;
  @override
  bool get statusOverlayFps => _fps;
  @override
  List<String> get statusOverlayOrder => List.unmodifiable(_order);
  @override
  List<String> get statusOverlaySegmentIds => defaultNovelStatusOverlayOrder;
  @override
  int get statusOverlayPosition => _position;
  @override
  double get statusOverlayOpacity => _opacity;
  @override
  int? get statusOverlayForeground => _foreground;
  @override
  int? get statusOverlayBackground => _background;
  @override
  bool get statusOverlayFollowTheme => _followTheme;
  @override
  bool get supportsStatusOverlayFollowTheme => true;

  // ── Init ───────────────────────────────────────────────────────────

  /// 由 `UserManager.init` 调用（与漫画侧同一 prefs 实例）。
  Future<void> initFromPrefs(
    SharedPreferences prefs, {
    bool persistMigrations = true,
  }) async {
    syncPrefs(prefs);
    final fresh =
        !_allKeys.any(prefs.containsKey) && prefs.getBool(_keySeeded) != true;
    if (fresh) {
      // 一次性继承漫画侧现值（含默认值），固化后两侧独立。
      final manga = ReaderSettings();
      _overlay = manga.statusOverlay;
      _time = manga.statusOverlayTime;
      _battery = manga.statusOverlayBattery;
      _network = manga.statusOverlayNetwork;
      _page = manga.statusOverlayPage;
      _fps = manga.statusOverlayFps;
      _position = manga.statusOverlayPosition;
      _opacity = manga.statusOverlayOpacity;
      _foreground = manga.statusOverlayForeground;
      _background = manga.statusOverlayBackground;
      // `chapter` 是小说新增段位，漫画没有对应值：默认展示。
      _chapter = true;
      // 章节名默认排第一，其余段位沿用漫画侧用户顺序。
      _order = [
        'chapter',
        ...manga.statusOverlayOrder.where((id) => id != 'chapter'),
      ];
      // 配色默认跟随阅读主题，不继承漫画的手动颜色。
      _followTheme = true;
      _foreground = null;
      _background = null;
      if (persistMigrations) {
        await _persistSnapshot(prefs);
        await prefs.setBool(_keySeeded, true);
      }
      return;
    }
    _overlay = prefs.getBool(_keyOverlay) ?? _overlay;
    _time = prefs.getBool(_keyTime) ?? _time;
    _battery = prefs.getBool(_keyBattery) ?? _battery;
    _network = prefs.getBool(_keyNetwork) ?? _network;
    _chapter = prefs.getBool(_keyChapter) ?? _chapter;
    _page = prefs.getBool(_keyPage) ?? _page;
    _fps = prefs.getBool(_keyFps) ?? _fps;
    _position = (prefs.getInt(_keyPosition) ?? _position).clamp(0, 5);
    _opacity = (prefs.getDouble(_keyOpacity) ?? _opacity).clamp(0.0, 1.0);
    _foreground = prefs.getInt(_keyForeground);
    _background = prefs.getInt(_keyBackground);
    _followTheme = prefs.getBool(_keyFollowTheme) ?? true;
    final savedOrder = prefs.getStringList(_keyOrder);
    if (savedOrder != null) {
      _order = sanitizeReaderStatusOrder(savedOrder, statusOverlaySegmentIds);
    }
  }

  Future<void> _persistSnapshot(SharedPreferences prefs) async {
    await prefs.setBool(_keyOverlay, _overlay);
    await prefs.setBool(_keyTime, _time);
    await prefs.setBool(_keyBattery, _battery);
    await prefs.setBool(_keyNetwork, _network);
    await prefs.setBool(_keyChapter, _chapter);
    await prefs.setBool(_keyPage, _page);
    await prefs.setBool(_keyFps, _fps);
    await prefs.setStringList(_keyOrder, _order);
    await prefs.setInt(_keyPosition, _position);
    await prefs.setDouble(_keyOpacity, _opacity);
    await prefs.setBool(_keyFollowTheme, _followTheme);
    if (_foreground != null) {
      await prefs.setInt(_keyForeground, _foreground!);
    }
    if (_background != null) {
      await prefs.setInt(_keyBackground, _background!);
    }
  }

  // ── Setters ────────────────────────────────────────────────────────

  @override
  Future<void> setStatusOverlay(bool value) async {
    _overlay = value;
    await setBool(_keyOverlay, value);
  }

  @override
  Future<void> setStatusOverlayTime(bool value) async {
    _time = value;
    await setBool(_keyTime, value);
  }

  @override
  Future<void> setStatusOverlayBattery(bool value) async {
    _battery = value;
    await setBool(_keyBattery, value);
  }

  @override
  Future<void> setStatusOverlayNetwork(bool value) async {
    _network = value;
    await setBool(_keyNetwork, value);
  }

  @override
  Future<void> setStatusOverlayChapter(bool value) async {
    _chapter = value;
    await setBool(_keyChapter, value);
  }

  @override
  Future<void> setStatusOverlayPage(bool value) async {
    _page = value;
    await setBool(_keyPage, value);
  }

  @override
  Future<void> setStatusOverlayFps(bool value) async {
    _fps = value;
    await setBool(_keyFps, value);
  }

  @override
  Future<void> setStatusOverlayOrder(List<String> value) async {
    final sanitized = sanitizeReaderStatusOrder(value, statusOverlaySegmentIds);
    if (_listEquals(_order, sanitized)) return;
    _order = sanitized;
    await setStringList(_keyOrder, sanitized);
  }

  @override
  Future<void> setStatusOverlayPosition(int value) async {
    final clamped = value.clamp(0, 5);
    _position = clamped;
    await setInt(_keyPosition, clamped);
  }

  @override
  Future<void> setStatusOverlayOpacity(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    _opacity = clamped;
    await setDouble(_keyOpacity, clamped);
  }

  @override
  Future<void> setStatusOverlayFollowTheme(bool value) async {
    if (_followTheme == value) return;
    _followTheme = value;
    await setBool(_keyFollowTheme, value);
  }

  @override
  Future<void> setStatusOverlayForeground(int? value) async {
    if (_foreground == value) return;
    _foreground = value;
    if (value == null) {
      await remove(_keyForeground);
    } else {
      await setInt(_keyForeground, value);
    }
  }

  @override
  Future<void> setStatusOverlayBackground(int? value) async {
    if (_background == value) return;
    _background = value;
    if (value == null) {
      await remove(_keyBackground);
    } else {
      await setInt(_keyBackground, value);
    }
  }
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
