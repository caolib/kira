import 'package:flutter/material.dart';

import '../../backup/backup_schedule.dart';
import '../../backup/webdav_config.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_status_colors.dart';
import '../../theme/app_typography.dart';
import '../../widgets/error_retry_view.dart';
import '../../widgets/setting_tile_group.dart';
import 'backup_labels.dart';
import 'backup_schedule_controls.dart';
import 'webdav_retention_dialog.dart';

class WebDavPanel extends StatefulWidget {
  final WebDavConfig? config;
  final List<WebDavBackupEntry> entries;

  /// WebDAV 总开关：关闭时下面的连接设置、定时备份与远端列表全部收起来。
  final bool enabled;

  /// 有备份操作在跑时为 false：此时连总开关也锁住，避免中途改设置。
  final bool interactive;
  final bool canUpload;
  final bool listed;
  final BackupSchedule schedule;
  final int retentionLimit;

  /// 定时备份的开启条件：服务器已配置，且加密开启时有可用密码。
  final bool scheduleReady;

  /// 定时备份不可开启时的原因提示，可为空。
  final String? scheduleHint;
  final String? error;
  final ValueChanged<bool>? onToggle;
  final VoidCallback onConfigure;
  final VoidCallback onTest;
  final VoidCallback onUpload;
  final VoidCallback onRefresh;
  final ValueChanged<WebDavBackupEntry> onRestore;
  final ValueChanged<WebDavBackupEntry> onDelete;
  final Future<void> Function(List<WebDavBackupEntry>) onDeleteSelected;
  final ValueChanged<BackupSchedule> onScheduleChanged;
  final ValueChanged<int> onRetentionChanged;

  const WebDavPanel({
    super.key,
    required this.config,
    required this.entries,
    required this.enabled,
    required this.interactive,
    required this.canUpload,
    required this.listed,
    required this.schedule,
    required this.retentionLimit,
    required this.scheduleReady,
    required this.error,
    this.scheduleHint,
    required this.onToggle,
    required this.onConfigure,
    required this.onTest,
    required this.onUpload,
    required this.onRefresh,
    required this.onRestore,
    required this.onDelete,
    required this.onDeleteSelected,
    required this.onScheduleChanged,
    required this.onRetentionChanged,
  });

  @override
  State<WebDavPanel> createState() => _WebDavPanelState();
}

class _WebDavPanelState extends State<WebDavPanel> {
  final _selected = <String>{};
  bool _selecting = false;
  bool _deleting = false;

  bool get _interactive => widget.interactive && !_deleting;

