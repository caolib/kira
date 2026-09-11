part of '../comic_detail_page.dart';

extension _ComicDetailSlivers on _ComicDetailPageState {
  List<Widget> _buildInfoSlivers(ColorScheme cs, TextTheme tt, Comic comic) {
    final authors = comic.authors
        .where((author) => author.name.trim().isNotEmpty)
        .toList();
    return [
      // ── 漫画信息卡片 ──
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _hero(
                ComicHeroTags.cover,
                ClipRRect(
                  borderRadius: AppRadius.mdR,
                  child: CoverBrightnessFilter(
                    child: CachedNetworkImage(
                      imageUrl: comic.cover,
                      width: 120,
                      height: 160,
                      fit: BoxFit.cover,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      placeholder: (_, _) => Container(
                        width: 120,
                        height: 160,
                        color: cs.surfaceContainerHighest,
                      ),
                      errorWidget: (_, _, _) => Container(
                        width: 120,
                        height: 160,
                        color: cs.surfaceContainerHighest,
                        child: Icon(
                          Icons.broken_image,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comic.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (authors.isNotEmpty ||
                        comic.status != null ||
                        comic.region != null ||
                        comic.themes.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final author in authors)
                            AuthorChip(
                              author: author,
                              onTap: () => _openAuthorWorks(author),
                            ),
                          if (comic.status != null)
                            InfoChip(
                              icon: Icons.timelapse,
                              label: comic.status!['display'] ?? '',
                              color: cs.primaryContainer,
                              textColor: cs.onPrimaryContainer,
                            ),
                          if (comic.region != null)
                            InfoChip(
                              icon: Icons.public,
                              label: comic.region!['display'] ?? '',
                              color: cs.secondaryContainer,
                              textColor: cs.onSecondaryContainer,
                            ),
                          for (final theme in comic.themes)
                            ThemeChip(
                              theme: theme,
                              onTap: () => _openThemeWorks(theme),
                              color: cs.tertiaryContainer,
                              textColor: cs.onTertiaryContainer,
                            ),
                        ],
                      ),
                    if (comic.popular > 0) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            Icons.local_fire_department,
                            size: 14,
                            color: cs.primary,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            formatPopularCount(context, comic.popular),
                            style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (comic.datetimeUpdated != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: [
                          Icon(
                            Icons.update,
                            size: 14,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            TimeFormat.relativeOf(
                              comic.datetimeUpdated!,
                              AppLocalizations.of(context)!,
                            ),
                            style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      // ── 简介 ──（横屏左栏空间充裕，默认展开；竖屏仍折叠 3 行）
      if (comic.brief != null && comic.brief!.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Builder(
              builder: (context) {
                final expanded =
                    _briefExpanded ||
                    comicDetailUsesTwoPane(MediaQuery.sizeOf(context));
                return GestureDetector(
                  onTap: () =>
                      _setState(() => _briefExpanded = !_briefExpanded),
                  child: Text(
                    comic.brief!,
                    maxLines: expanded ? null : 3,
                    overflow: expanded ? null : TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                );
              },
            ),
          ),
        ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _buildDetailActions(comic),
        ),
      ),
    ];
  }

  List<Widget> _buildChapterSlivers(ColorScheme cs, TextTheme tt, Comic comic) {
    return [
      // ── 分组切换 ──
      if (comic.groups != null && comic.groups!.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _totalPages <= 1
                // 无分页时把排序按钮放到分组按钮后面，节省空间
                ? Row(
                    children: [
                      Expanded(child: _buildGroupSegments(comic)),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        child: _refreshingComic
                            ? const Padding(
                                key: ValueKey('comic_detail_refreshing'),
                                padding: EdgeInsets.only(left: 8),
                                child: SizedBox.square(
                                  dimension: 38,
                                  child: Center(
                                    child: SizedBox.square(
                                      dimension: 22,
                                      child: ExpressiveLoadingIndicator(),
                                    ),
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(
                                key: ValueKey('comic_detail_not_refreshing'),
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: _buildSortButton(cs),
                      ),
                    ],
                  )
                : _buildGroupSegments(comic),
          ),
        ),
      // ── 章节标题 + 排序 + 分页（单页时排序按钮已合并到分组行）──
      if (_totalPages > 1)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: List.generate(_totalPages, (i) {
                        final isSelected = i == _chapterPage;
                        final pageButtonShape = RoundedRectangleBorder(
                          borderRadius: AppRadius.mdR,
                        );
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: isSelected
                              ? FilledButton(
                                  onPressed: () {},
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(38, 38),
                                    maximumSize: const Size(38, 38),
                                    fixedSize: const Size(38, 38),
                                    padding: EdgeInsets.zero,
                                    backgroundColor: cs.primary,
                                    foregroundColor: cs.onPrimary,
                                    disabledBackgroundColor: cs.primary,
                                    disabledForegroundColor: cs.onPrimary,
                                    shape: pageButtonShape,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text('${i + 1}'),
                                )
                              : FilledButton.tonal(
                                  onPressed: () => _loadChapterPage(i),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(38, 38),
                                    maximumSize: const Size(38, 38),
                                    fixedSize: const Size(38, 38),
                                    padding: EdgeInsets.zero,
                                    backgroundColor: cs.surfaceContainerHigh,
                                    foregroundColor: cs.onSurfaceVariant,
                                    shape: pageButtonShape,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text('${i + 1}'),
                                ),
                        );
                      }),
                    ),
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: _refreshingComic
                      ? const Padding(
                          key: ValueKey('comic_detail_refreshing'),
                          padding: EdgeInsets.only(left: 8),
                          child: SizedBox.square(
                            dimension: 38,
                            child: Center(
                              child: SizedBox.square(
                                dimension: 22,
                                child: ExpressiveLoadingIndicator(),
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(
                          key: ValueKey('comic_detail_not_refreshing'),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _buildSortButton(cs),
                ),
              ],
            ),
          ),
        ),
      _buildDownloadToolbar(cs, tt),
      // ── 章节网格 ──
      if (_loadingChapters &&
          (!_keepShowingCachedChapters || _chapters.isEmpty))
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: ExpressiveLoadingIndicator()),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate((_, i) {
              final ch = _displayChapters[i];
              return _buildChapterCard(ch);
            }, childCount: _displayChapters.length),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 150,
              mainAxisExtent: chapterTileExtent(
                MediaQuery.textScalerOf(context).scale(1),
              ),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
          ),
        ),
      const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
    ];
  }
}
