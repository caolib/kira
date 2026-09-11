part of '../home_page.dart';

class _CopyCollapsibleSection extends StatefulWidget {
  final String storageKey;
  final String title;
  final IconData icon;
  final double hp;
  final Widget child;
  final VoidCallback? onMore;
  final double topPadding;

  const _CopyCollapsibleSection({
    required this.storageKey,
    required this.title,
    required this.icon,
    required this.hp,
    required this.child,
    this.onMore,
    this.topPadding = 0,
  });

  @override
  State<_CopyCollapsibleSection> createState() =>
      _CopyCollapsibleSectionState();
}

class _CopyCollapsibleSectionState extends State<_CopyCollapsibleSection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = !UserManager().isCopyHomeSectionCollapsed(widget.storageKey);
  }

  void _toggleExpanded() {
    final expanded = !_expanded;
    setState(() => _expanded = expanded);
    unawaited(
      UserManager().setCopyHomeSectionCollapsed(widget.storageKey, !expanded),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(widget.hp, widget.topPadding, widget.hp, 12),
      child: Material(
        color: cs.surfaceBright,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.smR,
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.72)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: _toggleExpanded,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Row(
                  children: [
                    Icon(widget.icon, size: 20, color: cs.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (widget.onMore != null)
                      TextButton(
                        onPressed: widget.onMore,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              l10n.moreButton,
                              style: TextStyle(color: cs.primary),
                            ),
                            Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: cs.primary,
                            ),
                          ],
                        ),
                      ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      child: Icon(
                        Icons.expand_more,
                        size: 22,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ClipRect(
              child: AnimatedAlign(
                alignment: Alignment.topCenter,
                heightFactor: _expanded ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: widget.child,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CopyHorizontalComicList extends StatelessWidget {
  final List<Comic> items;
  final void Function(Comic, String) onTap;
  final String scope;

  const _CopyHorizontalComicList({
    required this.items,
    required this.onTap,
    required this.scope,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const _CopyEmptySectionMessage();

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = math.max(
          1.0,
          _copySectionContentWidth(context, constraints),
        );
        final cardWidth = _mangaHomeGridCardWidth(
          contentWidth,
          maxCardExtent: _mangaHomeCardMaxExtent(contentWidth),
        );
        final cardHeight = cardWidth / _mangaHomeCardAspectRatio;

        return SizedBox(
          height: cardHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: items.length,
            itemBuilder: (_, i) {
              final comic = items[i];
              final heroTagBase = ComicHeroTags.base(
                scope: scope,
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

class _CopyTwoRowComicGrid extends StatelessWidget {
  final List<Comic> items;
  final void Function(Comic, String) onTap;
  final String scope;

  const _CopyTwoRowComicGrid({
    required this.items,
    required this.onTap,
    required this.scope,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const _CopyEmptySectionMessage();

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = math.max(
          1.0,
          _copySectionContentWidth(context, constraints),
        );
        // 普通换行网格：列数按宽度算（ceil，与其他网格一致），
        // 从左到右放不下才换行，全部展示、不滚动。
        final columns =
            (contentWidth /
                    (_mangaHomeCardMaxExtent(contentWidth) +
                        _mangaHomeCardSpacing))
                .ceil()
                .clamp(1, items.length);
        final rows = (items.length / columns).ceil();
        final cardWidth = _mangaHomeGridCardWidth(
          contentWidth,
          maxCardExtent: _mangaHomeCardMaxExtent(contentWidth),
        );
        final cardHeight = cardWidth / _mangaHomeCardAspectRatio;
        final gridHeight =
            cardHeight * rows + _mangaHomeCardSpacing * (rows - 1);

        return SizedBox(
          height: gridHeight,
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
                scope: scope,
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

class _CopyRankingTabs extends StatelessWidget {
  final List<Comic> dayItems;
  final List<Comic> weekItems;
  final List<Comic> monthItems;
  final void Function(Comic, String) onTap;

  const _CopyRankingTabs({
    required this.dayItems,
    required this.weekItems,
    required this.monthItems,
    required this.onTap,
  });

  /// 三个榜全部直接展示，一行一榜（标题 + 横滑卡片），不用 tab。
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final boards = <(String, List<Comic>, String)>[
      (l10n.dayRank, dayItems, 'copy-rank-day'),
      (l10n.weekRank, weekItems, 'copy-rank-week'),
      (l10n.monthRank, monthItems, 'copy-rank-month'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (title, items, scope) in boards)
          if (items.isNotEmpty) ...[
            Row(
              children: [
                Container(
                  width: 3,
                  height: 14,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: AppRadius.fullR,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: tt.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _CopyHorizontalComicList(items: items, onTap: onTap, scope: scope),
            const SizedBox(height: AppSpacing.md),
          ],
      ],
    );
  }
}

class _CopyEmptySectionMessage extends StatelessWidget {
  const _CopyEmptySectionMessage();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SizedBox(
      height: 96,
      child: Center(
        child: Text(
          AppLocalizations.of(context)!.noContent,
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}
