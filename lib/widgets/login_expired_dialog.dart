import 'package:flutter/material.dart';

/// Shows a "login expired" dialog with customizable [featureName] and
/// returns `true` if the user taps "去登录", `false` otherwise.
///
/// Used by browse_history_page, bookshelf_page, and any future page
/// that needs to prompt re-login after token expiry.
Future<bool> showLoginExpiredDialog(
  BuildContext context, {
  required String featureName,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('登录已过期'),
      content: Text('$featureName需要登录后才能继续使用，是否现在重新登录？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('稍后再说'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('去登录'),
        ),
      ],
    ),
  ).then((value) => value ?? false);
}
