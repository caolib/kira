part of '../user_manager.dart';

extension UserManagerReaderPart on UserManager {
  /// 委托给 [reader]。子 store 的 notifyListeners 会经
  /// _onSubStoreChanged 转发到本 facade 的监听者。
  Future<void> setReaderMode(int mode) => reader.setMode(mode);

  Future<void> setReaderScrollDirection(int direction) =>
      reader.setScrollDirection(direction);

  Future<void> setReaderImageGap(double gap) => reader.setImageGap(gap);

  Future<void> setReaderVolumeKey(bool enabled) => reader.setVolumeKey(enabled);

  Future<void> setReaderInstantPageTurn(bool enabled) =>
      reader.setInstantPageTurn(enabled);

  Future<void> setReaderPageRTL(bool rtl) => reader.setPageRTL(rtl);

  Future<void> setReaderPageVertical(bool vertical) =>
      reader.setPageVertical(vertical);

  Future<void> setReaderDimming(double value) => reader.setDimming(value);

  Future<void> setReaderAutoScrollEnabled(bool enabled) =>
      reader.setAutoScrollEnabled(enabled);

  Future<void> setReaderAutoScrollPause(double seconds) =>
      reader.setAutoScrollPause(seconds);

  Future<void> setReaderAutoScrollResume(bool enabled) =>
      reader.setAutoScrollResume(enabled);

  Future<void> setReaderAutoScrollResumeDelay(double seconds) =>
      reader.setAutoScrollResumeDelay(seconds);

  Future<void> setReaderAutoScrollDistance(double factor) =>
      reader.setAutoScrollDistance(factor);

  Future<void> setReaderContinuousReading(bool enabled) =>
      reader.setContinuousReading(enabled);

  Future<void> setReaderHorizontalImageScale(double scale) async {
    _readerHorizontalImageScale = scale.clamp(0.7, 1.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(
      UserManager._keyReaderHorizontalImageScale,
      _readerHorizontalImageScale,
    );
    _notifyListeners();
  }

  Future<void> setImageViewerAutoRotateLandscape(bool enabled) =>
      reader.setViewerAutoRotateLandscape(enabled);

  Future<void> setImageViewerLandscapeRotation(int rotation) =>
      reader.setViewerLandscapeRotation(rotation);

  Future<void> setImageLoadTimeout(int seconds) =>
      reader.setImageLoadTimeout(seconds);

  Future<void> setImageRetryCount(int count) =>
      reader.setImageRetryCount(count);

  Future<void> setCommentCompactLayout(bool compact) =>
      comment.setCompactLayout(compact);

  Future<void> setCommentShowAvatar(bool enabled) =>
      comment.setShowAvatar(enabled);

  Future<void> setCommentShowUserName(bool enabled) =>
      comment.setShowUserName(enabled);

  Future<void> setCommentShowTime(bool enabled) => comment.setShowTime(enabled);

  /// 委托给 [comment]。子 store 的 notifyListeners 会经
  /// _onSubStoreChanged 转发到本 facade 的监听者。
  Future<void> setCommentFontScale(double scale) => comment.setFontScale(scale);

  Future<void> setCommentPreload(bool enabled) => comment.setPreload(enabled);

  Future<void> setCommentInitialPages(int pages) =>
      comment.setInitialPages(pages);
}
