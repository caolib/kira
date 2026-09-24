import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'shimmer_skeleton.dart';

/// 与漫画结果卡片使用相同响应式列宽的首屏骨架。
class SliverComicGridSkeleton extends StatelessWidget {
  const SliverComicGridSkeleton({
    super.key,
    required this.horizontalPadding,
    required this.cardExtent,
    this.count = 20,
  });

  final double horizontalPadding;
  final double cardExtent;
  final int count;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        AppSpacing.sm,
        horizontalPadding,
        0,
      ),
      sliver: ComicCoverSkeletonGrid(
        count: count,
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: cardExtent,
          childAspectRatio: 0.55,
          mainAxisSpacing: AppSpacing.md,
          crossAxisSpacing: AppSpacing.md,
        ),
      ),
    );
  }
}
