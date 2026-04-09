import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/download_manager.dart';
import '../utils/reading_history.dart';
import '../utils/toast.dart';
import 'chapter_comments_sheet.dart';
import 'comic_detail_page.dart';
import 'reader_page.dart';

class LocalComicsPage extends StatefulWidget {
  const LocalComicsPage({super.key});

  @override
  State<LocalComicsPage> createState() => _LocalComicsPageState();
}

class _LocalComicsPageState extends State<LocalComicsPage> {
  final _downloads = DownloadManager();
  final Set<String> _selectedPathWords = {};
  bool _selectionMode = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _downloads.addListener(_handleChanged);
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _downloads.removeListener(_handleChanged);
    super.dispose();
  }

  void _handleChanged() {
    if (!mounted) return;
    final valid = _downloads
        .localComics()
        .map((item) => item.info.comic.pathWord)
        .toSet();
    _selectedPathWords.removeWhere((pathWord) => !valid.contains(pathWord));
    if (_selectedPathWords.isEmpty) {
      _selectionMode = false;
    }
    setState(() {});
  }

  Future<void> _initialize() async {
    await _downloads.init();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _deleteSelected() async {
    if (_selectedPathWords.isEmpty) return;
    final count = _selectedPathWords.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除本地漫画'),
        content: Text('确定删除选中的 $count 部本地漫画吗？已下载章节和封面都会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _downloads.deleteLocalComics(_selectedPathWords);
    if (!mounted) return;
    setState(() {
      _selectedPathWords.clear();
      _selectionMode = false;
    });
    showToast(context, '已删除 $count 部本地漫画');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final items = _downloads.localComics();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectionMode ? '已选 ${_selectedPathWords.length} 部' : '本地漫画',
        ),
        actions: [
          if (!_selectionMode && items.isNotEmpty)
            IconButton(
              onPressed: () => setState(() => _selectionMode = true),
              icon: const Icon(Icons.checklist),
              tooltip: '批量管理',
            ),
          if (_selectionMode) ...[
            IconButton(
              onPressed: items.isEmpty
                  ? null
                  : () => setState(() {
                      _selectedPathWords
                        ..clear()
                        ..addAll(items.map((item) => item.info.comic.pathWord));
                    }),
              icon: const Icon(Icons.select_all),
              tooltip: '全选',
            ),
            IconButton(
              onPressed: _selectedPathWords.isEmpty ? null : _deleteSelected,
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除',
            ),
            IconButton(
              onPressed: () => setState(() {
                _selectionMode = false;
                _selectedPathWords.clear();
              }),
              icon: const Icon(Icons.close),
              tooltip: '取消',
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.download_done_outlined,
                    size: 56,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text('还没有本地漫画', style: tt.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    '去漫画详情页下载章节后，这里会显示离线内容',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 150,
                childAspectRatio: 0.58,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
              itemCount: items.length,
              itemBuilder: (_, index) {
                final item = items[index];
                final pathWord = item.info.comic.pathWord;
                final selected = _selectedPathWords.contains(pathWord);
                return _LocalComicCard(
                  entry: item,
                  selected: selected,
                  selectionMode: _selectionMode,
                  onTap: () {
                    if (_selectionMode) {
                      setState(() {
                        if (selected) {
                          _selectedPathWords.remove(pathWord);
                        } else {
                          _selectedPathWords.add(pathWord);
                        }
                        if (_selectedPathWords.isEmpty) {
                          _selectionMode = false;
                        }
                      });
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            LocalComicDetailPage(pathWord: pathWord),
                      ),
                    );
                  },
                  onLongPress: () => setState(() {
                    _selectionMode = true;
                    _selectedPathWords.add(pathWord);
                  }),
                );
              },
            ),
    );
  }
}

class _LocalComicCard extends StatelessWidget {
  final LocalComicEntry entry;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _LocalComicCard({
    required this.entry,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final comic = entry.info.comic;
    final coverPath = entry.info.coverPath;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? cs.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox.expand(
                        child: coverPath != null && File(coverPath).existsSync()
                            ? Image.file(File(coverPath), fit: BoxFit.cover)
                            : ColoredBox(
                                color: cs.surfaceContainerHighest,
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: cs.onSurfaceVariant,
                                  size: 32,
                                ),
                              ),
                      ),
                    ),
                    if (selectionMode)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: selected ? cs.primary : Colors.black45,
                            shape: BoxShape.circle,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              selected ? Icons.check : Icons.circle_outlined,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '已下载 ${entry.downloadedCount} 章',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                comic.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.bodySmall,
              ),
              const SizedBox(height: 2),
              Text(
                comic.authors.isNotEmpty
                    ? comic.authors.map((item) => item.name).join(' / ')
                    : comic.pathWord,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
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
  final _downloads = DownloadManager();
  final Set<String> _selectedChapterIds = {};
  bool _selectionMode = false;
  bool _reversed = true;
  bool _didPopAfterDeletion = false;
  String? _lastBrowseId;
  String? _lastBrowseName;
  int _lastBrowsePage = 1;

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
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedChapterIds.isEmpty) return;
    final count = _selectedChapterIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除本地章节'),
        content: Text('确定删除选中的 $count 个章节吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _downloads.deleteChapters(widget.pathWord, _selectedChapterIds);
    if (!mounted) return;
    showToast(context, '已删除 $count 个章节');
    final remain = _downloads.downloadedChapters(widget.pathWord);
    if (remain.isEmpty) {
      return;
    }
    setState(() {
      _selectedChapterIds.clear();
      _selectionMode = false;
    });
  }

  Future<void> _showComments(DownloadedChapterSummary summary) async {
    final detail = await _downloads.getDownloadedChapterDetail(
      widget.pathWord,
      summary.chapterUuid,
    );
    if (!mounted || detail == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width,
      ),
      backgroundColor: Colors.transparent,
      builder: (_) => ChapterCommentsSheet(
        chapterUuid: detail.uuid,
        chapterName: detail.name,
        initialComments: detail.comments,
        initialTotal: detail.commentTotal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final info = _downloads.getLocalComicInfo(widget.pathWord);
    final chapters = _downloads.downloadedChapters(widget.pathWord);

    if (info == null || chapters.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final displayChapters = _reversed ? chapters.reversed.toList() : chapters;
    final comic = info.comic;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectionMode ? '已选 ${_selectedChapterIds.length} 章' : comic.name,
        ),
        actions: [
          if (!_selectionMode)
            IconButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ComicDetailPage(pathWord: widget.pathWord),
                ),
              ),
              icon: const Icon(Icons.public),
              tooltip: '查看在线详情',
            ),
          if (!_selectionMode)
            IconButton(
              onPressed: () => setState(() => _selectionMode = true),
              icon: const Icon(Icons.checklist),
              tooltip: '管理章节',
            ),
          if (_selectionMode) ...[
            IconButton(
              onPressed: () => setState(() {
                _selectedChapterIds
                  ..clear()
                  ..addAll(chapters.map((item) => item.chapterUuid));
              }),
              icon: const Icon(Icons.select_all),
              tooltip: '全选',
            ),
            IconButton(
              onPressed: _selectedChapterIds.isEmpty ? null : _deleteSelected,
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除',
            ),
            IconButton(
              onPressed: () => setState(() {
                _selectionMode = false;
                _selectedChapterIds.clear();
              }),
              icon: const Icon(Icons.close),
              tooltip: '取消',
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
                          ? Image.file(File(info.coverPath!), fit: BoxFit.cover)
                          : ColoredBox(
                              color: cs.surfaceContainerHighest,
                              child: Icon(
                                Icons.image_not_supported_outlined,
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
                        if (comic.authors.isNotEmpty)
                          Text(
                            comic.authors.map((item) => item.name).join(' / '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodyMedium,
                          ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (comic.status != null)
                              _DetailChip(
                                label:
                                    comic.status!['display']?.toString() ?? '',
                              ),
                            if (comic.region != null)
                              _DetailChip(
                                label:
                                    comic.region!['display']?.toString() ?? '',
                              ),
                            ...comic.themes.map(
                              (item) => _DetailChip(label: item.name),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '已下载 ${chapters.length} 章',
                          style: tt.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_lastBrowseId != null) ...[
                          const SizedBox(height: 8),
                          FilledButton.tonalIcon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ReaderPage(
                                  pathWord: widget.pathWord,
                                  chapterUuid: _lastBrowseId!,
                                  chapterName: _lastBrowseName ?? '',
                                  initialPage: _lastBrowsePage,
                                ),
                              ),
                            ).then((_) => _loadHistory()),
                            icon: const Icon(Icons.play_arrow, size: 18),
                            label: Text('继续  ${_lastBrowseName ?? ''}'),
                          ),
                        ],
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
                    '本地章节 (${chapters.length})',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => setState(() => _reversed = !_reversed),
                    icon: Icon(
                      _reversed ? Icons.arrow_downward : Icons.arrow_upward,
                      size: 20,
                    ),
                    tooltip: _reversed ? '逆序（新→旧）' : '正序（旧→新）',
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate((_, index) {
                final chapter = displayChapters[index];
                final selected = _selectedChapterIds.contains(
                  chapter.chapterUuid,
                );
                final isLastRead = _lastBrowseId == chapter.chapterUuid;
                return _LocalChapterCard(
                  summary: chapter,
                  selected: selected,
                  isLastRead: isLastRead,
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
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReaderPage(
                          pathWord: widget.pathWord,
                          chapterUuid: chapter.chapterUuid,
                          chapterName: chapter.chapterName,
                        ),
                      ),
                    ).then((_) => _loadHistory());
                  },
                  onLongPress: () => setState(() {
                    _selectionMode = true;
                    _selectedChapterIds.add(chapter.chapterUuid);
                  }),
                  onCommentsTap: _selectionMode
                      ? null
                      : () => _showComments(chapter),
                );
              }, childCount: displayChapters.length),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 160,
                mainAxisExtent: 74,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
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
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onCommentsTap;

  const _LocalChapterCard({
    required this.summary,
    required this.selected,
    required this.isLastRead,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
    this.onCommentsTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final background = selected
        ? cs.secondaryContainer
        : isLastRead
        ? cs.primaryContainer
        : cs.surfaceContainerLow;
    final foreground = selected
        ? cs.onSecondaryContainer
        : isLastRead
        ? cs.onPrimaryContainer
        : cs.onSurface;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      summary.chapterName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(
                        color: foreground,
                        fontWeight: isLastRead || selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (selectionMode)
                    Icon(
                      selected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: selected ? cs.primary : cs.onSurfaceVariant,
                    )
                  else
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: onCommentsTap,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.forum_outlined,
                          size: 16,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                '${summary.pageCount}P',
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  final String label;

  const _DetailChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: cs.onSecondaryContainer),
      ),
    );
  }
}
