import 'package:flutter/material.dart';

import '../../backup/webdav_config.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_spacing.dart';
import '../../utils/dialog_width.dart';
import 'backup_labels.dart';

class WebDavConnectionDialog extends StatefulWidget {
  final WebDavConfig? config;
  final WebDavCredentials credentials;

  const WebDavConnectionDialog({
    super.key,
    this.config,
    required this.credentials,
  });

  @override
  State<WebDavConnectionDialog> createState() => _WebDavConnectionDialogState();
}

class _WebDavConnectionDialogState extends State<WebDavConnectionDialog> {
  /// 首次打开时给出的文件夹默认值，重置也回到这里。
  static const _defaultDirectory = 'kira/backups/';

  final _formKey = GlobalKey<FormState>();
  late final _server = TextEditingController(
    text: widget.config?.server.toString(),
  );
  late final _username = TextEditingController(
    text: widget.credentials.username,
  );
  late final _password = TextEditingController(
    text: widget.credentials.password,
  );
  late final _directory = TextEditingController(
    text: widget.config?.directory ?? _defaultDirectory,
  );
  String? _error;
  bool _confirming = false;

  /// 三个字段都清空就是「清除配置」：允许保存，由调用方落盘。
  bool get _blank =>
      _server.text.trim().isEmpty &&
      _username.text.trim().isEmpty &&
      _password.text.isEmpty;

  @override
  void dispose() {
    _server.dispose();
    _username.dispose();
    _password.dispose();
    _directory.dispose();
    super.dispose();
  }

  /// 把表单恢复到刚打开时的样子：三个连接字段留空即清除配置。
  void _reset() {
    for (final field in [_server, _username, _password]) {
      field.clear();
    }
    _directory.text = _defaultDirectory;
    setState(() => _error = null);
  }

  void _fillServer(String url) {
    _server
      ..text = url
      ..selection = TextSelection.collapsed(offset: url.length);
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // 三个字段都空：清除配置，由调用方删除已保存的服务器与账号密码。
    if (_blank) {
      Navigator.pop(context, (
        null,
        const WebDavCredentials(username: '', password: ''),
      ));
      return;
    }
    try {
      final config = WebDavConfig(
        serverUrl: _server.text,
        directory: _directory.text,
        allowHttp: true,
      );
      if (_username.text.contains(':') ||
          _username.text.contains(RegExp(r'[\r\n]'))) {
        throw const WebDavException(WebDavErrorCode.invalidConfiguration);
      }
      if (config.server.scheme == 'http') {
        setState(() => _confirming = true);
        final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.backupHttpWarningTitle),
            content: Text(l10n.backupHttpWarning),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.cancelButton),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.backupAcceptRisk),
              ),
            ],
          ),
        );
        if (!mounted) return;
        setState(() => _confirming = false);
        if (accepted != true) return;
      }
      if (!mounted) return;
      Navigator.pop(context, (
        config,
        WebDavCredentials(username: _username.text, password: _password.text),
      ));
    } catch (error) {
      if (mounted) setState(() => _error = backupErrorMessage(error, l10n));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final presets = [
      (
        label: l10n.backupWebDavPresetJianguoyun,
        url: 'https://dav.jianguoyun.com/dav/',
      ),
    ];
    return AlertDialog(
      title: Text(l10n.backupWebDavConfiguration),
      scrollable: true,
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: dialogContentWidth(context, 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _server,
                keyboardType: TextInputType.url,
                autocorrect: false,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                // 只做纠错：单个字段留空不算错，三个都空才是「清除配置」。
                validator: (value) => _blank || (value ?? '').trim().isNotEmpty
                    ? null
                    : l10n.backupWebDavServerRequired,
                decoration: InputDecoration(
                  labelText: l10n.backupWebDavServer,
                  hintText: 'https://example.com/dav/',
                  suffixIcon: PopupMenuButton<String>(
                    tooltip: l10n.backupWebDavPresetTitle,
                    icon: const Icon(Icons.arrow_drop_down),
                    onSelected: _fillServer,
                    itemBuilder: (context) => [
                      for (final preset in presets)
                        PopupMenuItem(
                          value: preset.url,
                          height: 64,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(preset.label),
                              Text(
                                preset.url,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              TextFormField(
                controller: _username,
                autocorrect: false,
                enableIMEPersonalizedLearning: false,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (value) => _blank || (value ?? '').trim().isNotEmpty
                    ? null
                    : l10n.backupWebDavUsernameRequired,
                decoration: InputDecoration(
                  labelText: l10n.backupWebDavUsername,
                ),
              ),
              TextFormField(
                controller: _password,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (value) => _blank || (value ?? '').isNotEmpty
                    ? null
                    : l10n.backupWebDavPasswordRequired,
                decoration: InputDecoration(
                  labelText: l10n.backupWebDavPassword,
                ),
              ),
              TextFormField(
                controller: _directory,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: l10n.backupWebDavDirectory,
                  helperText: l10n.backupWebDavDirectoryHint,
                ),
              ),
              if (_error case final error?) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  error,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      // 重置靠左、保存取消靠右：重置是清空表单，别和提交挨在一起误触。
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        // 清空即清除：三格都空着保存，等同于删掉已保存的服务器与账号密码。
        TextButton(
          onPressed: _confirming ? null : _reset,
          child: Text(l10n.resetButton),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: _confirming ? null : () => Navigator.pop(context),
              child: Text(l10n.cancelButton),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton(
              onPressed: _confirming ? null : _submit,
              child: Text(l10n.backupSaveConfiguration),
            ),
          ],
        ),
      ],
    );
  }
}
