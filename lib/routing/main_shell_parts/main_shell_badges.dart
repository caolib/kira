part of '../main_shell.dart';

class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String labelKey;
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.labelKey,
  });
}

class _BadgeIcon extends StatelessWidget {
  const _BadgeIcon({required this.showBadge, required this.child});

  final bool showBadge;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!showBadge) return child;
    final cs = Theme.of(context).colorScheme;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -2,
          top: -2,
          child: ExcludeSemantics(
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: cs.primary,
                shape: BoxShape.circle,
                border: Border.all(color: cs.surface, width: 1.2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NoticeBadgeIcon extends StatelessWidget {
  const _NoticeBadgeIcon({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: RemoteNoticeService.unreadActiveCount,
      builder: (_, count, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: AppUpdateService.hasUnseenUpdate,
          builder: (_, hasUnseenUpdate, _) {
            final showBadge = count > 0 || hasUnseenUpdate;
            return _BadgeIcon(showBadge: showBadge, child: child);
          },
        );
      },
    );
  }
}

class _DisclaimerDialog extends StatefulWidget {
  final List<String> items;
  final String confirmLabel;

  const _DisclaimerDialog({required this.items, required this.confirmLabel});

  @override
  State<_DisclaimerDialog> createState() => _DisclaimerDialogState();
}

class _DisclaimerDialogState extends State<_DisclaimerDialog> {
  bool _accepted = false;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(l10n.disclaimerTitle),
        content: SizedBox(
          width: dialogContentWidth(context, 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final item in widget.items) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('• ', style: tt.bodyMedium),
                            Expanded(child: Text(item, style: tt.bodyMedium)),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        l10n.disclaimerAgreeNote,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              CheckboxListTile(
                value: _accepted,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(widget.confirmLabel),
                onChanged: (value) {
                  setState(() => _accepted = value ?? false);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => SystemNavigator.pop(),
            child: Text(l10n.disagreeAndExit),
          ),
          FilledButton(
            onPressed: _accepted ? () => Navigator.of(context).pop(true) : null,
            child: Text(l10n.confirmButton),
          ),
        ],
      ),
    );
  }
}
