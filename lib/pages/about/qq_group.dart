part of '../about_page.dart';

extension _AboutPageQqGroup on _AboutPageState {
  void _showQQGroupDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset(
                'assets/qq.svg',
                width: 64,
                height: 64,
                colorFilter: const ColorFilter.mode(
                  Color(0xFF1EBAFC),
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                l10n.aboutQqGroupTitle,
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppSpacing.xl),
              InkWell(
                onTap: () async {
                  await launchUrl(
                    Uri.parse(_AboutPageState._qqGroupUrl),
                    mode: LaunchMode.externalApplication,
                  );
                },
                borderRadius: AppRadius.mdR,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.08),
                    borderRadius: AppRadius.mdR,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.open_in_new, size: 18, color: cs.primary),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        l10n.aboutJoinGroupButton,
                        style: tt.bodyLarge?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              InkWell(
                onTap: () async {
                  await Clipboard.setData(
                    const ClipboardData(text: _AboutPageState._qqGroupNumber),
                  );
                  if (dialogContext.mounted) {
                    showToast(dialogContext, l10n.aboutGroupNumberCopiedToast);
                  }
                },
                borderRadius: AppRadius.mdR,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: AppRadius.mdR,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _AboutPageState._qqGroupNumber,
                        style: tt.titleMedium?.copyWith(
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Icon(
                        Icons.copy_rounded,
                        size: 18,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.closeButton),
            ),
          ],
        );
      },
    );
  }
}
