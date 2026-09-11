import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/cover_brightness_filter.dart';
import '../utils/download_manager.dart';
import '../utils/toast.dart';
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
        actions: [
          IconButton(
            tooltip: _comicDownloads.paused
                ? l10n.downloadResumeButton
                : l10n.downloadPauseButton,
            icon: Icon(
              _comicDownloads.paused
                  ? Icons.play_arrow_rounded
                  : Icons.pause_rounded,
            ),
            onPressed: () {
              if (_comicDownloads.paused) {
                _comicDownloads.resumeDownloads();
              } else {
                _comicDownloads.pauseDownloads();
              }
            },
          ),
        ],
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
          _buildQueueTab(),
        ],
      ),
    );
  }

  /// 队列页：顶部可选的批次失败提示条 + 任务列表 + 设置悬浮按钮。
  Widget _buildQueueTab() {
    final summary = _comicDownloads.lastBatchSummary;
    return Column(
      children: [
        if (summary != null)
          _BatchSummaryBanner(
            summary: summary,
            onRetry: _retryFailedBatch,
            onDismiss: _comicDownloads.clearBatchSummary,
          ),
        Expanded(
          child: _withSettingsFab(
            const _ComicDownloadQueueView(),
            'download_settings_queue',
          ),
        ),
      ],
    );
  }

  Future<void> _retryFailedBatch() async {
    final added = await _comicDownloads.retryFailedBatch();
    if (!mounted || added == 0) return;
    showToast(
      context,
      AppLocalizations.of(context)!.downloadBatchRequeued(added),
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

/// 批次下载结束后有失败章节时，在队列页顶部展示的提示条。
class _BatchSummaryBanner extends StatelessWidget {
  final DownloadBatchSummary summary;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  const _BatchSummaryBanner({
    required this.summary,
    required this.onRetry,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: cs.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.xs,
          AppSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 20, color: cs.onErrorContainer),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                l10n.downloadBatchFailedCount(summary.failures.length),
                style: tt.bodyMedium?.copyWith(color: cs.onErrorContainer),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: cs.onErrorContainer),
              child: Text(l10n.downloadBatchRetryAll),
            ),
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close),
              iconSize: 18,
              color: cs.onErrorContainer,
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            ),
          ],
        ),
      ),
    );
  }
}

enum _QueueFilter { all, downloading, paused }

class _ComicDownloadQueueView extends StatefulWidget {
  const _ComicDownloadQueueView();

  @override
  State<_ComicDownloadQueueView> createState() =>
      _ComicDownloadQueueViewState();
}

class _ComicDownloadQueueViewState extends State<_ComicDownloadQueueView> {
  _QueueFilter _filter = _QueueFilter.all;
  // 多选模式下已勾选的任务 key（pathWord|||chapterUuid）。
  final Set<String> _selectedKeys = {};
  final Set<String> _deletingKeys = {};
  bool _batchDeleting = false;

  DownloadManager get _downloads => DownloadManager();

  @override
  void initState() {
    super.initState();
    _downloads.addListener(_onDownloadsChanged);
  }

  @override
  void dispose() {
    _downloads.removeListener(_onDownloadsChanged);
    super.dispose();
  }

  void _onDownloadsChanged() {
    if (!mounted) return;
    final visibleKeys = _filteredTasks.map(_keyOf).toSet();
    setState(() {
      _selectedKeys.removeWhere((key) => !visibleKeys.contains(key));
    });
  }

  String _keyOf(ComicDownloadTaskInfo task) =>
      '${task.pathWord}|||${task.chapterUuid}';

