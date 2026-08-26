import 'package:shared_preferences/shared_preferences.dart';

import 'prefs_store.dart';

/// Reader-specific settings, extracted from UserManager.
///
/// Each field change notifies only the listeners of *this* store,
/// not the entire app — enabling fine-grained rebuilds.
class ReaderSettings extends PrefsStore {
  static final ReaderSettings _instance = ReaderSettings._();
  factory ReaderSettings() => _instance;
  ReaderSettings._();

  // ── Preference keys ────────────────────────────────────────────────

  static const _keyMode = 'reader_mode';
  static const _keyScrollDirection = 'reader_scroll_direction';
  static const _keyImageGap = 'reader_image_gap';
  static const _keyVolumeKey = 'reader_volume_key';
  static const _keyInstantPageTurn = 'reader_instant_page_turn';
  static const _keyPageRTL = 'reader_page_rtl';
  static const _keyPageVertical = 'reader_page_vertical';
  static const _keyDimming = 'reader_dimming';
  static const _keyAutoScrollEnabled = 'reader_auto_scroll_enabled';
  static const _keyAutoScrollPause = 'reader_auto_scroll_pause';
  static const _keyAutoScrollResume = 'reader_auto_scroll_resume';
  static const _keyAutoScrollResumeDelay = 'reader_auto_scroll_resume_delay';
  static const _keyAutoScrollDistance = 'reader_auto_scroll_distance';
  static const _keyContinuousReading = 'reader_continuous_reading';
  static const _keyViewerAutoRotateLandscape =
      'image_viewer_auto_rotate_landscape';
  static const _keyViewerLandscapeRotation = 'image_viewer_landscape_rotation';
  static const _keyImageLoadTimeout = 'image_load_timeout';
  static const _keyImageRetryCount = 'image_retry_count';
  static const _keyStatusOverlay = 'reader_status_overlay';
  static const _keyStatusOverlayTime = 'reader_status_overlay_time';
  static const _keyStatusOverlayBattery = 'reader_status_overlay_battery';
  static const _keyStatusOverlayNetwork = 'reader_status_overlay_network';
  static const _keyStatusOverlayPage = 'reader_status_overlay_page';
  static const _keyStatusOverlayFps = 'reader_status_overlay_fps';
  static const _keyStatusOverlayOrder = 'reader_status_overlay_order';
  static const _keyStatusOverlayPosition = 'reader_status_overlay_position';
  static const _keyStatusOverlayOpacity = 'reader_status_overlay_opacity';
  static const _keyReadingStatsEnabled = 'reader_reading_stats_enabled';
  static const _keyReadingStatsChartStyle = 'reader_reading_stats_chart_style';
  static const _keyReadingStatsShowOverview =
      'reader_reading_stats_show_overview';
  static const _keyReadingStatsShowTags = 'reader_reading_stats_show_tags';
  static const _keyReadingStatsShowActivityChart =
      'reader_reading_stats_show_activity_chart';
  static const _keyReadingStatsSectionOrder =
      'reader_reading_stats_section_order';

  /// 统计页三个组件的默认显示顺序（与开关独立）。
  static const List<String> defaultReadingStatsSectionOrder = [
    'overview',
    'tags',
    'activity',
  ];

  /// 状态显示各段位的默认显示顺序（时间/网络/电量/页码/帧率）。
  static const List<String> defaultStatusOverlayOrder = [
    'time',
    'network',
    'battery',
    'page',
    'fps',
  ];

  // ── Fields ─────────────────────────────────────────────────────────

  int _mode = 0;
  int _scrollDirection = 2;
  double _imageGap = 0.0;
  bool _volumeKey = true;
  bool _instantPageTurn = false;
  bool _pageRTL = false;
  bool _pageVertical = false;
  double _dimming = 0.3;
  bool _autoScrollEnabled = false;
  double _autoScrollPause = 3.0;
  bool _autoScrollResume = false;
  double _autoScrollResumeDelay = 2.0;
  double _autoScrollDistance = 0.8;
  bool _continuousReading = true;
  bool _viewerAutoRotateLandscape = false;
  int _viewerLandscapeRotation = 1;
  int _imageLoadTimeout = 15;
  int _imageRetryCount = 1;
  bool _statusOverlay = false;
  bool _statusOverlayTime = true;
  bool _statusOverlayBattery = true;
  bool _statusOverlayNetwork = true;
  bool _statusOverlayPage = false;
  bool _statusOverlayFps = false;
  List<String> _statusOverlayOrder = List.of(defaultStatusOverlayOrder);
  // 0=左上 1=顶部中间 2=右上(默认) 3=右下 4=底部中间 5=左下
  int _statusOverlayPosition = 2;
  // 0.0(透明)~1.0(全黑)，默认即原 Color(0xB3000000) 的 alpha≈0.7
  double _statusOverlayOpacity = 0.7;
  bool _readingStatsEnabled = false;

