import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_spacing.dart';
import '../../utils/dialog_width.dart';

class BackupPasswordChoice {
  final String password;
  final bool remember;

  const BackupPasswordChoice(this.password, this.remember);
}

class BackupPasswordDialog extends StatefulWidget {
  final String initialPassword;
  final bool remember;
  final bool decrypting;

  const BackupPasswordDialog({
    super.key,
    this.initialPassword = '',
    this.remember = false,
    this.decrypting = false,
  });

  @override
  State<BackupPasswordDialog> createState() => _BackupPasswordDialogState();
}

class _BackupPasswordDialogState extends State<BackupPasswordDialog> {
  late final _password = TextEditingController(text: widget.initialPassword);
  late final _confirmation = TextEditingController(
    text: widget.initialPassword,
  );
  late bool _remember = widget.remember;
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final valid =
        _password.text.isNotEmpty &&
        (widget.decrypting || _password.text == _confirmation.text);
    return AlertDialog(
      title: Text(
        widget.decrypting ? l10n.backupDecryptPassword : l10n.backupPassword,
      ),
      scrollable: true,
      content: SizedBox(
        width: dialogContentWidth(context, 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.backupPasswordExplanation),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _password,
              autofocus: true,
              obscureText: _obscurePassword,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              decoration: InputDecoration(
                labelText: l10n.backupPassword,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (!widget.decrypting) ...[
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _confirmation,
                obscureText: _obscureConfirmation,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                decoration: InputDecoration(
                  labelText: l10n.backupConfirmPassword,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmation
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () => setState(
                      () => _obscureConfirmation = !_obscureConfirmation,
                    ),
                  ),
                  errorText:
                      _confirmation.text.isNotEmpty &&
                          _confirmation.text != _password.text
                      ? l10n.backupPasswordMismatch
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.backupRememberPassword),
                value: _remember,
                onChanged: (value) =>
                    setState(() => _remember = value ?? false),
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
          onPressed: valid
              ? () => Navigator.pop(
                  context,
                  BackupPasswordChoice(_password.text, _remember),
                )
              : null,
          child: Text(l10n.confirmButton),
        ),
      ],
    );
  }
}