  List<ComicDownloadTaskInfo> get _filteredTasks {
    final tasks = _downloads.tasks;
    switch (_filter) {
      case _QueueFilter.all:
        return tasks;
      case _QueueFilter.downloading:
        return tasks
            .where((t) => t.status == ComicDownloadTaskStatus.downloading)
            .toList();
      case _QueueFilter.paused:
        return tasks
            .where((t) => t.status == ComicDownloadTaskStatus.paused)
            .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tasks = _filteredTasks;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final selecting = _selectedKeys.isNotEmpty;

    final allTasks = _downloads.tasks;
    if (allTasks.isEmpty) {
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

    return Column(
      children: [
        _buildFilterBar(context, l10n),
        if (selecting) _buildSelectionActions(context, l10n),
        Expanded(
          child: tasks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.noContent,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextButton(
                        onPressed: _batchDeleting
                            ? null
                            : () => setState(() {
                                _filter = _QueueFilter.all;
                                _selectedKeys.clear();
                              }),
                        child: Text(l10n.downloadQueueFilterAll),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    4,
                    16,
                    88 + MediaQuery.paddingOf(context).bottom,
                  ),
                  itemCount: tasks.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final task = tasks[i];
                    final key = _keyOf(task);
                    final selected = _selectedKeys.contains(key);
                    return _ComicQueueTaskCard(
                      key: ValueKey(key),
                      task: task,
                      selected: selected,
                      selecting: selecting,
                      onToggleSelect: _batchDeleting
                          ? null
                          : () => _toggleSelect(task),
                      onTogglePause:
                          _downloads.paused || _deletingKeys.contains(key)
                          ? null
                          : () => _togglePause(task),
                      onDelete: _deletingKeys.contains(key)
                          ? null
                          : () => unawaited(_confirmDeleteTask(context, task)),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// 筛选 chips + 多选入口 + 全选按钮。
  Widget _buildFilterBar(BuildContext context, AppLocalizations l10n) {
    final tasks = _downloads.tasks;
    final downloadingCount = tasks
        .where((t) => t.status == ComicDownloadTaskStatus.downloading)
        .length;
    final pausedCount = tasks
        .where((t) => t.status == ComicDownloadTaskStatus.paused)
        .length;

    Widget chip(_QueueFilter value, String label, int count) {
      final selected = _filter == value;
      return ChoiceChip(
        label: Text('$label $count'),
        selected: selected,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        onSelected: _batchDeleting
            ? null
            : (_) => setState(() {
                _filter = value;
                // 筛选切换后清空选择，避免误操作看不见的任务。
                _selectedKeys.clear();
              }),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              chip(_QueueFilter.all, l10n.downloadQueueFilterAll, tasks.length),
              chip(
                _QueueFilter.downloading,
                l10n.downloadQueueFilterDownloading,
                downloadingCount,
              ),
              chip(
                _QueueFilter.paused,
                l10n.downloadQueueFilterPaused,
                pausedCount,
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _batchDeleting || _filteredTasks.isEmpty
                  ? null
                  : _toggleSelectAll,
              child: Text(
                _allVisibleSelected
                    ? l10n.downloadQueueDeselectAll
                    : l10n.downloadQueueSelectAll,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 多选模式下的批量操作栏：暂停 / 继续 / 删除所选。
  Widget _buildSelectionActions(BuildContext context, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    final count = _selectedKeys.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${l10n.downloadQueueSelect}: $count',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          IconButton(
            onPressed: _batchDeleting || _downloads.paused
                ? null
                : () => _batchPauseResume(resume: false),
            tooltip: l10n.downloadPauseButton,
            icon: const Icon(Icons.pause_rounded),
          ),
          IconButton(
            onPressed: _batchDeleting || _downloads.paused
                ? null
                : () => _batchPauseResume(resume: true),
            tooltip: l10n.downloadResumeButton,
            icon: const Icon(Icons.play_arrow_rounded),
          ),
          IconButton(
            tooltip: l10n.downloadQueueDeleteSelected,
            color: cs.error,
            onPressed: _batchDeleting ? null : _batchDelete,
            icon: const Icon(Icons.delete_outline),
          ),
          IconButton(
            tooltip: l10n.cancelButton,
            onPressed: _batchDeleting
                ? null
                : () => setState(() => _selectedKeys.clear()),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  bool get _allVisibleSelected {
    final tasks = _filteredTasks;
    return tasks.isNotEmpty &&
        tasks.every((t) => _selectedKeys.contains(_keyOf(t)));
  }

  /// 全选/取消全选只作用于当前筛选出的任务。
  void _toggleSelectAll() {
    if (_batchDeleting) return;
    setState(() {
      if (_allVisibleSelected) {
        for (final task in _filteredTasks) {
          _selectedKeys.remove(_keyOf(task));
        }
      } else {
        for (final task in _filteredTasks) {
          _selectedKeys.add(_keyOf(task));
        }
      }
    });
  }

  void _toggleSelect(ComicDownloadTaskInfo task) {
    if (_batchDeleting) return;
    setState(() {
      final key = _keyOf(task);
      if (!_selectedKeys.remove(key)) _selectedKeys.add(key);
    });
  }

  ({String pathWord, String chapterUuid}) _selectedRecord(
    ComicDownloadTaskInfo task,
  ) => (pathWord: task.pathWord, chapterUuid: task.chapterUuid);

  List<ComicDownloadTaskInfo> get _selectedTasks =>
      _downloads.tasks.where((t) => _selectedKeys.contains(_keyOf(t))).toList();

  void _batchPauseResume({required bool resume}) {
    if (_batchDeleting || _downloads.paused) return;
    final selected = _selectedTasks;
    if (selected.isEmpty) return;
    final keys = selected.map(_selectedRecord).toList();
    if (resume) {
      _downloads.resumeChapters(keys);
    } else {
      _downloads.pauseChapters(keys);
    }
  }

  /// 批量删除所选任务：确认后逐个删除并删除已下载文件。
  Future<void> _batchDelete() async {
    if (_batchDeleting) return;
    final selected = _selectedTasks;
    if (selected.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _batchDeleting = true);

    try {
      var fileCount = 0;
      for (final task in selected) {
        fileCount += await _downloads.downloadedFileCountOf(
          task.pathWord,
          task.chapterUuid,
        );
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.downloadQueueDeleteBatchTitle(selected.length)),
          content: Text(l10n.downloadQueueDeleteBatchContent(fileCount)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancelButton),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.deleteButton),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      await _downloads.deleteQueuedChapters(
        selected.map(_selectedRecord).toList(),
      );
      if (!mounted) return;
      _selectedKeys.clear();
      showToast(
        context,
        AppLocalizations.of(
          context,
        )!.downloadQueueBatchDeleted(selected.length),
      );
    } finally {
      if (mounted) setState(() => _batchDeleting = false);
    }
  }

  /// 切换单个章节任务的暂停/继续。
  void _togglePause(ComicDownloadTaskInfo task) {
    final downloads = _downloads;
    if (downloads.paused) return;
    if (downloads.isChapterPaused(task.pathWord, task.chapterUuid)) {
      downloads.resumeChapter(task.pathWord, task.chapterUuid);
    } else {
      downloads.pauseChapter(task.pathWord, task.chapterUuid);
    }
  }

  /// 删除队列任务：确认后移出队列并删除该章节已下载的文件。
  Future<void> _confirmDeleteTask(
    BuildContext context,
    ComicDownloadTaskInfo task,
  ) async {
    final key = _keyOf(task);
    if (!_deletingKeys.add(key)) return;
    if (mounted) setState(() {});
    try {
      final l10n = AppLocalizations.of(context)!;
      final fileCount = await _downloads.downloadedFileCountOf(
        task.pathWord,
        task.chapterUuid,
      );
      if (!context.mounted) return;
      if (!_downloads.tasks.any((item) => _keyOf(item) == key)) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.downloadQueueDeleteTitle),
          content: Text(
            l10n.downloadQueueDeleteContent(task.chapterName, fileCount),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancelButton),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.deleteButton),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      if (!_downloads.tasks.any((item) => _keyOf(item) == key)) return;
      await _downloads.deleteQueuedChapter(task.pathWord, task.chapterUuid);
    } finally {
      _deletingKeys.remove(key);
      if (mounted) setState(() {});
    }
  }
}

/// 漫画下载队列卡片：展示任务状态与进度，可暂停/继续或删除。
/// 多选模式下点击卡片切换勾选，长按进入多选。
class _ComicQueueTaskCard extends StatelessWidget {
  final ComicDownloadTaskInfo task;
  final bool selected;
  final bool selecting;
  final VoidCallback? onToggleSelect;
  final VoidCallback? onTogglePause;
  final VoidCallback? onDelete;

  const _ComicQueueTaskCard({
    super.key,
    required this.task,
    required this.selected,
    required this.selecting,
    required this.onToggleSelect,
    required this.onTogglePause,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      color: selected ? cs.primaryContainer : cs.surfaceContainerLow,
      child: InkWell(
        borderRadius: AppRadius.mdR,
        onTap: selecting ? onToggleSelect : null,
        onLongPress: selecting ? null : onToggleSelect,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (selecting) ...[
                    Icon(
                      selected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 22,
                      color: selected ? cs.primary : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
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
                  const SizedBox(width: AppSpacing.xs),
                  if (!selecting) ...[
                    IconButton(
                      onPressed: onTogglePause,
                      visualDensity: VisualDensity.compact,
                      tooltip: task.status == ComicDownloadTaskStatus.paused
                          ? AppLocalizations.of(context)!.downloadResumeButton
                          : AppLocalizations.of(context)!.downloadPauseButton,
                      icon: Icon(
                        task.status == ComicDownloadTaskStatus.paused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                        size: 22,
                      ),
                    ),
                    IconButton(
                      onPressed: onDelete,
                      visualDensity: VisualDensity.compact,
                      tooltip: AppLocalizations.of(context)!.deleteButton,
                      icon: const Icon(Icons.delete_outline, size: 22),
                    ),
                  ],
                ],
              ),
              if (task.status != ComicDownloadTaskStatus.pending &&
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
      case ComicDownloadTaskStatus.paused:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.pause_circle_outline,
              size: 14,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              l10n.pausedStatus,
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        );
    }
  }
}
