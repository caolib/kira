import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/cover_brightness_filter.dart';
import '../utils/download_manager.dart';
import '../widgets/download_settings_sheet.dart';
import 'local_comics_page.dart';

class DownloadCenterPage extends StatefulWidget {
  final int initialTab;

  const DownloadCenterPage({super.key, this.initialTab = 0});

  @override
  State<DownloadCenterPage> createState() => _DownloadCenterPageState();
}

class _DownloadCenterPageState extends State<DownloadCenterPage>
    with TickerProviderStateMixin {
  TabController? _tabController;
  final _comicDownloads = DownloadManager();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
    _comicDownloads.addListener(_onQueueChanged);
  }

  @override
  void dispose() {
    _comicDownloads.removeListener(_onQueueChanged);
    _tabController?.dispose();
    super.dispose();
  }

  void _onQueueChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = _tabController!;
    final comicTasks = _comicDownloads.tasks;
    final comicQueueCount = comicTasks.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.downloadCenterTitle),
        bottom: TabBar(
          controller: controller,
          tabs: [
            Tab(
              icon: const Icon(Icons.menu_book_outlined),
              text: l10n.comicLabel,
            ),
            Tab(
              icon: Badge(
                isLabelVisible: comicQueueCount > 0,
                label: Text('$comicQueueCount'),
                child: const Icon(Icons.downloading_outlined),
              ),
              text: l10n.downloadQueueTab,
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: controller,
        children: [
          LocalComicsPage(
            embedded: true,
            trailingAction: _settingsFab('download_settings_comic'),
          ),
          _withSettingsFab(
            _ComicDownloadQueueView(),
            'download_settings_queue',
          ),
        ],
      ),
    );
  }

  /// 下载设置悬浮按钮：与列表页的"打开下载位置"按钮同行、位于最右。
  /// 每个挂载点用独立 heroTag，避免多 tab 同时存活时 Hero 标签冲突。
  Widget _settingsFab(String heroTag) {
    return FloatingActionButton(
      heroTag: heroTag,
      tooltip: AppLocalizations.of(context)!.downloadSettingsTitle,
      onPressed: () =>
          showDownloadSettingsSheet(context, downloads: _comicDownloads),
      child: const Icon(Icons.settings_outlined),
    );
  }

  /// 队列页没有内嵌列表，单独把设置按钮叠加到右下角。
  Widget _withSettingsFab(Widget child, String heroTag) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(right: 16, bottom: 16, child: _settingsFab(heroTag)),
      ],
    );
  }
}

class _ComicDownloadQueueView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final downloads = DownloadManager();
    final tasks = downloads.tasks;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.download_done_outlined,
              size: 56,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(l10n.downloadQueueEmpty, style: tt.titleMedium),
            const SizedBox(height: 6),
            Text(
              l10n.downloadQueueEmptyComicHint,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: tasks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final task = tasks[i];
        return _ComicQueueTaskCard(task: task);
      },
    );
  }
}

/// Comic download queue card (read-only; comic queue does not support pause/cancel).
class _ComicQueueTaskCard extends StatelessWidget {
  final ComicDownloadTaskInfo task;

  const _ComicQueueTaskCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: AppRadius.smR,
                  child: SizedBox(
                    width: 48,
                    height: 64,
                    child: task.cover != null && task.cover!.isNotEmpty
                        ? CoverBrightnessFilter(
                            child: Image.network(
                              task.cover!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => _placeholder(cs),
                            ),
                          )
                        : _placeholder(cs),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.comicName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.labelMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        task.chapterName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _buildStatusLabel(context, cs, tt),
                    ],
                  ),
                ),
                const Icon(
                  Icons.menu_book_outlined,
                  size: 20,
                  color: Colors.amber,
                ),
              ],
            ),
            if (task.status == ComicDownloadTaskStatus.downloading &&
                task.progress != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: AppRadius.xsR,
                child: LinearProgressIndicator(value: task.progress!.ratio),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _buildProgressText(context, task.progress!),
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _placeholder(ColorScheme cs) => ColoredBox(
    color: cs.surfaceContainerHighest,
    child: Icon(Icons.menu_book_outlined, size: 24, color: cs.onSurfaceVariant),
  );

  String _buildProgressText(
    BuildContext context,
    ChapterDownloadProgress progress,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final percent = (progress.ratio * 100).toStringAsFixed(0);
    final completed = progress.completed;
    final total = progress.total;
    if (progress.failed > 0) {
      return l10n.downloadProgressPartial(
        percent,
        completed,
        total,
        progress.failed,
      );
    }
    return l10n.downloadProgressCount(percent, completed, total);
  }

  Widget _buildStatusLabel(BuildContext context, ColorScheme cs, TextTheme tt) {
    final l10n = AppLocalizations.of(context)!;
    switch (task.status) {
      case ComicDownloadTaskStatus.downloading:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: cs.primary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              l10n.downloadingStatus,
              style: tt.labelSmall?.copyWith(color: cs.primary),
            ),
          ],
        );
      case ComicDownloadTaskStatus.pending:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule, size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              l10n.waitingStatus,
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        );
    }
  }
}
