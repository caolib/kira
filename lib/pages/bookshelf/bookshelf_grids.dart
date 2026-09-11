part of '../bookshelf_page.dart';

extension _BookshelfGrids on _BookshelfPageState {
  Widget _buildEmptyState(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bookmark_border, size: 64, color: cs.onSurfaceVariant),
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.bookshelfEmpty,
            style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.goFindSomething(_typeLabel(l10n)),
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.tonalIcon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: Text(l10n.refreshButton),
          ),
        ],
      ),
    );
  }

  Widget _buildNoUpdates(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 48,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            AppLocalizations.of(context)!.noComicUpdates,
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildComicGrid(BuildContext context, double hp) {
    final filtered = _showUpdateOnly
        ? _items.where((e) => e.hasUpdate).toList()
        : _items;
    final skeletonCount = _loadingMore ? 6 : 0;
    final totalCount = filtered.length + skeletonCount;
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: hp),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate((_, i) {
          if (i >= filtered.length) {
            return const ComicCardSkeleton();
          }
          final item = filtered[i];
          final heroTagBase = ComicHeroTags.base(
            scope: _showUpdateOnly ? 'bookshelf-updates' : 'bookshelf',
            pathWord: item.comic.pathWord,
            index: i,
          );
          return Stack(
            children: [
              ComicCard(
                comic: item.comic,
                heroTagBase: heroTagBase,
                onTap: () => _openComicDetail(item, heroTagBase),
              ),
              if (item.hasUpdate) const _UpdateBadge(),
            ],
          );
        }, childCount: totalCount),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: ScreenLayout.cardExtent(
            MediaQuery.sizeOf(context).width,
          ),
          childAspectRatio: 0.55,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
      ),
    );
  }

  Future<void> _openComicDetail(BookshelfItem item, String heroTagBase) async {
    final pathWord = item.comic.pathWord;
    final before = await ReadingHistory.latestForComic(pathWord);
    if (!mounted) return;

    await context.pushNamed(
      AppRoutes.comicDetail,
      pathParameters: {'pathWord': pathWord},
      extra: ComicDetailExtra(
        initialComic: item.comic,
        heroTagBase: heroTagBase,
        lastBrowseId: item.lastBrowseId,
        lastBrowseName: item.lastBrowseName,
      ),
    );
    if (!mounted) return;

    await _refreshLoaded();
    if (!mounted) return;
    await _applyLocalBrowseToComicItem(pathWord, before);
  }

  Future<void> _applyLocalBrowseToComicItem(
    String pathWord,
    ReadingRecord? before,
  ) async {
    final record = await ReadingHistory.latestForComic(pathWord);
    if (!mounted || record == null || record.chapterUuid.isEmpty) return;

    final changedDuringNavigation = _readingRecordChanged(before, record);
    var changed = false;
    final nextItems = _items.map((item) {
      if (item.comic.pathWord != pathWord) return item;
      final alreadyCurrent =
          item.lastBrowseId == record.chapterUuid &&
          item.lastBrowseName == record.chapterName;
      if (alreadyCurrent) return item;

      final localRecordClearsUpdate =
          item.comic.lastChapterId != null &&
          item.comic.lastChapterId == record.chapterUuid;
      if (!changedDuringNavigation && !localRecordClearsUpdate) return item;

      changed = true;
      return BookshelfItem(
        comic: item.comic,
        lastBrowseId: record.chapterUuid,
        lastBrowseName: record.chapterName,
      );
    }).toList();

    if (!changed || !mounted) return;
    _setState(() => _items = nextItems);
    unawaited(
      _saveComicCache(
        nextItems,
        _comicTotal > 0 ? _comicTotal : _total,
        _comicCacheTime ?? DateTime.now(),
      ),
    );
  }

  bool _readingRecordChanged(ReadingRecord? before, ReadingRecord after) {
    if (before == null) return true;
    final beforeUpdatedAt = before.updatedAt;
    final afterUpdatedAt = after.updatedAt;
    if (beforeUpdatedAt != null && afterUpdatedAt != null) {
      return afterUpdatedAt.isAfter(beforeUpdatedAt);
    }
    return before.chapterUuid != after.chapterUuid ||
        before.chapterName != after.chapterName;
  }

  Widget _buildAnimeGrid(BuildContext context, double hp) {
    final skeletonCount = _loadingMore ? 6 : 0;
    final totalCount = _animeItems.length + skeletonCount;
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: hp),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate((_, i) {
          if (i >= _animeItems.length) {
            return const ComicCardSkeleton();
          }
          final item = _animeItems[i];
          return _AnimeBookshelfCard(
            anime: item.anime,
            onTap: () => context
                .pushNamed(
                  AppRoutes.animeDetail,
                  pathParameters: {'pathWord': item.anime.pathWord},
                  extra: AnimeDetailExtra(initialAnime: item.anime),
                )
                .then((_) => _refreshLoaded()),
          );
        }, childCount: totalCount),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: ScreenLayout.cardExtent(
            MediaQuery.sizeOf(context).width,
          ),
          childAspectRatio: 0.55,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
      ),
    );
  }
}
