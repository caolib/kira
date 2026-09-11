part of '../cache_management_page.dart';

class _CacheEntryTile extends StatelessWidget {
  const _CacheEntryTile({
    required this.entry,
    required this.preview,
    required this.sizeLabel,
    required this.value,
    required this.revealed,
    required this.onToggleSensitive,
    required this.onDelete,
  });

  final _CacheEntry entry;
  final String preview;
  final String sizeLabel;
  final String value;
  final bool revealed;
  final VoidCallback? onToggleSensitive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 8),
      onTap: () => _showDetailDialog(context),
      title: Text(
        entry.key,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: tt.bodyMedium?.copyWith(fontFamily: 'monospace'),
      ),
      subtitle: Text(
        '${entry.typeLabel} · $sizeLabel · $preview',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: tt.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onToggleSensitive != null)
            IconButton(
              tooltip: revealed
                  ? l10n.cacheHideSensitiveTooltip
                  : l10n.cacheShowSensitiveTooltip,
              onPressed: onToggleSensitive,
              icon: Icon(
                revealed ? Icons.visibility_off_rounded : Icons.visibility,
              ),
            ),
          IconButton(
            tooltip: l10n.deleteButton,
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline_rounded, color: cs.error),
          ),
        ],
      ),
    );
  }

  Future<void> _showDetailDialog(BuildContext context) async {
    final copied = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        final tt = Theme.of(dialogContext).textTheme;
        final maxContentHeight = MediaQuery.sizeOf(dialogContext).height * 0.6;

        return AlertDialog(
          title: Text(l10n.cacheEntryDataTitle),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  entry.key,
                  style: tt.titleSmall?.copyWith(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 6),
                Text('$sizeLabel · ${entry.typeLabel}', style: tt.bodySmall),
                const SizedBox(height: AppSpacing.md),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxContentHeight),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      value,
                      style: tt.bodySmall?.copyWith(fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.closeButton),
            ),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: value));
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              },
              icon: const Icon(Icons.copy_rounded),
              label: Text(l10n.copyButton),
            ),
          ],
        );
      },
    );

    if (copied == true && context.mounted) {
      showToast(context, AppLocalizations.of(context)!.cacheDataCopiedToast);
    }
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 40),
            const SizedBox(height: AppSpacing.md),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(AppLocalizations.of(context)!.retryButton),
            ),
          ],
        ),
      ),
    );
  }
}
