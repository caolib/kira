import 'package:flutter/material.dart';

import '../../backup/backup_category.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/section_header.dart';
import '../../widgets/setting_tile_group.dart';
import 'backup_labels.dart';

class BackupContentControls extends StatelessWidget {
  final Set<BackupCategory> selected;

  /// Entry sizes per category, absent until the first measurement completes.
  final Map<BackupCategory, int>? sizes;
  final bool enabled;
  final bool encrypted;
  final bool passwordSet;
  final bool passwordRemembered;
  final void Function(BackupCategory category, bool selected) onSelect;
  final ValueChanged<bool> onSelectAll;
  final ValueChanged<bool> onEncryptionChanged;
  final VoidCallback onPassword;

  const BackupContentControls({
    super.key,
    required this.selected,
    required this.sizes,
    required this.enabled,
    required this.encrypted,
    required this.passwordSet,
    required this.passwordRemembered,
    required this.onSelect,
    required this.onSelectAll,
    required this.onEncryptionChanged,
    required this.onPassword,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sizes = this.sizes;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: l10n.backupContent, icon: Icons.checklist_rounded),
        const SizedBox(height: AppSpacing.sm),
        SettingTileGroup(
          children: [
            CheckboxListTile(
              title: Text(l10n.selectAll),
              value: selected.length == BackupCategory.values.length,
              onChanged: enabled
                  ? (value) => onSelectAll(value ?? false)
                  : null,
            ),
            for (final category in BackupCategory.values)
              CheckboxListTile(
                title: Text(backupCategoryLabel(category, l10n)),
                subtitle: sizes == null
                    ? null
                    : Text(
                        formatBackupBytes(sizes[category] ?? 0),
                        style: AppTypography.meta(tt),
                      ),
                value: selected.contains(category),
                onChanged: enabled
                    ? (value) => onSelect(category, value ?? false)
                    : null,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxl),
        SettingTileGroup(
          children: [
            SwitchListTile(
              title: Text(l10n.backupEncryption),
              value: encrypted,
              onChanged: enabled ? onEncryptionChanged : null,
            ),
            if (encrypted)
              ListTile(
                leading: const Icon(Icons.password_rounded),
                title: Text(l10n.backupPassword),
                subtitle: Text(
                  passwordSet
                      ? (passwordRemembered
                            ? l10n.backupPasswordRemembered
                            : l10n.backupPasswordSessionOnly)
                      : l10n.backupPasswordNotSet,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: enabled ? onPassword : null,
              ),
          ],
        ),
      ],
    );
  }
}
