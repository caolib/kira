import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_icon_sizes.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_status_colors.dart';
import '../utils/download_directory.dart';
import '../utils/download_manager.dart';
import '../utils/novel_download_manager.dart';
import '../utils/toast.dart';
import 'app_sheet.dart';
import 'settings_section.dart';

/// 弹出下载设置面板（并发数量、章节评论、保存位置等），
/// 供漫画详情页、轻小说详情页与下载中心共用。
///
/// 传入 [downloads] 显示漫画下载设置，传入 [novelDownloads] 显示轻小说下载设置，
/// 两者至少传一个；小说没有章节评论概念，因此该开关只在漫画侧显示。
Future<void> showDownloadSettingsSheet(
  BuildContext context, {
  DownloadManager? downloads,
  NovelDownloadManager? novelDownloads,
}) {
  return showAppSheet<void>(
    context,
    maxHeightFactor: 0.9,
    child: DownloadSettingsSheet(
      downloads: downloads,
      novelDownloads: novelDownloads,
    ),
  );
}

/// 漫画下载设置抽屉，从底部出现，用于配置图片并发下载数量等。
class DownloadSettingsSheet extends StatefulWidget {
  final DownloadManager? downloads;
  final NovelDownloadManager? novelDownloads;
  const DownloadSettingsSheet({super.key, this.downloads, this.novelDownloads});

  @override
  State<DownloadSettingsSheet> createState() => _DownloadSettingsSheetState();
}

class _DownloadSettingsSheetState extends State<DownloadSettingsSheet> {
  late int _concurrency;
  late bool _downloadComments;
  late int _novelConcurrency;

  @override
  void initState() {
    super.initState();
    _concurrency = widget.downloads?.imageDownloadConcurrency ?? 8;
    _downloadComments = widget.downloads?.downloadCommentsEnabled ?? false;
    _novelConcurrency = widget.novelDownloads?.concurrency ?? 2;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 并发警告只提示一次：两区的并发滑杆共用这条风险说明。
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppStatusColors.warning(cs).withValues(alpha: 0.12),
              borderRadius: AppRadius.mdR,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_outlined,
                  size: AppIconSize.lg,
                  color: AppStatusColors.warning(cs),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    l10n.downloadImageConcurrencyDesc,
                    style: tt.bodySmall?.copyWith(
                      color: AppStatusColors.warning(cs),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (widget.downloads case final downloads?) ...[
            const SizedBox(height: AppSpacing.sm),
            SettingsSection(
              key: const ValueKey('comic-download-settings-card'),
              title: l10n.comicDownloadSection,
              icon: Icons.menu_book_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.downloadImageConcurrency, style: tt.bodyMedium),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          min: 1,
                          max: 32,
                          divisions: 31,
                          value: _concurrency.toDouble(),
                          label: '$_concurrency',
                          onChanged: (v) =>
                              setState(() => _concurrency = v.round()),
                          onChangeEnd: (v) => unawaited(
                            downloads.setImageDownloadConcurrency(v.round()),
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
                  Text(l10n.downloadSaveLocation, style: tt.titleSmall),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.folder_open_outlined),
                    title: Text(
                      downloads.customSaveDirectory ??
                          l10n.downloadSaveLocationDefault,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: downloads.customSaveDirectory == null
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
                  const Divider(height: AppSpacing.xl),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.downloadChapterComments),
                    value: _downloadComments,
                    onChanged: (v) {
                      setState(() => _downloadComments = v);
                      unawaited(downloads.setDownloadCommentsEnabled(v));
                    },
                  ),
                ],
              ),
            ),
          ],
          if (widget.novelDownloads case final novels?) ...[
            const SizedBox(height: AppSpacing.sm),
            SettingsSection(
              key: const ValueKey('novel-download-settings-card'),
              title: l10n.novelDownloadSection,
              icon: Icons.auto_stories_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.downloadImageConcurrency, style: tt.bodyMedium),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          min: 1,
                          max: 32,
                          divisions: 31,
                          value: _novelConcurrency.toDouble(),
                          label: '$_novelConcurrency',
                          onChanged: (v) =>
                              setState(() => _novelConcurrency = v.round()),
                          onChangeEnd: (v) =>
                              unawaited(novels.setConcurrency(v.round())),
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Text(
                          '$_novelConcurrency',
                          style: tt.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(l10n.downloadSaveLocation, style: tt.titleSmall),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.folder_open_outlined),
                    title: Text(
                      novels.customSaveDirectory ??
                          l10n.downloadSaveLocationDefault,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: novels.customSaveDirectory == null
                        ? const Icon(Icons.chevron_right)
                        : PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'reset') {
                                unawaited(
                                  _resetNovelSaveLocation(l10n, novels),
                                );
                              }
                            },
                            itemBuilder: (ctx) => [
                              PopupMenuItem(
                                value: 'reset',
                                child: Text(l10n.downloadSaveLocationReset),
                              ),
                            ],
                          ),
                    onTap: () => _changeNovelSaveLocation(novels),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 小说保存位置：与漫画同款确认迁移流程，但检查小说队列空闲。
  Future<void> _changeNovelSaveLocation(NovelDownloadManager novels) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final path = await pickDownloadDirectory(
        dialogTitle: l10n.downloadSaveLocationPickerTitle,
      );
      if (path == null || !mounted) return;
      await _applyNovelSaveDirectory(novels, path, l10n);
    } on DownloadDirectoryException catch (e) {
      if (!mounted) return;
      showToast(context, switch (e.reason) {
        DownloadDirectoryError.permissionDenied =>
          l10n.downloadSaveLocationPermissionDenied,
        DownloadDirectoryError.notWritable =>
          l10n.downloadSaveLocationNotWritable,
      }, isError: true);
    } on ArgumentError {
      // 小说目录与漫画目录相同或互相包含时由管理器拒绝。
      if (!mounted) return;
      showToast(context, l10n.novelDownloadDirectoryOverlap, isError: true);
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

  Future<void> _resetNovelSaveLocation(
    AppLocalizations l10n,
    NovelDownloadManager novels,
  ) async {
    try {
      await _applyNovelSaveDirectory(novels, null, l10n);
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

  Future<void> _applyNovelSaveDirectory(
    NovelDownloadManager novels,
    String? path,
    AppLocalizations l10n,
  ) async {
    await novels.init();
    final existingCount = novels.localNovels.length;
    if (existingCount > 0 && mounted) {
      final migrate = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.downloadMigrateConfirmTitle),
          content: Text(l10n.novelDownloadMigrateConfirmContent(existingCount)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancelButton),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.confirmButton),
            ),
          ],
        ),
      );
      if (migrate != true) return;
    }
    if (!mounted) return;

    final progress = ValueNotifier<NovelDownloadMigrationProgress?>(null);
    var dialogPopped = false;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) =>
            ValueListenableBuilder<NovelDownloadMigrationProgress?>(
              valueListenable: progress,
              builder: (dialogContext, value, _) {
                final total = value?.total ?? 0;
                final current = value?.completed ?? 0;
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
      await novels.setSaveDirectory(
        path,
        onProgress: (value) => progress.value = value,
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
    if (downloads == null) return;
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
