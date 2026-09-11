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
    _chapterImageStarts.clear();
    _chapterScrollStarts.clear();
    _cachedChainImageCount = 0;

    if (_chain.isEmpty) {
      _scrollItems = const [];
      return;
    }

    final items = <_ScrollItem>[];
    final hasHeader = _chain.first.prev == null;
    if (hasHeader) {
      items.add(_ScrollItem.header());
    } else if (_continuousReading) {
      // 链首之上还有上一话：头部触发区，上滑进入视口即预取拼接上一话。
      items.add(_ScrollItem.prevHead());
    }

    var imageCursor = 0;
    if (_continuousReading) {
      for (var ci = 0; ci < _chain.length; ci++) {
        final chapter = _chain[ci];
        _chapterImageStarts.add(imageCursor);
        _chapterScrollStarts.add(items.length);
        for (var i = 0; i < chapter.contents.length; i++) {
          items.add(_ScrollItem.image(chapter, i, imageCursor + i));
        }
        imageCursor += chapter.contents.length;

        final isLast = ci == _chain.length - 1;
        if (isLast) {
          if (chapter.next == null) {
            items.add(_ScrollItem.tail());
          } else {
            items.add(_ScrollItem.loadMore());
          }
        } else {
          items.add(_ScrollItem.chapterDivider(chapter));
        }
      }
    } else {
      final chapter = _detail ?? _chain.first;
      _chapterImageStarts.add(0);
      _chapterScrollStarts.add(items.length);
      for (var i = 0; i < chapter.contents.length; i++) {
        items.add(_ScrollItem.image(chapter, i, i));
      }
      imageCursor = chapter.contents.length;
      items.add(_ScrollItem.tail());
    }

    _cachedChainImageCount = imageCursor;
    _scrollItems = items;
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

  /// 按「前1后1」窗口裁剪连续阅读链，限制长会话内存与列表规模。
  /// 返回是否实际裁剪。调用方负责随后 setState。
  bool _pruneChainWindow() {
    if (!_continuousReading || _chain.isEmpty) return false;

    final behindRemoveCount =
        _chainIndex - _ReaderPageState._maxChainChaptersBehind;
    final maxKeepIndex = _chainIndex + _ReaderPageState._maxChainChaptersAhead;
    final aheadRemoveCount = _chain.length - 1 - maxKeepIndex;

    if (behindRemoveCount <= 0 && aheadRemoveCount <= 0) return false;

    // 在改动链结构前记录视口锚点，裁剪后按相同 alignment 还原，避免顶对齐跳动。
    final viewportAnchor = (!_isPageMode && behindRemoveCount > 0)
        ? _captureLeadingScrollAnchor()
        : null;
    final removedLeadingScrollItems = behindRemoveCount > 0
        ? _leadingScrollItemCount(behindRemoveCount)
        : 0;

    final prunedChapters = <ChapterDetail>[];
    var shifted = false;
    if (aheadRemoveCount > 0) {
      prunedChapters.addAll(_chain.sublist(_chain.length - aheadRemoveCount));
      _chain.removeRange(_chain.length - aheadRemoveCount, _chain.length);
    }
    if (behindRemoveCount > 0) {
      prunedChapters.addAll(_chain.sublist(0, behindRemoveCount));
      _chain.removeRange(0, behindRemoveCount);
      _chainIndex -= behindRemoveCount;
      shifted = true;
    }

    _discardPrunedChapters(prunedChapters);
    if (shifted) {
      // 全局图片索引会因头部裁剪而重编号，清空以全局索引为键的重试状态。
      _imageReloadVersions.clear();
      _imageRetryCounts.clear();
      _imageRetryTokens.clear();
    }

    _rebuildChainStructure();

    // 仅头部裁剪会移动当前项索引，需要重建阅读控件对齐位置。
    // 只裁链尾时保持现有滚动/翻页位置。
    if (shifted) {
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
          final maxIndex = _scrollItems.isEmpty ? 0 : _scrollItems.length - 1;
          _scrollModeInitialIndex =
              (viewportAnchor.index - removedLeadingScrollItems).clamp(
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
        if (_autoScrollEnabled && !_isPageMode) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _autoScrollEnabled && !_isPageMode) {
              _restartAutoScroll();
            }
          });
        }
      }
    }
    return true;
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

  /// 裁剪链头 [chapterCount] 章时，滚动列表会从开头删掉的 item 数量。
  /// 必须在 `_rebuildChainStructure` 之前、基于旧结构计算。
  int _leadingScrollItemCount(int chapterCount) {
    if (chapterCount <= 0) return 0;
    if (_chapterScrollStarts.isEmpty) {
      _rebuildChainStructure();
    }
    if (_chapterScrollStarts.isEmpty) return 0;
    if (chapterCount >= _chapterScrollStarts.length) {
      return _scrollItems.length;
    }
    return _chapterScrollStarts[chapterCount];
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
      final startBounds = _chapterScrollStarts.isEmpty
          ? 0
          : _chapterScrollStarts[_chainIndex.clamp(
              0,
              _chapterScrollStarts.length - 1,
            )];
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
  bool _syncActiveChapterFromGlobal(int chapterIndex) {
    if (chapterIndex < 0 || chapterIndex >= _chain.length) return false;
    if (chapterIndex == _chainIndex) return false;
    final newDetail = _chain[chapterIndex];
    _chainIndex = chapterIndex;
    _detail = newDetail;
    _currentUuid = newDetail.uuid;
    // 章节切换后延后裁剪窗口，避免滚动过程中同步重建列表。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_pruneChainWindow()) {
        _setState(() {});
      }
    });
    return true;
  }
}
