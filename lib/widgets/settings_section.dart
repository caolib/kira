import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Shared card section used by settings-style pages.
///
/// Layout:
/// ```
/// ┌─ icon  title ──────────────────────────┐
/// │  optional description                  │
/// │  child                                 │
/// └────────────────────────────────────────┘
/// ```
class SettingsSection extends StatelessWidget {
  final IconData? icon;
  final String? title;
  final String? description;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  const SettingsSection({
    super.key,
    this.icon,
    this.title,
    this.description,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hasHeader = title != null || icon != null || description != null;

    return Card(
      color: color ?? cs.surfaceContainerLow,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasHeader) ...[
              if (title != null || icon != null)
                Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, color: cs.onSurfaceVariant),
                      const SizedBox(width: AppSpacing.lg),
                    ],
                    if (title != null)
                      Expanded(
                        child: Text(
                          title!,
                          style: tt.titleSmall ?? tt.titleMedium,
                        ),
                      ),
                  ],
                ),
              if (description != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Padding(
                  padding: EdgeInsets.only(left: icon != null ? 40.0 : 0),
                  child: Text(
                    description!,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// A single settings row: icon + title/subtitle + trailing control.
class SettingsTile extends StatelessWidget {
  final IconData? icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry contentPadding;

  const SettingsTile({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 16),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: icon == null ? null : Icon(icon, color: cs.onSurfaceVariant),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing:
          trailing ??
          (onTap == null
              ? null
              : Icon(Icons.chevron_right, color: cs.onSurfaceVariant)),
      contentPadding: contentPadding,
      onTap: onTap,
    );
  }
}
