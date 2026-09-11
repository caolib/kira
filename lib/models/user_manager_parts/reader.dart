part of '../user_manager.dart';

extension UserManagerReaderPart on UserManager {
  /// 委托给 [reader]。子 store 的 notifyListeners 会经
  /// _onSubStoreChanged 转发到本 facade 的监听者。
  Future<void> setReaderMode(int mode) => reader.setMode(mode);

  Future<void> setReaderScrollDirection(int direction) async {
    _readerScrollDirection = direction;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(UserManager._keyReaderScrollDirection, direction);
    _notifyListeners();
  }

  Future<void> setReaderImageGap(double gap) async {
    _readerImageGap = gap;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(UserManager._keyReaderImageGap, gap);
    _notifyListeners();
  }

  Future<void> setReaderVolumeKey(bool enabled) async {
    _readerVolumeKey = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(UserManager._keyReaderVolumeKey, enabled);
    _notifyListeners();
  }

  Future<void> setReaderInstantPageTurn(bool enabled) async {
    _readerInstantPageTurn = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(UserManager._keyReaderInstantPageTurn, enabled);
    _notifyListeners();
  }

  Future<void> setReaderPageRTL(bool rtl) async {
    _readerPageRTL = rtl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(UserManager._keyReaderPageRTL, rtl);
    _notifyListeners();
  }

  Future<void> setReaderPageVertical(bool vertical) async {
    _readerPageVertical = vertical;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(UserManager._keyReaderPageVertical, vertical);
    _notifyListeners();
  }

  Future<void> setReaderDimming(double value) async {
    _readerDimming = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(UserManager._keyReaderDimming, value);
    _notifyListeners();
  }

  Future<void> setReaderAutoScrollEnabled(bool enabled) async {
    _readerAutoScrollEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(UserManager._keyReaderAutoScrollEnabled, enabled);
    _notifyListeners();
  }

  Future<void> setReaderAutoScrollPause(double seconds) async {
    _readerAutoScrollPause = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(UserManager._keyReaderAutoScrollPause, seconds);
    _notifyListeners();
  }

  Future<void> setReaderAutoScrollResume(bool enabled) async {
    _readerAutoScrollResume = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(UserManager._keyReaderAutoScrollResume, enabled);
    _notifyListeners();
  }

  Future<void> setReaderAutoScrollResumeDelay(double seconds) async {
    _readerAutoScrollResumeDelay = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(UserManager._keyReaderAutoScrollResumeDelay, seconds);
    _notifyListeners();
  }

  Future<void> setReaderAutoScrollDistance(double factor) async {
    _readerAutoScrollDistance = factor;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(UserManager._keyReaderAutoScrollDistance, factor);
    _notifyListeners();
  }

  Future<void> setReaderContinuousReading(bool enabled) async {
    _readerContinuousReading = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(UserManager._keyReaderContinuousReading, enabled);
    _notifyListeners();
  }

  Future<void> setReaderHorizontalImageScale(double scale) async {
    _readerHorizontalImageScale = scale.clamp(0.7, 1.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(
      UserManager._keyReaderHorizontalImageScale,
      _readerHorizontalImageScale,
    );
    _notifyListeners();
  }

  Future<void> setImageViewerAutoRotateLandscape(bool enabled) async {
    if (_imageViewerAutoRotateLandscape == enabled) return;
    _imageViewerAutoRotateLandscape = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      UserManager._keyImageViewerAutoRotateLandscape,
      enabled,
    );
    _notifyListeners();
  }

  Future<void> setImageViewerLandscapeRotation(int rotation) async {
    final nextRotation = rotation < 0 ? -1 : 1;
    if (_imageViewerLandscapeRotation == nextRotation) return;
    _imageViewerLandscapeRotation = nextRotation;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      UserManager._keyImageViewerLandscapeRotation,
      nextRotation,
    );
    _notifyListeners();
  }

  Future<void> setImageLoadTimeout(int seconds) async {
    _imageLoadTimeout = seconds;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(UserManager._keyImageLoadTimeout, seconds);
    _notifyListeners();
  }

  Future<void> setImageRetryCount(int count) async {
    _imageRetryCount = count;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(UserManager._keyImageRetryCount, count);
    _notifyListeners();
  }

  Future<void> setCommentCompactLayout(bool compact) async {
    _commentCompactLayout = compact;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(UserManager._keyCommentCompactLayout, compact);
    _notifyListeners();
  }

  Future<void> setCommentShowAvatar(bool enabled) async {
    _commentShowAvatar = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(UserManager._keyCommentShowAvatar, enabled);
    _notifyListeners();
  }

  Future<void> setCommentShowUserName(bool enabled) async {
    _commentShowUserName = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(UserManager._keyCommentShowUserName, enabled);
    _notifyListeners();
  }

  Future<void> setCommentShowTime(bool enabled) async {
    _commentShowTime = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(UserManager._keyCommentShowTime, enabled);
    _notifyListeners();
  }

  /// 委托给 [comment]。子 store 的 notifyListeners 会经
  /// _onSubStoreChanged 转发到本 facade 的监听者。
  Future<void> setCommentFontScale(double scale) => comment.setFontScale(scale);

  Future<void> setCommentPreload(bool enabled) async {
    _commentPreload = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(UserManager._keyCommentPreload, enabled);
    _notifyListeners();
  }

  Future<void> setCommentAutoLoadAll(bool enabled) async {
    _commentAutoLoadAll = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(UserManager._keyCommentAutoLoadAll, enabled);
    _notifyListeners();
  }
}
