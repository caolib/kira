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
    _autoScrollPause =
        (prefs.getDouble(_keyAutoScrollPause) ?? 3.0).clamp(0.5, 8.0);
    _autoScrollResume = prefs.getBool(_keyAutoScrollResume) ?? false;
    _autoScrollResumeDelay =
        (prefs.getDouble(_keyAutoScrollResumeDelay) ?? 2.0).clamp(1.0, 5.0);
    _autoScrollDistance =
        (prefs.getDouble(_keyAutoScrollDistance) ?? 0.8).clamp(0.2, 1.0);
    _continuousReading = prefs.getBool(_keyContinuousReading) ?? true;
    _viewerAutoRotateLandscape =
        prefs.getBool(_keyViewerAutoRotateLandscape) ?? false;
    final savedRotation = prefs.getInt(_keyViewerLandscapeRotation) ?? 1;
    _viewerLandscapeRotation = savedRotation < 0 ? -1 : 1;
    _imageLoadTimeout = prefs.getInt(_keyImageLoadTimeout) ?? 15;
    _imageRetryCount = prefs.getInt(_keyImageRetryCount) ?? 1;
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
}
