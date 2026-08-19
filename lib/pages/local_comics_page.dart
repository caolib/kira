import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';

import '../l10n/app_localizations.dart';
import '../models/comic.dart' hide Theme;
import '../routing/app_router.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/cover_brightness_filter.dart';
import '../utils/download_manager.dart';
import '../utils/reading_history.dart';
import '../utils/toast.dart';
import '../widgets/detail_chip.dart';
import '../widgets/local_content_list_page.dart';

class LocalComicsPage extends StatefulWidget {
  final bool embedded;

  const LocalComicsPage({super.key, this.embedded = false});

  @override
  State<LocalComicsPage> createState() => _LocalComicsPageState();
}

class _LocalComicsPageState extends State<LocalComicsPage> {
  final _downloads = DownloadManager();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return LocalContentListPage(
      embedded: widget.embedded,
      title: l10n.localComicsTitle,
      emptyTitle: l10n.noLocalComicsTitle,
      emptySubtitle: l10n.noLocalComicsSubtitle,
      downloadFolderName: 'comic_downloads',
      deleteDialogTitle: l10n.deleteLocalComicsTitle,
      deleteDialogContent: l10n.deleteLocalComicsContent,
      deleteToastPrefix: l10n.deleteToastPrefix,
      deleteToastSuffix: l10n.deleteToastSuffixComic,
      heroTagPrefix: 'local_comics',
      gridAspectRatio: 0.58,
      unitLabel: l10n.chapterUnit,
      downloadManager: _downloads,
      initDownloads: _downloads.init,
      getLocalItems: () => _downloads
          .localComics()
          .map((entry) => ComicLocalContentEntry(entry))
          .toList(),
      deleteLocalItems: (pathWords) => _downloads.deleteLocalComics(pathWords),
      onOpenDetail: (context, pathWord) => context.pushNamed(
        AppRoutes.localComicDetail,
        pathParameters: {'pathWord': pathWord},
      ),
    );
  }
}

class LocalComicDetailPage extends StatefulWidget {
  final String pathWord;

  const LocalComicDetailPage({super.key, required this.pathWord});

  @override
  State<LocalComicDetailPage> createState() => _LocalComicDetailPageState();
}

class _LocalComicDetailPageState extends State<LocalComicDetailPage> {
  static const _continueReadingNameMaxLength = 10;
  static const _nextChapterNameMaxLength = 10;

  final _downloads = DownloadManager();
  final Set<String> _selectedChapterIds = {};
  bool _selectionMode = false;
  bool _reversed = true;
  bool _didPopAfterDeletion = false;
  String? _selectedGroup;
  String? _lastBrowseId;
  String? _lastBrowseName;
  int _lastBrowsePage = 1;
  int _lastBrowseTotalPage = 0;
  Set<String> _readChapterUuids = const <String>{};

  @override
  void initState() {
    super.initState();
    _downloads.addListener(_handleChanged);
    _loadHistory();
  }

  @override
  void dispose() {
    _downloads.removeListener(_handleChanged);
    super.dispose();
  }

  void _handleChanged() {
    if (!mounted) return;
    final info = _downloads.getLocalComicInfo(widget.pathWord);
    if (info == null ||
        _downloads.downloadedChapters(widget.pathWord).isEmpty) {
      if (_didPopAfterDeletion) return;
      _didPopAfterDeletion = true;
      Navigator.pop(context);
      return;
    }
    final validIds = _downloads
        .downloadedChapters(widget.pathWord)
        .map((item) => item.chapterUuid)
        .toSet();
    _selectedChapterIds.removeWhere((id) => !validIds.contains(id));
    if (_selectedChapterIds.isEmpty) {
      _selectionMode = false;
    }
    setState(() {});
  }

  Future<void> _loadHistory() async {
    final record = await ReadingHistory.get(widget.pathWord);
    if (!mounted || record == null) return;
    setState(() {
      _lastBrowseId = record.chapterUuid;
      _lastBrowseName = record.chapterName;
      _lastBrowsePage = record.page;
      _lastBrowseTotalPage = record.totalPage;
      _readChapterUuids = <String>{...record.readChapterUuids};
    });
  }

  bool get _isLastBrowseComplete {
    if (_lastBrowseTotalPage <= 0) return false;
    final unreadThreshold = _lastBrowseTotalPage <= 1
        ? 1
        : _lastBrowseTotalPage - 1;
    return _lastBrowsePage >= unreadThreshold;
  }

