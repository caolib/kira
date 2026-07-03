import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
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
      final backup = await _settingsBackup.exportPlainText();
      final summary = _settingsBackup.inspectPlainText(backup);
      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导出设置'),
          content: Text(
            '将复制 ${summary.preferenceCount} 项持久化配置到剪贴板，包含账号、密码、令牌和本地阅读记录。导出内容为明文，请谨慎保管。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('复制'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
      await Clipboard.setData(ClipboardData(text: backup));
      if (mounted) {
        showToast(context, '设置已复制到剪贴板，内容为明文');
      }
    } catch (e) {
      if (mounted) {
        showToast(context, '导出失败：$e', isError: true);
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
        showToast(context, '没有可导入的配置内容', isError: true);
      }
      return;
    }

    final SettingsBackupSummary summary;
    try {
      summary = _settingsBackup.inspectPlainText(text);
    } catch (e) {
      if (mounted) {
        showToast(context, '导入失败：$e', isError: true);
      }
      return;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('覆盖导入'),
        content: Text(
          '将覆盖当前 ${summary.preferenceCount} 项持久化配置，包含账号、主题、阅读器设置和本地阅读记录。'
          '${summary.exportedAt != null ? '\n\n备份时间：${_formatBackupTime(summary.exportedAt!)}' : ''}'
          '\n\n临时缓存不会导入，当前配置会被替换。是否继续？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认导入'),
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
        showToast(context, '配置已导入并覆盖本地设置');
      }
    } catch (e) {
      if (mounted) {
        showToast(context, '导入失败：$e', isError: true);
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
        showToast(context, '应用已重置，已清除 $removedCount 项本地数据');
      }
    } catch (e) {
      if (mounted) {
        showToast(context, '重置失败：$e', isError: true);
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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final canAutoLogin =
        _user.isLoggedIn &&
        _user.savedUsername != null &&
        _user.savedPassword != null;

    return Scaffold(
      appBar: AppBar(title: const Text('通用')),
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
                    title: const Text('自动登录'),
                    subtitle: Text(
                      canAutoLogin ? '登录过期时自动重新登录' : '登录并保存账号密码后可用',
                      style: tt.bodySmall,
                    ),
                    value: canAutoLogin ? _user.autoLogin : false,
                    onChanged: canAutoLogin ? _user.setAutoLogin : null,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  SwitchListTile(
                    secondary: const Icon(Icons.movie_outlined),
                    title: const Text('动漫功能'),
                    subtitle: Text('关闭后隐藏动漫相关功能', style: tt.bodySmall),
                    value: _user.animeFeatureEnabled,
                    onChanged: _user.setAnimeFeatureEnabled,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  SwitchListTile(
                    secondary: const Icon(Icons.view_carousel_outlined),
                    title: const Text('显示Banner'),
                    subtitle: Text(
                      '关闭后漫画和动漫主页顶部Banner不显示',
                      style: tt.bodySmall,
                    ),
                    value: _user.bannerVisible,
                    onChanged: _user.setBannerVisible,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.language_rounded),
                    title: const Text('语言'),
                    subtitle: Text(switch (_user.locale) {
                      'zh-Hant' => '繁體中文',
                      _ => '简体中文（跟随系统）',
                    }, style: tt.bodySmall),
                    trailing: PopupMenuButton<String>(
                      icon: const Icon(Icons.arrow_drop_down),
                      onSelected: _user.setLocale,
                      itemBuilder: (ctx) => const [
                        PopupMenuItem(value: '', child: Text('简体中文（跟随系统）')),
                        PopupMenuItem(value: 'zh-Hant', child: Text('繁體中文')),
                      ],
                    ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.storage_rounded),
                    title: const Text('缓存管理'),
                    subtitle: const Text('查看和删除本地缓存、历史和账号数据'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      context.pushNamed(AppRoutes.cacheManagement);
                    },
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.upload_file_rounded),
                    title: const Text('导出设置'),
                    subtitle: const Text('复制配置到剪贴板'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _exportSettings,
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.download_for_offline_rounded),
                    title: const Text('导入设置'),
                    subtitle: const Text('粘贴导入配置'),
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
                      '重置应用',
                      style: tt.titleMedium?.copyWith(
                        color: cs.onErrorContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      '清除本地设置、账号、阅读记录和缓存，不会删除已下载的本地漫画文件',
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
                        label: Text(_resetting ? '正在重置...' : '重置应用'),
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
    return AlertDialog(
      title: const Text('导入设置'),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: _controller,
          autofocus: true,
          minLines: 10,
          maxLines: 18,
          decoration: const InputDecoration(
            hintText: '粘贴导出的配置 JSON',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('继续'),
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
  static const _requiredText = '重置应用';

  late final TextEditingController _controller;

  bool get _matched => _controller.text.trim() == _requiredText;

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
    return AlertDialog(
      title: const Text('确认重置应用'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('此操作会清除应用本地保存的设置、账号、阅读记录和缓存，且无法撤销。'),
            const SizedBox(height: 12),
            const Text('如需继续，请在下方输入框中输入“重置应用”。'),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '确认文本',
                hintText: '重置应用',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _matched ? () => Navigator.pop(context, true) : null,
          child: const Text('确认重置'),
        ),
      ],
    );
  }
}
