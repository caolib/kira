import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/api_client.dart';
import '../models/comic.dart' hide Theme;
import '../models/chapter.dart';
import '../utils/data_cache.dart';
import '../utils/download_manager.dart';
import '../utils/reading_history.dart';
import '../utils/toast.dart';
import 'reader_page.dart';

class ComicDetailPage extends StatefulWidget {
  final String pathWord;
  final String? lastBrowseId;
  final String? lastBrowseName;
  const ComicDetailPage({
    super.key,
    required this.pathWord,
    this.lastBrowseId,
    this.lastBrowseName,
  });

  @override
  State<ComicDetailPage> createState() => _ComicDetailPageState();
}

class _ComicDetailPageState extends State<ComicDetailPage> {
  final _api = ApiClient();
  final _cache = DataCache();
  final _downloads = DownloadManager();
  Comic? _comic;
  List<Chapter> _chapters = [];
  final Set<String> _selectedChapterIds = {};
  String _selectedGroup = 'default';
  bool _loadingComic = true;
  bool _refreshingComic = false;
  bool _loadingChapters = false;
  bool _keepShowingCachedChapters = false;
  int _chapterTotal = 0;
  int _chapterPage = 0; // 当前页码（0-based）
  static const _pageSize = 100;
  bool _briefExpanded = false;
  bool _reversed = true;
  bool _isCollected = false;
  bool _selectionMode = false;
  Chapter? _nextBrowseChapter;
  String? _nextBrowseChapterSourceId;
  bool _loadingNextBrowseChapter = false;
  // 本地阅读记录（优先级高于书架传入的记录）
  String? _lastBrowseId;
  String? _lastBrowseName;
  int _lastBrowsePage = 1;
  int _lastBrowseTotalPage = 0;

  String get _cacheKey => 'comic_detail_${widget.pathWord}';

  @override
  void initState() {
    super.initState();
    _lastBrowseId = widget.lastBrowseId;
    _lastBrowseName = widget.lastBrowseName;
    _downloads.addListener(_handleDownloadChanged);
    _initializePage();
  }

  @override
  void dispose() {
    _downloads.removeListener(_handleDownloadChanged);
    super.dispose();
  }

  Future<void> _initializePage() async {
    await Future.wait([
      _downloads.init(),
      _loadLocalHistory(),
      _loadFromCache(),
    ]);
    await _loadComic();
  }

  void _handleDownloadChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadLocalHistory() async {
    final record = await ReadingHistory.get(widget.pathWord);
    if (record != null && mounted) {
      setState(() {
        _lastBrowseId = record.chapterUuid;
        _lastBrowseName = record.chapterName;
        _lastBrowsePage = record.page;
        _lastBrowseTotalPage = record.totalPage;
      });
      await _syncNextBrowseChapter();
    }
  }

  Future<void> _loadFromCache() async {
    final cached = await _cache.get(_cacheKey);
    if (cached is! Map) return;
    final comicJson = cached['comic'];
    if (comicJson is! Map) return;

    final comic = Comic.fromJson(Map<String, dynamic>.from(comicJson));
    final cachedGroup = cached['selectedGroup']?.toString();
    final selectedGroup = _resolveSelectedGroup(
      comic,
      preferredGroup: cachedGroup,
    );
    final canReuseCachedChapters =
        cachedGroup == null || cachedGroup == selectedGroup;
    final cachedChapters = canReuseCachedChapters
        ? (cached['chapters'] as List?)
                  ?.map((j) => Chapter.fromJson(Map<String, dynamic>.from(j)))
                  .toList() ??
              []
        : <Chapter>[];

    if (!mounted) return;
    setState(() {
      _comic = comic;
      _selectedGroup = selectedGroup;
      _chapters = cachedChapters;
      _chapterTotal = canReuseCachedChapters ? cached['chapterTotal'] ?? 0 : 0;
      _chapterPage = canReuseCachedChapters ? cached['chapterPage'] ?? 0 : 0;
      _isCollected = cached['isCollected'] == true;
      _loadingComic = false;
    });
    await _syncNextBrowseChapter();
  }

