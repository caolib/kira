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

  Widget _buildSortButton(ColorScheme cs) {
    return FilledButton.tonal(
      onPressed: () => _setState(() => _reversed = !_reversed),
      style: FilledButton.styleFrom(
        minimumSize: const Size(38, 38),
        maximumSize: const Size(38, 38),
        fixedSize: const Size(38, 38),
        padding: EdgeInsets.zero,
        backgroundColor: cs.surfaceContainerHigh,
        foregroundColor: cs.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdR),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
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

  Widget _buildDownloadToolbar(ColorScheme cs, TextTheme tt) {
    final pendingCount = _downloads.pendingCountForComic(widget.pathWord);

    return SliverToBoxAdapter(
      child: Padding(
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
                          .pushNamed(AppRoutes.downloadCenter)
                          .then((_) => _handleDownloadChanged()),
                    ),
                ],
              ),
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
    return Hero(
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
            onPressed: comic.uuid == null || comic.uuid!.isEmpty
                ? null
                : _toggleCollect,
            icon: Icon(
              _isCollected ? Icons.bookmark : Icons.bookmark_border,
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
    final infoSlivers = _buildInfoSlivers(cs, tt, comic);
    final chapterSlivers = _buildChapterSlivers(cs, tt, comic);

    if (!isWide) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(slivers: [...infoSlivers, ...chapterSlivers]),
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
                ...infoSlivers,
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
            child: CustomScrollView(slivers: chapterSlivers),
          ),
        ),
      ],
    );
  }
}
