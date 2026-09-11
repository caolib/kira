import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_icon_sizes.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

/// Unified section header row: primary-tinted leading icon + bold title +
/// optional trailing affordance.
///
/// Home, search and reader-chrome sections used to each hand-roll this row
/// (icon 18 vs 20, title small vs medium). Keep one component so a section
/// reads identically everywhere.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.onMore,
    this.trailing,
    this.onTap,
  });

  final String title;

  /// Leading icon — section headers always lead with a primary-tinted glyph.
  final IconData? icon;

  /// Convenience for the common "更多 ›" affordance.
  final VoidCallback? onMore;

  /// Custom trailing widget (e.g. a rotating expand arrow). Ignored when
  /// [onMore] is set.
  final Widget? trailing;

  /// Makes the whole row tappable (collapsible sections).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.xsR,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            if (icon case final icon?) ...[
              Icon(icon, size: AppIconSize.lg, color: cs.primary),
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            if (onMore != null)
              TextButton(
                onPressed: onMore,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.moreButton),
                    const Icon(Icons.chevron_right, size: AppIconSize.md),
                  ],
                ),
              )
            else
              ?trailing,
          ],
        ),
      ),
    );
  }
}
