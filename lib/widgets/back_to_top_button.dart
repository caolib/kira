import 'package:flutter/material.dart';

import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';

/// 右下角悬浮「回到顶部」按钮。
///
/// 方形 FilledButton：primaryContainer 底 + 零内边距固定 48px，
/// 保证正方形且图标居中。书架、搜索、推荐/榜单等列表页共用。
class BackToTopButton extends StatelessWidget {
  final VoidCallback onPressed;

  final String? tooltip;

  const BackToTopButton({super.key, required this.onPressed, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final button = SizedBox.square(
      dimension: 48,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: cs.primaryContainer,
          foregroundColor: cs.onPrimaryContainer,
          elevation: 6,
          shadowColor: AppShadows.floatingTint(0.22),
          padding: EdgeInsets.zero,
          minimumSize: const Size.square(48),
          maximumSize: const Size.square(48),
          fixedSize: const Size.square(48),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.smR),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: onPressed,
        child: const Icon(Icons.arrow_upward_rounded),
      ),
    );

    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}