  /// 阅读活跃度图表样式：0=热力图（默认），1=条形图。
  /// 见 [readingStatsChartStyle] / [setReadingStatsChartStyle]。
  int _readingStatsChartStyle = 0;

  /// 统计页三个组件是否显示，默认全开。至少保留一个由 UI 层强制。
  bool _readingStatsShowOverview = true;
  bool _readingStatsShowTags = true;
  bool _readingStatsShowActivityChart = true;
  List<String> _readingStatsSectionOrder = List.of(
    defaultReadingStatsSectionOrder,
  );

  // ── Getters ────────────────────────────────────────────────────────

  int get mode => _mode;
  int get scrollDirection => _scrollDirection;
  double get imageGap => _imageGap;
  bool get volumeKey => _volumeKey;
  bool get instantPageTurn => _instantPageTurn;
  bool get pageRTL => _pageRTL;
  bool get pageVertical => _pageVertical;
  double get dimming => _dimming;
  bool get autoScrollEnabled => _autoScrollEnabled;
  double get autoScrollPause => _autoScrollPause;
  bool get autoScrollResume => _autoScrollResume;
  double get autoScrollResumeDelay => _autoScrollResumeDelay;
  double get autoScrollDistance => _autoScrollDistance;
  bool get continuousReading => _continuousReading;
  bool get viewerAutoRotateLandscape => _viewerAutoRotateLandscape;
  int get viewerLandscapeRotation => _viewerLandscapeRotation;
  int get imageLoadTimeout => _imageLoadTimeout;
  int get imageRetryCount => _imageRetryCount;
  bool get statusOverlay => _statusOverlay;
  bool get statusOverlayTime => _statusOverlayTime;
  bool get statusOverlayBattery => _statusOverlayBattery;
  bool get statusOverlayNetwork => _statusOverlayNetwork;
  bool get statusOverlayPage => _statusOverlayPage;
  bool get statusOverlayFps => _statusOverlayFps;
  int get statusOverlayPosition => _statusOverlayPosition;
  double get statusOverlayOpacity => _statusOverlayOpacity;
  bool get readingStatsEnabled => _readingStatsEnabled;

  /// 阅读活跃度图表样式：0=热力图（默认），1=条形图。
  int get readingStatsChartStyle => _readingStatsChartStyle;

  bool get readingStatsShowOverview => _readingStatsShowOverview;
  bool get readingStatsShowTags => _readingStatsShowTags;
  bool get readingStatsShowActivityChart => _readingStatsShowActivityChart;

  /// 统计组件显示顺序（未知 id 剔除、去重，缺失的按默认顺序补到末尾）。
  List<String> get readingStatsSectionOrder =>
      List.unmodifiable(_readingStatsSectionOrder);

  /// 状态显示段位顺序（未知 id 会被剔除，缺失的段位按默认顺序补到末尾）。
  List<String> get statusOverlayOrder => List.unmodifiable(_statusOverlayOrder);

  // ── Init (called from UserManager.init) ────────────────────────────

