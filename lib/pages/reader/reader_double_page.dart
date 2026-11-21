part of '../reader_page.dart';

/// 双页阅读：翻页模式下每屏并排显示同一话的两页，一次翻过一个跨页。
///
/// 只在横向翻页生效。竖排（上到下）翻页时两页只能上下堆叠，没有并排
/// 阅读的意义，因此回退为单页；滚动模式不受影响。
extension _ReaderDoublePage on _ReaderPageState {
  /// 当前是否真正按双页渲染（设置开启 + 翻页模式 + 非竖排）。
  bool get _isDoublePageMode {
    return _isPageMode && _user.readerDoublePage && !_isVerticalPageMode;
  }

  /// 章节链的跨页分组，按链结构 + 「首图单页」设置缓存。
  ///
  /// 链会在连续阅读中追加/裁剪章节，键取各章页数之和即可命中变化。
  DoublePageLayout _doublePageLayout() {
    final pageCounts = [for (final chapter in _chain) chapter.contents.length];
    final signature = Object.hash(
      Object.hashAll(pageCounts),
      _user.readerDoublePageCoverAlone,
    );
    final cached = _doublePageLayoutCache;
    if (cached != null && _doublePageLayoutSignature == signature) {
      return cached;
    }
    final layout = DoublePageLayout.fromPageCounts(
      pageCounts,
      coverAlone: _user.readerDoublePageCoverAlone,
    );
    _doublePageLayoutCache = layout;
    _doublePageLayoutSignature = signature;
    return layout;
  }

  /// 当前页所在的跨页序号。
  int _currentSpreadIndex(DoublePageLayout layout) {
    return layout.spreadIndexOf(_chainIndex, _currentPage - 1);
  }

  /// 翻页控制器索引：单页模式是全局页索引，双页模式是全局跨页序号。
  /// 所有「重建 PageController 指向当前页」的调用点都走这里，
  /// 切换双页设置后位置才不会跳。
  int _pageControllerIndexFor(int chapterIndex, int imageIndex) {
    if (_isDoublePageMode) {
      return _doublePageLayout().spreadIndexOf(chapterIndex, imageIndex);
    }
    return _chainChapterStart(chapterIndex) + imageIndex;
  }

  /// 切到指定跨页：同步当前章节、页码、历史与控制器位置。
  void _applySpread(int spreadIndex, [DoublePageLayout? layout]) {
    final target = layout ?? _doublePageLayout();
    if (target.spreadCount <= 0) return;
    final anchor = target.spreadStart(spreadIndex);
    final chapterChanged = _syncActiveChapterFromGlobal(anchor.chapterIndex);
    _setState(() {
      _currentPage = anchor.imageIndex + 1;
      // 换页后新页面没有放大，恢复翻页手势。
      _pageImageZoomed = false;
    });
    _jumpPageControllerTo(spreadIndex);
    _saveReadingHistory();
    _preloadChainImages(anchor.chapterIndex, anchor.imageIndex, range: 3);
    if (chapterChanged) _preloadComments();
  }

  void _goToSpread(int spreadIndex) {
    final layout = _doublePageLayout();
    if (layout.spreadCount <= 0) return;
    _applySpread(spreadIndex.clamp(0, layout.spreadCount - 1), layout);
  }

  /// 前进一个跨页；链尾还有下一话时追加后跳到其首页。
  void _nextSpread() {
    if (_detail == null) return;
    final layout = _doublePageLayout();
    final current = _currentSpreadIndex(layout);
    if (current + 1 < layout.spreadCount) {
      _goToSpread(current + 1);
      return;
    }
    final nextUuid = _chain.last.next;
    if (nextUuid != null) {
      if (_loadingNextChainChapter) {
        showToast(
          context,
          AppLocalizations.of(context)!.readerLoadingNextChapter,
        );
        return;
      }
      unawaited(
        _appendNextChapterToChain().then((_) {
          if (!mounted) return;
          final newChapterIndex = _chain.length - 1;
          final nextLayout = _doublePageLayout();
          final target = nextLayout.spreadIndexOf(newChapterIndex, 0);
          _syncActiveChapterFromGlobal(newChapterIndex);
          _setState(() {
            _currentPage = 1;
            _pageImageZoomed = false;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _jumpPageControllerTo(target);
          });
          _saveReadingHistory();
        }),
      );
      return;
    }
    // 最后一话：翻到末尾空白页，由 onPageChanged 触发返回目录。
    _jumpPageControllerTo(layout.spreadCount);
  }

