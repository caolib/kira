import 'package:flutter/widgets.dart';

/// 评论列表共用的滚动行为：浮动按钮的显隐与触底加载下一页。
///
/// 两个评论 sheet 此前各自维护一份逐字相同的实现，并已经出现分叉——
/// 只有章节评论会在滚到底部时重新显示浮动按钮，漫画评论一路下滑到底后
/// 按钮再也回不来。这里采用前者的行为。
///
/// 使用方需要：
/// - 在自己的 `initState` / `dispose` 中调用 `super`（沿用 Flutter 惯例即可）
/// - **不要**自行 dispose [scrollController] 或 [showFloatingButtons]
mixin CommentScrollBehavior<T extends StatefulWidget> on State<T> {
  /// 距底部多远开始预加载下一页。
  static const loadMoreThreshold = 240.0;

  /// 方向判定死区，避免细微抖动让按钮反复显隐。
  static const _directionDeadZone = 2.0;

  final ScrollController scrollController = ScrollController();

  /// 向下滚动隐藏、向上滚动或抵达底部时显示。
  final ValueNotifier<bool> showFloatingButtons = ValueNotifier(true);

  double _lastScrollOffset = 0;

  /// 是否还有下一页可以加载（加载中或已全部载入时应返回 false）。
  bool get canLoadMore;

  /// 接近底部时触发，实现方在此发起下一页请求。
  void loadMoreComments();

  @override
  void initState() {
    super.initState();
    scrollController.addListener(_handleScrollDirection);
  }

  @override
  void dispose() {
    scrollController.removeListener(_handleScrollDirection);
    scrollController.dispose();
    showFloatingButtons.dispose();
    super.dispose();
  }

  void _handleScrollDirection() {
    if (!scrollController.hasClients) return;
    final position = scrollController.position;
    final offset = position.pixels;
    // 抵达底部时始终恢复显示，否则滑到底后按钮无法再出现。
    if (offset >= position.maxScrollExtent && !showFloatingButtons.value) {
      showFloatingButtons.value = true;
    } else if (offset > _lastScrollOffset + _directionDeadZone &&
        showFloatingButtons.value) {
      showFloatingButtons.value = false;
    } else if (offset < _lastScrollOffset - _directionDeadZone &&
        !showFloatingButtons.value) {
      showFloatingButtons.value = true;
    }
    _lastScrollOffset = offset;
  }

  /// 挂到 `NotificationListener<ScrollNotification>` 上。
  bool handleScrollNotification(ScrollNotification notification) {
    tryLoadMoreWhenNearBottom(metrics: notification.metrics);
    return false;
  }

  /// 列表内容变化后也可主动调用，处理「首屏未填满」的情况。
  void tryLoadMoreWhenNearBottom({ScrollMetrics? metrics}) {
    if (!canLoadMore) return;
    final currentMetrics =
        metrics ??
        (scrollController.hasClients ? scrollController.position : null);
    if (currentMetrics == null) return;
    if (currentMetrics.extentAfter <= loadMoreThreshold) {
      loadMoreComments();
    }
  }
}
