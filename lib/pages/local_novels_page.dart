import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';

import '../api/novel/novel_api.dart' show novelErrorMessage;
import '../l10n/app_localizations.dart';
import '../models/novel_reading_progress.dart';
import '../providers/novel_providers.dart';
import '../routing/app_router.dart';
import '../theme/app_icon_sizes.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/app_logger.dart';
import '../utils/cover_brightness_filter.dart';
import '../utils/novel_download_manager.dart';
import '../utils/toast.dart';
import '../widgets/comic_info_chips.dart';
import '../widgets/local_content_list_page.dart';
import 'comic_detail_page.dart'
    show ChapterCard, chapterTileExtent, comicDetailUsesTwoPane;

/// 本机永久保存的轻小说；不按当前账号过滤，和漫画本地书架保持一致。
class LocalNovelsPage extends ConsumerStatefulWidget {
  const LocalNovelsPage({
    super.key,
    this.embedded = false,
    this.trailingAction,
  });

  final bool embedded;
  final Widget? trailingAction;

  @override
  ConsumerState<LocalNovelsPage> createState() => _LocalNovelsPageState();
}

class _LocalNovelsPageState extends ConsumerState<LocalNovelsPage> {
  late final NovelDownloadManager _downloads = ref.read(
    novelDownloadManagerProvider,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return LocalContentListPage(
      embedded: widget.embedded,
      trailingAction: widget.trailingAction,
      title: l10n.novelLocalTitle,
      emptyTitle: l10n.novelNoLocalTitle,
      emptySubtitle: l10n.novelNoLocalSubtitle,
      downloadFolderName: 'novel_downloads',
      downloadFolderPath: () => _downloads.rootPath,
      deleteDialogTitle: l10n.novelDeleteLocalTitle,
      deleteDialogContent: l10n.novelDeleteLocalContent,
      deleteToastPrefix: l10n.deleteToastPrefix,
      deleteToastSuffix: l10n.novelDeleteToastSuffix,
      heroTagPrefix: 'local_novels',
      gridAspectRatio: 0.58,
      unitLabel: l10n.novelVolumeUnit,
      downloadManager: _downloads,
      initDownloads: _downloads.init,
      getLocalItems: () => _downloads.localNovels
          .map((entry) => NovelLocalContentEntry(entry))
          .toList(),
      deleteLocalItems: (pathWords) async {
        for (final pathWord in pathWords) {
          await _downloads.deleteNovel(pathWord);
        }
      },
      onOpenDetail: (context, pathWord) => context.pushNamed(
        AppRoutes.localNovelDetail,
        pathParameters: {'pathWord': pathWord},
      ),
    );
  }
}

/// Adapter for downloaded novels, mirroring [ComicLocalContentEntry].
class NovelLocalContentEntry implements LocalContentEntry {
  final LocalNovelInfo _info;

  const NovelLocalContentEntry(this._info);

  @override
  String get pathWord => _info.pathWord;

  @override
  String get name => _info.name;

  @override
  String? get coverPath => _info.coverPath;

  @override
  int get downloadedCount => _info.downloadedCount;

  @override
  String get subtitle {
    final authors = _info.book.authors
        .map((author) => author.name)
        .where((name) => name.trim().isNotEmpty);
    return authors.isNotEmpty ? authors.join(' / ') : _info.pathWord;
  }

  @override
  IconData get fallbackIcon => Icons.menu_book_outlined;
}

/// 本地轻小说详情：分卷列表、续读、逐卷删除与失败重试。
/// 交互与 [LocalComicDetailPage] 对齐，数据来自小说下载 store。
class LocalNovelDetailPage extends ConsumerStatefulWidget {
  const LocalNovelDetailPage({super.key, required this.pathWord});

  final String pathWord;

  @override
  ConsumerState<LocalNovelDetailPage> createState() =>
      _LocalNovelDetailPageState();
}

class _LocalNovelDetailPageState extends ConsumerState<LocalNovelDetailPage> {
  late final NovelDownloadManager _downloads = ref.read(
    novelDownloadManagerProvider,
  );
  final Set<String> _selectedVolumeIds = {};
  bool _selectionMode = false;
  bool _reversed = false;
  bool _briefExpanded = false;
  bool _didPopAfterDeletion = false;
  NovelReadingProgress? _progress;

  @override
  void initState() {
    super.initState();
    _downloads.addListener(_handleChanged);
    unawaited(_loadProgress());
  }

  @override
  void dispose() {
    _downloads.removeListener(_handleChanged);
    super.dispose();
  }

  Future<void> _loadProgress() async {
    final progress = await ref
        .read(novelReadingStoreProvider)
        .readProgress(widget.pathWord);
    if (!mounted) return;
    setState(() => _progress = progress);
  }

