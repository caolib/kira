import 'package:flutter/material.dart';

/// 结果列表的回顶显隐和近底加载；不处理内嵌列表或横向筛选条。
class ResultScrollListener extends StatefulWidget {
  const ResultScrollListener({
    super.key,
    required this.child,
    required this.canScrollUp,
    required this.onCanScrollUpChanged,
    this.onLoadMore,
  });

  final Widget child;
  final bool canScrollUp;
  final ValueChanged<bool> onCanScrollUpChanged;
  final VoidCallback? onLoadMore;

  @override
  State<ResultScrollListener> createState() => _ResultScrollListenerState();
}

class _ResultScrollListenerState extends State<ResultScrollListener> {
  late bool _canScrollUp = widget.canScrollUp;

  @override
  void didUpdateWidget(covariant ResultScrollListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    _canScrollUp = widget.canScrollUp;
  }

  void _updateScrollability(ScrollMetrics metrics) {
    final next =
        metrics.pixels > metrics.minScrollExtent &&
        metrics.maxScrollExtent > metrics.minScrollExtent;
    if (next == _canScrollUp) return;
    // 同一帧可能往返滚动，按最近一次通知去重，不能用上次 build 的快照。
    _canScrollUp = next;
    widget.onCanScrollUpChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        if (notification.depth == 0 &&
            notification.metrics.axis == Axis.vertical) {
          _updateScrollability(notification.metrics);
        }
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.depth != 0 ||
              notification.metrics.axis != Axis.vertical) {
            return false;
          }
          final metrics = notification.metrics;
          _updateScrollability(metrics);
          if ((notification is ScrollUpdateNotification ||
                  notification is ScrollEndNotification) &&
              metrics.pixels > metrics.minScrollExtent &&
              metrics.extentAfter < 300) {
            widget.onLoadMore?.call();
          }
          return false;
        },
        child: widget.child,
      ),
    );
  }
}
