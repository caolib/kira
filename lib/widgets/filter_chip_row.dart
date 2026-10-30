import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_icon_sizes.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

part 'filter_chip_row_parts/justified_tag_wrap.dart';

/// 筛选 chip 行里的一个选项。
class FilterChipOption {
  final String label;

  /// 选项值；空串表示「不筛选」（如「全部」）。
  final String value;
  final IconData? icon;
  final bool selected;

  const FilterChipOption({
    required this.label,
    required this.value,
    this.icon,
    this.selected = false,
  });
}

/// 一条可横向滚动的筛选 chip 行，「发现」页与轻小说首页共用。
///
/// 选项较多时横向浏览，展开全部时改用换行网格（见 [AllTagsGrid]）。
/// [trailing] 固定在行尾（不随 chips 滚动），用于「重置」这类常驻操作。
class FilterChipRow extends StatelessWidget {
  final List<FilterChipOption> options;
  final ValueChanged<FilterChipOption> onTap;
  final Widget? trailing;

  const FilterChipRow({
    super.key,
    required this.options,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty && trailing == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final labelPainter = TextPainter(
      text: TextSpan(text: '字', style: tt.labelLarge),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    // 38 为 shrinkWrap 下 labelLarge 文字的默认 chip 高；大字号时按文字高跟踪。
    final rowHeight = math.max(38.0, labelPainter.height + AppSpacing.lg);
    labelPainter.dispose();

    final chips = SizedBox(
      height: rowHeight,
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

/// 筛选行行尾的文字按钮，与标签同样保持紧凑外观。
TextButton filterRowButton({
  required VoidCallback onPressed,
  required IconData icon,
  required String label,
}) => TextButton.icon(
  onPressed: onPressed,
  icon: Icon(icon, size: AppIconSize.lg),
  label: Text(label),
  style: TextButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
);

/// 标签区的展开/收起按钮，沿用筛选 chip 的边框、圆角与紧凑高度。
class FilterTagsToggleButton extends StatelessWidget {
  final bool expanded;
  final VoidCallback onPressed;

  const FilterTagsToggleButton({
    super.key,
    required this.expanded,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return ActionChip(
      avatar: Icon(
        expanded ? Icons.expand_less : Icons.expand_more,
        size: AppIconSize.lg,
        color: theme.colorScheme.primary,
      ),
      label: Text(expanded ? l10n.tagsCollapseAll : l10n.tagsExpandAll),
      labelStyle: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.primary,
      ),
      onPressed: onPressed,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

/// 行尾「重置」按钮：与未选中筛选 chip 同款（边框 + 透明底 + onSurfaceVariant），
/// 视觉上融入 chip 行，而非无边框的文字按钮。
class FilterRowResetButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const FilterRowResetButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return FilterChip(
      avatar: Icon(icon, size: AppIconSize.sm, color: cs.onSurfaceVariant),
      label: Text(
        label,
        style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant),
      ),
      showCheckmark: false,
      onSelected: (_) => onPressed(),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

/// 展开后的全部标签网格（内联，非弹层），与横向标签行互斥显示。
///
/// 漫画题材（`comic.Theme`）与小说题材（`NovelTag`）都只用到名字/slug/数量，
/// 由调用方映射成 [FilterTagOption]，避免共享组件依赖任一模型。
class FilterTagOption {
  final String name;
  final String pathWord;
  final int count;

  const FilterTagOption({
    required this.name,
    required this.pathWord,
    this.count = 0,
  });
}

class AllTagsGrid extends StatelessWidget {
  final List<FilterTagOption> tags;
  final String? selectedTag;
  final ValueChanged<String?> onSelected;

  const AllTagsGrid({
    super.key,
    required this.tags,
    required this.selectedTag,
    required this.onSelected,
  });

  /// 数量的紧凑显示：11376 -> 1.1万。与漫画详情页 formatPopular 同规则。
  static String _formatCount(AppLocalizations l10n, int n) {
    if (n >= 100000000) {
      return l10n.hundredMillionUnit((n / 100000000).toStringAsFixed(1));
    }
    if (n >= 10000) {
      return l10n.tenThousandUnit((n / 10000).toStringAsFixed(1));
    }
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    FilterChip chip({
      required Widget label,
      required bool selected,
      required VoidCallback onSelected,
    }) => FilterChip(
      // label 撑开后，chip 的可见边框与点击区域才会一起填满分配的宽度。
      label: Center(heightFactor: 1, child: label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onSelected(),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    return _JustifiedTagWrap(
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

/// 非阻断错误：保留已有筛选/内容，且只有显式点击才会重试。
class InlineRetryNotice extends StatelessWidget {
  final String message;

  /// 失败的具体原因（`NetworkError.describe` 的结果），单独一行显示，
  /// 与固定文案分开，避免把可排查的信息压成一句「失败，请重试」。
  final String? detail;

  final VoidCallback onRetry;

  const InlineRetryNotice({
    super.key,
    required this.message,
    this.detail,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final detail = this.detail?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Semantics(
        liveRegion: true,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(message),
                  if (detail.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        detail,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: AppIconSize.lg),
              label: Text(l10n.retryButton),
            ),
          ],
        ),
      ),
    );
  }
}

/// 「数据源切换」这类行尾按钮：与同行筛选 chip 一致的圆角矩形，
/// 而非按钮默认的胶囊形。
class FilterRowAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? tooltip;
  final VoidCallback onPressed;

  const FilterRowAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final button = FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon, size: AppIconSize.lg),
      label: Text(label, style: tt.labelLarge),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        minimumSize: const Size(0, 34),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.smR),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
