import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Shows the unified "login expired" dialog with page-specific [content]
/// copy and returns `true` if the user taps "去登录", `false` otherwise.
///
/// Used by browse_history_page, bookshelf_page, and any future page
/// that needs to prompt re-login after token expiry — never hand-roll an
/// AlertDialog for this flow again.
Future<bool> showLoginExpiredDialog(
  BuildContext context, {
  required String content,
}) {
  final l10n = AppLocalizations.of(context)!;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.loginExpiredTitle),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.laterButton),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.goLoginButton),
        ),
      ],
    ),
  ).then((value) => value ?? false);
}
