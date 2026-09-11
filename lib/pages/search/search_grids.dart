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
