part of '../reader_page.dart';

/// Custom pull-to-refresh wrapper for horizontal scroll modes where
/// [RefreshIndicator] cannot intercept drag gestures.
class _ReaderPullToRefresh extends StatefulWidget {
  final bool enabled;
  final Future<void> Function() onRefresh;
  final Widget child;

  const _ReaderPullToRefresh({
    required this.enabled,
    required this.onRefresh,
    required this.child,
  });

  @override
  State<_ReaderPullToRefresh> createState() => _ReaderPullToRefreshState();
}

class _ReaderPullToRefreshState extends State<_ReaderPullToRefresh> {
  static const _triggerExtent = 90.0;
  double _dragExtent = 0;
  bool _refreshing = false;

  bool get _indicatorVisible => _dragExtent > 0 || _refreshing;

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled || _refreshing) return;
    final nextExtent = (_dragExtent + details.delta.dy).clamp(
      0.0,
      _triggerExtent * 1.4,
    );
    if (nextExtent == _dragExtent) return;
    setState(() => _dragExtent = nextExtent);
  }

  Future<void> _handleDragEnd() async {
    if (!widget.enabled || _refreshing) return;
    if (_dragExtent < _triggerExtent) {
      setState(() => _dragExtent = 0);
      return;
    }

    setState(() {
      _refreshing = true;
      _dragExtent = _triggerExtent;
    });
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
          _dragExtent = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final progress = (_dragExtent / _triggerExtent).clamp(0.0, 1.0);
    return Stack(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragUpdate: _handleDragUpdate,
          onVerticalDragEnd: (_) => _handleDragEnd(),
          onVerticalDragCancel: () {
            if (!_refreshing && mounted) setState(() => _dragExtent = 0);
          },
          child: widget.child,
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: _indicatorVisible ? 1 : 0,
              child: Center(
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(10),
                  child: CircularProgressIndicator(
                    value: _refreshing ? null : progress,
                    strokeWidth: 2.4,
                    color: Colors.white,
                    backgroundColor: Colors.white24,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
