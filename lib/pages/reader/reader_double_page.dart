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

  /// 章节链的跨页分组，按链结构 + 「首图单页」设置 + 已知的横向大图缓存。
  ///
  /// 链会在连续阅读中追加/裁剪章节，键取各章页数之和即可命中变化；
  /// 图片真实尺寸是异步解析的，解析出新的大图会让分组变化，因此也要进签名。
  DoublePageLayout _doublePageLayout() {
    final pageCounts = [for (final chapter in _chain) chapter.contents.length];
    final widePages = _wideSpreadAnchors();
    final wideKeys = [
      for (final anchor in widePages) anchor.$1 * 100000 + anchor.$2,
    ]..sort();
    final signature = Object.hash(
      Object.hashAll(pageCounts),
      _user.readerDoublePageCoverAlone,
      Object.hashAll(wideKeys),
    );
    final cached = _doublePageLayoutCache;
    if (cached != null && _doublePageLayoutSignature == signature) {
      return cached;
    }
    final layout = DoublePageLayout.fromPageCounts(
      pageCounts,
      coverAlone: _user.readerDoublePageCoverAlone,
      widePages: widePages,
    );
    _doublePageLayoutCache = layout;
    _doublePageLayoutSignature = signature;
    return layout;
  }

  /// 已知尺寸里「本身已经是横向跨页」的页面。尺寸未解析时不算，
  /// 解析完成后由 [_scheduleSpreadSizeRebuild] 重新分组。
  Set<(int, int)> _wideSpreadAnchors() {
    final result = <(int, int)>{};
    for (var ci = 0; ci < _chain.length; ci++) {
      final contents = _chain[ci].contents;
      for (var li = 0; li < contents.length; li++) {
        final size = _imageNaturalSizes[contents[li]];
        if (size == null || size.height <= 0) {
          continue;
        }
        if (size.width / size.height >= DoublePageLayout.wideAspectThreshold) {
          result.add((ci, li));
        }
      }
    }
    return result;
  }

  /// 分组因新解析的尺寸而变化时，把控制器重新定位到当前页所在的跨页。
  ///
  /// 跨页编号是「链内全局」的：前面插入一个大图跨页，后面所有跨页序号都会
  /// 后移。不重定位的话，用户会突然看到别的页面。
  void _reanchorDoublePageController() {
    if (!_isPageMode || !_isDoublePageMode) return;
    if (_chain.isEmpty || _chainIndex >= _chain.length) return;
    final chapterPages = _chain[_chainIndex].contents.length;
    if (chapterPages <= 0) return;
    final page = _currentPage.clamp(1, chapterPages);
    final layout = _doublePageLayout();
    final target = layout.spreadIndexOf(_chainIndex, page - 1);
    final anchor = layout.spreadStart(target);
    final oldController = _pageController;
    _pageController = PageController(initialPage: target);
    _setState(() {
      // 页码统一取跨页首页，与翻页、书签、历史口径一致。
      _currentPage = anchor.imageIndex + 1;
      _pageImageZoomed = false;
      // 递增版本号：PageView 换新 key，新控制器的 initialPage 才会生效。
      _bumpScrollWidgetVersion();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldController.dispose();
    });
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
        _appendNextChapterToChain().then((appended) {
          // 追加失败时保持原位：不能把链尾当成新章节跳过去。
          if (!mounted || !appended) return;
          final newChapterIndex = _chain.indexWhere(
            (chapter) => chapter.uuid == nextUuid,
          );
          if (newChapterIndex < 0) return;
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
    // 两页并排时整组共用一个缩放手势容器：两根手指分别落在左右页时，
    // 每页各自独立的识别器只会各拿到一根指针，无法识别跨页捏合。
    final content = LayoutBuilder(
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
                      enablePinchZoom: false,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
    return PinchZoomable(
      active: zoomActive,
      // 跨页内任一页放大都会锁定翻页：整组共用一个缩放状态，不会出现
      // 「右页缩回 1x 就把仍放大的左页一并解锁」。
      onZoomChanged: _handlePageZoomChanged,
      child: content,
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
  ///
  /// 解析失败不再触发重建：失败会记入 [_spreadSizeFailures]，后续构建直接
  /// 沿用兜底比例，直到用户手动重试（[_retryImage]）把它清掉。否则持续
  /// 404 / 断网时「失败 → 清 pending → 重建 → 再请求」会形成无界重试，
  /// 绕过用户设置的重试次数。
  void _requestSpreadImageSize(DoublePageAnchor anchor, String source) {
    if (source.isEmpty) return;
    if (_spreadSizeFailures.contains(source)) return;
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
        _scheduleSpreadSizeRebuild();
      },
      onFailed: () {
        _spreadSizePending.remove(source);
        _spreadSizeFailures.add(source);
      },
    );
  }

  /// 尺寸解析完成后重建一次，让跨页按真实宽高比重排。
  ///
  /// 命中 Flutter 图片缓存时解析回调可能同步执行——直接父层 setState 会撞上
  /// 「布局阶段 markNeedsBuild」。统一排到帧末尾，并把同一帧内的多次通知合并
  /// 成一次重建。分组真的变了（出现了横向大图跨页）时再顺带重定位控制器。
  void _scheduleSpreadSizeRebuild() {
    if (_spreadSizeRebuildScheduled) return;
    _spreadSizeRebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _spreadSizeRebuildScheduled = false;
      if (!mounted) return;
      if (!_isDoublePageMode || _chain.isEmpty) return;
      final previousSignature = _doublePageLayoutSignature;
      _doublePageLayoutCache = null;
      _doublePageLayoutSignature = null;
      _doublePageLayout();
      if (_doublePageLayoutSignature != previousSignature) {
        _reanchorDoublePageController();
        return;
      }
      _setState(() {});
    });
  }

  /// 跨页内图片的重试状态键：沿用单页模式的全局图片索引口径。
  int _spreadImageRetryKey(DoublePageAnchor anchor) {
    return _chainChapterStart(anchor.chapterIndex) + anchor.imageIndex;
  }
}