  @override
  void didUpdateWidget(WebDavPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_selecting) return;
    if (!widget.enabled || widget.config == null || widget.entries.isEmpty) {
      _clearSelection();
    } else if (_selected.isNotEmpty) {
      // 父页可能就地修改 entries。只移除已消失的文件，取消确认或部分失败时仍可重试。
      _selected.retainAll(widget.entries.map((entry) => entry.name).toSet());
      if (_selected.isEmpty) _selecting = false;
    }
  }

  void _clearSelection() {
    _selecting = false;
    _selected.clear();
  }

  void _refresh() {
    if (!_interactive || widget.config == null) return;
    if (_selecting) setState(_clearSelection);
    widget.onRefresh();
  }

  Future<void> _deleteSelected() async {
    if (!_interactive || _selected.isEmpty) return;
    final entries = widget.entries
        .where((entry) => _selected.contains(entry.name))
        .toList(growable: false);
    if (entries.isEmpty) return;
    setState(() => _deleting = true);
    try {
      await widget.onDeleteSelected(entries);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _editRetention() async {
    final initialLimit = widget.retentionLimit;
    final limit = await showDialog<int>(
      context: context,
      builder: (_) => WebDavRetentionDialog(initialLimit: initialLimit),
    );
    if (mounted &&
        widget.enabled &&
        _interactive &&
        limit != null &&
        limit != widget.retentionLimit) {
      widget.onRetentionChanged(limit);
    }
  }

  Widget _selectionBar(AppLocalizations l10n) {
    final allSelected = _selected.length == widget.entries.length;
    return Wrap(
      spacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(l10n.backupSelectedCount(_selected.length)),
        ),
        TextButton(
          onPressed: !_interactive
              ? null
              : () => setState(() {
                  if (allSelected) {
                    _selected.clear();
                  } else {
                    _selected.addAll(widget.entries.map((entry) => entry.name));
                  }
                }),
          child: Text(
            allSelected ? l10n.downloadQueueDeselectAll : l10n.selectAll,
          ),
        ),
        TextButton.icon(
          onPressed: _interactive && _selected.isNotEmpty
              ? _deleteSelected
              : null,
          style: TextButton.styleFrom(
            foregroundColor: AppStatusColors.danger(
              Theme.of(context).colorScheme,
            ),
          ),
          icon: const Icon(Icons.delete_outline),
          label: Text(l10n.deleteButton),
        ),
        TextButton(
          onPressed: _interactive ? () => setState(_clearSelection) : null,
          child: Text(l10n.cancelButton),
        ),
      ],
    );
  }

  Widget _entryTile(WebDavBackupEntry entry, AppLocalizations l10n) {
    final title = Text(
      entry.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final metadata = [
      if (entry.size case final size?) formatBackupBytes(size),
      if (entry.modified case final time?) formatBackupTime(time),
    ].join(' · ');
    final subtitle = metadata.isEmpty
        ? null
        : Text(
            metadata,
            style: AppTypography.meta(Theme.of(context).textTheme),
          );
    if (_selecting) {
      return CheckboxListTile(
        controlAffinity: ListTileControlAffinity.leading,
        title: title,
        subtitle: subtitle,
        value: _selected.contains(entry.name),
        onChanged: !_interactive
            ? null
            : (checked) => setState(() {
                if (checked == true) {
                  _selected.add(entry.name);
                } else {
                  _selected.remove(entry.name);
                }
              }),
      );
    }
    return ListTile(
      leading: const Icon(Icons.description_outlined),
      title: title,
      subtitle: subtitle,
      trailing: PopupMenuButton<String>(
        enabled: _interactive,
        onSelected: (action) => action == 'restore'
            ? widget.onRestore(entry)
            : widget.onDelete(entry),
        itemBuilder: (context) => [
          PopupMenuItem(value: 'restore', child: Text(l10n.backupRestore)),
          PopupMenuItem(value: 'delete', child: Text(l10n.deleteButton)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final config = widget.config;
    final connected = widget.enabled && _interactive && config != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingTileGroup(
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.cloud_outlined),
              title: Text(l10n.backupWebDav),
              value: widget.enabled,
              onChanged: _interactive ? widget.onToggle : null,
            ),
          ],
        ),
        if (!widget.enabled)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            // 已有配置时说明「设置还在」，否则关掉开关看起来像配置被清空了。
            child: Text(
              config == null
                  ? l10n.backupWebDavDisabledHint
                  : l10n.backupWebDavDisabledHintSaved,
            ),
          )
        else ...[
          const SizedBox(height: AppSpacing.md),
          SettingTileGroup(
            children: [
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: Text(l10n.backupWebDavConfiguration),
                subtitle: Text(
                  config?.root.toString() ?? l10n.backupWebDavNotConfigured,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                enabled: _interactive,
                onTap: widget.onConfigure,
              ),
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text(l10n.backupRetentionTitle),
                subtitle: Text(
                  widget.retentionLimit == 0
                      ? l10n.backupRetentionUnlimited
                      : l10n.backupRetentionCount(widget.retentionLimit),
                ),
                trailing: const Icon(Icons.chevron_right),
                enabled: _interactive,
                onTap: _editRetention,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          BackupScheduleControls(
            schedule: widget.schedule,
            canEnable: connected && widget.scheduleReady,
            enabled: _interactive,
            hint: widget.scheduleHint,
            onChanged: widget.onScheduleChanged,
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: connected ? widget.onTest : null,
                icon: const Icon(Icons.lan_outlined),
                label: Text(l10n.backupTestConnection),
              ),
              FilledButton.icon(
                onPressed: connected && widget.canUpload
                    ? widget.onUpload
                    : null,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text(l10n.backupUpload),
              ),
              OutlinedButton.icon(
                onPressed: connected ? _refresh : null,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(l10n.refreshButton),
              ),
              if (!_selecting &&
                  widget.entries.isNotEmpty &&
                  widget.error == null)
                OutlinedButton.icon(
                  onPressed: connected
                      ? () => setState(() => _selecting = true)
                      : null,
                  icon: const Icon(Icons.checklist),
                  label: Text(l10n.backupSelectFiles),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (widget.error case final message?)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: ErrorRetryView(message: message, onRetry: _refresh),
            )
          else if (widget.entries.isEmpty && connected)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: Text(
                widget.listed
                    ? l10n.backupNoRemoteFiles
                    : l10n.backupRemoteFilesHint,
                textAlign: TextAlign.center,
              ),
            )
          else ...[
            if (_selecting) _selectionBar(l10n),
            SettingTileGroup(
              children: [
                for (final entry in widget.entries) _entryTile(entry, l10n),
              ],
            ),
          ],
        ],
      ],
    );
  }
}
