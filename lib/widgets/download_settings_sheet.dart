import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_spacing.dart';
import '../utils/download_directory.dart';
import '../utils/download_manager.dart';
import '../utils/toast.dart';

/// 弹出漫画下载设置面板（并发数量、章节评论、保存位置等），
/// 供漫画详情页与下载中心共用。
Future<void> showDownloadSettingsSheet(
  BuildContext context, {
  DownloadManager? downloads,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) =>
        DownloadSettingsSheet(downloads: downloads ?? DownloadManager()),
  );
}

/// 漫画下载设置抽屉，从底部出现，用于配置单话图片并发下载数量等。
class DownloadSettingsSheet extends StatefulWidget {
  final DownloadManager downloads;
  const DownloadSettingsSheet({super.key, required this.downloads});

  @override
  State<DownloadSettingsSheet> createState() => _DownloadSettingsSheetState();
}

class _DownloadSettingsSheetState extends State<DownloadSettingsSheet> {
  late int _concurrency;
  late bool _downloadComments;

  @override
  void initState() {
    super.initState();
    _concurrency = widget.downloads.imageDownloadConcurrency;
    _downloadComments = widget.downloads.downloadCommentsEnabled;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg + bottomInset,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                l10n.downloadSettingsTitle,
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Text(l10n.downloadImageConcurrency, style: tt.titleSmall),
            Text(
              l10n.downloadImageConcurrencyDesc,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    min: 1,
                    max: 10,
                    divisions: 9,
                    value: _concurrency.toDouble(),
                    label: '$_concurrency',
                    onChanged: (v) => setState(() => _concurrency = v.round()),
                    onChangeEnd: (v) => unawaited(
                      widget.downloads.setImageDownloadConcurrency(v.round()),
                    ),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    '$_concurrency',
                    style: tt.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            const Divider(height: AppSpacing.xl),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.downloadChapterComments),
              subtitle: Text(
                l10n.downloadChapterCommentsDesc,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              value: _downloadComments,
              onChanged: (v) {
                setState(() => _downloadComments = v);
                unawaited(widget.downloads.setDownloadCommentsEnabled(v));
              },
            ),
            const Divider(height: AppSpacing.xl),
            Text(l10n.downloadSaveLocation, style: tt.titleSmall),
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.folder_open_outlined),
              title: Text(
                widget.downloads.customSaveDirectory ??
                    l10n.downloadSaveLocationDefault,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: widget.downloads.customSaveDirectory == null
                  ? const Icon(Icons.chevron_right)
                  : PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'reset') {
                          unawaited(_resetSaveLocation(l10n));
                        }
                      },
                      itemBuilder: (ctx) => [
                        PopupMenuItem(
                          value: 'reset',
                          child: Text(l10n.downloadSaveLocationReset),
                        ),
                      ],
                    ),
              onTap: _changeSaveLocation,
            ),
          ],
        ),
      ),
    );
  }

  /// 保存位置条目点击：选目录 →（有下载时）确认迁移 → 进度弹窗 → 结果提示。
  Future<void> _changeSaveLocation() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final path = await pickDownloadDirectory(
        dialogTitle: l10n.downloadSaveLocationPickerTitle,
      );
      if (path == null || !mounted) return;
      await _applySaveDirectory(path, l10n);
    } on DownloadDirectoryException catch (e) {
      if (!mounted) return;
      showToast(context, switch (e.reason) {
        DownloadDirectoryError.permissionDenied =>
          l10n.downloadSaveLocationPermissionDenied,
        DownloadDirectoryError.notWritable =>
          l10n.downloadSaveLocationNotWritable,
      }, isError: true);
    } on StateError {
      if (!mounted) return;
      showToast(context, l10n.downloadQueueBusy, isError: true);
    } catch (e) {
      if (!mounted) return;
      showToast(
        context,
        l10n.downloadSaveLocationFailed(e.toString()),
        isError: true,
      );
    }
  }

  /// 恢复默认内部目录（trailing 菜单触发），同样走确认迁移流程。
  Future<void> _resetSaveLocation(AppLocalizations l10n) async {
    try {
      await _applySaveDirectory(null, l10n);
    } on StateError {
      if (!mounted) return;
      showToast(context, l10n.downloadQueueBusy, isError: true);
    } catch (e) {
      if (!mounted) return;
      showToast(
        context,
        l10n.downloadSaveLocationFailed(e.toString()),
        isError: true,
      );
    }
  }

  /// 切换保存目录的共用流程：（有下载时）确认迁移 → 进度弹窗 → 结果提示。
  Future<void> _applySaveDirectory(String? path, AppLocalizations l10n) async {
    final downloads = widget.downloads;
    await downloads.init();
    final existingCount = downloads.localComics().length;
    if (existingCount > 0 && mounted) {
      final migrate = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.downloadMigrateConfirmTitle),
          content: Text(l10n.downloadMigrateConfirmContent(existingCount)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancelButton),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.confirmButton),
            ),
          ],
        ),
      );
      if (migrate != true) return;
    }
    if (!mounted) return;

    final progress = ValueNotifier<DownloadMigrationProgress?>(null);
    var dialogPopped = false;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => ValueListenableBuilder<DownloadMigrationProgress?>(
          valueListenable: progress,
          builder: (ctx, value, _) {
            final total = value?.total ?? 0;
            final current = value?.current ?? 0;
            return AlertDialog(
              title: Text(l10n.downloadMigratingTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: total > 0 ? current / total : null,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(l10n.downloadMigratingProgress(current, total)),
                ],
              ),
            );
          },
        ),
      ).then((_) => dialogPopped = true),
    );
    try {
      await downloads.setSaveDirectory(
        path,
        onProgress: (p) => progress.value = p,
      );
    } finally {
      progress.dispose();
      if (!dialogPopped && mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
    if (!mounted) return;
    setState(() {});
    showToast(context, l10n.downloadSaveLocationChanged);
  }
}