  /// 后退一个跨页；链首之前还有上一话时拼接后跳到其末个跨页。
  void _prevSpread() {
    if (_detail == null) return;
    final layout = _doublePageLayout();
    final current = _currentSpreadIndex(layout);
    if (current > 0) {
      _goToSpread(current - 1);
      return;
    }
    final prevUuid = _chain.first.prev;
    if (prevUuid == null) {
      showToast(context, AppLocalizations.of(context)!.readerNoPreviousChapter);
      return;
    }
    if (_loadingPrevChainChapter) {
      showToast(
        context,
        AppLocalizations.of(context)!.readerLoadingPrevChapter,
      );
      return;
    }
    unawaited(
      _prependPrevChapterToChain().then((prepended) {
        if (!mounted) return;
        if (!prepended) {
          // 拼接失败：降级为整章跳转（重新加载）。
          _goChapter(prevUuid);
          return;
        }
        final prevLayout = _doublePageLayout();
        final targetSpread = prevLayout.spreadsInChapter(0) - 1;
        if (targetSpread < 0) return;
        final anchor = prevLayout.spreadStart(targetSpread);
        _syncActiveChapterFromGlobal(anchor.chapterIndex);
        _setState(() {
          _currentPage = anchor.imageIndex + 1;
          _pageImageZoomed = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _jumpPageControllerTo(targetSpread);
        });
        _saveReadingHistory();
      }),
    );
  }

  Widget _buildDoublePageSpreadMode() {
    final instantTurn = _user.readerInstantPageTurn;
    final turnGesturesLocked = _pageImageZoomed;
    final horizontalDrag = instantTurn && !turnGesturesLocked;
    final layout = _doublePageLayout();
    final totalSpreads = layout.spreadCount;
    // 最后一话无下一话时，末尾追加一个空白跨页用于返回目录。
    final hasEndBlank = _chain.last.next == null;
    final itemCount = totalSpreads + (hasEndBlank ? 1 : 0);
    final pageView = NotificationListener<ScrollNotification>(
      onNotification: (n) {
        _recordFlingBrakeScroll(n);
        if (n is OverscrollNotification && n.overscroll < 0) {
          _maybePrependPrevForPageMode();
        }
        return false;
      },
      child: GestureDetector(
        onTapUp: (details) => _handlePageModeTapAt(details.globalPosition),
        onHorizontalDragStart: horizontalDrag ? _onInstantTurnDragStart : null,
        onHorizontalDragUpdate: horizontalDrag
            ? _onInstantTurnDragUpdate
            : null,
        onHorizontalDragEnd: horizontalDrag ? _onInstantTurnDragEnd : null,
        onHorizontalDragCancel: horizontalDrag
            ? _onInstantTurnDragCancel
            : null,
        child: PageView.builder(
          key: ValueKey('page-double-$_scrollWidgetVersion'),
          controller: _pageController,
          reverse: _user.readerScrollDirection == 1,
          allowImplicitScrolling: true,
          physics: instantTurn || turnGesturesLocked
              ? const NeverScrollableScrollPhysics()
              : null,
          itemCount: itemCount,
          onPageChanged: (index) => _onSpreadChanged(
            index,
            layout: layout,
            totalSpreads: totalSpreads,
            hasEndBlank: hasEndBlank,
          ),
          itemBuilder: (_, i) => _buildSpreadItem(
            i,
            layout: layout,
            totalSpreads: totalSpreads,
            hasEndBlank: hasEndBlank,
          ),
        ),
      ),
    );
    return Listener(
      onPointerDown: (_) => _flingBrakeGuard.onPointerDown(DateTime.now()),
      child: pageView,
    );
  }

  void _onSpreadChanged(
    int index, {
    required DoublePageLayout layout,
    required int totalSpreads,
    required bool hasEndBlank,
  }) {
    if (hasEndBlank && index == totalSpreads) {
      if (!_autoAdvancingChapter) {
        _autoAdvancingChapter = true;
        _exitToCatalog();
      }
      return;
    }
    final pages = layout.pagesInSpread(index);
    if (pages.isEmpty) return;
    final anchor = pages.first;
    final chapterChanged = _syncActiveChapterFromGlobal(anchor.chapterIndex);
    _setState(() {
      // 页码沿用「跨页首页」，书签、历史、底部进度条口径保持一致。
      _currentPage = anchor.imageIndex + 1;
      _pageImageZoomed = false;
      if (!_isDraggingSlider) {
        _showToolbar = false;
        _systemUi.setToolbarVisible(false);
      }
    });
    _saveReadingHistory();
    _preloadChainImages(anchor.chapterIndex, anchor.imageIndex, range: 3);
    final tail = pages.last;
    if (tail.chapterIndex == _chain.length - 1 &&
        tail.imageIndex >= _chain.last.contents.length - 2 &&
        _chain.last.next != null &&
        !_loadingNextChainChapter) {
      _appendNextChapterToChain();
    }
    if (chapterChanged) {
      _preloadComments();
    }
    _maybePrependPrevForPageMode();
  }

