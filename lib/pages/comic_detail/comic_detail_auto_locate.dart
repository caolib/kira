part of '../comic_detail_page.dart';

extension _ComicDetailAutoLocate on _ComicDetailPageState {
  Future<void> _toggleAutoLocate() async {
    if (_savingAutoLocate) return;
    final enabled = !_readerSettings.autoLocateLastReadChapter;
    _setState(() => _savingAutoLocate = true);
    try {
      await _readerSettings.setAutoLocateLastReadChapter(enabled);
      if (!mounted) return;
      if (enabled) {
        _scheduleLastReadLocation();
      } else {
        _locateRequest++;
        _locateHighlightTimer?.cancel();
        _setState(() => _locateHighlightedId = null);
      }
    } catch (error) {
      // 底层设置写入已记录原始异常和堆栈。
      if (!mounted) return;
      showToast(
        context,
        NetworkError.message(error, l10n: AppLocalizations.of(context)),
        isError: true,
      );
    } finally {
      if (mounted) _setState(() => _savingAutoLocate = false);
    }
  }

  void _scheduleLastReadLocation() {
    final id = _lastBrowseId;
    if (id == null ||
        !_readerSettings.autoLocateLastReadChapter ||
        _chapterListGroup != _selectedGroup ||
        _chapterByUuid(id) == null) {
      return;
    }
    final request = ++_locateRequest;
    final chapters = _chapters;
    final group = _selectedGroup;
    final page = _chapterPage;
    bool isCurrent() =>
        mounted &&
        request == _locateRequest &&
        _readerSettings.autoLocateLastReadChapter &&
        _lastBrowseId == id &&
        identical(_chapters, chapters) &&
        _selectedGroup == group &&
        _chapterPage == page &&
        (!_loadingChapters || _keepShowingCachedChapters) &&
        (ModalRoute.of(context)?.isCurrent ?? true);

    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      if (!isCurrent()) return;
      // 下一帧再定位，等底栏测量结果写入滚动范围，避免末章被盖住。
      binding.addPostFrameCallback((_) {
        if (isCurrent()) unawaited(_locateLastReadChapter(id, isCurrent));
      });
      binding.scheduleFrame();
    });
  }

  Future<void> _locateLastReadChapter(
    String id,
    bool Function() isCurrent,
  ) async {
    final gridContext = _chapterGridKey.currentContext;
    final grid = gridContext?.findRenderObject();
    if (gridContext == null || grid is! RenderSliverGrid || !grid.attached) {
      return;
    }
    final position = Scrollable.maybeOf(
      gridContext,
      axis: Axis.vertical,
    )?.position;
    if (position == null || !position.hasContentDimensions) return;

    final reversed = _reversed;
    final index = _displayChapters.indexWhere((chapter) => chapter.uuid == id);
    if (index < 0) return;
    // 使用网格实际布局计算目标行，不要求离屏卡片已构建。
    final tile = grid.gridDelegate
        .getLayout(grid.constraints)
        .getGeometryForChildIndex(index);
    // getOffsetToReveal 已从起点扣除吸顶栏；可用高度也要排除顶部和底部遮挡。
    final gridStart = RenderAbstractViewport.of(
      grid,
    ).getOffsetToReveal(grid, 0).offset;
    final controls = _chapterControlsKey.currentContext?.findRenderObject();
    final pinnedExtent = controls is RenderSliver
        ? controls.geometry?.maxScrollObstructionExtent ?? 0.0
        : 0.0;
    final visibleExtent =
        position.viewportDimension -
        pinnedExtent -
        _readingActionsBottomPadding;
    final top = gridStart + tile.scrollOffset;
    final bottom = top + tile.mainAxisExtent;
    final current = position.pixels;
    if (top < current || bottom > current + visibleExtent) {
      final inset = ((visibleExtent - tile.mainAxisExtent) / 2).clamp(
        0.0,
        position.viewportDimension,
      );
      final offset = (top - inset).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      final duration = adaptiveDuration(
        context,
        const Duration(milliseconds: 240),
      );
      if (duration == Duration.zero) {
        position.jumpTo(offset);
      } else {
        await position.animateTo(
          offset,
          duration: duration,
          curve: Curves.easeOutCubic,
        );
      }
      // 手势打断滚动、切换布局或排序时，不在旧位置高亮。
      if (!gridContext.mounted ||
          !isCurrent() ||
          _reversed != reversed ||
          !identical(_chapterGridKey.currentContext, gridContext) ||
          (position.pixels - offset).abs() > 1) {
        return;
      }
    }

    _locateHighlightTimer?.cancel();
    _setState(() => _locateHighlightedId = id);
    _locateHighlightTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) _setState(() => _locateHighlightedId = null);
    });
  }

  void _returnToChapterListStart(double? previousOffset) {
    if (previousOffset == null || previousOffset <= 0) return;
    final chapters = _chapters;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !identical(chapters, _chapters) ||
          !_detailScrollController.hasClients) {
        return;
      }
      final grid = _chapterGridKey.currentContext?.findRenderObject();
      final position = _detailScrollController.position;
      if (grid is! RenderSliverGrid ||
          !grid.attached ||
          !position.hasContentDimensions) {
        return;
      }
      final gridStart = RenderAbstractViewport.of(grid)
          .getOffsetToReveal(grid, 0)
          .offset
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      final offset = previousOffset.clamp(position.minScrollExtent, gridStart);
      if (position.pixels != offset) position.jumpTo(offset);
    });
  }
}