  Future<void> initFromPrefs(SharedPreferences prefs) async {
    _mode = prefs.getInt(_keyMode) ?? 0;
    _scrollDirection = prefs.getInt(_keyScrollDirection) ?? 2;
    _imageGap = prefs.getDouble(_keyImageGap) ?? 0.0;
    _volumeKey = prefs.getBool(_keyVolumeKey) ?? true;
    _instantPageTurn = prefs.getBool(_keyInstantPageTurn) ?? false;
    _pageRTL = prefs.getBool(_keyPageRTL) ?? false;
    _pageVertical = prefs.getBool(_keyPageVertical) ?? false;
    _dimming = prefs.getDouble(_keyDimming) ?? 0.3;
    _autoScrollEnabled = prefs.getBool(_keyAutoScrollEnabled) ?? false;
    _autoScrollPause = (prefs.getDouble(_keyAutoScrollPause) ?? 3.0).clamp(
      0.5,
      8.0,
    );
    _autoScrollResume = prefs.getBool(_keyAutoScrollResume) ?? false;
    _autoScrollResumeDelay = (prefs.getDouble(_keyAutoScrollResumeDelay) ?? 2.0)
        .clamp(1.0, 5.0);
    _autoScrollDistance = (prefs.getDouble(_keyAutoScrollDistance) ?? 0.8)
        .clamp(0.2, 1.0);
    _continuousReading = prefs.getBool(_keyContinuousReading) ?? true;
    _viewerAutoRotateLandscape =
        prefs.getBool(_keyViewerAutoRotateLandscape) ?? false;
    final savedRotation = prefs.getInt(_keyViewerLandscapeRotation) ?? 1;
    _viewerLandscapeRotation = savedRotation < 0 ? -1 : 1;
    _imageLoadTimeout = prefs.getInt(_keyImageLoadTimeout) ?? 15;
    _imageRetryCount = prefs.getInt(_keyImageRetryCount) ?? 1;
    _statusOverlay = prefs.getBool(_keyStatusOverlay) ?? false;
    _statusOverlayTime = prefs.getBool(_keyStatusOverlayTime) ?? true;
    _statusOverlayBattery = prefs.getBool(_keyStatusOverlayBattery) ?? true;
    _statusOverlayNetwork = prefs.getBool(_keyStatusOverlayNetwork) ?? true;
    _statusOverlayPage = prefs.getBool(_keyStatusOverlayPage) ?? false;
    _statusOverlayFps = prefs.getBool(_keyStatusOverlayFps) ?? false;
    _statusOverlayPosition = (prefs.getInt(_keyStatusOverlayPosition) ?? 2)
        .clamp(0, 5);
    _statusOverlayOpacity = (prefs.getDouble(_keyStatusOverlayOpacity) ?? 0.7)
        .clamp(0.0, 1.0);
    final savedOrder = prefs.getStringList(_keyStatusOverlayOrder) ?? const [];
    _statusOverlayOrder = _sanitizeStatusOverlayOrder(savedOrder);
    _readingStatsEnabled = prefs.getBool(_keyReadingStatsEnabled) ?? false;
    _readingStatsChartStyle = prefs.getInt(_keyReadingStatsChartStyle) ?? 0;
    _readingStatsShowOverview =
        prefs.getBool(_keyReadingStatsShowOverview) ?? true;
    _readingStatsShowTags = prefs.getBool(_keyReadingStatsShowTags) ?? true;
    _readingStatsShowActivityChart =
        prefs.getBool(_keyReadingStatsShowActivityChart) ?? true;
    final savedSectionOrder =
        prefs.getStringList(_keyReadingStatsSectionOrder) ?? const [];
    _readingStatsSectionOrder = _sanitizeReadingStatsSectionOrder(
      savedSectionOrder,
    );
  }

  // ── Setters ────────────────────────────────────────────────────────

  Future<void> setMode(int value) async {
    _mode = value;
    await setInt(_keyMode, value);
  }

  Future<void> setScrollDirection(int value) async {
    _scrollDirection = value;
    await setInt(_keyScrollDirection, value);
  }

  Future<void> setImageGap(double value) async {
    _imageGap = value;
    await setDouble(_keyImageGap, value);
  }

  Future<void> setVolumeKey(bool value) async {
    _volumeKey = value;
    await setBool(_keyVolumeKey, value);
  }

  Future<void> setInstantPageTurn(bool value) async {
    _instantPageTurn = value;
    await setBool(_keyInstantPageTurn, value);
  }

  Future<void> setPageRTL(bool value) async {
    _pageRTL = value;
    await setBool(_keyPageRTL, value);
  }

  Future<void> setPageVertical(bool value) async {
    _pageVertical = value;
    await setBool(_keyPageVertical, value);
  }

  Future<void> setDimming(double value) async {
    _dimming = value;
    await setDouble(_keyDimming, value);
  }

  Future<void> setAutoScrollEnabled(bool value) async {
    _autoScrollEnabled = value;
    await setBool(_keyAutoScrollEnabled, value);
  }

  Future<void> setAutoScrollPause(double value) async {
    _autoScrollPause = value;
    await setDouble(_keyAutoScrollPause, value);
  }

  Future<void> setAutoScrollResume(bool value) async {
    _autoScrollResume = value;
    await setBool(_keyAutoScrollResume, value);
  }

  Future<void> setAutoScrollResumeDelay(double value) async {
    _autoScrollResumeDelay = value;
    await setDouble(_keyAutoScrollResumeDelay, value);
  }

  Future<void> setAutoScrollDistance(double value) async {
    _autoScrollDistance = value;
    await setDouble(_keyAutoScrollDistance, value);
  }

  Future<void> setContinuousReading(bool value) async {
    _continuousReading = value;
    await setBool(_keyContinuousReading, value);
  }

  Future<void> setViewerAutoRotateLandscape(bool value) async {
    if (_viewerAutoRotateLandscape == value) return;
    _viewerAutoRotateLandscape = value;
    await setBool(_keyViewerAutoRotateLandscape, value);
  }

