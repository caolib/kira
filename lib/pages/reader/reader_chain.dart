part of '../reader_page.dart';

extension _ReaderChain on _ReaderPageState {
  /// 链中所有章节图片的累计数量（用于渲染 PageView / 滚动列表的总条目数）。
  int get _chainImageCount => _cachedChainImageCount;

  /// 全局图片索引 -> (章节索引, 章节内图片索引)。
  (int chapterIndex, int imageIndex) _resolveChainImage(int globalIndex) {
    if (_chain.isEmpty) return (0, 0);
    if (_chapterImageStarts.isEmpty) {
      _rebuildChainStructure();
    }
    if (globalIndex <= 0) return (0, 0);
    if (globalIndex >= _cachedChainImageCount) {
      return (_chain.length - 1, _chain.last.contents.length - 1);
    }
    final chapterIndex = _upperBoundStarts(_chapterImageStarts, globalIndex);
    return (chapterIndex, globalIndex - _chapterImageStarts[chapterIndex]);
  }

  /// 章节索引在链中的起始全局图片索引。
  int _chainChapterStart(int chapterIndex) {
    if (_chapterImageStarts.isEmpty) {
      _rebuildChainStructure();
    }
    if (chapterIndex <= 0) return 0;
    if (chapterIndex >= _chapterImageStarts.length) {
      return _cachedChainImageCount;
    }
    return _chapterImageStarts[chapterIndex];
  }

  /// 当前滚动列表的总条目数。
  int get _scrollItemCount {
    if (_scrollItems.isEmpty && _chain.isNotEmpty) {
      _rebuildChainStructure();
    }
    return _scrollItems.length;
  }

