part of '../about_page.dart';

extension _AboutPageUpdateSettings on _AboutPageState {
  bool _isValidUpdateMirrorPrefix(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.hasScheme &&
        uri.hasAuthority &&
        (uri.scheme == 'http' || uri.scheme == 'https');
  }

  Future<void> _editUpdateMirrorPrefix() async {
    final l10n = AppLocalizations.of(context)!;
    final formKey = GlobalKey<FormState>();

    // 控制器交给 TextControllerScope 托管：弹窗退出动画期间子树仍会重建，
    // 提前 dispose 会命中 “used after being disposed” 断言。
    final mirrorPrefix = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final cs = Theme.of(dialogContext).colorScheme;
        final tt = Theme.of(dialogContext).textTheme;

        return TextControllerScope(
          initialText: _user.updateMirrorPrefix,
          builder: (dialogContext, controller) => AlertDialog(
            title: Text(l10n.aboutMirrorPrefixTitle),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.aboutMirrorPrefixDesc,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: controller,
                      autofocus: true,
                      keyboardType: TextInputType.url,
                      inputFormatters: [
                        FilteringTextInputFormatter.deny(RegExp(r'\s')),
                      ],
                      decoration: InputDecoration(
                        labelText: l10n.aboutMirrorPrefixLabel,
                        hintText: UserManager.defaultUpdateMirrorPrefix,
                        helperText: l10n.aboutMirrorPrefixHelper,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final trimmed = value?.trim() ?? '';
                        if (trimmed.isEmpty) return null;
                        if (!_isValidUpdateMirrorPrefix(trimmed)) {
                          return l10n.aboutInvalidMirrorPrefix;
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  UserManager.defaultUpdateMirrorPrefix,
                ),
                child: Text(l10n.aboutRestoreDefaultButton),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(l10n.cancelButton),
              ),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState?.validate() ?? false) {
                    Navigator.pop(dialogContext, controller.text);
                  }
                },
                child: Text(l10n.aboutSaveButton),
              ),
            ],
          ),
        );
      },
    );

    if (mirrorPrefix == null) return;
    await _user.setUpdateMirrorPrefix(mirrorPrefix);
    if (!mounted) return;
    showToast(context, l10n.aboutMirrorPrefixSavedToast);
  }

  Widget _buildUpdateChannelChip(ColorScheme cs, AppLocalizations l10n) {
    final isBeta = _user.isBetaUpdateChannel;
    final fg = isBeta ? Colors.amber.shade900 : cs.onSurfaceVariant;
    return InkWell(
      onTap: _showUpdateChannelDialog,
      borderRadius: AppRadius.xlR,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isBeta
              ? Colors.amber.withValues(alpha: 0.14)
              : cs.surfaceContainerHighest,
          borderRadius: AppRadius.xlR,
          border: Border.all(color: isBeta ? Colors.amber : cs.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isBeta ? Icons.science_outlined : Icons.flag_outlined,
              size: 14,
              color: fg,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              isBeta ? 'Beta' : l10n.aboutStableChannelShort,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showUpdateChannelDialog() async {
    final l10n = AppLocalizations.of(context)!;
    var selected = _user.updateChannel;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: Text(l10n.aboutUpdateChannelTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioGroup<String>(
                    groupValue: selected,
                    onChanged: (value) {
                      if (value != null) _setState(() => selected = value);
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          value: 'stable',
                          title: Text(l10n.aboutStableChannelTitle),
                          subtitle: Text(l10n.aboutStableChannelDesc),
                        ),
                        RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          value: 'beta',
                          title: Text(l10n.aboutBetaChannelTitle),
                          subtitle: Text(l10n.aboutBetaChannelDesc),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n.cancelButton),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, selected),
                  child: Text(l10n.confirmButton),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null && result != _user.updateChannel) {
      await _user.setUpdateChannel(result);
      if (!mounted) return;
      if (result == 'beta') {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.aboutBetaChannelSwitchedTitle),
            content: Text(l10n.aboutBetaChannelSwitchedContent),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.aboutGotItButton),
              ),
            ],
          ),
        );
      }
    }
  }

  /// 更新设置卡：检查更新 / 自动检查 / 更新镜像。
  Widget _buildUpdateSettingsCard(ColorScheme cs, AppLocalizations l10n) {
    return SettingTileGroup(
      children: [
        ListTile(
          leading: const Icon(Icons.system_update_alt),
          title: Text(l10n.aboutCheckUpdateTitle),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildUpdateChannelChip(cs, l10n),
              const SizedBox(width: AppSpacing.xs),
              const Icon(Icons.chevron_right),
            ],
          ),
          onTap: () => AppUpdateService.checkAndPrompt(context),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.autorenew),
          title: Text(l10n.aboutAutoCheckUpdateTitle),
          value: _user.autoCheckUpdate,
          onChanged: _user.setAutoCheckUpdate,
        ),
        ListTile(
          leading: const Icon(Icons.public),
          title: Text(l10n.aboutMirrorPrefixTitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: _editUpdateMirrorPrefix,
        ),
      ],
    );
  }

  /// 法律/致谢卡：免责声明 / 鸣谢 / 许可证。
  Widget _buildLegalCard(ColorScheme cs, AppLocalizations l10n) {
    return SettingTileGroup(
      children: [
        ListTile(
          leading: const Icon(Icons.gavel_outlined),
          title: Text(l10n.disclaimerTitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.pushNamed(AppRoutes.disclaimer),
        ),
        ListTile(
          leading: const Icon(Icons.favorite_outline),
          title: Text(l10n.aboutAcknowledgementTitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.pushNamed(AppRoutes.acknowledgement),
        ),
        ListTile(
          leading: const Icon(Icons.copyright_outlined),
          title: Text(l10n.aboutLicenseTitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.pushNamed(AppRoutes.license),
        ),
      ],
    );
  }
}
