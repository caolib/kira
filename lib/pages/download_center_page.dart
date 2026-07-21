import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/user_manager.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/anime_download_manager.dart';
import '../utils/cover_brightness_filter.dart';
import '../utils/download_manager.dart';
import 'local_anime_page.dart';
import 'local_comics_page.dart';

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(unit >= 2 ? 1 : 0)} ${units[unit]}';
}

class DownloadCenterPage extends StatefulWidget {
  final int initialTab;

  const DownloadCenterPage({super.key, this.initialTab = 0});

  @override
  State<DownloadCenterPage> createState() => _DownloadCenterPageState();
}

class _DownloadCenterPageState extends State<DownloadCenterPage>
    with TickerProviderStateMixin {
  TabController? _tabController;
  final _user = UserManager();
  final _animeDownloads = AnimeDownloadManager();
  final _comicDownloads = DownloadManager();

  /// Tracks anime feature state to rebuild TabController on changes.
  bool _wasAnimeEnabled = true;

  int get _tabCount => _user.animeFeatureEnabled ? 3 : 2;

  @override
  void initState() {
    super.initState();
    _wasAnimeEnabled = _user.animeFeatureEnabled;
    _tabController = TabController(
      length: _tabCount,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, _tabCount - 1),
    );
    _user.addListener(_onSettingsChanged);
    _animeDownloads.addListener(_onQueueChanged);
    _comicDownloads.addListener(_onQueueChanged);
  }

  @override
  void dispose() {
    _user.removeListener(_onSettingsChanged);
    _animeDownloads.removeListener(_onQueueChanged);
    _comicDownloads.removeListener(_onQueueChanged);
    _tabController?.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    final animeEnabled = _user.animeFeatureEnabled;
    if (animeEnabled != _wasAnimeEnabled) {
      _wasAnimeEnabled = animeEnabled;
      _tabController?.dispose();
      _tabController = TabController(
        length: _tabCount,
        vsync: this,
        initialIndex: widget.initialTab.clamp(0, _tabCount - 1),
      );
    }
    setState(() {});
  }

  void _onQueueChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = _tabController!;

    if (_user.animeFeatureEnabled) {
      final animeTasks = _animeDownloads.tasks;
      final animeQueueCount = animeTasks.length;
      final comicTasks = _comicDownloads.tasks;
      final comicQueueCount = comicTasks.length;
      final totalQueueCount = animeQueueCount + comicQueueCount;

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
                icon: const Icon(Icons.movie_outlined),
                text: l10n.animeLabel,
              ),
              Tab(
                icon: Badge(
                  isLabelVisible: totalQueueCount > 0,
                  label: Text('$totalQueueCount'),
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
            const LocalComicsPage(embedded: true),
            const LocalAnimePage(embedded: true),
            _CombinedDownloadQueueView(),
          ],
        ),
      );
    }

    // Anime feature disabled: comic + queue tabs.
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
          const LocalComicsPage(embedded: true),
          _ComicDownloadQueueView(),
        ],
      ),
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

/// Shows comic and anime download queues together when anime is enabled.
class _CombinedDownloadQueueView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final comicDownloads = DownloadManager();
    final animeDownloads = AnimeDownloadManager();
    final comicTasks = comicDownloads.tasks;
    final animeTasks = animeDownloads.tasks;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final totalTasks = comicTasks.length + animeTasks.length;

    if (totalTasks == 0) {
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
              l10n.downloadQueueEmptyMixedHint,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: totalTasks,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        if (i < comicTasks.length) {
          return _ComicQueueTaskCard(task: comicTasks[i]);
        }
        return _AnimeQueueTaskCard(task: animeTasks[i - comicTasks.length]);
      },
    );
  }
}

class _AnimeQueueTaskCard extends StatelessWidget {
  final AnimeDownloadTaskInfo task;

