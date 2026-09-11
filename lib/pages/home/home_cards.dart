part of '../home_page.dart';

class _MangaHorizontalList extends StatelessWidget {
  final List<Comic> items;
  final void Function(Comic, String) onTap;

  const _MangaHorizontalList({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // 用 LayoutBuilder 而非 MediaQuery：双栏里实际可用宽是半栏，
    // 卡片尺寸必须按真实约束算。
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = math.max(1.0, constraints.maxWidth - 32);
        final cardWidth = _mangaHomeGridCardWidth(
          available,
          maxCardExtent: _mangaHomeCardMaxExtent(available),
        );
        final cardHeight = cardWidth / _mangaHomeCardAspectRatio;

        return SizedBox(
          height: cardHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final comic = items[i];
              final heroTagBase = ComicHeroTags.base(
                scope: 'home-recommend',
                pathWord: comic.pathWord,
                index: i,
              );
              return _MangaCard(
                comic: comic,
                width: cardWidth,
                heroTagBase: heroTagBase,
                onTap: () => onTap(comic, heroTagBase),
              );
            },
          ),
        );
      },
    );
  }
}

class _MangaCard extends StatelessWidget {
  final Comic comic;
  final double width;
  final String? heroTagBase;
  final VoidCallback onTap;

  const _MangaCard({
    required this.comic,
    required this.width,
    this.heroTagBase,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        margin: const EdgeInsets.only(right: _mangaHomeCardSpacing),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _hero(
                ComicHeroTags.cover,
                ComicCardSurface(
                  child: CoverBrightnessFilter(
                    child: CachedNetworkImage(
                      imageUrl: comic.cover,
                      fit: BoxFit.cover,
                      width: width,
                      height: double.infinity,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      placeholder: (_, _) => const CoverPlaceholder(),
                      errorWidget: (_, _, _) => const CoverPlaceholder.error(),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              comic.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.bodySmall,
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.local_fire_department, size: 12, color: cs.primary),
                const SizedBox(width: 2),
                Text(
                  ComicCard.formatPopular(comic.popular, l10n),
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                if (comic.authors.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      comic.authors.map((a) => a.name).join(' / '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero(String Function(String base) tagOf, Widget child) {
    final base = heroTagBase;
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
}

// ── 通用组件 ──

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  final double hp;
  final VoidCallback? onMore;
  const _SectionTitle({
    required this.title,
    required this.icon,
    required this.hp,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(hp, 0, hp - 8, 6),
        child: SectionHeader(title: title, icon: icon, onMore: onMore),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  final IconData icon;

  const _ImagePlaceholder({required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerHighest,
      child: Center(child: Icon(icon, color: cs.onSurfaceVariant, size: 32)),
    );
  }
}

/// 漫画网格卡片，多页面复用
class ComicCard extends StatelessWidget {
  final Comic comic;
  final String? heroTagBase;
  final VoidCallback onTap;
  const ComicCard({
    super.key,
    required this.comic,
    this.heroTagBase,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final title = Text(
      comic.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: tt.bodySmall,
    );

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _hero(
              ComicHeroTags.cover,
              ComicCardSurface(
                child: CoverBrightnessFilter(
                  child: CachedNetworkImage(
                    imageUrl: comic.cover,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    placeholder: (_, _) => const CoverPlaceholder(),
                    errorWidget: (_, _, _) => const CoverPlaceholder.error(),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          title,
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.local_fire_department, size: 12, color: cs.primary),
              const SizedBox(width: 2),
              Flexible(
                child: Text(
                  formatPopular(comic.popular, l10n),
                  overflow: TextOverflow.ellipsis,
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
              if (comic.datetimeUpdated != null) ...[
                const SizedBox(width: AppSpacing.xs),
                Text(
                  TimeFormat.relativeOf(comic.datetimeUpdated!, l10n),
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _hero(String Function(String base) tagOf, Widget child) {
    final base = heroTagBase;
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

  static String formatPopular(int n, AppLocalizations l10n) {
    if (n >= 100000000) {
      return l10n.hundredMillionUnit((n / 100000000).toStringAsFixed(1));
    }
    if (n >= 10000) {
      return l10n.tenThousandUnit((n / 10000).toStringAsFixed(1));
    }
    return n.toString();
  }
}
