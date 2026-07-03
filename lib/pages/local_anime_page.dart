import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../routing/app_router.dart';
import '../utils/anime_download_manager.dart';
import '../utils/cover_brightness_filter.dart';
import '../utils/toast.dart';
import '../widgets/detail_chip.dart';
import '../widgets/local_content_list_page.dart';

class LocalAnimePage extends StatefulWidget {
  final bool embedded;

  const LocalAnimePage({super.key, this.embedded = false});

  @override
  State<LocalAnimePage> createState() => _LocalAnimePageState();
}

class _LocalAnimePageState extends State<LocalAnimePage> {
  final _downloads = AnimeDownloadManager();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return LocalContentListPage(
      embedded: widget.embedded,
      title: l10n.localAnimeTitle,
      emptyTitle: l10n.noLocalAnimeTitle,
      emptySubtitle: l10n.noLocalAnimeSubtitle,
      downloadFolderName: 'anime_downloads',
      deleteDialogTitle: l10n.deleteLocalAnimeTitle,
      deleteDialogContent: l10n.deleteLocalAnimeContent,
      deleteToastPrefix: l10n.deleteToastPrefix,
      deleteToastSuffix: l10n.deleteToastSuffixAnime,
      heroTagPrefix: 'local_anime',
      gridAspectRatio: 0.6,
      unitLabel: l10n.episodeUnit,
      downloadManager: _downloads,
      initDownloads: _downloads.init,
      getLocalItems: () => _downloads
          .localAnimes()
          .map((entry) => AnimeLocalContentEntry(entry))
          .toList(),
      deleteLocalItems: (pathWords) => _downloads.deleteLocalAnimes(pathWords),
      onOpenDetail: (context, pathWord) => context.pushNamed(
        AppRoutes.localAnimeDetail,
        pathParameters: {'pathWord': pathWord},
      ),
    );
  }
}

class LocalAnimeDetailPage extends StatefulWidget {
  final String pathWord;

  const LocalAnimeDetailPage({super.key, required this.pathWord});

  @override
  State<LocalAnimeDetailPage> createState() => _LocalAnimeDetailPageState();
}

class _LocalAnimeDetailPageState extends State<LocalAnimeDetailPage> {
  final _downloads = AnimeDownloadManager();
  final Set<String> _selectedChapterIds = {};
  bool _selectionMode = false;
  bool _didPopAfterDeletion = false;

  @override
  void initState() {
    super.initState();
    _downloads.addListener(_handleChanged);
  }

  @override
  void dispose() {
    _downloads.removeListener(_handleChanged);
    super.dispose();
  }

  void _handleChanged() {
    if (!mounted) return;
    final info = _downloads.getLocalAnimeInfo(widget.pathWord);
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
    if (_selectedChapterIds.isEmpty) _selectionMode = false;
    setState(() {});
  }

  Future<void> _deleteSelected() async {
    if (_selectedChapterIds.isEmpty) return;
    final count = _selectedChapterIds.length;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteLocalEpisodesTitle),
        content: Text(l10n.deleteEpisodesConfirm(count)),
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
    showToast(context, l10n.deletedEpisodesCount(count));
    final remain = _downloads.downloadedChapters(widget.pathWord);
    if (remain.isEmpty) return;
    setState(() {
      _selectedChapterIds.clear();
      _selectionMode = false;
    });
  }

  void _playChapter(DownloadedAnimeChapterSummary summary) {
    final videoPath = _downloads.getLocalVideoPath(
      widget.pathWord,
      summary.chapterUuid,
    );
    if (videoPath == null || !File(videoPath).existsSync()) {
      showToast(
        context,
        AppLocalizations.of(context)!.videoFileNotFound,
        isError: true,
      );
      return;
    }
    context.pushNamed(
      AppRoutes.animePlayer,
      pathParameters: {
        'pathWord': widget.pathWord,
        'chapterUuid': summary.chapterUuid,
      },
      extra: AnimePlayerExtra(
        animeName:
            _downloads.getLocalAnimeInfo(widget.pathWord)?.anime.name ?? '',
        chapterName: summary.chapterName,
        line: '',
        localVideoPath: videoPath,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final info = _downloads.getLocalAnimeInfo(widget.pathWord);
    final chapters = _downloads.downloadedChapters(widget.pathWord);

    if (info == null || chapters.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final l10n = AppLocalizations.of(context)!;
    final anime = info.anime;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectionMode
              ? l10n.selectedCount(_selectedChapterIds.length, l10n.episodeUnit)
              : anime.name,
        ),
        actions: [
          if (!_selectionMode)
            IconButton(
              onPressed: () => context.pushNamed(
                AppRoutes.animeDetail,
                pathParameters: {'pathWord': widget.pathWord},
                extra: AnimeDetailExtra(initialAnime: anime),
              ),
              icon: const Icon(Icons.public),
              tooltip: l10n.viewOnlineDetail,
            ),
          if (!_selectionMode)
            IconButton(
              onPressed: () => setState(() => _selectionMode = true),
              icon: const Icon(Icons.checklist),
              tooltip: l10n.manageEpisodes,
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
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
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
                                Icons.movie_outlined,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (anime.company != null)
                          Text(anime.company!.name, style: tt.bodyMedium),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (anime.category?['display'] != null)
                              DetailChip(
                                label: anime.category!['display'].toString(),
                                borderRadius: 999,
                              ),
                            if (anime.grade?['display'] != null)
                              DetailChip(
                                label: anime.grade!['display'].toString(),
                                borderRadius: 999,
                              ),
                            ...anime.themes.map(
                              (item) => DetailChip(
                                label: item.name,
                                borderRadius: 999,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          l10n.downloadedEpisodeCount(chapters.length),
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
          if (anime.brief != null && anime.brief!.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  anime.brief!,
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
              child: Text(
                l10n.localEpisodesTitle(chapters.length),
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 100,
                childAspectRatio: 1.8,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              delegate: SliverChildBuilderDelegate((_, index) {
                final chapter = chapters[index];
                final selected = _selectedChapterIds.contains(
                  chapter.chapterUuid,
                );
                return _LocalAnimeChapterCard(
                  summary: chapter,
                  selected: selected,
                  selectionMode: _selectionMode,
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
                    _playChapter(chapter);
                  },
                  onLongPress: () => setState(() {
                    _selectionMode = true;
                    _selectedChapterIds.add(chapter.chapterUuid);
                  }),
                );
              }, childCount: chapters.length),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalAnimeChapterCard extends StatelessWidget {
  final DownloadedAnimeChapterSummary summary;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _LocalAnimeChapterCard({
    required this.summary,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Center(
                child: Text(
                  summary.chapterName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected
                        ? cs.onPrimaryContainer
                        : cs.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    height: 1.2,
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
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                  size: 20,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