  void _handleChanged() {
    if (!mounted) return;
    if (_downloads.localVolumeIds(widget.pathWord).isEmpty) {
      if (_didPopAfterDeletion) return;
      _didPopAfterDeletion = true;
      Navigator.pop(context);
      return;
    }
    final valid = _downloads.localVolumeIds(widget.pathWord);
    _selectedVolumeIds.removeWhere((id) => !valid.contains(id));
    if (_selectedVolumeIds.isEmpty) _selectionMode = false;
    setState(() {});
  }

  Future<void> _openVolume(String volumeId) async {
    await context.pushNamed(
      AppRoutes.novelReader,
      pathParameters: {'pathWord': widget.pathWord, 'volumeId': volumeId},
      extra: NovelReaderExtra(
        name: _downloads.localInfo(widget.pathWord)?.name ?? '',
        cover: _downloads.localInfo(widget.pathWord)?.book.cover ?? '',
        preferDownloads: true,
        noDetailBelow: true,
      ),
    );
    if (mounted) await _loadProgress();
  }

  Future<void> _retryVolume(String volumeId) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await _downloads.requeueVolume(widget.pathWord, volumeId);
    } catch (error, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          error,
          stackTrace: stack,
          source: 'local_novel.retry',
        ),
      );
      if (mounted) {
        showToast(
          context,
          l10n.novelDownloadEnqueueFailed(novelErrorMessage(error)),
          isError: true,
        );
      }
      return;
    }
    if (!mounted) return;
    showToast(context, l10n.retryButton);
  }

  Future<void> _deleteSelected() async {
    if (_selectedVolumeIds.isEmpty) return;
    final count = _selectedVolumeIds.length;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.novelDeleteLocalVolumesTitle),
        content: Text(l10n.novelDeleteLocalVolumesContent(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.deleteButton),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _downloads.deleteVolumes(
      widget.pathWord,
      _selectedVolumeIds.toList(growable: false),
    );
    if (!mounted) return;
    setState(() {
      _selectedVolumeIds.clear();
      _selectionMode = false;
    });
    showToast(context, l10n.novelDeletedVolumesToast(count));
  }

  String? get _resumeVolumeId {
    final progress = _progress;
    if (progress == null || progress.volumeId.isEmpty) return null;
    return _downloads
            .localVolumeIds(widget.pathWord)
            .contains(progress.volumeId)
        ? progress.volumeId
        : null;
  }

  String? get _resumePercent {
    final progress = _progress;
    if (progress == null) return null;
    final ratio = progress.progress;
    if (ratio == 0 &&
        (progress.entryIndex > 0 ||
            progress.paragraphIndex > 0 ||
            progress.paragraphAlignment < 0)) {
      return null;
    }
    if (ratio == 1) return '100.00';
    final percent = ratio * 100;
    final capped = ratio < 1 && percent > 99.99 ? 99.99 : percent;
    return capped.toStringAsFixed(2);
  }

  Widget _buildResumeButton(String volumeId) {
    final l10n = AppLocalizations.of(context)!;
    final volume = _downloads.localVolumeInfo(widget.pathWord, volumeId);
    final percent = _resumePercent;
    final label = [
      volume?.volume.name ?? '',
      if (percent != null) '$percent%',
    ].where((part) => part.isNotEmpty).join(' · ');
    return FloatingActionButton.extended(
      heroTag: 'local_novel_continue_reading',
      onPressed: () => unawaited(_openVolume(volumeId)),
      icon: const Icon(Icons.play_arrow, size: AppIconSize.lg),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Text(
          label.isEmpty ? l10n.novelContinueReading : label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final local = _downloads.localInfo(widget.pathWord);
    if (local == null || _downloads.localVolumeIds(widget.pathWord).isEmpty) {
      return const Scaffold(body: Center(child: ExpressiveLoadingIndicator()));
    }
    final book = local.book;
    final volumes = _downloads.localVolumes(widget.pathWord);
    final displayVolumes = _reversed
        ? volumes.reversed.toList(growable: false)
        : volumes;
    final readVolumeIds = {
      ...?_progress?.readVolumeIds,
      if (_progress?.volumeId.isNotEmpty == true) _progress!.volumeId,
    };
    final size = MediaQuery.sizeOf(context);
    final isWide = comicDetailUsesTwoPane(size);
    final authors = book.authors
        .where((author) => author.name.trim().isNotEmpty)
        .toList();

    final infoSlivers = <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: AppRadius.mdR,
                child: SizedBox(
                  width: 120,
                  height: 160,
                  child:
                      local.coverPath != null &&
                          File(local.coverPath!).existsSync()
                      ? CoverBrightnessFilter(
                          child: Image.file(
                            File(local.coverPath!),
                            fit: BoxFit.cover,
                          ),
                        )
                      : ColoredBox(
                          color: cs.surfaceContainerHighest,
                          child: Icon(
                            Icons.menu_book_outlined,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final author in authors)
                          InfoChip(
                            icon: Icons.person_outline,
                            label: author.name,
                            color: cs.primaryContainer,
                            textColor: cs.onPrimaryContainer,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      if (book.brief.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Builder(
              builder: (context) {
                final expanded = _briefExpanded || isWide;
                return GestureDetector(
                  onTap: () => setState(() => _briefExpanded = !_briefExpanded),
                  child: Text(
                    book.brief,
                    maxLines: expanded ? null : 3,
                    overflow: expanded ? null : TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                );
              },
            ),
          ),
        ),
    ];

    final volumeSlivers = <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Text(
                l10n.novelLocalVolumesTitle(volumes.length),
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => setState(() => _reversed = !_reversed),
                icon: Icon(
                  _reversed ? Icons.arrow_downward : Icons.arrow_upward,
                  size: AppIconSize.lg,
                ),
                tooltip: _reversed ? l10n.sortReverse : l10n.sortNormal,
              ),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        sliver: SliverGrid(
          delegate: SliverChildBuilderDelegate((_, index) {
            final volume = displayVolumes[index];
            final selected = _selectedVolumeIds.contains(volume.id);
            final info = local.downloaded[volume.id];
            final needsRepair = info?.needsRepair == true;
            final card = ChapterCard(
              name: volume.name,
              subtitle: needsRepair
                  ? l10n.novelDownloadNeedsRepair
                  : info == null || info.total <= 1
                  ? null
                  : '${info.completed}/${info.total}',
              isSelected: selected,
              isLastRead: _progress?.volumeId == volume.id,
              isRead: readVolumeIds.contains(volume.id),
              isDownloaded: info?.isDownloaded == true,
              onTap: () {
                if (_selectionMode) {
                  setState(() {
                    if (selected) {
                      _selectedVolumeIds.remove(volume.id);
                    } else {
                      _selectedVolumeIds.add(volume.id);
                    }
                    if (_selectedVolumeIds.isEmpty) _selectionMode = false;
                  });
                  return;
                }
                unawaited(_openVolume(volume.id));
              },
              onLongPress: () => setState(() {
                _selectionMode = true;
                _selectedVolumeIds.add(volume.id);
              }),
            );
            if (!needsRepair || _selectionMode) return card;
            // 待修复的卷不能阅读，只能重下；卡片右上角给一个明确入口。
            return Stack(
              children: [
                card,
                Positioned(
                  left: 0,
                  top: 0,
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: l10n.retryButton,
                    onPressed: () => unawaited(_retryVolume(volume.id)),
                    icon: Icon(
                      Icons.refresh,
                      size: AppIconSize.md,
                      color: cs.primary,
                    ),
                  ),
                ),
              ],
            );
          }, childCount: displayVolumes.length),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 150,
            mainAxisExtent: chapterTileExtent(
              MediaQuery.textScalerOf(context).scale(1),
            ),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
          ),
        ),
      ),
    ];

    final Widget bodyContent;
    if (isWide) {
      bodyContent = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: (size.width * 0.36).clamp(300.0, 420.0),
            child: CustomScrollView(slivers: infoSlivers),
          ),
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: cs.outlineVariant.withValues(alpha: 0.6),
          ),
          Expanded(child: CustomScrollView(slivers: volumeSlivers)),
        ],
      );
    } else {
      bodyContent = CustomScrollView(
        slivers: [...infoSlivers, ...volumeSlivers],
      );
    }

    final resumeVolumeId = _resumeVolumeId;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectionMode
              ? l10n.selectedCount(
                  _selectedVolumeIds.length,
                  l10n.novelVolumeUnit,
                )
              : book.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (!_selectionMode)
            IconButton(
              onPressed: () => context.pushNamed(
                AppRoutes.novelDetail,
                pathParameters: {'pathWord': widget.pathWord},
              ),
              icon: const Icon(Icons.public),
              tooltip: l10n.viewOnlineDetail,
            ),
          if (!_selectionMode)
            IconButton(
              onPressed: () => setState(() => _selectionMode = true),
              icon: const Icon(Icons.checklist),
              tooltip: l10n.novelManageVolumes,
            ),
          if (_selectionMode) ...[
            IconButton(
              onPressed: () => setState(() {
                _selectedVolumeIds
                  ..clear()
                  ..addAll(volumes.map((volume) => volume.id));
              }),
              icon: const Icon(Icons.select_all),
              tooltip: l10n.selectAll,
            ),
            IconButton(
              onPressed: _selectedVolumeIds.isEmpty ? null : _deleteSelected,
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.deleteButton,
            ),
            IconButton(
              onPressed: () => setState(() {
                _selectionMode = false;
                _selectedVolumeIds.clear();
              }),
              icon: const Icon(Icons.close),
              tooltip: l10n.cancelButton,
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          bodyContent,
          if (resumeVolumeId != null)
            Positioned(
              right: 16,
              bottom: 16,
              child: _buildResumeButton(resumeVolumeId),
            ),
        ],
      ),
    );
  }
}

/// 兼容旧的独立入口：单独打开本地轻小说列表。
class LocalNovelsStandalonePage extends StatelessWidget {
  const LocalNovelsStandalonePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.novelLocalTitle)),
      body: const LocalNovelsPage(),
    );
  }
}
