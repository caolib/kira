part of '../search_page.dart';

class _ComicGrid extends StatelessWidget {
  final List<Comic> comics;
  final double hp;
  final double cardExtent;
  final bool loadingMore;
  final void Function(Comic comic, String heroTagBase) onOpen;

  const _ComicGrid({
    required this.comics,
    required this.hp,
    required this.cardExtent,
    required this.loadingMore,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(hp, 8, hp, 0),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate((_, i) {
          if (i >= comics.length) {
            return const ComicCardSkeleton();
          }
          final comic = comics[i];
          final heroTagBase = ComicHeroTags.base(
            scope: 'search',
            pathWord: comic.pathWord,
            index: i,
          );
          return ComicCard(
            comic: comic,
            heroTagBase: heroTagBase,
            onTap: () => onOpen(comic, heroTagBase),
          );
        }, childCount: comics.length + (loadingMore ? 6 : 0)),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: cardExtent,
          childAspectRatio: 0.55,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
      ),
    );
  }
}

class _AnimeGrid extends StatelessWidget {
  final List<Anime> animes;
  final double hp;
  final double cardExtent;
  final bool loadingMore;
  final ValueChanged<Anime> onOpen;

  const _AnimeGrid({
    required this.animes,
    required this.hp,
    required this.cardExtent,
    required this.loadingMore,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: hp),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate((_, i) {
          if (i >= animes.length) {
            return const ComicCardSkeleton();
          }
          final anime = animes[i];
          return _AnimeGridItem(anime: anime, onTap: () => onOpen(anime));
        }, childCount: animes.length + (loadingMore ? 6 : 0)),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: cardExtent,
          childAspectRatio: 0.55,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
      ),
    );
  }
}

class _AnimeGridItem extends StatelessWidget {
  final Anime anime;
  final VoidCallback onTap;

  const _AnimeGridItem({required this.anime, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              margin: EdgeInsets.zero,
              child: CoverBrightnessFilter(
                child: CachedNetworkImage(
                  imageUrl: anime.cover,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  placeholder: (_, _) => Container(
                    color: cs.surfaceContainerHighest,
                    child: Center(
                      child: Icon(
                        Icons.movie_outlined,
                        color: cs.onSurfaceVariant,
                        size: 32,
                      ),
                    ),
                  ),
                  errorWidget: (_, _, _) => Container(
                    color: cs.surfaceContainerHighest,
                    child: Center(
                      child: Icon(
                        Icons.broken_image,
                        color: cs.onSurfaceVariant,
                        size: 32,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            anime.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
