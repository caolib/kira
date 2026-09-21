import 'package:flutter/material.dart';

import '../../backup/backup_category.dart';
import '../../backup/backup_codec.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_status_colors.dart';
import '../../theme/app_typography.dart';
import '../../utils/dialog_width.dart';
import 'backup_labels.dart';

class BackupPreviewDialog extends StatelessWidget {
  final PreparedBackup prepared;
  final bool encrypted;
  final String actionLabel;

  const BackupPreviewDialog({
    super.key,
    required this.prepared,
    required this.encrypted,
    required this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final total = prepared.entryBytes;
    return AlertDialog(
      title: Text(l10n.backupPreview),
      scrollable: true,
      content: SizedBox(
        width: dialogContentWidth(context, 480),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.backupPreviewContents, style: tt.bodySmall),
            const SizedBox(height: AppSpacing.lg),
            for (final category in BackupCategory.values)
              if (prepared.summaries[category] case final summary?) ...[
                Text(backupCategoryLabel(category, l10n), style: tt.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.backupCategorySize(
                    summary.count,
                    formatBackupBytes(summary.rawBytes),
                    (total == 0 ? 0 : 100 * summary.rawBytes / total)
                        .toStringAsFixed(1),
                  ),
                  style: AppTypography.meta(tt),
                ),
                const SizedBox(height: AppSpacing.sm),
                LinearProgressIndicator(
                  value: total == 0 ? 0 : summary.rawBytes / total,
                  color: cs.primary,
                  backgroundColor: cs.surfaceContainerHighest,
                  borderRadius: AppRadius.xsR,
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            Text(
              l10n.backupFinalSize(
                formatBackupBytes(
                  prepared.compressed.length +
                      (encrypted
                          ? BackupCodec.headerLength + BackupCodec.tagLength
                          : 0),
                ),
              ),
              style: tt.titleSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              encrypted
                  ? l10n.backupEncryptedFormat
                  : l10n.backupUnencryptedFormat,
              style: tt.bodyMedium?.copyWith(
                color: encrypted ? cs.primary : AppStatusColors.warning(cs),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancelButton),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(actionLabel),
        ),
      ],
    );
  }
}
