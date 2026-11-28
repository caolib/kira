import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_radius.dart';
import '../utils/adaptive_motion.dart';

/// Unified bottom-sheet chrome: shape, background color and drag handle in
/// one place.
///
/// Previously five sheets (comments x3 panels, reader panels x2) each
/// hand-rolled this chrome with drifting radii (20/24) and two handle
/// variants; system `showModalBottomSheet` callers got a third look. Now:
/// - build chrome by hand → use [AppSheet] / [showAppSheet];
/// - existing widgets that draw their own frame for layout reasons → apply
///   [AppSheet.borderRadius] / [AppSheet.backgroundColor] / [AppSheetHandle]
///   so every sheet reads as the same component.
class AppSheet extends StatelessWidget {
  const AppSheet({
    super.key,
    this.heightFactor,
    this.showHandle = true,
    this.padding = EdgeInsets.zero,
    required this.child,
  });

  /// When set, the sheet is pinned to the bottom at this fraction of the
  /// screen height and [child] expands to fill it (for scrollable sheets).
  /// When null the sheet hugs its content.
  final double? heightFactor;

  /// Whether to render the drag handle above the content.
  final bool showHandle;

  /// Padding around [child] (below the handle).
  final EdgeInsets padding;

  final Widget child;

  /// Sheet corner radius — matches `bottomSheetTheme` in main.dart so themed
  /// and hand-built sheets look identical.
  static const BorderRadius borderRadius = BorderRadius.vertical(
    top: Radius.circular(20),
  );

  /// Material 3's width limit, also used when setting custom height bounds.
  static const double maxWidth = 640;

  /// Sheet background — M3 modal-sheet role.
  static Color backgroundColor(ColorScheme cs) => cs.surfaceContainerLow;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fixedHeight = heightFactor != null;

    Widget frame = Material(
      color: backgroundColor(cs),
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: fixedHeight ? MainAxisSize.max : MainAxisSize.min,
          children: [
            if (showHandle) const AppSheetHandle(),
            if (fixedHeight)
              Expanded(
                child: Padding(padding: padding, child: child),
              )
            else
              // Hug-content sheet: child provides its own scrolling
              // (e.g. SingleChildScrollView) when it exceeds the screen.
              Flexible(
                child: Padding(padding: padding, child: child),
              ),
          ],
        ),
      ),
    );

    if (heightFactor case final factor?) {
      frame = Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: double.infinity,
          height: MediaQuery.sizeOf(context).height * factor,
          child: frame,
        ),
      );
    }
    return frame;
  }
}

/// M3-spec drag handle (32x4) with its own top spacing, used by every sheet.
class AppSheetHandle extends StatelessWidget {
  const AppSheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Center(
        child: Container(
          width: 32,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            borderRadius: AppRadius.fullR,
          ),
        ),
      ),
    );
  }
}

/// Show a modal bottom sheet in the unified [AppSheet] chrome.
///
/// Fills the available width up to [maxWidth]. Only full-screen sheets should
/// pass [double.infinity]. Pass [heightFactor] for a fixed height, or
/// [maxHeightFactor] to cap a content-sized sheet (including its handle and
/// safe area). Leave both height parameters null for compact menus.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  double? heightFactor,
  double? maxHeightFactor,
  double maxWidth = AppSheet.maxWidth,
  bool showHandle = true,
  EdgeInsets padding = EdgeInsets.zero,

  /// 屏障颜色；传 [Colors.transparent] 时面板背后的页面保持原有明暗
  /// （如调整遮罩类设置时需要实时看到正文）。
  Color? barrierColor,

  /// 为 true 时整个面板（含底色与把手）淡出，便于拖动遮罩类滑块时
  /// 直接观察背后的实际效果；松手后恢复。淡出不改变布局与命中测试，
  /// 正在进行的拖动可以继续。
  ValueListenable<bool>? fadeOutWhen,
  required Widget child,
}) {
  assert(
    maxHeightFactor == null || (maxHeightFactor > 0 && maxHeightFactor <= 1),
  );
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    sheetAnimationStyle: prefersReducedMotion(context)
        ? AnimationStyle.noAnimation
        : null,
    constraints: BoxConstraints(
      maxWidth: maxWidth,
      maxHeight: maxHeightFactor == null
          ? double.infinity
          : MediaQuery.sizeOf(context).height * maxHeightFactor,
    ),
    backgroundColor: Colors.transparent,
    barrierColor: barrierColor,
    builder: (_) {
      final sheet = AppSheet(
        heightFactor: heightFactor,
        showHandle: showHandle,
        padding: padding,
        child: child,
      );
      if (fadeOutWhen == null) return sheet;
      return AnimatedBuilder(
        animation: fadeOutWhen,
        builder: (context, child) => AnimatedOpacity(
          key: const ValueKey('app-sheet-fade'),
          opacity: fadeOutWhen.value ? 0 : 1,
          duration: adaptiveDuration(
            context,
            const Duration(milliseconds: 200),
          ),
          child: child,
        ),
        child: sheet,
      );
    },
  );
}
