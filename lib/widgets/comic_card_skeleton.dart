import 'package:flutter/material.dart';

/// 漫画卡片骨架占位（封面 + 标题 + 副信息条），带呼吸式透明度动画。
/// 用于网格列表的初始加载与加载更多状态。
class ComicCardSkeleton extends StatefulWidget {
  const ComicCardSkeleton({super.key});

  @override
  State<ComicCardSkeleton> createState() => _ComicCardSkeletonState();
}

class _ComicCardSkeletonState extends State<ComicCardSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final alpha = 0.15 + 0.15 * _controller.value;
        final color = cs.onSurfaceVariant.withValues(alpha: alpha);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: 60,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        );
      },
    );
  }
}
