import 'package:flutter/material.dart';

import '../../backup/backup_category.dart';
import '../../backup/backup_codec.dart';
import '../../backup/backup_document.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_spacing.dart';
import '../../utils/dialog_width.dart';
import 'backup_labels.dart';

class BackupRestoreDialog extends StatefulWidget {
  final BackupDocument document;

  const BackupRestoreDialog({super.key, required this.document});

  @override
  State<BackupRestoreDialog> createState() => _BackupRestoreDialogState();
}

class _BackupRestoreDialogState extends State<BackupRestoreDialog> {
  /// Every category stored in the file starts selected.
  late final _selected = Set<BackupCategory>.of(widget.document.categories);
  late final _summaries = measureBackupCategories(widget.document);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final document = widget.document;
    return AlertDialog(
      title: Text(l10n.backupRestoreTitle),
      scrollable: true,
      content: SizedBox(
        width: dialogContentWidth(context, 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.backupRestoreWarning),
            if (document.exportedAt case final time?) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                formatBackupTime(time),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (document.skippedCount > 0) ...[
              const SizedBox(height: AppSpacing.md),
              Text(l10n.backupLegacyWarning(document.skippedCount)),
            ],
            const SizedBox(height: AppSpacing.md),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _selected.length == document.categories.length,
              title: Text(l10n.selectAll),
              onChanged: (value) => setState(() {
                _selected.clear();
                if (value == true) _selected.addAll(document.categories);
              }),
            ),
            for (final category in BackupCategory.values)
              if (document.categories.contains(category))
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _selected.contains(category),
                  title: Text(backupCategoryLabel(category, l10n)),
                  subtitle: Text(_categoryCountLabel(category, l10n)),
                  onChanged: (value) => setState(() {
                    if (value == true) {
                      _selected.add(category);
                    } else {
                      _selected.remove(category);
                    }
                  }),
                ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancelButton),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, Set<BackupCategory>.of(_selected)),
          child: Text(l10n.backupRestore),
        ),
      ],
    );
  }

  String _categoryCountLabel(BackupCategory category, AppLocalizations l10n) {
    final summary = _summaries[category];
    if (summary == null || summary.count == 0) return l10n.backupEmptyCategory;
    return l10n.backupCategoryCountSize(
      summary.count,
      formatBackupBytes(summary.rawBytes),
    );
  }
}
