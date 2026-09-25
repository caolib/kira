part of '../search_page.dart';

/// 两个标签页共用的右下角「回到顶部」按钮。
class _BackToTopButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _BackToTopButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: SizedBox.square(
        dimension: 48,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: cs.primaryContainer,
            foregroundColor: cs.onPrimaryContainer,
            elevation: 6,
            shadowColor: AppShadows.floatingTint(0.22),
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.smR),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: onPressed,
          child: const Icon(Icons.arrow_upward_rounded),
        ),
      ),
    );
  }
}

/// 排序行行尾的数据源切换按钮（仅「发现」页用，搜索页固定 HOT 源）。
///
/// 显示**当前**源名称，点击后切到另一个源。只影响「发现」页，
/// 与首页各自独立。
class _SourceToggle extends StatelessWidget {
  final bool isCopy;
  final VoidCallback onPressed;

  const _SourceToggle({required this.isCopy, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tt = Theme.of(context).textTheme;

    return Tooltip(
      message: isCopy ? l10n.switchToHotSource : l10n.switchToCopySource,
      child: FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: const Icon(Icons.swap_horiz, size: AppIconSize.lg),
        label: Text(
          isCopy ? l10n.homeSourceCopy : l10n.homeSourceHot,
          style: tt.labelLarge,
        ),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          minimumSize: const Size(0, 34),
          // 与同行筛选 chip 一致的圆角矩形，而非按钮默认的胶囊形。
          shape: RoundedRectangleBorder(borderRadius: AppRadius.smR),
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

/// 筛选 chip 行里的一个选项。
class _ChipOption {
  final String label;

  /// 选项值；空串表示「不筛选」（地区行的「全部」）。
  final String value;
  final IconData? icon;
  final bool selected;

  const _ChipOption({
    required this.label,
    required this.value,
    this.icon,
    this.selected = false,
  });
}

/// 筛选行行尾的紧凑文字按钮（展开全部 / 收起 / 重置）。
///
/// 必须显式压掉平台默认的触控尺寸：Android 默认
/// `MaterialTapTargetSize.padded` + `VisualDensity.standard`，按钮最小高 48，
/// 比 34pt 的 chip 高 14pt；同级 Row 取两者最大高度，chip 垂直居中后上下各
/// 多出 7pt 空白，「地区 / 题材 / 排序」三层筛选的间隔因此比 Windows 大。
/// 桌面默认本就是 compact + shrinkWrap，所以这里只影响移动端。
TextButton _filterRowButton({
  required VoidCallback onPressed,
  required IconData icon,
  required String label,
}) => TextButton.icon(
  onPressed: onPressed,
  icon: Icon(icon, size: AppIconSize.lg),
  label: Text(label),
  style: TextButton.styleFrom(
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  ),
);

/// 一条可横向滚动的筛选 chip 行，用于「发现」页筛选区。
///
/// COPY 源题材较多，收起时横向浏览，展开时改用换行网格。
/// [trailing] 固定在行尾（不随 chips 滚动），用于「重置」这类常驻操作。
class _FilterChipRow extends StatelessWidget {
  final List<_ChipOption> options;
  final ValueChanged<_ChipOption> onTap;
  final Widget? trailing;

  const _FilterChipRow({
    required this.options,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty && trailing == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final chips = SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (_, i) {
          final option = options[i];
          final fg = option.selected
              ? cs.onSecondaryContainer
              : cs.onSurfaceVariant;
          return FilterChip(
            avatar: option.icon == null
                ? null
                : Icon(option.icon, size: AppIconSize.sm, color: fg),
            label: Text(option.label),
            selected: option.selected,
            showCheckmark: false,
            labelStyle: tt.labelLarge?.copyWith(color: fg),
            onSelected: (_) => onTap(option),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          );
        },
      ),
    );

    if (trailing == null) return chips;
    return Row(
      children: [
        // 可滚动部分占据剩余宽度，trailing 固定在最右。
        Expanded(child: chips),
        const SizedBox(width: AppSpacing.sm),
        trailing!,
      ],
    );
  }
}

/// 漫画结果网格，两个标签页共用。
class _ComicGrid extends StatelessWidget {
  final List<Comic> comics;
  final double hp;
  final double cardExtent;
  final bool loadingMore;
  final String scope;
  final void Function(Comic comic, String heroTagBase) onOpen;

  const _ComicGrid({
    required this.comics,
    required this.hp,
    required this.cardExtent,
    required this.loadingMore,
    required this.scope,
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
            scope: scope,
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

/// 展开后的全部题材网格（内联，非弹层），与横向题材行互斥显示。
class _AllTagsGrid extends StatelessWidget {
  final List<m.Theme> tags;
  final String? selectedTag;
  final ValueChanged<String?> onSelected;

  const _AllTagsGrid({
    required this.tags,
    required this.selectedTag,
    required this.onSelected,
  });

  /// tag 数量的紧凑显示：11376 -> 1.1万。与漫画详情页 formatPopular 同规则。
  static String _formatCount(AppLocalizations l10n, int n) {
    if (n >= 100000000) {
      return l10n.hundredMillionUnit((n / 100000000).toStringAsFixed(1));
    }
    if (n >= 10000) {
      return l10n.tenThousandUnit((n / 10000).toStringAsFixed(1));
    }
    return n.toString();
  }

  /// 与筛选行 chip 同样的尺寸压制，否则 Android 上这里的 chip 会比
  /// 上面那行高 4pt，展开前后的标签看起来是两种规格。
  static const _chipDensity = VisualDensity.compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // 显式压掉平台默认尺寸：Android 的 padded + standard 会把 chip 撑到 38，
    // 桌面本就是 compact，只会让两端一致。
    FilterChip chip({
      required Widget label,
      required bool selected,
      required VoidCallback onSelected,
    }) => FilterChip(
      label: label,
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onSelected(),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: _chipDensity,
    );

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip(
          label: Text(l10n.searchFilterAll),
          selected: selectedTag == null,
          onSelected: () => onSelected(null),
        ),
        for (final t in tags)
          chip(
            // 数字作为次级信息内联在名字后：小一号 + 降透明度，
            // 避免 4~5 位长数字喧宾夺主。
            label: Text.rich(
              TextSpan(
                text: t.name,
                children: [
                  if (t.count > 0)
                    TextSpan(
                      text: ' ${_formatCount(l10n, t.count)}',
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                ],
              ),
            ),
            selected: selectedTag == t.pathWord,
            onSelected: () => onSelected(t.pathWord),
          ),
      ],
    );
  }
}
