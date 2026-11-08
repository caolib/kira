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
          Icon(Icons.favorite_border, size: 64, color: cs.onSurfaceVariant),
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.bookshelfEmpty,
            style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.goFindSomething(l10n.comicLabel),
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
        ? _items.where(_hasUpdate).toList()
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
              if (_hasUpdate(item)) const UpdateBadge(),
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
    await _reloadLocalChapters();
  }
}