  const _AnimeQueueTaskCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final downloads = AnimeDownloadManager();

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
                        task.animeName,
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
                _buildActionButton(context, downloads, cs),
              ],
            ),
            if (task.status == DownloadTaskStatus.downloading &&
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
    child: Icon(Icons.movie_outlined, size: 24, color: cs.onSurfaceVariant),
  );

  String _buildProgressText(
    BuildContext context,
    AnimeChapterDownloadProgress progress,
  ) {
    final percent = (progress.ratio * 100).toStringAsFixed(0);
    final bytes = progress.estimatedTotalBytes;
    if (bytes == null || bytes <= 0) return '$percent%';
    return AppLocalizations.of(
      context,
    )!.downloadProgressApproxBytes(percent, _formatBytes(bytes));
  }

  Widget _buildStatusLabel(BuildContext context, ColorScheme cs, TextTheme tt) {
    final l10n = AppLocalizations.of(context)!;
    switch (task.status) {
      case DownloadTaskStatus.downloading:
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
      case DownloadTaskStatus.pending:
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
      case DownloadTaskStatus.paused:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.pause_circle_outline,
              size: 14,
              color: Colors.orange,
            ),
            const SizedBox(width: 6),
            Text(
              l10n.pausedStatus,
              style: tt.labelSmall?.copyWith(color: Colors.orange),
            ),
          ],
        );
      case DownloadTaskStatus.failed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 14, color: cs.error),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _localizedError(l10n),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.labelSmall?.copyWith(color: cs.error),
              ),
            ),
          ],
        );
    }
  }

  String _localizedError(AppLocalizations l10n) {
    final message = task.errorMessage;
    return switch (task.errorCode) {
      AnimeDownloadErrorCode.timeout => l10n.animeDownloadConnectionTimeout,
      AnimeDownloadErrorCode.proxySuggestion =>
        l10n.animeDownloadProxyRetrySuggestion,
      AnimeDownloadErrorCode.emptyVideoUrl => l10n.animeDownloadEmptyVideoUrl,
      AnimeDownloadErrorCode.unknown => l10n.animeDownloadUnknownError,
      null =>
        message?.trim().isNotEmpty == true
            ? message!
            : l10n.downloadFailedStatus,
    };
  }

  Widget _buildActionButton(
    BuildContext context,
    AnimeDownloadManager downloads,
    ColorScheme cs,
  ) {
    final l10n = AppLocalizations.of(context)!;
    switch (task.status) {
      case DownloadTaskStatus.downloading:
        return IconButton(
          onPressed: () => downloads.pauseTask(task.pathWord, task.chapterUuid),
          icon: Icon(Icons.pause, color: cs.primary),
          tooltip: l10n.pauseButton,
        );
      case DownloadTaskStatus.pending:
        return IconButton(
          onPressed: () => downloads.pauseTask(task.pathWord, task.chapterUuid),
          icon: Icon(Icons.pause_outlined, color: cs.onSurfaceVariant),
          tooltip: l10n.pauseButton,
        );
      case DownloadTaskStatus.paused:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () =>
                  downloads.resumeTask(task.pathWord, task.chapterUuid),
              icon: Icon(Icons.play_arrow, color: cs.primary),
              tooltip: l10n.resumeButton,
            ),
            IconButton(
              onPressed: () =>
                  downloads.cancelTask(task.pathWord, task.chapterUuid),
              icon: Icon(Icons.close, color: cs.error),
              tooltip: l10n.cancelButton,
            ),
          ],
        );
      case DownloadTaskStatus.failed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () =>
                  downloads.resumeTask(task.pathWord, task.chapterUuid),
              icon: Icon(Icons.refresh, color: cs.primary),
              tooltip: l10n.retryButton,
            ),
            IconButton(
              onPressed: () =>
                  downloads.cancelTask(task.pathWord, task.chapterUuid),
              icon: Icon(Icons.close, color: cs.error),
              tooltip: l10n.cancelButton,
            ),
          ],
        );
    }
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
    final percent = (progress.ratio * 100).toStringAsFixed(0);
    final completed = progress.completed;
    final total = progress.total;
    return AppLocalizations.of(
      context,
    )!.downloadProgressCount(percent, completed, total);
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
