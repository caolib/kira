part of '../profile_page.dart';

extension _ProfileAccount on _ProfilePageState {
  bool _isCopyCredential(SavedCredential credential) {
    final source = credential.loginSource;
    if (source != null && source.isNotEmpty) {
      return source == 'copy';
    }
    if (credential.username == _user.savedUsername) {
      return _user.loginSource == 'copy';
    }
    return false;
  }

  String _credentialTypeLabel(
    AppLocalizations l10n,
    SavedCredential credential,
  ) {
    return _isCopyCredential(credential)
        ? l10n.profileCopyCredentialLabel
        : l10n.profileHotCredentialLabel;
  }

  IconData _credentialTypeIcon(SavedCredential credential) {
    return _isCopyCredential(credential) ? Icons.language : Icons.phone_android;
  }

  void _goLogin() async {
    final result = await context.pushNamed<bool>(AppRoutes.login);
    if (result == true && mounted) _setState(() {});
  }

  void _switchAccount() async {
    final credentials = _user.savedCredentials;
    final otherAccounts = credentials
        .where((c) => c.username != _user.username)
        .toList();
    final hasToken = otherAccounts.any(
      (c) => c.token != null && c.token!.isNotEmpty,
    );

    // 没有其他账号或没有存储令牌，回退到登录页
    if (otherAccounts.isEmpty || !hasToken) {
      final result = await context.pushNamed<bool>(AppRoutes.login);
      if (result == true && mounted) {
        showToast(context, AppLocalizations.of(context)!.accountSwitchedToast);
        _setState(() {});
      }
      return;
    }

    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final selected = await showModalBottomSheet<Object>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.switchAccountTitle,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
            ...otherAccounts.map((cred) {
              final displayName = cred.nickname ?? cred.username;
              final showUsername =
                  cred.username.isNotEmpty && displayName != cred.username;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: cs.primaryContainer,
                  child: Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                    style: TextStyle(color: cs.onPrimaryContainer),
                  ),
                ),
                title: Text(displayName),
                subtitle: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showUsername)
                      Text(
                        cred.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (showUsername) const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _isCopyCredential(cred)
                            ? cs.tertiaryContainer
                            : cs.secondaryContainer,
                        borderRadius: AppRadius.fullR,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _credentialTypeIcon(cred),
                            size: 14,
                            color: _isCopyCredential(cred)
                                ? cs.onTertiaryContainer
                                : cs.onSecondaryContainer,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            _credentialTypeLabel(l10n, cred),
                            style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                              color: _isCopyCredential(cred)
                                  ? cs.onTertiaryContainer
                                  : cs.onSecondaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                trailing: const Icon(Icons.swap_horiz),
                onTap: () => Navigator.pop(ctx, cred),
              );
            }),
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () =>
                      Navigator.pop(ctx, _SwitchAccountSheetAction.addAccount),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: Text(l10n.addAccountButton),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (selected == null || !mounted) return;

    if (selected == _SwitchAccountSheetAction.addAccount) {
      final result = await context.pushNamed<bool>(AppRoutes.login);
      if (result == true && mounted) {
        showToast(context, AppLocalizations.of(context)!.accountSwitchedToast);
        _setState(() {});
      }
      return;
    }

    if (selected is! SavedCredential) return;

    if (selected.token != null && selected.token!.isNotEmpty) {
      final success = await _user.switchToCredential(selected);
      if (mounted) {
        if (success) {
          showToast(
            context,
            AppLocalizations.of(context)!.accountSwitchedToast,
          );
        } else {
          showToast(
            context,
            AppLocalizations.of(context)!.switchAccountFailedToast,
            isError: true,
          );
        }
      }
    } else {
      // 该账号无令牌，回退到登录页
      final result = await context.pushNamed<bool>(AppRoutes.login);
      if (result == true && mounted) {
        showToast(context, AppLocalizations.of(context)!.accountSwitchedToast);
        _setState(() {});
      }
    }
  }

  Future<void> _logout() async {
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.logoutTitle),
        content: Text(l10n.logoutConfirmContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.confirmButton),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await ApiClient().user.logout();
      } catch (e, stack) {
        unawaited(
          AppLogger.instance.recordWarning(
            e,
            stackTrace: stack,
            source: 'profile_page.logout',
          ),
        );
      } finally {
        await _user.logout();
      }
    }
  }

  Future<void> _refreshUserInfo() async {
    try {
      await _user.refreshUserInfo();
      if (mounted) {
        showToast(
          context,
          AppLocalizations.of(context)!.userInfoRefreshedToast,
        );
      }
    } catch (_) {
      if (mounted) {
        showToast(
          context,
          AppLocalizations.of(context)!.userInfoRefreshFailedToast,
          isError: true,
        );
      }
    }
  }

  Future<void> _copyToken() async {
    final token = _user.token;
    if (token == null || token.isEmpty) {
      showToast(
        context,
        AppLocalizations.of(context)!.tokenUnavailableToast,
        isError: true,
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: token));
    if (mounted) {
      showToast(context, AppLocalizations.of(context)!.tokenCopiedToast);
    }
  }
}
