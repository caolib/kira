import 'package:flutter/material.dart';

/// A pulsing skeleton placeholder that animates between two alpha levels.
///
/// Wraps any child with a shimmer-like fade animation. Use the provided
/// [ShimmerBox] for simple rectangular placeholder blocks.
class ShimmerShell extends StatefulWidget {
  final Widget child;
  const ShimmerShell({super.key, required this.child});

  @override
  State<ShimmerShell> createState() => _ShimmerShellState();
}

class _ShimmerShellState extends State<ShimmerShell>
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final alpha = 0.15 + 0.15 * _controller.value;
        return Opacity(opacity: alpha + 0.15, child: child);
      },
      child: widget.child,
    );
  }
}

/// A simple rounded-rect placeholder box for skeleton layouts.
///
/// Combine multiple [ShimmerBox] widgets inside a [ShimmerShell] to build
/// complete skeleton screens.
class ShimmerBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const ShimmerBox({super.key, this.width, this.height = 14, this.radius = 4});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: cs.onSurfaceVariant.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Pre-built grid skeleton for comic cover cards.
///
/// Shows [count] placeholder cards in a [SliverGrid] layout matching
/// the typical cover-card grid used across the app.
class ComicCoverSkeletonGrid extends StatelessWidget {
  final int count;
  final int crossAxisCount;
  final double childAspectRatio;

  const ComicCoverSkeletonGrid({
    super.key,
    this.count = 6,
    this.crossAxisCount = 3,
    this.childAspectRatio = 0.55,
  });

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: childAspectRatio,
        mainAxisSpacing: 12,
        crossAxisSpacing: 8,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) => const ShimmerShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: SizedBox.expand(),
                ),
              ),
              SizedBox(height: 6),
              ShimmerBox(height: 12),
              SizedBox(height: 4),
              ShimmerBox(width: 60, height: 10),
            ],
          ),
        ),
        childCount: count,
      ),
    );
  }
}

/// Pre-built list skeleton for horizontal comic rows.
class ComicRowSkeletonList extends StatelessWidget {
  final int count;
  final double cardWidth;

  const ComicRowSkeletonList({super.key, this.count = 4, this.cardWidth = 110});

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 180,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: count,
          itemBuilder: (context, index) => Padding(
            padding: EdgeInsets.only(right: index < count - 1 ? 10 : 0),
            child: SizedBox(
              width: cardWidth,
              child: const ShimmerShell(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Card(
                        margin: EdgeInsets.zero,
                        clipBehavior: Clip.antiAlias,
                        child: SizedBox.expand(),
                      ),
                    ),
                    SizedBox(height: 6),
                    ShimmerBox(height: 12),
                    SizedBox(height: 4),
                    ShimmerBox(width: 50, height: 10),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
