import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_spacing.dart';
import '../../utils/dialog_width.dart';

/// 只编辑保留策略，不在修改上限时清理远端文件。
class WebDavRetentionDialog extends StatefulWidget {
  final int initialLimit;

  const WebDavRetentionDialog({super.key, required this.initialLimit});

  @override
  State<WebDavRetentionDialog> createState() => _WebDavRetentionDialogState();
}

class _WebDavRetentionDialogState extends State<WebDavRetentionDialog> {
  late bool _unlimited = widget.initialLimit == 0;
  late String _input = widget.initialLimit == 0
      ? ''
      : widget.initialLimit.toString();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final limit = _unlimited ? 0 : int.tryParse(_input.trim(), radix: 10);
    final valid = limit != null && limit >= 0;
    return AlertDialog(
      scrollable: true,
      title: Text(l10n.backupRetentionTitle),
      content: SizedBox(
        width: dialogContentWidth(context, 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.backupRetentionHint),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.backupRetentionUnlimited),
              value: _unlimited,
              onChanged: (value) => setState(() => _unlimited = value),
            ),
            if (!_unlimited) ...[
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                initialValue: _input,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.backupRetentionTitle,
                  border: const OutlineInputBorder(),
                  errorText: !valid && _input.isNotEmpty
                      ? l10n.backupRetentionInvalid
                      : null,
                ),
                onChanged: (value) => setState(() => _input = value),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancelButton),
        ),
        FilledButton(
          onPressed: valid ? () => Navigator.pop(context, limit) : null,
          child: Text(l10n.backupSaveConfiguration),
        ),
      ],
    );
  }
}
