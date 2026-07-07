import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
import '../l10n/app_localizations.dart';
import '../models/user_manager.dart';
import '../routing/app_router.dart';
import '../utils/app_logger.dart';
import '../utils/settings_backup.dart';
import '../utils/toast.dart';

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

  Future<void> _exportSettings() async {
    try {
      final safeBackup = await _settingsBackup.exportPlainText();
      final safeSummary = _settingsBackup.inspectPlainText(safeBackup);
      final sensitiveBackup = await _settingsBackup.exportPlainText(
        options: const SettingsBackupOptions(includeSensitive: true),
      );
      final sensitiveSummary = _settingsBackup.inspectPlainText(
        sensitiveBackup,
      );
      if (!mounted) return;

      final includeSensitive = await showDialog<bool>(
        context: context,
        builder: (ctx) => _ExportSettingsDialog(
          safeSummary: safeSummary,
          sensitiveSummary: sensitiveSummary,
        ),
      );

      if (includeSensitive == null) return;
      await Clipboard.setData(
        ClipboardData(text: includeSensitive ? sensitiveBackup : safeBackup),
      );
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        showToast(
          context,
          includeSensitive
              ? l10n.settingsCopiedWithSensitive
              : l10n.settingsCopiedWithoutSensitive,
        );
      }
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          AppLocalizations.of(context)!.exportFailed(e.toString()),
          isError: true,
        );
      }
    }
  }

  Future<void> _importSettings() async {
    final clipboardText = (await Clipboard.getData('text/plain'))?.text ?? '';
    if (!mounted) return;

    final raw = await showDialog<String>(
      context: context,
      builder: (ctx) => _ImportSettingsDialog(initialValue: clipboardText),
    );
    if (raw == null) return;

    final text = raw.trim();
    if (text.isEmpty) {
      if (mounted) {
        showToast(
          context,
          AppLocalizations.of(context)!.noImportSettingsContent,
          isError: true,
        );
      }
      return;
    }

    final SettingsBackupSummary summary;
    try {
      summary = _settingsBackup.inspectPlainText(text);
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        final error = e is SettingsBackupException
            ? e.localizedMessage(l10n)
            : e.toString();
        showToast(context, l10n.importFailed(error), isError: true);
      }
      return;
    }

    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.overwriteImportTitle),
        content: Text(
          l10n.overwriteImportContent(
            summary.preferenceCount,
            summary.exportedAt == null
                ? ''
                : l10n.backupTimeLine(_formatBackupTime(summary.exportedAt!)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.confirmImportButton),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _settingsBackup.importPlainText(text);
      ApiClient().user.clearAuthState();
      await _user.init();
      if (mounted) {
        showToast(context, AppLocalizations.of(context)!.settingsImportedToast);
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        final error = e is SettingsBackupException
            ? e.localizedMessage(l10n)
            : e.toString();
        showToast(context, l10n.importFailed(error), isError: true);
      }
    }
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
      await _user.init();
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

  String _formatBackupTime(DateTime time) {
    final local = time.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
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
          Card(
            color: cs.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
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
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  SwitchListTile(
                    secondary: const Icon(Icons.movie_outlined),
                    title: Text(l10n.animeFeatureTitle),
                    subtitle: Text(l10n.animeFeatureDesc, style: tt.bodySmall),
                    value: _user.animeFeatureEnabled,
                    onChanged: _user.setAnimeFeatureEnabled,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  SwitchListTile(
                    secondary: const Icon(Icons.notifications_outlined),
                    title: Text(l10n.remoteNoticeTitle),
                    subtitle: Text(l10n.remoteNoticeDesc, style: tt.bodySmall),
                    value: _user.remoteNoticeEnabled,
                    onChanged: _user.setRemoteNoticeEnabled,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  SwitchListTile(
                    secondary: const Icon(Icons.view_carousel_outlined),
                    title: Text(l10n.bannerVisibleTitle),
                    subtitle: Text(l10n.bannerVisibleDesc, style: tt.bodySmall),
                    value: _user.bannerVisible,
                    onChanged: _user.setBannerVisible,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.language_rounded),
                    title: Text(l10n.languageTitle),
                    subtitle: Text(switch (_user.locale) {
                      'zh-Hant' => l10n.languageTraditional,
                      _ => l10n.languageSimplifiedSystem,
                    }, style: tt.bodySmall),
                    trailing: PopupMenuButton<String>(
                      icon: const Icon(Icons.arrow_drop_down),
                      onSelected: _user.setLocale,
                      itemBuilder: (ctx) => [
                        PopupMenuItem(
                          value: '',
                          child: Text(l10n.languageSimplifiedSystem),
                        ),
                        PopupMenuItem(
                          value: 'zh-Hant',
                          child: Text(l10n.languageTraditional),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.storage_rounded),
                    title: Text(l10n.cacheManagementTitle),
                    subtitle: Text(l10n.cacheManagementDesc),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      context.pushNamed(AppRoutes.cacheManagement);
                    },
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.upload_file_rounded),
                    title: Text(l10n.exportSettingsTitle),
                    subtitle: Text(l10n.exportSettingsDesc),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _exportSettings,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.download_for_offline_rounded),
                    title: Text(l10n.importSettingsTitle),
                    subtitle: Text(l10n.importSettingsDesc),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _importSettings,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: cs.errorContainer.withValues(alpha: 0.7),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(
                      Icons.restart_alt_rounded,
                      color: cs.onErrorContainer,
                    ),
                    title: Text(
                      l10n.resetAppTitle,
                      style: tt.titleMedium?.copyWith(
                        color: cs.onErrorContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      l10n.resetAppDesc,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onErrorContainer.withValues(alpha: 0.88),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _resetting ? null : _resetApp,
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.error,
                          foregroundColor: cs.onError,
                        ),
                        icon: _resetting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.delete_sweep_rounded),
                        label: Text(
                          _resetting ? l10n.resettingApp : l10n.resetAppTitle,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExportSettingsDialog extends StatefulWidget {
  final SettingsBackupSummary safeSummary;
  final SettingsBackupSummary sensitiveSummary;

  const _ExportSettingsDialog({
    required this.safeSummary,
    required this.sensitiveSummary,
  });

  @override
  State<_ExportSettingsDialog> createState() => _ExportSettingsDialogState();
}

class _ExportSettingsDialogState extends State<_ExportSettingsDialog> {
  bool _includeSensitive = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final exportedCount = _includeSensitive
        ? widget.sensitiveSummary.preferenceCount
        : widget.safeSummary.preferenceCount;
    final sensitiveCount = widget.sensitiveSummary.sensitivePreferenceCount;

    return AlertDialog(
      title: Text(l10n.exportSettingsTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.exportSettingsContent(exportedCount)),
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.includeSensitiveSettingsTitle),
            subtitle: Text(
              sensitiveCount == 0
                  ? l10n.noSensitiveSettingsFound
                  : l10n.includeSensitiveSettingsDesc(sensitiveCount),
            ),
            value: _includeSensitive,
            onChanged: sensitiveCount == 0
                ? null
                : (value) {
                    setState(() {
                      _includeSensitive = value ?? false;
                    });
                  },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancelButton),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _includeSensitive),
          child: Text(l10n.copyButton),
        ),
      ],
    );
  }
}

class _ImportSettingsDialog extends StatefulWidget {
  final String initialValue;

  const _ImportSettingsDialog({required this.initialValue});

  @override
  State<_ImportSettingsDialog> createState() => _ImportSettingsDialogState();
}

class _ImportSettingsDialogState extends State<_ImportSettingsDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.importSettingsTitle),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: _controller,
          autofocus: true,
          minLines: 10,
          maxLines: 18,
          decoration: InputDecoration(
            hintText: l10n.pasteExportedSettingsHint,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancelButton),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(l10n.continueButton),
        ),
      ],
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
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.resetAppWarning),
            const SizedBox(height: 12),
            Text(l10n.resetAppInstruction(requiredText)),
            const SizedBox(height: 16),
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
