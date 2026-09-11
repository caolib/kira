part of '../reader_page.dart';

extension _ReaderAutoScroll on _ReaderPageState {
  /// 主开关：仅由顶部按钮调用。关闭时取消恢复计时器。
  void _setAutoScroll(bool enabled) {
    if (enabled == _autoScrollEnabled) return;
    _autoScrollEnabled = enabled;
    _autoScrollActive = enabled;
    _autoScrollGeneration++;
    _cancelAutoScrollResumeTimer();
    if (enabled) {
      _continueAutoScroll();
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
    if (mounted) _setState(() {});
  }

  /// 触摸开始（按下）：暂停滚动。自动恢复模式下取消计时器，拖动期间不计时。
  void _onAutoScrollTouchStart() {
    if (!_autoScrollEnabled) return;
    if (_user.readerAutoScrollResume) {
      _autoScrollActive = false;
      _cancelAutoScrollResumeTimer();
      if (mounted) _setState(() {});
    } else {
      _setAutoScroll(false);
    }
  }

  /// 触摸结束（抬起/取消）：自动恢复模式下开始恢复倒计时。
  void _onAutoScrollTouchEnd() {
    if (!_autoScrollEnabled || !_user.readerAutoScrollResume) return;
    if (!_autoScrollActive) _scheduleAutoScrollResume();
  }

  /// 鼠标滚轮等瞬时交互：暂停并立即开始恢复倒计时。
  void _onAutoScrollWheel() {
    if (!_autoScrollEnabled) return;
    if (_user.readerAutoScrollResume) {
      _autoScrollActive = false;
      _scheduleAutoScrollResume();
      if (mounted) _setState(() {});
    } else {
      _setAutoScroll(false);
    }
  }

  void _scheduleAutoScrollResume() {
    _cancelAutoScrollResumeTimer();
    _autoScrollResumeTimer = Timer(
      Duration(
        milliseconds: (_user.readerAutoScrollResumeDelay * 1000).round(),
      ),
      () {
        _autoScrollResumeTimer = null;
        if (!mounted ||
            !_autoScrollEnabled ||
            _isPageMode ||
            _detail == null ||
            _autoScrollPausedForOverlay) {
          return;
        }
        _autoScrollActive = true;
        _restartAutoScroll();
        _setState(() {});
      },
    );
  }

  void _cancelAutoScrollResumeTimer() {
    _autoScrollResumeTimer?.cancel();
    _autoScrollResumeTimer = null;
  }

  /// 打开覆盖层（设置面板、评论面板）时暂停自动滚动：
  /// 废弃在途的滚动回调并标记为非活跃，避免覆盖层打开期间画面继续滚动或自动恢复。
  void _pauseAutoScrollForOverlay() {
    _autoScrollGeneration++;
    _autoScrollPausedForOverlay = true;
    _autoScrollActive = false;
    _cancelAutoScrollResumeTimer();
    if (mounted) _setState(() {});
  }

  /// 覆盖层关闭后按设置恢复自动滚动。仅当自动滚动仍开启时生效。
  void _resumeAutoScrollAfterOverlay() {
    _autoScrollPausedForOverlay = false;
    if (!_autoScrollEnabled || _isPageMode || _detail == null) return;
    if (_user.readerAutoScrollResume) {
      _scheduleAutoScrollResume();
    } else {
      _autoScrollActive = true;
      _restartAutoScroll();
      if (mounted) _setState(() {});
    }
  }

  /// 废弃在途的滚动回调并立即重新开始一段。用于章节切换、设置变更、自动恢复等重启点。
  void _restartAutoScroll() {
    _autoScrollGeneration++;
    _continueAutoScroll();
  }

  void _continueAutoScroll() {
    if (!_autoScrollEnabled ||
        !_autoScrollActive ||
        _detail == null ||
        _isPageMode) {
      return;
    }
    // 没有下一章且最后一张图已进入视口：滑到底后暂停，避免无意义滚动。
    final lastChapter = _chain.last;
    if (lastChapter.next == null) {
      final positions = _itemPositionsListener.itemPositions.value;
      if (positions.isNotEmpty) {
        // 计算链中最后一张图片的列表索引
        final hasHeader = _chain.first.prev == null;
        final lastImageIndex = _continuousReading
            ? _scrollItemIndexFor(
                chainIndex: _chain.length - 1,
                page: lastChapter.contents.length,
              )
            : (hasHeader ? 1 : 0) + (_detail!.contents.length - 1);
        final isLastImageFullyVisible = positions.any((p) {
          if (p.index != lastImageIndex) return false;
          return p.itemLeadingEdge >= 0.0 && p.itemTrailingEdge <= 1.0;
        });
        if (isLastImageFullyVisible) {
          _setAutoScroll(false);
          return;
        }
      }
    }
    // 间歇式滚动：快速上滑一段距离 → 停顿阅读 → 再上滑。
    // offset 取正值即沿阅读前进方向滚动（含右到左反向模式）。
    // 用 easeOutCubic 让画面快速启动、缓缓停稳，避免匀速移动带来的眼部追踪疲劳。
    // gen 用于丢弃章节切换等在途的旧回调，避免重启后多条滚动链并行。
    final gen = _autoScrollGeneration;
    // 水平滚动模式按视口宽度计算幅度，竖向按高度，避免左右滚动时单段距离不合理。
    final viewportSize = _isHorizontalScrollMode
        ? MediaQuery.sizeOf(context).width
        : MediaQuery.sizeOf(context).height;
    _scrollOffsetController
        .animateScroll(
          offset: (viewportSize * _user.readerAutoScrollDistance).clamp(
            80.0,
            4000.0,
          ),
          duration: _ReaderPageState._autoScrollSegmentDuration,
          curve: Curves.easeOutCubic,
        )
        .then((_) {
          if (gen != _autoScrollGeneration || !_autoScrollActive) return;
          // 停顿一段时间供眼睛阅读，随后继续下一段。
          Future.delayed(
            Duration(
              milliseconds: (_user.readerAutoScrollPause * 1000).round(),
            ),
            () {
              if (gen != _autoScrollGeneration || !_autoScrollActive) return;
              _continueAutoScroll();
            },
          );
        })
        .catchError((Object _) {
          // 用户拖动或章节切换会取消动画，链条在此自然中断
        });
  }
}
