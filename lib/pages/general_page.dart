import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
import '../l10n/app_localizations.dart';
import '../models/user_manager.dart';
import '../routing/app_router.dart';
import '../theme/app_spacing.dart';
import '../utils/app_logger.dart';
import '../utils/dialog_width.dart';
import '../utils/settings_backup.dart';
import '../utils/settings_reload.dart';
import '../utils/toast.dart';
import '../widgets/select_tile.dart';
import '../widgets/setting_tile_group.dart';

class GeneralPage extends StatefulWidget {
  const GeneralPage({super.key});

  @override
  State<GeneralPage> createState() => _GeneralPageState();
}

class _GeneralPageState extends State<GeneralPage> {
  final _user = UserManager();
  final _settingsBackup = SettingsBackupService();
  bool _resetting = false;

  @override
  void initState() {
    super.initState();
    _user.addListener(_onChanged);
  }

  @override
  void dispose() {
    _user.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _resetApp() async {
    if (_resetting) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _ResetAppDialog(),
    );
    if (confirmed != true) return;

    setState(() {
      _resetting = true;
    });

    try {
      final removedCount = await _settingsBackup.clearAllPreferences();
      await AppLogger.instance.clear();
      ApiClient().user.clearAuthState();
      await reloadRuntimeSettings();
      if (mounted) {
        showToast(
          context,
          AppLocalizations.of(context)!.appResetToast(removedCount),
        );
      }
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          AppLocalizations.of(context)!.resetFailed(e.toString()),
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _resetting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final canAutoLogin =
        _user.isLoggedIn &&
        _user.savedUsername != null &&
        _user.savedPassword != null;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.generalTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          SettingTileGroup(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.login_rounded),
                title: Text(l10n.autoLoginTitle),
                subtitle: Text(
                  canAutoLogin
                      ? l10n.autoLoginEnabledDesc
                      : l10n.autoLoginUnavailableDesc,
                  style: tt.bodySmall,
                ),
                value: canAutoLogin ? _user.autoLogin : false,
                onChanged: canAutoLogin ? _user.setAutoLogin : null,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.view_carousel_outlined),
                title: Text(l10n.bannerVisibleTitle),
                subtitle: Text(l10n.bannerVisibleDesc, style: tt.bodySmall),
                value: _user.bannerVisible,
                onChanged: _user.setBannerVisible,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.exit_to_app_rounded),
                title: Text(l10n.backExitConfirmTitle),
                subtitle: Text(l10n.backExitConfirmDesc, style: tt.bodySmall),
                value: _user.theme.backExitConfirm,
                onChanged: _user.theme.setBackExitConfirm,
              ),
              ListTile(
                leading: const Icon(Icons.language_rounded),
                title: Text(l10n.languageTitle),
                trailing: SelectTile<String>(
                  value: _user.locale,
                  items: [
                    SelectItem('', l10n.languageSystem),
                    SelectItem('zh', l10n.languageSimplified),
                    SelectItem('zh-Hant', l10n.languageTraditional),
                  ],
                  onChanged: _user.setLocale,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.storage_rounded),
                title: Text(l10n.cacheManagementTitle),
                subtitle: Text(l10n.cacheManagementDesc),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  context.pushNamed(AppRoutes.cacheManagement);
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SettingTileGroup(
            children: [
              ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: Text(l10n.backupTitle),
                subtitle: Text(l10n.backupEntryDescription),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.pushNamed(AppRoutes.backup),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SettingTileGroup(
            children: [
              ListTile(
                leading: const Icon(Icons.restart_alt_rounded),
                title: Text(l10n.resetAppTitle),
                subtitle: Text(
                  l10n.resetAppDesc,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                trailing: _resetting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: _resetting ? null : _resetApp,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResetAppDialog extends StatefulWidget {
  const _ResetAppDialog();

  @override
  State<_ResetAppDialog> createState() => _ResetAppDialogState();
}

class _ResetAppDialogState extends State<_ResetAppDialog> {
  late final TextEditingController _controller;

  bool _matched(String requiredText) => _controller.text.trim() == requiredText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController()..addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final requiredText = l10n.resetAppTitle;

    return AlertDialog(
      title: Text(l10n.confirmResetAppTitle),
      content: SizedBox(
        width: dialogContentWidth(context, 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.resetAppWarning),
            const SizedBox(height: AppSpacing.md),
            Text(l10n.resetAppInstruction(requiredText)),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.confirmTextLabel,
                hintText: requiredText,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancelButton),
        ),
        FilledButton(
          onPressed: _matched(requiredText)
              ? () => Navigator.pop(context, true)
              : null,
          child: Text(l10n.confirmResetButton),
        ),
      ],
    );
  }
}
