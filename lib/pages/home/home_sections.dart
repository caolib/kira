part of '../home_page.dart';

// ── Section & Card ──

/// 宽屏双栏里的分区标题行（无水平 padding，由外层统一控制）。
class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback? onMore;

  const _SectionHeader({required this.title, required this.icon, this.onMore});

  @override
  Widget build(BuildContext context) {
    return SectionHeader(title: title, icon: icon, onMore: onMore);
  }
}

/// 双栏内给横滑列表/网格一个已知宽度，使其卡片尺寸按半栏宽计算。
class _PaneScope extends StatelessWidget {
  final double width;
  final Widget child;

  const _PaneScope({required this.width, required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: width, child: child);
  }
}

/// 双栏里的排行榜网格：按半栏宽自适应列数、卡片尺寸与大屏规则一致。
class _RankingPaneGrid extends StatelessWidget {
  final List<Comic> items;
  final void Function(Comic, String) onTap;

  const _RankingPaneGrid({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final cardExtent = _mangaHomeCardMaxExtent(width);
        // 与 maxCrossAxisExtent 网格、横滑列表一致用 ceil 取列数，
        // 卡片宽 ≤ 上限且与同栏其他卡片同尺寸（floor 会少一列、卡片偏大）。
        final columns = (width / (cardExtent + _mangaHomeCardSpacing))
            .ceil()
            .clamp(1, items.length);
        final rows = (items.length / columns).ceil();
        final cardWidth = _mangaHomeGridCardWidth(
          width,
          maxCardExtent: cardExtent,
        );
        final cardHeight = cardWidth / _mangaHomeCardAspectRatio;
        return SizedBox(
          height: rows * cardHeight + (rows - 1) * _mangaHomeCardSpacing,
          child: GridView.builder(
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              childAspectRatio: _mangaHomeCardAspectRatio,
              mainAxisSpacing: _mangaHomeCardSpacing,
              crossAxisSpacing: _mangaHomeCardSpacing,
            ),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final comic = items[i];
              final heroTagBase = ComicHeroTags.base(
                scope: 'home-ranking',
                pathWord: comic.pathWord,
                index: i,
              );
              return ComicCard(
                comic: comic,
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

class _MangaSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final double hp;
  final Widget child;
  final VoidCallback? onMore;

  const _MangaSection({
    required this.title,
    required this.icon,
    required this.hp,
    required this.child,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(hp, 0, hp, 6),
            child: Row(
              children: [
                Icon(icon, size: 20, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (onMore != null)
                  TextButton(
                    onPressed: onMore,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.moreButton,
                          style: TextStyle(color: cs.primary),
                        ),
                        Icon(Icons.chevron_right, size: 18, color: cs.primary),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}