  String _continueReadingLabel() {
    final name = _truncateContinueReadingName(_lastBrowseName ?? '');
    if (_lastBrowseTotalPage > 1) {
      return name.isEmpty
          ? '$_lastBrowsePage/$_lastBrowseTotalPage'
          : '$name · $_lastBrowsePage/$_lastBrowseTotalPage';
    }
    return name;
  }

  String _truncateContinueReadingName(String name) =>
      _truncateChapterName(name, maxLength: _continueReadingNameMaxLength);

  String _truncateNextChapterName(String name) =>
      _truncateChapterName(name, maxLength: _nextChapterNameMaxLength);

  String _truncateChapterName(String name, {required int maxLength}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';
    final chars = trimmed.characters;
    if (chars.length <= maxLength) return trimmed;
    return '${chars.take(maxLength).toString()}...';
  }

  /// 在已下载章节中查找当前章节的下一章，未找到返回 null
  DownloadedChapterSummary? _findNextDownloadedChapter(
    List<DownloadedChapterSummary> chapters,
  ) {
    if (_lastBrowseId == null) return null;
    final index = chapters.indexWhere(
      (item) => item.chapterUuid == _lastBrowseId,
    );
    if (index < 0 || index + 1 >= chapters.length) return null;
    return chapters[index + 1];
  }

  /// 将 group key 映射为显示名（优先取漫画分组表，否则回退 key 本身）。
  String _groupDisplayName(Comic comic, String group) {
    final named = comic.groups?[group]?.name;
    if (named != null && named.trim().isNotEmpty) return named;
    return group;
  }

