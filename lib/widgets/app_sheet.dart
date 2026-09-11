import 'package:flutter/material.dart';

import '../theme/app_radius.dart';

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
/// Full-width like the app's existing sheets: pass [heightFactor] for
/// scrollable sheets (comments, settings), leave it null for compact menus.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  double? heightFactor,
  bool showHandle = true,
  EdgeInsets padding = EdgeInsets.zero,
  required Widget child,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width),
    backgroundColor: Colors.transparent,
    builder: (_) => AppSheet(
      heightFactor: heightFactor,
      showHandle: showHandle,
      padding: padding,
      child: child,
    ),
  );
}
