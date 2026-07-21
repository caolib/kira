part of '../anime_player_page.dart';

class _ErrorPanel extends StatelessWidget {
  final String message;
  final String? rawError;
  final bool requiresLogin;
  final VoidCallback onLogin;
  final VoidCallback onRetry;
  final VoidCallback onLogCopied;

  const _ErrorPanel({
    required this.message,
    this.rawError,
    required this.requiresLogin,
    required this.onLogin,
    required this.onRetry,
    required this.onLogCopied,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              requiresLogin ? Icons.lock_outline : Icons.cloud_off,
              color: PlayerChrome.onSurfaceMuted,
              size: 40,
            ),
            const SizedBox(height: 8),
            Text(
              requiresLogin
                  ? l10n.loginRequiredTitle
                  : l10n.playbackFailedTitle,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: PlayerChrome.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: PlayerChrome.onSurfaceMuted,
              ),
            ),
            const SizedBox(height: 10),
            if (requiresLogin)
              FilledButton.icon(
                onPressed: onLogin,
                icon: const Icon(Icons.login),
                label: Text(l10n.goLoginButton),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (rawError != null) ...[
                    TextButton.icon(
                      onPressed: () => _showErrorLog(context),
                      icon: const Icon(Icons.bug_report_outlined, size: 18),
                      label: Text(l10n.viewLogButton),
                      style: TextButton.styleFrom(
                        foregroundColor: PlayerChrome.onSurfaceMuted,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  FilledButton.tonal(
                    onPressed: onRetry,
                    child: Text(l10n.retryButton),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _showErrorLog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;

        return AlertDialog(
          title: Text(l10n.errorLogTitle),
          content: SingleChildScrollView(
            child: SelectableText(
              rawError ?? l10n.noLogInfo,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                if (rawError != null) {
                  await Clipboard.setData(ClipboardData(text: rawError!));
                  if (context.mounted) {
                    onLogCopied();
                  }
                }
              },
              child: Text(l10n.copyButton),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.closeButton),
            ),
          ],
        );
      },
    );
  }
}