  Future<void> setViewerLandscapeRotation(int value) async {
    final next = value < 0 ? -1 : 1;
    if (_viewerLandscapeRotation == next) return;
    _viewerLandscapeRotation = next;
    await setInt(_keyViewerLandscapeRotation, next);
  }

  Future<void> setImageLoadTimeout(int value) async {
    _imageLoadTimeout = value;
    await setInt(_keyImageLoadTimeout, value);
  }

  Future<void> setImageRetryCount(int value) async {
    _imageRetryCount = value;
    await setInt(_keyImageRetryCount, value);
  }

  Future<void> setStatusOverlay(bool value) async {
    _statusOverlay = value;
    await setBool(_keyStatusOverlay, value);
  }

  Future<void> setStatusOverlayTime(bool value) async {
    _statusOverlayTime = value;
    await setBool(_keyStatusOverlayTime, value);
  }

  Future<void> setStatusOverlayBattery(bool value) async {
    _statusOverlayBattery = value;
    await setBool(_keyStatusOverlayBattery, value);
  }

  Future<void> setStatusOverlayNetwork(bool value) async {
    _statusOverlayNetwork = value;
    await setBool(_keyStatusOverlayNetwork, value);
  }

  Future<void> setStatusOverlayPage(bool value) async {
    _statusOverlayPage = value;
    await setBool(_keyStatusOverlayPage, value);
  }

  Future<void> setStatusOverlayFps(bool value) async {
    _statusOverlayFps = value;
    await setBool(_keyStatusOverlayFps, value);
  }

  Future<void> setStatusOverlayOrder(List<String> value) async {
    final sanitized = _sanitizeStatusOverlayOrder(value);
    if (_listEquals(_statusOverlayOrder, sanitized)) return;
    _statusOverlayOrder = sanitized;
    await setStringList(_keyStatusOverlayOrder, sanitized);
  }

  Future<void> setStatusOverlayPosition(int value) async {
    final clamped = value.clamp(0, 5);
    _statusOverlayPosition = clamped;
    await setInt(_keyStatusOverlayPosition, clamped);
  }

  Future<void> setStatusOverlayOpacity(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    _statusOverlayOpacity = clamped;
    await setDouble(_keyStatusOverlayOpacity, clamped);
  }

  Future<void> setReadingStatsEnabled(bool value) async {
    _readingStatsEnabled = value;
    await setBool(_keyReadingStatsEnabled, value);
  }

  Future<void> setReadingStatsChartStyle(int value) async {
    _readingStatsChartStyle = value;
    await setInt(_keyReadingStatsChartStyle, value);
  }

  Future<void> setReadingStatsShowOverview(bool value) async {
    _readingStatsShowOverview = value;
    await setBool(_keyReadingStatsShowOverview, value);
  }

  Future<void> setReadingStatsShowTags(bool value) async {
    _readingStatsShowTags = value;
    await setBool(_keyReadingStatsShowTags, value);
  }

  Future<void> setReadingStatsShowActivityChart(bool value) async {
    _readingStatsShowActivityChart = value;
    await setBool(_keyReadingStatsShowActivityChart, value);
  }

  Future<void> setReadingStatsSectionOrder(List<String> value) async {
    final sanitized = _sanitizeReadingStatsSectionOrder(value);
    if (_listEquals(_readingStatsSectionOrder, sanitized)) return;
    _readingStatsSectionOrder = sanitized;
    await setStringList(_keyReadingStatsSectionOrder, sanitized);
  }
}

/// 保留输入顺序、剔除未知 id、去重，并把缺失的段位按默认顺序补到末尾。
List<String> _sanitizeStatusOverlayOrder(List<String> input) {
  final seen = <String>{};
  final sanitized = [
    for (final id in input)
      if (ReaderSettings.defaultStatusOverlayOrder.contains(id) && seen.add(id))
        id,
    ...ReaderSettings.defaultStatusOverlayOrder.where(
      (id) => !seen.contains(id),
    ),
  ];
  return sanitized;
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 保留输入顺序、剔除未知 id、去重，并把缺失的段位按默认顺序补到末尾。
List<String> _sanitizeReadingStatsSectionOrder(List<String> input) {
  final seen = <String>{};
  final sanitized = [
    for (final id in input)
      if (ReaderSettings.defaultReadingStatsSectionOrder.contains(id) &&
          seen.add(id))
        id,
    ...ReaderSettings.defaultReadingStatsSectionOrder.where(
      (id) => !seen.contains(id),
    ),
  ];
  return sanitized;
}