  /// 渲染当前选中分组的章节网格。
  Widget _buildSelectedGroupChapterSliver(
    List<DownloadedChapterSummary> groupChapters,
    Comic comic,
    ColorScheme cs,
    TextTheme tt,
  ) {
    final displayChapters = _reversed
        ? groupChapters.reversed.toList()
        : groupChapters;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate((_, index) {
          final chapter = displayChapters[index];
          final selected = _selectedChapterIds.contains(chapter.chapterUuid);
          final isLastRead = _lastBrowseId == chapter.chapterUuid;
          final isRead = _readChapterUuids.contains(chapter.chapterUuid);
          return _LocalChapterCard(
            summary: chapter,
            selected: selected,
            isLastRead: isLastRead,
            isRead: isRead,
            selectionMode: _selectionMode,
            onRetry: () => _retryChapter(chapter.chapterUuid),
            onTap: () {
              if (_selectionMode) {
                setState(() {
                  if (selected) {
                    _selectedChapterIds.remove(chapter.chapterUuid);
                  } else {
                    _selectedChapterIds.add(chapter.chapterUuid);
                  }
                  if (_selectedChapterIds.isEmpty) {
                    _selectionMode = false;
                  }
                });
                return;
              }
              context
                  .pushNamed(
                    AppRoutes.reader,
                    pathParameters: {
                      'pathWord': widget.pathWord,
                      'chapterUuid': chapter.chapterUuid,
                    },
                    extra: ReaderExtra(
                      comicName: comic.name,
                      chapterName: chapter.chapterName,
                    ),
                  )
                  .then((_) => _loadHistory());
            },
            onLongPress: () => setState(() {
              _selectionMode = true;
              _selectedChapterIds.add(chapter.chapterUuid);
            }),
          );
        }, childCount: displayChapters.length),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 120,
          mainAxisExtent: 52,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
        ),
      ),
    );
  }

  Future<void> _deleteSelected() async {
    if (_selectedChapterIds.isEmpty) return;
    final count = _selectedChapterIds.length;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteLocalChaptersTitle),
        content: Text(l10n.deleteChaptersConfirm(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.deleteButton),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _downloads.deleteChapters(widget.pathWord, _selectedChapterIds);
    if (!mounted) return;
    showToast(context, l10n.deletedChaptersCount(count));
    final remain = _downloads.downloadedChapters(widget.pathWord);
    if (remain.isEmpty) {
      return;
    }
    setState(() {
      _selectedChapterIds.clear();
      _selectionMode = false;
    });
  }

  Future<void> _retryChapter(String chapterUuid) async {
    final l10n = AppLocalizations.of(context)!;
    final queued = await _downloads.retryChapter(widget.pathWord, chapterUuid);
    if (!mounted) return;
    if (queued) showToast(context, l10n.retryButton);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final info = _downloads.getLocalComicInfo(widget.pathWord);
    final chapters = _downloads.downloadedChapters(widget.pathWord);
    final grouped = _downloads.downloadedChaptersGrouped(widget.pathWord);

    if (info == null || chapters.isEmpty) {
      return const Scaffold(body: Center(child: ExpressiveLoadingIndicator()));
    }

    final comic = info.comic;
    final nextChapter = _findNextDownloadedChapter(chapters);

    // 分组排序：默认分组固定置顶，其余按漫画分组表定义顺序，
    // 未登记在 groups 中的分组追加到末尾（按章节数倒序次要排序）。
    final groupOrder = comic.groups?.keys.toList(growable: false) ?? const [];
    int groupRank(String g) {
      if (g == 'default') return -1;
      final idx = groupOrder.indexOf(g);
      return idx == -1 ? groupOrder.length : idx;
    }

    grouped.sort((a, b) {
      final ra = groupRank(a.group);
      final rb = groupRank(b.group);
      if (ra != rb) return ra.compareTo(rb);
      return b.chapters.length.compareTo(a.chapters.length);
    });

    // 初始化/校正当前选中分组：保持上次选择，否则回退到第一个分组。
    final groupKeys = grouped.map((e) => e.group).toSet();
    if (_selectedGroup == null || !groupKeys.contains(_selectedGroup)) {
      _selectedGroup = grouped.isNotEmpty ? grouped.first.group : 'default';
    }
    final selectedGroupChapters = grouped
        .firstWhere(
          (e) => e.group == _selectedGroup,
          orElse: () => grouped.first,
        )
        .chapters;

    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectionMode
              ? l10n.selectedCount(_selectedChapterIds.length, l10n.chapterUnit)
              : comic.name,
        ),
        actions: [
          if (!_selectionMode)
            IconButton(
              onPressed: () => context.pushNamed(
                AppRoutes.comicDetail,
                pathParameters: {'pathWord': widget.pathWord},
                extra: ComicDetailExtra(initialComic: comic),
              ),
              icon: const Icon(Icons.public),
              tooltip: l10n.viewOnlineDetail,
            ),
          if (!_selectionMode)
            IconButton(
              onPressed: () => setState(() => _selectionMode = true),
              icon: const Icon(Icons.checklist),
              tooltip: l10n.manageChapters,
            ),
          if (_selectionMode) ...[
            IconButton(
              onPressed: () => setState(() {
                _selectedChapterIds
                  ..clear()
                  ..addAll(chapters.map((item) => item.chapterUuid));
              }),
              icon: const Icon(Icons.select_all),
              tooltip: l10n.selectAll,
            ),
            IconButton(
              onPressed: _selectedChapterIds.isEmpty ? null : _deleteSelected,
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.deleteButton,
            ),
            IconButton(
              onPressed: () => setState(() {
                _selectionMode = false;
                _selectedChapterIds.clear();
              }),
              icon: const Icon(Icons.close),
              tooltip: l10n.cancelButton,
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: AppRadius.mdR,
                        child: SizedBox(
                          width: 110,
                          height: 150,
                          child:
                              info.coverPath != null &&
                                  File(info.coverPath!).existsSync()
                              ? CoverBrightnessFilter(
                                  child: Image.file(
                                    File(info.coverPath!),
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : ColoredBox(
                                  color: cs.surfaceContainerHighest,
                                  child: Icon(
                                    Icons.image_not_supported_outlined,
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
                            if (comic.authors.isNotEmpty)
                              Text(
                                comic.authors
                                    .map((item) => item.name)
                                    .join(' / '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: tt.bodyMedium,
                              ),
                            const SizedBox(height: AppSpacing.sm),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (comic.status != null)
                                  DetailChip(
                                    label:
                                        comic.status!['display']?.toString() ??
                                        '',
                                  ),
                                if (comic.region != null)
                                  DetailChip(
                                    label:
                                        comic.region!['display']?.toString() ??
                                        '',
                                  ),
                                ...comic.themes.map(
                                  (item) => DetailChip(label: item.name),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              l10n.downloadedChapterCount(chapters.length),
                              style: tt.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (comic.brief != null && comic.brief!.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text(
                      comic.brief!,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        l10n.localChaptersTitle(chapters.length),
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => setState(() => _reversed = !_reversed),
                        icon: Icon(
                          _reversed ? Icons.arrow_downward : Icons.arrow_upward,
                          size: 20,
                        ),
                        tooltip: _reversed ? l10n.sortReverse : l10n.sortNormal,
                      ),
                    ],
                  ),
                ),
              ),
              if (grouped.length > 1)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: grouped
                          .map(
                            (e) => ButtonSegment(
                              value: e.group,
                              label: Text(
                                '${_groupDisplayName(comic, e.group)}(${e.chapters.length})',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          )
                          .toList(),
                      selected: {_selectedGroup!},
                      onSelectionChanged: (v) =>
                          setState(() => _selectedGroup = v.first),
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                ),
              _buildSelectedGroupChapterSliver(
                selectedGroupChapters,
                comic,
                cs,
                tt,
              ),
            ],
          ),
          if (_lastBrowseId != null)
            Positioned(
              right: 16,
              bottom: 16,
              child: Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.end,
                children: [
                  if (nextChapter != null && _isLastBrowseComplete)
                    FloatingActionButton.extended(
                      heroTag: 'local_next_chapter',
                      onPressed: () => context
                          .pushNamed(
                            AppRoutes.reader,
                            pathParameters: {
                              'pathWord': widget.pathWord,
                              'chapterUuid': nextChapter.chapterUuid,
                            },
                            extra: ReaderExtra(
                              comicName: comic.name,
                              chapterName: nextChapter.chapterName,
                            ),
                          )
                          .then((_) => _loadHistory()),
                      icon: const Icon(Icons.skip_next, size: 20),
                      label: Text(
                        _truncateNextChapterName(nextChapter.chapterName),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  FloatingActionButton.extended(
                    heroTag: 'local_continue_reading',
                    onPressed: () => context
                        .pushNamed(
                          AppRoutes.reader,
                          pathParameters: {
                            'pathWord': widget.pathWord,
                            'chapterUuid': _lastBrowseId!,
                          },
                          extra: ReaderExtra(
                            comicName: comic.name,
                            chapterName: _lastBrowseName ?? '',
                            initialPage: _lastBrowsePage,
                          ),
                        )
                        .then((_) => _loadHistory()),
                    icon: const Icon(Icons.play_arrow, size: 20),
                    label: Text(
                      _continueReadingLabel(),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _LocalChapterCard extends StatelessWidget {
  final DownloadedChapterSummary summary;
  final bool selected;
  final bool isLastRead;
  final bool isRead;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onRetry;

  const _LocalChapterCard({
    required this.summary,
    required this.selected,
    required this.isLastRead,
    required this.isRead,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final brightness = Theme.of(context).brightness;
    final background = selected
        ? cs.secondaryContainer
        : isLastRead
        ? cs.primaryContainer
        : isRead
        ? Color.alphaBlend(
            cs.primary.withValues(
              alpha: brightness == Brightness.dark ? 0.16 : 0.08,
            ),
            cs.surfaceContainerLow,
          )
        : cs.surfaceContainerLow;
    final foreground = selected
        ? cs.onSecondaryContainer
        : isLastRead
        ? cs.onPrimaryContainer
        : isRead
        ? cs.onSurface.withValues(
            alpha: brightness == Brightness.dark ? 0.70 : 0.62,
          )
        : cs.onSurface;
    final subtitleColor = selected
        ? foreground.withValues(alpha: 0.8)
        : isRead && !isLastRead
        ? cs.onSurfaceVariant.withValues(
            alpha: brightness == Brightness.dark ? 0.72 : 0.62,
          )
        : cs.onSurfaceVariant;

    final isPartial = summary.isPartial;
    final statusText = '${summary.pageCount}P';
    final partialText = isPartial
        ? l10n.downloadChapterPartialFailed(summary.failedIndices.length)
        : null;
    final subtitle = isRead && !isLastRead
        ? l10n.comicDetailReadWithStatus(
            partialText != null ? '$statusText · $partialText' : statusText,
          )
        : (partialText != null ? '$statusText · $partialText' : statusText);
    final partialColor = cs.error;

    return Stack(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: background,
            borderRadius: AppRadius.mdR,
            border: Border.all(
              color: selected
                  ? cs.primary
                  : cs.outlineVariant.withValues(
                      alpha: brightness == Brightness.dark ? 0.22 : 0.45,
                    ),
              width: selected ? 1.4 : 0.6,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: brightness == Brightness.dark ? 0.30 : 0.14,
                ),
                blurRadius: brightness == Brightness.dark ? 12 : 14,
                spreadRadius: brightness == Brightness.dark ? 0 : -1,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: AppRadius.mdR,
            child: InkWell(
              borderRadius: AppRadius.mdR,
              onTap: onTap,
              onLongPress: onLongPress,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        summary.chapterName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: tt.bodySmall?.copyWith(
                          color: foreground,
                          fontWeight: isLastRead || selected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.labelSmall?.copyWith(
                          color: isPartial ? partialColor : subtitleColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (selectionMode)
          Positioned(
            top: 6,
            right: 6,
            child: Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 18,
              color: selected ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
        if (isPartial && !selectionMode && onRetry != null)
          Positioned(
            top: 4,
            left: 4,
            child: InkWell(
              onTap: onRetry,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.refresh,
                  size: 14,
                  color: cs.onErrorContainer,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
