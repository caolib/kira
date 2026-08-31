import 'package:flutter/material.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';

/// 列表底部的「加载更多」按钮。
///
/// 宽屏下一页结果可能不满一屏、列表不可滚动，近底自动加载永远等不到
/// 触发——这个显式按钮是那种场景下的兜底入口；可滚动的列表里它同时
/// 充当底部加载指示，与自动加载互不冲突（由各页 `_loadMore` 守卫防重）。
class LoadMoreFooter extends StatelessWidget {
  const LoadMoreFooter({
    super.key,
    required this.loading,
    required this.onPressed,
    required this.label,
    this.horizontalPadding = 0,
  });

  final bool loading;
  final VoidCallback onPressed;
  final String label;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 4, horizontalPadding, 8),
      child: Center(
        child: loading
            ? const SizedBox.square(
                dimension: 28,
                child: ExpressiveLoadingIndicator(),
              )
            : OutlinedButton.icon(
                onPressed: onPressed,
                icon: const Icon(Icons.expand_more_rounded),
                label: Text(label),
              ),
      ),
    );
  }
}
