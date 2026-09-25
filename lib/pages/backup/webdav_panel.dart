import 'package:flutter/material.dart';

import '../../backup/backup_schedule.dart';
import '../../backup/webdav_config.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/error_retry_view.dart';
import '../../widgets/setting_tile_group.dart';
import 'backup_labels.dart';
import 'backup_schedule_controls.dart';

class WebDavPanel extends StatelessWidget {
  final WebDavConfig? config;
  final List<WebDavBackupEntry> entries;

  /// WebDAV 总开关：关闭时下面的连接设置、定时备份与远端列表全部收起来。
  final bool enabled;

  /// 有备份操作在跑时为 false：此时连总开关也锁住，避免中途改设置。
  final bool interactive;
  final bool canUpload;
  final bool listed;
  final BackupSchedule schedule;

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
  final ValueChanged<BackupSchedule> onScheduleChanged;

  const WebDavPanel({
    super.key,
    required this.config,
    required this.entries,
    required this.enabled,
    required this.interactive,
    required this.canUpload,
    required this.listed,
    required this.schedule,
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
    required this.onScheduleChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final config = this.config;
    final connected = enabled && interactive && config != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingTileGroup(
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.cloud_outlined),
              title: Text(l10n.backupWebDav),
              value: enabled,
              onChanged: interactive ? onToggle : null,
            ),
          ],
        ),
        if (!enabled)
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
                enabled: interactive,
                onTap: onConfigure,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          BackupScheduleControls(
            schedule: schedule,
            canEnable: connected && scheduleReady,
            enabled: interactive,
            hint: scheduleHint,
            onChanged: onScheduleChanged,
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: connected ? onTest : null,
                icon: const Icon(Icons.lan_outlined),
                label: Text(l10n.backupTestConnection),
              ),
              FilledButton.icon(
                onPressed: connected && canUpload ? onUpload : null,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text(l10n.backupUpload),
              ),
              OutlinedButton.icon(
                onPressed: connected ? onRefresh : null,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(l10n.refreshButton),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (error case final message?)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: ErrorRetryView(message: message, onRetry: onRefresh),
            )
          else if (entries.isEmpty && connected)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: Text(
                listed ? l10n.backupNoRemoteFiles : l10n.backupRemoteFilesHint,
                textAlign: TextAlign.center,
              ),
            )
          else
            SettingTileGroup(
              children: [
                for (final entry in entries)
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      [
                        if (entry.size case final size?)
                          formatBackupBytes(size),
                        if (entry.modified case final time?)
                          formatBackupTime(time),
                      ].join(' · '),
                      style: AppTypography.meta(Theme.of(context).textTheme),
                    ),
                    trailing: PopupMenuButton<String>(
                      enabled: interactive,
                      onSelected: (action) => action == 'restore'
                          ? onRestore(entry)
                          : onDelete(entry),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'restore',
                          child: Text(l10n.backupRestore),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(l10n.deleteButton),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ],
    );
  }
}
