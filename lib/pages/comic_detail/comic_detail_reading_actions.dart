part of '../comic_detail_page.dart';

extension _ComicDetailReadingActionsPart on _ComicDetailPageState {
  double get _readingActionsBottomPadding =>
      (_readingActionsHeight == 0 ? 0 : _readingActionsHeight + AppSpacing.lg) +
      AppSpacing.lg +
      MediaQuery.viewPaddingOf(context).bottom;

  void _syncReadingActionsAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateBackToTopVisibility();
      final height = _readingActionsKey.currentContext?.size?.height ?? 0;
      if (height == _readingActionsHeight) return;
      _setState(() => _readingActionsHeight = height);
    });
  }

  void _updateBackToTopVisibility() {
    // 横屏双栏的封面不会随章节列表滚走。
    final controller = _detailScrollController;
    final info = _comicInfoKey.currentContext?.findRenderObject();
    final infoExtent = info is RenderSliver
        ? info.geometry?.scrollExtent
        : null;
    final show =
        controller.hasClients &&
        infoExtent != null &&
        controller.position.hasContentDimensions &&
        controller.position.maxScrollExtent >= infoExtent &&
        controller.offset >= infoExtent;
    if (show != _showBackToTop) _setState(() => _showBackToTop = show);
  }

  void _scrollToComicTop() {
    final controller = _detailScrollController;
    if (!controller.hasClients) return;
    // 用户手动回顶优先，不再执行本轮待处理的自动定位。
    _locateRequest++;
    final top = controller.position.minScrollExtent;
    final duration = adaptiveDuration(
      context,
      const Duration(milliseconds: 250),
    );
    if (duration == Duration.zero) {
      controller.jumpTo(top);
    } else {
      unawaited(
        controller.animateTo(
          top,
          duration: duration,
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  Widget _buildReadingActions() {
    return Positioned(
      left: AppSpacing.lg,
      right: AppSpacing.lg,
      bottom: AppSpacing.lg,
      child: SafeArea(
        top: false,
        child: ComicDetailReadingActions(
          key: _readingActionsKey,
          continueLabel: _continueReadingLabel(),
          onContinue: _canShowLastBrowseAction ? _continueReading : null,
          nextLabel: _nextBrowseChapter == null
              ? null
              : _truncateNextChapterName(_nextBrowseChapter!.name),
          onNext: _nextBrowseChapter == null ? null : _readNextChapter,
          onBackToTop: _showBackToTop ? _scrollToComicTop : null,
        ),
      ),
    );
  }

  void _continueReading() {
    context
        .pushNamed(
          AppRoutes.reader,
          pathParameters: {
            'pathWord': widget.pathWord,
            'chapterUuid': _lastBrowseId!,
          },
          extra: ReaderExtra(
            comicName: _comic?.name,
            group: _selectedGroup,
            chapterName: _lastBrowseName ?? '',
            chapterListPage: _lastBrowseReaderChapterListPage,
            initialPage: _lastBrowsePage,
          ),
        )
        .then((_) => _loadLocalHistory(locateAfterLoad: true));
  }

  void _readNextChapter() {
    final chapter = _nextBrowseChapter!;
    context
        .pushNamed(
          AppRoutes.reader,
          pathParameters: {
            'pathWord': widget.pathWord,
            'chapterUuid': chapter.uuid,
          },
          extra: ReaderExtra(
            comicName: _comic?.name,
            group: _selectedGroup,
            chapterName: chapter.name,
            chapterListPage: _nextBrowseChapterListPage ?? _chapterPage,
          ),
        )
        .then((_) => _loadLocalHistory(locateAfterLoad: true));
  }
}