  Future<void> _saveCache() async {
    final comic = _comic;
    if (comic == null) return;
    await _cache.put(_cacheKey, {
      'comic': comic.toJson(),
      'selectedGroup': _selectedGroup,
      'chapterPage': _chapterPage,
      'chapterTotal': _chapterTotal,
      'chapters': _chapters.map((c) => c.toJson()).toList(),
      'isCollected': _isCollected,
    });
  }

  String _resolveSelectedGroup(Comic comic, {String? preferredGroup}) {
    final groups = comic.groups;
    if (groups != null && groups.isNotEmpty) {
      if (preferredGroup != null && groups.containsKey(preferredGroup)) {
        return preferredGroup;
      }
      return groups.keys.first;
    }
    return 'default';
  }

  Future<void> _loadComic() async {
    final showRefreshNotice = _comic != null;
    if (mounted) {
      setState(() {
        if (!showRefreshNotice) {
          _loadingComic = true;
        }
        _refreshingComic = showRefreshNotice;
      });
    }

    try {
      final comic = await _api.getComicDetail(widget.pathWord);
      if (!mounted) return;
      final selectedGroup = _resolveSelectedGroup(
        comic,
        preferredGroup: _selectedGroup,
      );

      setState(() {
        _comic = comic;
        _loadingComic = false;
        _selectedGroup = selectedGroup;
      });

      await _saveCache();
      await _loadChapterPageForHistory(comic: comic, group: selectedGroup);
      await _loadCollectState();
    } catch (_) {
      if (mounted) setState(() => _loadingComic = false);
    } finally {
      if (mounted) setState(() => _refreshingComic = false);
    }
  }

  Future<void> _loadCollectState() async {
    try {
      final query = await _api.getComicQuery(widget.pathWord);
      if (!mounted) return;
      setState(() => _isCollected = query['collect'] != null);
      await _saveCache();
    } catch (_) {}
  }

