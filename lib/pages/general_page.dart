import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
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
import '../widgets/setting_action_tile.dart';
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
  bool _importing = false;

  /// 导入进度框自己的 [BuildContext],用于精确关闭它(见 [_dismissImportProgress])。
  BuildContext? _importDialogContext;

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
      final now = DateTime.now();
      final fileName =
          'kira-settings-'
          '${now.year.toString().padLeft(4, '0')}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}'
          '-'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}'
          '.json';
      final uri = await FilePicker.saveFile(
        fileName: fileName,
        mimeType: 'application/json',
        bytes: utf8.encode(includeSensitive ? sensitiveBackup : safeBackup),
      );
      if (uri == null) return;
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        showToast(
          context,
          includeSensitive
              ? l10n.settingsExportedWithSensitive
              : l10n.settingsExportedWithoutSensitive,
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
    if (_importing) return;
    final l10n = AppLocalizations.of(context)!;
    final PlatformFile? file;
    try {
      file = await FilePicker.pickFile(dialogTitle: l10n.importSettingsTitle);
    } catch (e) {
      if (mounted) {
        showToast(context, l10n.importFailed(e.toString()), isError: true);
      }
      return;
    }
    if (file == null) return;

    final String text;
    try {
      text = utf8.decode(await file.readAsBytes());
    } catch (e) {
      if (mounted) {
        showToast(context, l10n.importFailed(e.toString()), isError: true);
      }
      return;
    }

    if (text.trim().isEmpty) {
      if (mounted) {
        showToast(context, l10n.noImportSettingsContent, isError: true);
      }
      return;
    }

    final SettingsBackupSummary summary;
    try {
      summary = _settingsBackup.inspectPlainText(text);
    } catch (e) {
      if (mounted) {
        final error = e is SettingsBackupException
            ? e.localizedMessage(l10n)
            : e.toString();
        showToast(context, l10n.importFailed(error), isError: true);
      }
      return;
    }

    if (!mounted) return;
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

    if (confirmed != true || !mounted) return;

    // 写入 + 重载各内存单例需要时间,期间给出遮罩与进度提示;
    // 否则对话框一关用户会以为已经导入完成。
    setState(() => _importing = true);
    try {
      await _showImportProgress();
      await _settingsBackup.importPlainText(text);
      ApiClient().user.clearAuthState();
      await reloadRuntimeSettings();
      if (mounted) {
        showToast(context, AppLocalizations.of(context)!.settingsImportedToast);
      }
    } catch (e) {
      if (mounted) {
        final error = e is SettingsBackupException
            ? e.localizedMessage(l10n)
            : e.toString();
        showToast(context, l10n.importFailed(error), isError: true);
      }
    } finally {
      _dismissImportProgress();
      if (mounted) setState(() => _importing = false);
    }
  }

  /// 弹出不可取消的导入进度框,直到 [_dismissImportProgress] 关闭。
  ///
  /// 与下载目录迁移的进度弹窗同款:barrierDismissible 关掉返回键与点外关闭,
  /// 让「正在导入」的状态不会被误触打断。
  Future<void> _showImportProgress() async {
    final l10n = AppLocalizations.of(context)!;
    _importDialogContext = null;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          // 记下进度框自己的 context:关闭时经它 pop,保证 pop 的是这个
          // 对话框而不是页面本身(用 canPop 判断会在对话框未入栈时误伤页面)。
          _importDialogContext = ctx;
          return AlertDialog(
            title: Text(l10n.importingSettingsTitle),
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: AppSpacing.md),
                Flexible(child: Text(l10n.importingSettingsBody)),
              ],
            ),
          );
        },
      ),
    );
    // 让对话框先完成一帧绘制,避免导入极快时闪一下又消失。
    await WidgetsBinding.instance.endOfFrame;
  }

  void _dismissImportProgress() {
    final dialogContext = _importDialogContext;
    _importDialogContext = null;
    if (dialogContext == null || !dialogContext.mounted) return;
    Navigator.of(dialogContext).pop();
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
          // 导出 / 导入并排一行,与关于页「仓库 / 反馈 / 日志」同款布局。
          SettingTileGroup(
            axis: Axis.horizontal,
            children: [
              SettingActionTile(
                icon: const Icon(Icons.upload_file_rounded),
                label: l10n.exportSettingsTitle,
                onTap: _exportSettings,
              ),
              SettingActionTile(
                icon: _importing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_for_offline_rounded),
                label: l10n.importSettingsTitle,
                onTap: _importing ? null : _importSettings,
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
          const SizedBox(height: AppSpacing.md),
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
          child: Text(l10n.exportButton),
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
