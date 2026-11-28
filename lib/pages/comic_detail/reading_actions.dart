import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_icon_sizes.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

class ComicDetailReadingActions extends StatelessWidget {
  const ComicDetailReadingActions({
    super.key,
    required this.continueLabel,
    required this.onContinue,
    this.nextLabel,
    this.onNext,
    this.onBackToTop,
  });

  final String continueLabel;
  final VoidCallback? onContinue;
  final String? nextLabel;
  final VoidCallback? onNext;
  final VoidCallback? onBackToTop;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final labelStyle = AppTypography.fabLabel(theme.textTheme);

    final hasReading = onNext != null || onContinue != null;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 回顶出现前预留左槽，避免小屏或大字号下右侧按钮移位。
        SizedBox(
          width: 56,
          child: onBackToTop == null
              ? null
              : FloatingActionButton(
                  key: const ValueKey('comic_back_to_top_action'),
                  heroTag: null,
                  tooltip: l10n.backToTop,
                  backgroundColor: cs.secondaryContainer,
                  foregroundColor: cs.onSecondaryContainer,
                  onPressed: onBackToTop,
                  child: const Icon(
                    Icons.vertical_align_top,
                    size: AppIconSize.xl,
                  ),
                ),
        ),
        if (hasReading) const SizedBox(width: AppSpacing.md),
        if (hasReading)
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onNext != null)
                  Flexible(
                    child: FloatingActionButton.extended(
                      key: const ValueKey('comic_next_action'),
                      heroTag: 'next_chapter',
                      backgroundColor: cs.primaryContainer,
                      foregroundColor: cs.onPrimaryContainer,
                      onPressed: onNext,
                      icon: const Icon(Icons.skip_next, size: AppIconSize.lg),
                      label: Text(
                        nextLabel ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: labelStyle,
                      ),
                    ),
                  ),
                if (onNext != null && onContinue != null)
                  const SizedBox(width: AppSpacing.md),
                if (onContinue != null)
                  Flexible(
                    child: FloatingActionButton.extended(
                      key: const ValueKey('comic_continue_action'),
                      heroTag: 'continue_reading',
                      backgroundColor: onNext == null
                          ? cs.primaryContainer
                          : cs.secondaryContainer,
                      foregroundColor: onNext == null
                          ? cs.onPrimaryContainer
                          : cs.onSecondaryContainer,
                      onPressed: onContinue,
                      icon: const Icon(Icons.play_arrow, size: AppIconSize.lg),
                      label: Text(
                        continueLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: labelStyle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