  Future<void> _loadChapterPage(
    int page, {
    String? group,
    bool keepVisibleDuringLoad = false,
  }) async {
    if (_loadingChapters) return;
    final targetGroup = group ?? _selectedGroup;

    setState(() {
      _loadingChapters = true;
      _keepShowingCachedChapters =
          keepVisibleDuringLoad &&
          _chapters.isNotEmpty &&
          targetGroup == _selectedGroup &&
          page == _chapterPage;
      _selectionMode = false;
      _selectedChapterIds.clear();
    });

    try {
      final result = await _api.getChapterList(
        widget.pathWord,
        group: targetGroup,
        limit: _pageSize,
        offset: page * _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _chapters = result.list;
        _chapterTotal = result.total;
        _chapterPage = page;
        _loadingChapters = false;
        _keepShowingCachedChapters = false;
      });
      await _saveCache();
      await _syncNextBrowseChapter();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingChapters = false;
          _keepShowingCachedChapters = false;
        });
      }
    }
  }

  int get _totalPages => (_chapterTotal / _pageSize).ceil();

  /// 根据阅读记录中的章节名提取数字，自动跳到对应分页
  Future<void> _loadChapterPageForHistory({Comic? comic, String? group}) async {
    final targetGroup = group ?? _selectedGroup;
    final total =
        comic?.groups?[targetGroup]?.count ??
        _comic?.groups?[targetGroup]?.count ??
        0;
    final page = _resolveHistoryChapterPage(total);
    await _loadChapterPage(
      page,
      group: targetGroup,
      keepVisibleDuringLoad:
          targetGroup == _selectedGroup &&
          page == _chapterPage &&
          _chapters.isNotEmpty,
    );
  }

  int _resolveHistoryChapterPage(int total) {
    if (_lastBrowseName == null || total <= _pageSize) return 0;
    final match = RegExp(r'第(\d+)[话集章回]').firstMatch(_lastBrowseName!);
    if (match == null) return 0;

    final num = int.parse(match.group(1)!);
    final totalPages = (total / _pageSize).ceil();
    return ((num - 1) / _pageSize).floor().clamp(0, totalPages - 1);
  }

  Chapter? _chapterByUuid(String? uuid) {
    if (uuid == null || uuid.isEmpty) return null;
    for (final chapter in _chapters) {
      if (chapter.uuid == uuid) return chapter;
    }
    return null;
  }

  bool get _isLastBrowseComplete {
    if (_lastBrowseTotalPage <= 0) return false;
    final unreadThreshold = _lastBrowseTotalPage <= 1
        ? 1
        : _lastBrowseTotalPage - 1;
    return _lastBrowsePage >= unreadThreshold;
  }

  String _continueReadingLabel() {
    final name = _lastBrowseName ?? '';
    if (_lastBrowseTotalPage > 1) {
      return '$name · $_lastBrowsePage/$_lastBrowseTotalPage';
    }
    return name;
  }

  Future<void> _syncNextBrowseChapter() async {
    if (!mounted) return;

    final currentChapter = _chapterByUuid(_lastBrowseId);
    final canShowNext =
        currentChapter != null &&
        _isLastBrowseComplete &&
        currentChapter.next != null;

    if (!canShowNext) {
      if (_nextBrowseChapter != null || _nextBrowseChapterSourceId != null) {
        setState(() {
          _nextBrowseChapter = null;
          _nextBrowseChapterSourceId = null;
        });
      }
      return;
    }

    final nextUuid = currentChapter.next!;
    final cachedNext = _chapterByUuid(nextUuid);
    if (cachedNext != null) {
      if (_nextBrowseChapter?.uuid != cachedNext.uuid) {
        setState(() {
          _nextBrowseChapter = cachedNext;
          _nextBrowseChapterSourceId = nextUuid;
        });
      }
      return;
    }

    if (_loadingNextBrowseChapter && _nextBrowseChapterSourceId == nextUuid) {
      return;
    }

    _loadingNextBrowseChapter = true;
    _nextBrowseChapterSourceId = nextUuid;
    try {
      final nextPage = _chapterPage < _totalPages - 1 ? _chapterPage + 1 : null;
      Chapter? nextChapter;
      if (nextPage != null) {
        final result = await _api.getChapterList(
          widget.pathWord,
          group: _selectedGroup,
          limit: _pageSize,
          offset: nextPage * _pageSize,
        );
        for (final chapter in result.list) {
          if (chapter.uuid == nextUuid) {
            nextChapter = chapter;
            break;
          }
        }
      }

      if (nextChapter != null &&
          mounted &&
          _lastBrowseId == currentChapter.uuid) {
        setState(() {
          _nextBrowseChapter = nextChapter;
        });
      } else if (mounted && _lastBrowseId == currentChapter.uuid) {
        setState(() {
          _nextBrowseChapter = null;
        });
      }
    } catch (_) {
      if (mounted && _nextBrowseChapterSourceId == nextUuid) {
        setState(() {
          _nextBrowseChapter = null;
        });
      }
    } finally {
      if (_nextBrowseChapterSourceId == nextUuid) {
        _loadingNextBrowseChapter = false;
      }
    }
  }

  Future<void> _toggleCollect() async {
    final newState = !_isCollected;
    setState(() => _isCollected = newState);
    try {
      await _api.toggleCollect(_comic!.uuid!, collect: newState);
      await _saveCache();
    } catch (_) {
      setState(() => _isCollected = !newState);
      await _saveCache();
    }
  }

  bool _isChapterDownloaded(String chapterUuid) =>
      _downloads.isDownloaded(widget.pathWord, chapterUuid);

  bool _isChapterQueued(String chapterUuid) =>
      _downloads.isQueued(widget.pathWord, chapterUuid);

  bool _isChapterSelectable(Chapter chapter) =>
      !_isChapterDownloaded(chapter.uuid) && !_isChapterQueued(chapter.uuid);

  void _enterSelectionMode([String? chapterUuid]) {
    setState(() {
      _selectionMode = true;
      if (chapterUuid != null) {
        _selectedChapterIds.add(chapterUuid);
      }
    });
  }

  void _exitSelectionMode() {
    if (!_selectionMode && _selectedChapterIds.isEmpty) return;
    setState(() {
      _selectionMode = false;
      _selectedChapterIds.clear();
    });
  }

  void _toggleChapterSelection(Chapter chapter) {
    if (!_isChapterSelectable(chapter)) return;
    setState(() {
      _selectionMode = true;
      if (_selectedChapterIds.contains(chapter.uuid)) {
        _selectedChapterIds.remove(chapter.uuid);
      } else {
        _selectedChapterIds.add(chapter.uuid);
      }
      if (_selectedChapterIds.isEmpty) {
        _selectionMode = false;
      }
    });
  }

  void _selectAllVisibleDownloadable() {
    final selectableIds = _displayChapters
        .where(_isChapterSelectable)
        .map((chapter) => chapter.uuid)
        .toSet();
    setState(() {
      _selectionMode = true;
      _selectedChapterIds
        ..clear()
        ..addAll(selectableIds);
    });
  }

  Future<void> _downloadSelectedChapters() async {
    final chapters = _displayChapters
        .where((chapter) => _selectedChapterIds.contains(chapter.uuid))
        .where(_isChapterSelectable)
        .toList();

    if (chapters.isEmpty) {
      showToast(context, '请选择未下载的章节', isError: true);
      return;
    }

    final added = await _downloads.enqueueChapters(
      pathWord: widget.pathWord,
      comic: _comic!,
      chapters: chapters,
    );
    if (!mounted) return;

    showToast(context, added > 0 ? '已加入下载队列：$added 章（顺序下载）' : '所选章节已下载或已在队列中');
    _exitSelectionMode();
  }

  void _openReader(Chapter chapter) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReaderPage(
          pathWord: widget.pathWord,
          chapterUuid: chapter.uuid,
          chapterName: chapter.name,
        ),
      ),
    ).then((_) => _loadLocalHistory());
  }

  List<Chapter> get _displayChapters =>
      _reversed ? _chapters.reversed.toList() : _chapters;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_comic?.name ?? ''),
        actions: [
          if (_comic != null)
            IconButton(
              icon: Icon(
                _isCollected ? Icons.bookmark : Icons.bookmark_border,
                color: _isCollected ? cs.primary : null,
              ),
              onPressed: _toggleCollect,
              tooltip: _isCollected ? '取消收藏' : '收藏',
            ),
        ],
      ),
      body: _loadingComic
          ? const Center(child: CircularProgressIndicator())
          : _comic == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  const Text('加载失败'),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: _loadComic,
                    child: const Text('重试'),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                _buildBody(cs, tt),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: _refreshingComic
                          ? _buildRefreshingNotice(cs, tt)
                          : const SizedBox.shrink(),
                    ),
                  ),
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
                        if (_nextBrowseChapter != null)
                          FloatingActionButton.extended(
                            heroTag: 'next_chapter',
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ReaderPage(
                                  pathWord: widget.pathWord,
                                  chapterUuid: _nextBrowseChapter!.uuid,
                                  chapterName: _nextBrowseChapter!.name,
                                ),
                              ),
                            ).then((_) => _loadLocalHistory()),
                            icon: const Icon(Icons.skip_next, size: 20),
                            label: Text(
                              _nextBrowseChapter!.name,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        FloatingActionButton.extended(
                          heroTag: 'continue_reading',
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
                          ).then((_) => _loadLocalHistory()),
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

  Future<void> _refresh() async {
    _exitSelectionMode();
    await _loadLocalHistory();
    await _loadComic();
  }

  Widget _buildRefreshingNotice(ColorScheme cs, TextTheme tt) {
    return Material(
      color: cs.primaryContainer.withValues(alpha: 0.7),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '正在刷新最新数据...',
                style: tt.bodySmall?.copyWith(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadToolbar(ColorScheme cs, TextTheme tt) {
    final pendingCount = _downloads.pendingCountForComic(widget.pathWord);
    final downloadedCount = _downloads
        .downloadedChapterIds(widget.pathWord)
        .length;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: _selectionMode
            ? Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '已选 ${_selectedChapterIds.length} 章',
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  OutlinedButton.icon(
                    onPressed: _displayChapters.any(_isChapterSelectable)
                        ? _selectAllVisibleDownloadable
                        : null,
                    icon: const Icon(Icons.select_all, size: 18),
                    label: const Text('全选'),
                  ),
                  FilledButton.icon(
                    onPressed: _selectedChapterIds.isEmpty
                        ? null
                        : _downloadSelectedChapters,
                    icon: const Icon(Icons.download_for_offline, size: 18),
                    label: const Text('下载选中'),
                  ),
                  TextButton(
                    onPressed: _exitSelectionMode,
                    child: const Text('取消'),
                  ),
                  Text(
                    '按当前列表顺序串行下载，避免并发请求',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              )
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _displayChapters.any(_isChapterSelectable)
                        ? () => _enterSelectionMode()
                        : null,
                    icon: const Icon(
                      Icons.download_for_offline_outlined,
                      size: 18,
                    ),
                    label: const Text('下载'),
                  ),
                  if (pendingCount > 0)
                    Chip(
                      avatar: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.primary,
                        ),
                      ),
                      label: Text('顺序下载中 $pendingCount 章'),
                    ),
                  if (downloadedCount > 0)
                    Chip(
                      avatar: const Icon(
                        Icons.check_circle,
                        size: 18,
                        color: Colors.green,
                      ),
                      label: Text('已下载 $downloadedCount 章'),
                    ),
                  Text(
                    '长按章节卡片可快速多选',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildChapterCard(Chapter chapter, ColorScheme cs, TextTheme tt) {
    final isLastRead = _lastBrowseId == chapter.uuid;
    final isDownloaded = _isChapterDownloaded(chapter.uuid);
    final isQueued = _isChapterQueued(chapter.uuid);
    final isDownloading = _downloads.isDownloading(
      widget.pathWord,
      chapter.uuid,
    );
    final progress = _downloads.progressOf(widget.pathWord, chapter.uuid);
    final isSelected = _selectedChapterIds.contains(chapter.uuid);

    final backgroundColor = isSelected
        ? cs.secondaryContainer
        : isLastRead
        ? cs.primaryContainer
        : cs.surfaceContainerLow;
    final foregroundColor = isSelected
        ? cs.onSecondaryContainer
        : isLastRead
        ? cs.onPrimaryContainer
        : cs.onSurface;

    final subtitle = isDownloaded
        ? '已下载'
        : isDownloading && progress != null
        ? '下载 ${progress.completed}/${progress.total}'
        : isQueued
        ? '排队中'
        : '${chapter.size}P';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? cs.primary : Colors.transparent,
          width: 1.4,
        ),
      ),
      child: Stack(
        children: [
          Material(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                if (_selectionMode) {
                  _toggleChapterSelection(chapter);
                  return;
                }
                _openReader(chapter);
              },
              onLongPress: _selectionMode || !_isChapterSelectable(chapter)
                  ? null
                  : () => _enterSelectionMode(chapter.uuid),
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
                        chapter.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: tt.bodySmall?.copyWith(
                          color: foregroundColor,
                          fontWeight: isLastRead || isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: tt.labelSmall?.copyWith(
                          color: isSelected
                              ? foregroundColor.withValues(alpha: 0.8)
                              : cs.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (isDownloaded)
            const Positioned(top: 4, right: 4, child: _DownloadedBadge()),
          if (isDownloading && progress != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(10),
                ),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  value: progress.ratio,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme cs, TextTheme tt) {
    final comic = _comic!;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        slivers: [
          // ── 漫画信息卡片 ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: comic.cover,
                      width: 120,
                      height: 160,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(
                        width: 120,
                        height: 160,
                        color: cs.surfaceContainerHighest,
                      ),
                      errorWidget: (_, _, _) => Container(
                        width: 120,
                        height: 160,
                        color: cs.surfaceContainerHighest,
                        child: Icon(
                          Icons.broken_image,
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
                        if (comic.authors.isNotEmpty) ...[
                          Row(
                            children: [
                              Icon(
                                Icons.person_outline,
                                size: 16,
                                color: cs.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  comic.authors.map((a) => a.name).join(' / '),
                                  style: tt.bodyMedium,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (comic.status != null)
                              _InfoChip(
                                icon: Icons.timelapse,
                                label: comic.status!['display'] ?? '',
                                color: cs.primaryContainer,
                                textColor: cs.onPrimaryContainer,
                              ),
                            if (comic.region != null)
                              _InfoChip(
                                icon: Icons.public,
                                label: comic.region!['display'] ?? '',
                                color: cs.secondaryContainer,
                                textColor: cs.onSecondaryContainer,
                              ),
                            ...comic.themes.map(
                              (t) => _InfoChip(
                                icon: Icons.label_outline,
                                label: t.name,
                                color: cs.tertiaryContainer,
                                textColor: cs.onTertiaryContainer,
                              ),
                            ),
                          ],
                        ),
                        if (comic.popular > 0) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(
                                Icons.local_fire_department,
                                size: 16,
                                color: cs.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatPopular(comic.popular),
                                style: tt.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (comic.datetimeUpdated != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.update,
                                size: 16,
                                color: cs.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '更新于 ${comic.datetimeUpdated}',
                                style: tt.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── 简介 ──
          if (comic.brief != null && comic.brief!.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: GestureDetector(
                  onTap: () => setState(() => _briefExpanded = !_briefExpanded),
                  child: Text(
                    comic.brief!,
                    maxLines: _briefExpanded ? null : 3,
                    overflow: _briefExpanded ? null : TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ),
            ),
          // ── 分组切换 ──
          if (comic.groups != null && comic.groups!.length > 1)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: SegmentedButton<String>(
                  segments: comic.groups!.entries
                      .map(
                        (e) => ButtonSegment(
                          value: e.key,
                          label: Text(
                            '${e.value.name}(${e.value.count})',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      )
                      .toList(),
                  selected: {_selectedGroup},
                  onSelectionChanged: (v) {
                    setState(() => _selectedGroup = v.first);
                    _loadChapterPage(0);
                  },
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ),
          // ── 章节标题 + 排序 + 分页 ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.list, size: 20, color: cs.primary),
                  const SizedBox(width: 6),
                  Text(
                    '章节 ($_chapterTotal)',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  if (_totalPages > 1) ...[
                    ...List.generate(_totalPages, (i) {
                      final isSelected = i == _chapterPage;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: isSelected
                            ? FilledButton.tonal(
                                onPressed: null,
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(36, 36),
                                  padding: EdgeInsets.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text('${i + 1}'),
                              )
                            : OutlinedButton(
                                onPressed: () => _loadChapterPage(i),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(36, 36),
                                  padding: EdgeInsets.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text('${i + 1}'),
                              ),
                      );
                    }),
                  ],
                  IconButton(
                    icon: Icon(
                      _reversed ? Icons.arrow_downward : Icons.arrow_upward,
                      size: 20,
                    ),
                    tooltip: _reversed ? '逆序（新→旧）' : '正序（旧→新）',
                    onPressed: () => setState(() => _reversed = !_reversed),
                  ),
                ],
              ),
            ),
          ),
          _buildDownloadToolbar(cs, tt),
          // ── 章节网格 ──
          if (_loadingChapters &&
              (!_keepShowingCachedChapters || _chapters.isEmpty))
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate((_, i) {
                  final ch = _displayChapters[i];
                  return _buildChapterCard(ch, cs, tt);
                }, childCount: _displayChapters.length),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 120,
                  mainAxisExtent: 52,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                ),
              ),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
        ],
      ),
    );
  }

  static String _formatPopular(int n) {
    if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}亿';
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    return n.toString();
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color textColor;
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: textColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadedBadge extends StatelessWidget {
  const _DownloadedBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.green,
        shape: BoxShape.circle,
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(Icons.check, size: 12, color: Colors.white),
      ),
    );
  }
}
