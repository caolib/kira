import 'package:flutter/material.dart';

import '../theme/app_radius.dart';

/// A group of setting tiles separated by small gaps instead of dividers.
///
/// Inspired by RikkaHub's `CardGroup`: each child is wrapped in a rounded
/// [Material] clip with a [ColorScheme.surfaceBright] background, and tiles
/// are stacked with a thin [gap] between them that reveals the page
/// background — producing a subtle groove rather than a drawn line. Corner
/// radii follow RikkaHub's scheme: outer corners (top of the first tile,
/// bottom of the last) use [outerRadius], inner corners use [innerRadius].
///
/// Shadows follow the global card elevation from [CardTheme] — the same
/// mechanism [Card] uses — so the「卡片阴影大小」setting applies here too.
///
/// Wrap each child in a [ListTile] / [SwitchListTile] (or any widget whose
/// ink you want clipped to the tile shape).
///
/// Pass [axis] = [Axis.horizontal] to lay tiles out side by side — for rows of
/// equal-weight actions such as the about page's「仓库 / 反馈 / 日志」. Children
/// are wrapped in [Expanded], so they must be inside a bounded-width parent.
class SettingTileGroup extends StatelessWidget {
  final List<Widget> children;
  final Color? color;
  final double gap;
  final double outerRadius;
  final double innerRadius;

  /// [Axis.vertical] stacks tiles (default); [Axis.horizontal] puts them in a row.
  final Axis axis;

  const SettingTileGroup({
    super.key,
    required this.children,
    this.color,
    this.gap = 2,
    this.outerRadius = AppRadius.lg,
    this.innerRadius = AppRadius.xs,
    this.axis = Axis.vertical,
  });

  BorderRadius _radiusFor(int index, int count, Axis axis) {
    if (count == 1) {
      return BorderRadius.circular(outerRadius);
    }
    final isFirst = index == 0;
    final isLast = index == count - 1;
    switch (axis) {
      case Axis.vertical:
        return BorderRadius.only(
          topLeft: Radius.circular(isFirst ? outerRadius : innerRadius),
          topRight: Radius.circular(isFirst ? outerRadius : innerRadius),
          bottomLeft: Radius.circular(isLast ? outerRadius : innerRadius),
          bottomRight: Radius.circular(isLast ? outerRadius : innerRadius),
        );
      case Axis.horizontal:
        return BorderRadius.only(
          topLeft: Radius.circular(isFirst ? outerRadius : innerRadius),
          bottomLeft: Radius.circular(isFirst ? outerRadius : innerRadius),
          topRight: Radius.circular(isLast ? outerRadius : innerRadius),
          bottomRight: Radius.circular(isLast ? outerRadius : innerRadius),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = color ?? cs.surfaceBright;
    final count = children.length;
    if (axis == Axis.horizontal) {
      // IntrinsicHeight + stretch 让各 tile 等高:内容行高不同(如仅一方有
      // 两行文字)时,背景块仍对齐成一条。
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < count; i++) ...[
              Expanded(
                child: _SettingTile(
                  background: bg,
                  borderRadius: _radiusFor(i, count, Axis.horizontal),
                  child: children[i],
                ),
              ),
              if (i != count - 1) SizedBox(width: gap),
            ],
          ],
        ),
      );
    }
    return Column(
      children: [
        for (int i = 0; i < count; i++) ...[
          _SettingTile(
            background: bg,
            borderRadius: _radiusFor(i, count, Axis.vertical),
            child: children[i],
          ),
          if (i != count - 1) SizedBox(height: gap),
        ],
      ],
    );
  }
}

class _SettingTile extends StatelessWidget {
  final Widget child;
  final Color background;
  final BorderRadius borderRadius;

  const _SettingTile({
    required this.child,
    required this.background,
    required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    // 与 Card 同源的阴影机制：读取全局 CardTheme.elevation（由「卡片阴影
    // 大小」设置驱动），保证设置页的滑块对所有卡片生效。
    final elevation = Theme.of(context).cardTheme.elevation ?? 0;
    return Material(
      color: background,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      elevation: elevation,
      surfaceTintColor: Colors.transparent,
      child: child,
    );
  }
}