  /// 在非降 starts 中找最后一个 `starts[i] <= value` 的下标。
  int _upperBoundStarts(List<int> starts, int value) {
    var lo = 0;
    var hi = starts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (starts[mid] <= value) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// 根据章节链重建滚动 item 列表与索引缓存。
  void _rebuildChainStructure() {
    final layout = buildChainScrollLayout(
      chain: _chain,
      continuousReading: _continuousReading,
      currentChapter: _detail,
    );
    _chapterImageStarts
      ..clear()
      ..addAll(layout.chapterImageStarts);
    _chapterScrollStarts
      ..clear()
      ..addAll(layout.chapterScrollStarts);
    _cachedChainImageCount = layout.imageCount;
    _scrollItems = layout.items;
  }

  /// 清理被裁剪章节关联的缓存状态。
  void _discardPrunedChapters(List<ChapterDetail> prunedChapters) {
    for (final chapter in prunedChapters) {
      _commentCache.remove(chapter.uuid);
      _commentTotalCache.remove(chapter.uuid);
      for (final source in chapter.contents) {
        _imageNaturalSizes.remove(source);
      }
    }
  }

  /// 滚动列表此刻能否安全重建：没有拖动、惯性，也没有在拖进度条。
  bool get _canRebuildScrollList => !_scrollInProgress && !_isDraggingSlider;

  /// 按「前1后1」窗口裁剪连续阅读链，限制长会话内存与列表规模。
  /// 返回是否实际裁剪。调用方负责随后 setState。
  ///
  /// 链尾裁剪不改变任何现存 item 的索引，随时可做。链首裁剪会让索引整体前移，
  /// 只能靠「重建列表 + 视口锚点还原」补偿，因此仅在 [_canRebuildScrollList]
  /// 时执行；滚动途中改为登记 [_chainPrunePending]，等列表静止后由
  /// [_flushPendingChainPrune] 补做——惯性/拖动途中重建会打断手势，而且锚点
  /// 取自上一帧的位置快照，这一帧的位移会变成肉眼可见的跳变。
  bool _pruneChainWindow() {
    if (!_continuousReading || _chain.isEmpty) return false;

    final maxKeepIndex = _chainIndex + _ReaderPageState._maxChainChaptersAhead;
    final aheadRemoveCount = _chain.length - 1 - maxKeepIndex;
    final behindRemoveCount =
        _chainIndex - _ReaderPageState._maxChainChaptersBehind;
    final pruneBehind = behindRemoveCount > 0 && _canRebuildScrollList;
    if (behindRemoveCount > 0 && !pruneBehind) _chainPrunePending = true;
    if (aheadRemoveCount <= 0 && !pruneBehind) return false;

    // 改动链结构前固定视口锚点与「当前章起始 item 索引」，重建后按两者差值
    // 还原。差值不能换成「被删掉的 item 数」：链首的 header/prevHead 会被新
    // 链首的同类占位项替换（数量不变），按删除数折算会多减一项，还原位置整整
    // 偏移一个 item 的高度。
    final viewportAnchor = pruneBehind && !_isPageMode
        ? _captureLeadingScrollAnchor()
        : null;
    final anchorBase = pruneBehind ? _currentChapterScrollStart() : 0;

    final prunedChapters = <ChapterDetail>[];
    if (aheadRemoveCount > 0) {
      prunedChapters.addAll(_chain.sublist(_chain.length - aheadRemoveCount));
      _chain.removeRange(_chain.length - aheadRemoveCount, _chain.length);
    }
    if (pruneBehind) {
      prunedChapters.addAll(_chain.sublist(0, behindRemoveCount));
      _chain.removeRange(0, behindRemoveCount);
      _chainIndex -= behindRemoveCount;
      // 全局图片索引会因头部裁剪而重编号，清空以全局索引为键的重试状态。
      _imageReloadVersions.clear();
      _imageRetryCounts.clear();
      _imageRetryTokens.clear();
    }

    _discardPrunedChapters(prunedChapters);
    _rebuildChainStructure();

    // 仅头部裁剪会移动当前项索引，需要重建阅读控件对齐位置。
    // 只裁链尾时保持现有滚动/翻页位置。
    if (!pruneBehind) return true;

    final page = _currentPage.clamp(
      1,
      _detail?.contents.isNotEmpty == true ? _detail!.contents.length : 1,
    );
    if (_isPageMode) {
      final initialIndex = _chainChapterStart(_chainIndex) + (page - 1);
      final oldController = _pageController;
      _pageController = PageController(initialPage: initialIndex);
      _bumpScrollWidgetVersion();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oldController.dispose();
      });
    } else if (_chain.isNotEmpty) {
      if (viewportAnchor != null) {
        final shift = _currentChapterScrollStart() - anchorBase;
        final maxIndex = _scrollItems.isEmpty ? 0 : _scrollItems.length - 1;
        _scrollModeInitialIndex = (viewportAnchor.index + shift).clamp(
          0,
          maxIndex,
        );
        _scrollModeInitialAlignment = viewportAnchor.alignment;
      } else {
        _scrollModeInitialIndex = _scrollItemIndexFor(
          chainIndex: _chainIndex,
          page: page,
        );
        _scrollModeInitialAlignment = 0.0;
      }
      _bumpScrollWidgetVersion();
      // 列表重建会打断自动滚动，裁剪后按需恢复。
      if (_autoScrollEnabled) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _autoScrollEnabled && !_isPageMode) {
            _restartAutoScroll();
          }
        });
      }
    }
    return true;
  }

  /// 列表静止后补做被推迟的链首裁剪。
  ///
  /// 不在通知回调里直接裁剪，而是排到本帧结束后：
  /// - `ScrollEndNotification` 可能在布局阶段派发（越界回弹收敛时），此刻
  ///   setState 会撞上「build 期间 markNeedsBuild」；
  /// - 抬手与最后一次位移可能同批到达，通知派发时 item 位置快照还停留在上
  ///   一帧，按它还原锚点会差出这段位移。等本帧布局与位置上报都结束再裁剪，
  ///   锚点即真实当前位置。
  void _flushPendingChainPrune() {
    if (!_chainPrunePending) return;
    // addPostFrameCallback 自身不会调度新帧，静止时可能一直没有下一帧。
    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_chainPrunePending || !_canRebuildScrollList) return;
      _chainPrunePending = false;
      if (_pruneChainWindow()) _setState(() {});
    });
  }

  /// 视口中最靠近起始侧的可见项（leadingEdge 最小）。
  ({int index, double alignment})? _captureLeadingScrollAnchor() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return null;

    ItemPosition? leadingPosition;
    for (final position in positions) {
      if (leadingPosition == null ||
          position.itemLeadingEdge < leadingPosition.itemLeadingEdge) {
        leadingPosition = position;
      }
    }
    if (leadingPosition == null) return null;
    return (
      index: leadingPosition.index,
      alignment: leadingPosition.itemLeadingEdge,
    );
  }

  /// 当前章第一张图在滚动 item 列表中的索引（结构未建时先建）。
  ///
  /// 链首/链尾增删章前后各取一次，两者之差就是现存 item 的真实索引位移——
  /// 它天然排除了「链首占位项被替换而非删除」这类结构差异。
  int _currentChapterScrollStart() {
    if (_chapterScrollStarts.isEmpty) {
      _rebuildChainStructure();
    }
    if (_chapterScrollStarts.isEmpty) return 0;
    return _chapterScrollStarts[_chainIndex.clamp(
      0,
      _chapterScrollStarts.length - 1,
    )];
  }

  void _goChapter(String? uuid) {
    if (uuid == null) return;
    if (_currentUuid != uuid) {
      _clearCommentCache();
    }
    _currentUuid = uuid;
    _loadChapter();
  }

  /// 连续阅读：在链尾追加下一话。仅滚动/翻页构建逻辑需要在末尾追加更多内容时调用。
  /// 加载完成后触发 setState，由 PageView/ScrollablePositionedList 增量渲染新页。
  Future<void> _appendNextChapterToChain() async {
    if (_loadingNextChainChapter) return;
    final lastChapter = _chain.last;
    final nextUuid = lastChapter.next;
    if (nextUuid == null) return;
    _loadingNextChainChapter = true;
    try {
      final next =
          (await _downloads.getDownloadedChapterDetail(
            widget.pathWord,
            nextUuid,
          )) ??
          await _api.manga.getChapterDetail(widget.pathWord, nextUuid);
      if (next.contents.isEmpty) {
        throw StateError('Chapter has no readable pages');
      }
      if (!mounted) return;
      _setState(() {
        _chain.add(next);
        _loadingNextChainChapter = false;
        _rebuildChainStructure();
        // 链尾增长：登记新章图片归属（供阅读统计埋点反查）
        _registerChapterStatsUrls(next);
        // 链尾增长后按「前1后1」窗口裁剪，避免长会话无限膨胀。
        _pruneChainWindow();
      });
      // 追加后立即预加载该话评论，使分隔区评论按钮能显示数量
      if (_user.commentPreload) unawaited(_preloadComments(chapter: next));
    } catch (_) {
      _loadingNextChainChapter = false;
      // 追加失败保持链不变，用户可手动重试（继续翻页会再次触发）
    }
  }

  /// 连续阅读：在链首插入上一话。滚动模式头部触发区上滑 / 翻页模式链首回翻
  /// 需要拼接上一话时调用。返回是否成功拼接（链首即所取上一话）。
  /// 拼接会移动列表头部索引：滚动模式按视口锚点还原位置，翻页模式重建
  /// PageController 指向原内容，用户所在画面保持不动。
  Future<bool> _prependPrevChapterToChain() async {
    if (_loadingPrevChainChapter || _chain.isEmpty) return false;
    final firstChapter = _chain.first;
    final prevUuid = firstChapter.prev;
    if (prevUuid == null) return false;
    _setState(() {
      // 立即反馈：触发区切换为「正在加载上一话…」，避免取数期间无任何提示。
      _loadingPrevChainChapter = true;
    });
    try {
      final prev =
          (await _downloads.getDownloadedChapterDetail(
            widget.pathWord,
            prevUuid,
          )) ??
          await _api.manga.getChapterDetail(widget.pathWord, prevUuid);
      if (prev.contents.isEmpty) {
        throw StateError('Chapter has no readable pages');
      }
      if (!mounted) return false;
      // 等待期间链首可能已被裁剪/切换，章节对不上时放弃本次拼接。
      if (_chain.isEmpty || _chain.first.uuid != firstChapter.uuid) {
        _loadingPrevChainChapter = false;
        _setState(() {});
        return false;
      }
      // 改动链结构前记录视口锚点与当前章起始索引，重建后按差值还原。
      final viewportAnchor = !_isPageMode
          ? _captureLeadingScrollAnchor()
          : null;
      final startBounds = _currentChapterScrollStart();
      _setState(() {
        _chain.insert(0, prev);
        _chainIndex += 1;
        _loadingPrevChainChapter = false;
        _rebuildChainStructure();
        // 链首增长：登记新章图片归属（供阅读统计埋点反查）
        _registerChapterStatsUrls(prev);
      });
      if (_isPageMode) {
        final page = _currentPage.clamp(
          1,
          _detail?.contents.isNotEmpty == true ? _detail!.contents.length : 1,
        );
        final initialIndex = _chainChapterStart(_chainIndex) + (page - 1);
        final oldController = _pageController;
        _pageController = PageController(initialPage: initialIndex);
        _bumpScrollWidgetVersion();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          oldController.dispose();
        });
      } else if (_chain.isNotEmpty) {
        final shift = _chapterScrollStarts[_chainIndex] - startBounds;
        if (viewportAnchor != null) {
          final maxIndex = _scrollItems.isEmpty ? 0 : _scrollItems.length - 1;
          _scrollModeInitialIndex = (viewportAnchor.index + shift).clamp(
            0,
            maxIndex,
          );
          _scrollModeInitialAlignment = viewportAnchor.alignment;
        } else {
          _scrollModeInitialIndex = _scrollItemIndexFor(
            chainIndex: _chainIndex,
            page: _currentPage,
          );
          _scrollModeInitialAlignment = 0.0;
        }
        _bumpScrollWidgetVersion();
      }
      // 拼接后预加载该话评论，使分隔区评论按钮能显示数量
      if (_user.commentPreload) unawaited(_preloadComments(chapter: prev));
      return true;
    } catch (_) {
      _loadingPrevChainChapter = false;
      if (mounted) _setState(() {});
      // 拼接失败保持链不变：滚动模式可继续上滑重试；翻页模式由调用方降级整章跳转。
      return false;
    }
  }

  /// 根据全局图片位置更新当前所在章节，用于导航栏显示与历史记录。
  /// 返回章节是否发生变化（需要刷新评论缓存等）。
  ///
  /// 窗口裁剪的时机由阅读模式决定，不在此处统一处理：
  /// - 翻页模式仍延后一帧——各调用点紧接着要用「裁剪前」算出的全局页索引跳
  ///   PageController，同步裁剪会让它失效；调用点的 setState 保证有帧可等。
  /// - 滚动模式由 `_onItemPositionsChangedContinuous` 在同一帧内裁剪——延后
  ///   一帧会让视口锚点落后一帧的位移，还原时反而跳一下。
  bool _syncActiveChapterFromGlobal(int chapterIndex) {
    if (chapterIndex < 0 || chapterIndex >= _chain.length) return false;
    if (chapterIndex == _chainIndex) return false;
    final newDetail = _chain[chapterIndex];
    _chainIndex = chapterIndex;
    _detail = newDetail;
    _currentUuid = newDetail.uuid;
    if (_isPageMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_pruneChainWindow()) {
          _setState(() {});
        }
      });
    }
    return true;
  }
}