  Widget _buildSpreadItem(
    int index, {
    required DoublePageLayout layout,
    required int totalSpreads,
    required bool hasEndBlank,
  }) {
    if (hasEndBlank && index == totalSpreads) {
      return const SizedBox.expand();
    }
    final pages = layout.pagesInSpread(index);
    if (pages.isEmpty) return const SizedBox.expand();
    final lastAnchor = pages.last;
    final chapter = _chain[lastAnchor.chapterIndex];
    final isChapterLastPage =
        lastAnchor.imageIndex == chapter.contents.length - 1;
    final zoomActive = index == _currentSpreadIndex(layout);
    final spread = _buildSpreadContent(pages, zoomActive: zoomActive);
    if (!isChapterLastPage) return spread;
    // 每章末页均显示底部操作（目录/评论/下一章），便于随时切换。
    return Column(
      children: [
        Expanded(child: spread),
        _PageModeEndActions(
          hasNext: chapter.next != null,
          commentCount: _commentCountFor(chapter),
          onCatalog: _exitToCatalog,
          onComments: () => _showChapterComments(chapter: chapter),
          onNextChapter: chapter.next != null
              ? () => _goChapter(chapter.next)
              : null,
        ),
      ],
    );
  }

  /// 一个跨页的内容：两页并排，按阅读方向决定左右顺序。
  ///
  /// 右到左（日漫习惯）时前一页在右、后一页在左；只有一页时铺满整屏居中，
  /// 与单页模式观感一致。
  ///
  /// 两页按「同一高度 + 各自真实宽高比」定宽，因此左右紧贴、中间不留黑缝，
  /// 观感是一幅完整跨页；两页总宽超出屏幕时按宽度等比缩小，仍然贴合。
  Widget _buildSpreadContent(
    List<DoublePageAnchor> pages, {
    required bool zoomActive,
  }) {
    if (pages.length == 1) {
      final anchor = pages.first;
      return Center(
        child: _buildReaderImageGesture(
          _chain[anchor.chapterIndex],
          anchor.imageIndex,
          retryKey: _spreadImageRetryKey(anchor),
          zoomActive: zoomActive,
        ),
      );
    }
    final ordered = _user.readerScrollDirection == 1
        ? pages.reversed.toList()
        : pages;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;
        final aspects = [
          for (final anchor in ordered) _spreadAspectRatio(anchor),
        ];
        final totalAspect = aspects.fold<double>(
          0,
          (sum, aspect) => sum + aspect,
        );
        if (totalAspect <= 0) return const SizedBox.expand();
        // 两页等高 → 总宽 = 高度 × 宽高比之和；取能同时装下两页的缩放。
        final height = math.min(maxHeight, maxWidth / totalAspect);
        if (height <= 0) return const SizedBox.expand();
        return Center(
          child: SizedBox(
            height: height,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < ordered.length; i++)
                  SizedBox(
                    width: height * aspects[i],
                    height: height,
                    child: _buildReaderImageGesture(
                      _chain[ordered[i].chapterIndex],
                      ordered[i].imageIndex,
                      retryKey: _spreadImageRetryKey(ordered[i]),
                      zoomActive: zoomActive,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 单页宽高比（宽 / 高）。优先用已解析的真实尺寸；尚未解析时用本话
  /// 已读页的常见比例兜底并异步解析，解析完成后重排一次。
  double _spreadAspectRatio(DoublePageAnchor anchor) {
    final chapter = _chain[anchor.chapterIndex];
    final source = chapter.contents[anchor.imageIndex];
    final size = _imageNaturalSizes[source];
    if (size != null && !size.isEmpty) {
      final aspect = size.width / size.height;
      if (aspect > 0) return aspect;
    }
    _requestSpreadImageSize(anchor, source);
    final typical = _typicalImageAspectRatio;
    if (typical != null && typical > 0) return 1 / typical;
    // 兜底：常见漫画单页约 0.7（A4/A5 竖版）。
    return 0.7;
  }

  /// 主动解析跨页内图片的原始尺寸，供上面按真实比例拼合。
  void _requestSpreadImageSize(DoublePageAnchor anchor, String source) {
    if (!_spreadSizePending.add(source)) return;
    final chapter = _chain[anchor.chapterIndex];
    final ImageProvider<Object> imageProvider = chapter.isDownloaded
        ? FileImage(File(source))
        : CachedNetworkImageProvider(
            source,
            cacheManager: _readerImageCacheManager,
          );
    _resolveAndCacheImageSize(
      imageProvider,
      source,
      onResolved: () {
        _spreadSizePending.remove(source);
        if (!mounted) return;
        // 仅触发一次重建，让跨页按真实宽高比重排；不影响页码与滚动位置。
        _setState(() {});
      },
    );
  }

  /// 跨页内图片的重试状态键：沿用单页模式的全局图片索引口径。
  int _spreadImageRetryKey(DoublePageAnchor anchor) {
    return _chainChapterStart(anchor.chapterIndex) + anchor.imageIndex;
  }
}
