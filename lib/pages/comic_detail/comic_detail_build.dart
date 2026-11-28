part of '../comic_detail_page.dart';

extension _ComicDetailUiBuilders on _ComicDetailPageState {
  Future<void> _refresh() async {
    _exitSelectionMode();
    _chapterPageCache.clear();
    await _loadLocalHistory();
    await _loadComic();
  }

  Widget _buildGroupSegments(Comic comic) {
    return SegmentedButton<String>(
      showSelectedIcon: false,
      segments: comic.groups!.entries
          .map(
            (e) => ButtonSegment(
              value: e.key,
              label: Text(
                '${e.value.name}(${e.value.count})',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          )
          .toList(),
      selected: {_selectedGroup},
      onSelectionChanged: (v) async {
        final group = v.first;
        _setState(() => _selectedGroup = group);
        await _loadLocalHistory(group: group);
        await _loadChapterPageForHistory(group: group);
      },
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  ButtonStyle _chapterListButtonStyle(ColorScheme cs, {bool active = false}) =>
      FilledButton.styleFrom(
        fixedSize: const Size(38, 38),
        minimumSize: const Size(38, 38),
        maximumSize: const Size(38, 38),
        padding: EdgeInsets.zero,
        backgroundColor: active ? cs.primaryContainer : cs.surfaceContainerHigh,
        foregroundColor: active ? cs.onPrimaryContainer : cs.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdR),
        tapTargetSize: MaterialTapTargetSize.padded,
        visualDensity: VisualDensity.standard,
      );

  Widget _buildChapterListActions(ColorScheme cs) => Padding(
    padding: const EdgeInsets.only(left: AppSpacing.sm),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSortButton(cs),
        const SizedBox(width: AppSpacing.sm),
        _buildAutoLocateButton(cs),
      ],
    ),
  );

  Widget _buildAutoLocateButton(ColorScheme cs) => ListenableBuilder(
    listenable: _readerSettings,
    builder: (context, _) {
      final l10n = AppLocalizations.of(context)!;
      final enabled = _readerSettings.autoLocateLastReadChapter;
      return Tooltip(
        message: enabled
            ? l10n.comicDetailDisableAutoLocate
            : l10n.comicDetailEnableAutoLocate,
        child: Semantics(
          toggled: enabled,
          child: FilledButton.tonal(
            onPressed: _savingAutoLocate ? null : _toggleAutoLocate,
            style: _chapterListButtonStyle(cs, active: enabled),
            child: Icon(
              enabled ? Icons.my_location : Icons.location_searching,
              size: AppIconSize.lg,
            ),
          ),
        ),
      );
    },
  );

  Widget _buildSortButton(ColorScheme cs) {
    return FilledButton.tonal(
      onPressed: () => _setState(() => _reversed = !_reversed),
      style: _chapterListButtonStyle(cs),
      child: Tooltip(
        message: _reversed
            ? AppLocalizations.of(context)!.sortReverse
            : AppLocalizations.of(context)!.sortNormal,
        child: Icon(
          _reversed ? Icons.arrow_downward : Icons.arrow_upward,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildDownloadToolbar() {
    final pendingCount = _downloads.pendingCountForComic(widget.pathWord);
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: _selectionMode
          ? Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: _displayChapters.any(_isChapterSelectable)
                      ? _selectAllVisibleDownloadable
                      : null,
                  child: Text(AppLocalizations.of(context)!.selectAll),
                ),
                FilledButton(
                  onPressed: _selectedChapterIds.isEmpty
                      ? null
                      : _downloadSelectedChapters,
                  child: Text(
                    AppLocalizations.of(
                      context,
                    )!.comicDetailDownloadSelectedCount(
                      _selectedChapterIds.length,
                    ),
                  ),
                ),
                OutlinedButton(
                  onPressed: _showDownloadSettings,
                  child: Text(
                    AppLocalizations.of(context)!.downloadSettingsTitle,
                  ),
                ),
              ],
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (pendingCount > 0)
                  ActionChip(
                    avatar: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.primary,
                      ),
                    ),
                    label: Text(
                      AppLocalizations.of(
                        context,
                      )!.comicDetailSequentialDownloading(pendingCount),
                    ),
                    onPressed: () => context
                        .pushNamed(
                          AppRoutes.downloadCenter,
                          queryParameters: {'tab': '2'},
                        )
                        .then((_) => _handleDownloadChanged()),
                  ),
              ],
            ),
    );
  }

  Widget _buildChapterCard(Chapter chapter) {
    final isLastRead = _lastBrowseId == chapter.uuid;
    final isRead = _readChapterUuids.contains(chapter.uuid);
    final isDownloaded = _isChapterDownloaded(chapter.uuid);
    final isQueued = _isChapterQueued(chapter.uuid);
    final isDownloading = _downloads.isDownloading(
      widget.pathWord,
      chapter.uuid,
    );
    final progress = _downloads.progressOf(widget.pathWord, chapter.uuid);
    final isSelected = _selectedChapterIds.contains(chapter.uuid);

    // 已下载时右上角有勾选徽标，副标题仍显示页数即可
    final subtitle = isDownloading && progress != null
        ? AppLocalizations.of(
            context,
          )!.comicDetailDownloadProgress(progress.completed, progress.total)
        : isQueued
        ? AppLocalizations.of(context)!.comicDetailQueued
        : '${chapter.size}P';

    return ChapterCard(
      name: chapter.name,
      subtitle: subtitle,
      isSelected: isSelected,
      isLastRead: isLastRead,
      isLocateHighlighted: isLastRead && _locateHighlightedId == chapter.uuid,
      isRead: isRead,
      isDownloaded: isDownloaded,
      progressRatio: isDownloading && progress != null ? progress.ratio : null,
      onTap: () {
        if (_selectionMode) {
          _toggleChapterSelection(chapter);
          return;
        }
        _openReader(chapter);
      },
      onLongPress: _selectionMode || !_isChapterSelectable(chapter)
          ? null
          : () => _enterSelectionMode(chapter.uuid),
    );
  }

  Widget _hero(String Function(String base) tagOf, Widget child) {
    final base = widget.heroTagBase;
    if (base == null) return child;
    return AppHero(
      tag: tagOf(base),
      createRectTween: ComicHeroTags.createRectTween,
      placeholderBuilder: _buildHeroPlaceholder,
      child: child,
    );
  }

  Widget _buildHeroPlaceholder(
    BuildContext context,
    Size heroSize,
    Widget child,
  ) {
    return SizedBox(width: heroSize.width, height: heroSize.height);
  }

  Widget _buildDetailActions(Comic comic) {
    final buttonStyle = FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );

    return Row(
      children: [
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed:
                _selectionMode || _displayChapters.any(_isChapterSelectable)
                ? _toggleDownloadSelectionMode
                : null,
            icon: Icon(
              _selectionMode
                  ? Icons.close
                  : Icons.download_for_offline_outlined,
              size: 18,
            ),
            label: Text(
              _selectionMode
                  ? AppLocalizations.of(context)!.cancelButton
                  : AppLocalizations.of(context)!.downloadActionButton,
            ),
            style: buttonStyle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: comic.uuid == null || comic.uuid!.isEmpty
                ? null
                : _showComicComments,
            icon: const Icon(Icons.forum_outlined, size: 18),
            label: Text(AppLocalizations.of(context)!.chapterCommentsComment),
            style: buttonStyle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed:
                comic.uuid == null ||
                    comic.uuid!.isEmpty ||
                    _collectStateLoading ||
                    _collecting
                ? null
                : _toggleCollect,
            // 用爱心区分「收藏」（服务端）与右上角的「书签」（本地）。
            icon: Icon(
              _isCollected ? Icons.favorite : Icons.favorite_border,
              size: 18,
            ),
            label: Text(
              _isCollected
                  ? AppLocalizations.of(context)!.alreadyCollectedLabel
                  : AppLocalizations.of(context)!.collectButton,
            ),
            style: buttonStyle,
          ),
        ),
      ],
    );
  }

  /// 横屏（宽 > 高且 ≥640）时左右分栏：左侧漫画信息 + 操作按钮，右侧章节列表，
  /// 避免顶部按钮和内容在宽屏下被整行拉满；竖屏维持原单列滚动布局。
  Widget _buildBody(ColorScheme cs, TextTheme tt) {
    final comic = _comic!;
    final size = MediaQuery.sizeOf(context);
    final isWide = comicDetailUsesTwoPane(size);
    final comicInfo = _buildComicInfo(cs, tt, comic);
    final chapterControls = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!isWide) _buildDetailActionRow(comic),
        ..._buildChapterControls(cs, comic),
      ],
    );
    final chapterSlivers = _buildChapterSlivers();

    if (!isWide) {
      // 封面和简介先随手势滚出，章节工具栏留在顶部，网格用满下方空间。
      return RefreshIndicator(
        onRefresh: _refresh,
        child: RawScrollbar(
          controller: _detailScrollController,
          thumbColor: cs.onSurfaceVariant.withValues(alpha: 0.28),
          thickness: 3,
          radius: const Radius.circular(AppRadius.full),
          crossAxisMargin: AppSpacing.xs,
          child: CustomScrollView(
            controller: _detailScrollController,
            scrollBehavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            slivers: [
              SliverToBoxAdapter(key: _comicInfoKey, child: comicInfo),
              PinnedHeaderSliver(
                key: _chapterControlsKey,
                child: ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: chapterControls,
                ),
              ),
              ...chapterSlivers,
            ],
          ),
        ),
      );
    }

    final leftWidth = comicDetailInfoPaneWidth(size);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: leftWidth,
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: comicInfo),
                SliverToBoxAdapter(child: _buildDetailActionRow(comic)),
                const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
              ],
            ),
          ),
        ),
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: cs.outlineVariant.withValues(alpha: 0.6),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: chapterControls),
                ...chapterSlivers,
              ],
            ),
          ),
        ),
      ],
    );
  }
}
