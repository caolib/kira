import 'package:flutter/material.dart';

import '../models/user_manager.dart';
import '../utils/anime_download_manager.dart';
import '../utils/cover_brightness_filter.dart';
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
  late final TabController _tabController;
  final _user = UserManager();
  final _animeDownloads = AnimeDownloadManager();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
    );
    _user.addListener(_onSettingsChanged);
    _animeDownloads.addListener(_onQueueChanged);
  }

  @override
  void dispose() {
    _user.removeListener(_onSettingsChanged);
    _animeDownloads.removeListener(_onQueueChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  void _onQueueChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_user.animeFeatureEnabled) {
      return Scaffold(
        appBar: AppBar(title: const Text('下载中心')),
        body: const LocalComicsPage(embedded: true),
      );
    }

    final tasks = _animeDownloads.tasks;
    final queueCount = tasks.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('下载中心'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(icon: Icon(Icons.menu_book_outlined), text: '漫画'),
            const Tab(icon: Icon(Icons.movie_outlined), text: '动漫'),
            Tab(
              icon: Badge(
                isLabelVisible: queueCount > 0,
                label: Text('$queueCount'),
                child: const Icon(Icons.downloading_outlined),
              ),
              text: '队列',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const LocalComicsPage(embedded: true),
          const LocalAnimePage(embedded: true),
          _AnimeDownloadQueueView(),
        ],
      ),
    );
  }
}

class _AnimeDownloadQueueView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final downloads = AnimeDownloadManager();
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
            const SizedBox(height: 12),
            Text('下载队列为空', style: tt.titleMedium),
            const SizedBox(height: 6),
            Text(
              '去动漫详情页添加下载任务',
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
        return _QueueTaskCard(task: task);
      },
    );
  }
}

class _QueueTaskCard extends StatelessWidget {
  final AnimeDownloadTaskInfo task;

  const _QueueTaskCard({required this.task});

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
                  borderRadius: BorderRadius.circular(8),
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
                const SizedBox(width: 12),
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
                      const SizedBox(height: 4),
                      Text(
                        task.chapterName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _buildStatusLabel(cs, tt),
                    ],
                  ),
                ),
                _buildActionButton(downloads, cs),
              ],
            ),
            if (task.status == DownloadTaskStatus.downloading &&
                task.progress != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: task.progress!.ratio),
              ),
              const SizedBox(height: 4),
              Text(
                _buildProgressText(task.progress!),
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

  String _buildProgressText(AnimeChapterDownloadProgress progress) {
    final percent = (progress.ratio * 100).toStringAsFixed(0);
    final bytes = progress.estimatedTotalBytes;
    if (bytes == null || bytes <= 0) return '$percent%';
    return '$percent% · 约 ${_formatBytes(bytes)}';
  }

  Widget _buildStatusLabel(ColorScheme cs, TextTheme tt) {
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
            Text('下载中', style: tt.labelSmall?.copyWith(color: cs.primary)),
          ],
        );
      case DownloadTaskStatus.pending:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule, size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              '等待中',
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
            Text('已暂停', style: tt.labelSmall?.copyWith(color: Colors.orange)),
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
                task.errorMessage ?? '下载失败',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.labelSmall?.copyWith(color: cs.error),
              ),
            ),
          ],
        );
    }
  }

  Widget _buildActionButton(AnimeDownloadManager downloads, ColorScheme cs) {
    switch (task.status) {
      case DownloadTaskStatus.downloading:
        return IconButton(
          onPressed: () => downloads.pauseTask(task.pathWord, task.chapterUuid),
          icon: Icon(Icons.pause, color: cs.primary),
          tooltip: '暂停',
        );
      case DownloadTaskStatus.pending:
        return IconButton(
          onPressed: () => downloads.pauseTask(task.pathWord, task.chapterUuid),
          icon: Icon(Icons.pause_outlined, color: cs.onSurfaceVariant),
          tooltip: '暂停',
        );
      case DownloadTaskStatus.paused:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () =>
                  downloads.resumeTask(task.pathWord, task.chapterUuid),
              icon: Icon(Icons.play_arrow, color: cs.primary),
              tooltip: '继续',
            ),
            IconButton(
              onPressed: () =>
                  downloads.cancelTask(task.pathWord, task.chapterUuid),
              icon: Icon(Icons.close, color: cs.error),
              tooltip: '取消',
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
              tooltip: '重试',
            ),
            IconButton(
              onPressed: () =>
                  downloads.cancelTask(task.pathWord, task.chapterUuid),
              icon: Icon(Icons.close, color: cs.error),
              tooltip: '取消',
            ),
          ],
        );
    }
  }
}
