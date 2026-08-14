import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api_client.dart';
import '../l10n/app_localizations.dart';
import '../models/chapter.dart';
import '../models/comic.dart' as comic_model;
import '../models/comic.dart' hide Theme;
import '../repositories/comic_detail_repository.dart';
import '../routing/app_router.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/app_logger.dart';
import '../utils/cover_brightness_filter.dart';
import '../utils/download_manager.dart';
import '../utils/kira_links.dart';
import '../utils/reading_history.dart';
import '../utils/time_format.dart';
import '../utils/toast.dart';
import '../widgets/comic_hero_tags.dart';
import 'comic_comments_sheet.dart';

class ComicDetailPage extends StatefulWidget {
  final String pathWord;
  final Comic? initialComic;
  final String? heroTagBase;
  final String? lastBrowseId;
  final String? lastBrowseName;
  const ComicDetailPage({
    super.key,
    required this.pathWord,
    this.initialComic,
    this.heroTagBase,
    this.lastBrowseId,
    this.lastBrowseName,
  });

  static Route<void> route({
    required String pathWord,
    Comic? initialComic,
    String? heroTagBase,
    String? lastBrowseId,
    String? lastBrowseName,
  }) {
    return PageRouteBuilder<void>(
      transitionDuration: ComicHeroTags.transitionDuration,
      reverseTransitionDuration: ComicHeroTags.reverseTransitionDuration,
      pageBuilder: (context, animation, secondaryAnimation) => ComicDetailPage(
        pathWord: pathWord,
        initialComic: initialComic,
        heroTagBase: heroTagBase,
        lastBrowseId: lastBrowseId,
        lastBrowseName: lastBrowseName,
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (animation.status == AnimationStatus.reverse) {
          return Opacity(opacity: 0, child: child);
        }
        return child;
      },
    );
  }

  @override
  State<ComicDetailPage> createState() => _ComicDetailPageState();
}

class _ComicDetailPageState extends State<ComicDetailPage> {
  static const _continueReadingNameMaxLength = 10;
  static const _nextChapterNameMaxLength = 10;

  final _api = ApiClient();
  late final _repo = ComicDetailRepository(widget.pathWord);
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
  int _chapterPage = 0; // Current page index (0-based)
  static const _pageSize = 100;
  // In-session chapter page cache; destroyed with State.
  final Map<String, ({List<Chapter> list, int total})> _chapterPageCache = {};
  bool _briefExpanded = false;
  bool _reversed = false;
  bool _isCollected = false;
  bool _selectionMode = false;
  Chapter? _nextBrowseChapter;
  int? _nextBrowseChapterListPage;
  String? _nextBrowseChapterSourceId;
  bool _loadingNextBrowseChapter = false;
  // Local reading history takes precedence over bookshelf record.
  late final String? _officialLastBrowseId;
  late final String? _officialLastBrowseName;
  bool _usingLocalHistory = false;
  String? _lastBrowseId;
  String? _lastBrowseName;
  int? _lastBrowseChapterListPage;
  int _lastBrowsePage = 1;
  int _lastBrowseTotalPage = 0;
  Set<String> _readChapterUuids = const <String>{};

  @override
  void initState() {
    super.initState();
    _comic = widget.initialComic;
    _loadingComic = widget.initialComic == null;
    _officialLastBrowseId = widget.lastBrowseId;
    _officialLastBrowseName = widget.lastBrowseName;
    _lastBrowseId = widget.lastBrowseId;
    _lastBrowseName = widget.lastBrowseName;
    _downloads.addListener(_handleDownloadChanged);
    unawaited(_initializePage());
  }

  @override
  void dispose() {
    _downloads.removeListener(_handleDownloadChanged);
    super.dispose();
  }

  Future<void> _initializePage() async {
    unawaited(_initializeDownloads());
    await _loadFromCache();
    await _loadLocalHistory();
    await _loadComic();
  }

  Future<void> _initializeDownloads() async {
    try {
      await _downloads.init();
      if (mounted) setState(() {});
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'comic_detail.initialize_downloads',
        ),
      );
    }
  }

  void _handleDownloadChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadLocalHistory({String? group}) async {
    final targetGroup = group ?? _selectedGroup;
    final record = await ReadingHistory.get(
      widget.pathWord,
      group: targetGroup,
    );
    if (!mounted || targetGroup != _selectedGroup) return;

    final useOfficialLastBrowse =
        record == null && targetGroup == ReadingHistory.defaultGroup;
    setState(() {
      _usingLocalHistory = record != null;
      _lastBrowseId =
          record?.chapterUuid ??
          (useOfficialLastBrowse ? _officialLastBrowseId : null);
      _lastBrowseName =
          record?.chapterName ??
          (useOfficialLastBrowse ? _officialLastBrowseName : null);
      _lastBrowseChapterListPage = record?.chapterListPage;
      _lastBrowsePage = record?.page ?? 1;
      _lastBrowseTotalPage = record?.totalPage ?? 0;
      _readChapterUuids = <String>{...?record?.readChapterUuids};
      _reversed = _shouldReverseForCurrentPage();
    });
    await _syncNextBrowseChapter();
  }

  Future<void> _loadFromCache() async {
    final cached = await _repo.loadFromCache();
    if (cached == null) return;

    final comic = cached.comic;
    final cachedGroup = cached.selectedGroup;
    final selectedGroup = _resolveSelectedGroup(
      comic,
      preferredGroup: cachedGroup,
    );
    final canReuseCachedChapters =
        cachedGroup == 'default' || cachedGroup == selectedGroup;
    final cachedChapters = canReuseCachedChapters
        ? cached.chapters
        : <Chapter>[];

    if (!mounted) return;
    setState(() {
      _comic = comic;
      _selectedGroup = selectedGroup;
      _chapters = cachedChapters;
      _chapterTotal = canReuseCachedChapters ? cached.chapterTotal : 0;
      _chapterPage = canReuseCachedChapters ? cached.chapterPage : 0;
      _reversed = _shouldReverseForCurrentPage();
      _isCollected = cached.isCollected;
      _loadingComic = false;
    });
    await _syncNextBrowseChapter();
  }

  Future<void> _saveCache() async {
    final comic = _comic;
    if (comic == null) return;
    await _repo.saveToCache(
      ComicDetailData(
        comic: comic,
        selectedGroup: _selectedGroup,
        chapterPage: _chapterPage,
        chapterTotal: _chapterTotal,
        chapters: _chapters,
        isCollected: _isCollected,
      ),
    );
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
        if (showRefreshNotice) {
          _refreshingComic = true;
        } else {
          _loadingComic = true;
        }
      });
    }

    try {
      final comic = await _api.manga.getComicDetail(widget.pathWord);
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

      await _loadLocalHistory(group: selectedGroup);
      await _saveCache();
      await _loadChapterPageForHistory(comic: comic, group: selectedGroup);
      await _loadCollectState();
      if (mounted && showRefreshNotice) {
        setState(() => _refreshingComic = false);
      }
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'comic_detail.load',
        ),
      );
      if (mounted) {
        setState(() {
          _loadingComic = false;
          _refreshingComic = false;
        });
      }
    }
  }

  Future<void> _loadCollectState() async {
    try {
      final query = await _api.manga.getComicQuery(widget.pathWord);
      if (!mounted) return;
      setState(() => _isCollected = query['collect'] != null);
      await _saveCache();
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'comic_detail.load_collect_state',
        ),
      );
    }
  }

  Future<void> _loadChapterPage(
    int page, {
    String? group,
    bool keepVisibleDuringLoad = false,
    bool forceRefresh = false,
  }) async {
    if (_loadingChapters) return;
    final targetGroup = group ?? _selectedGroup;
    final cacheKey = '$targetGroup:$page';

    // 命中会话内缓存：直接复用，避免重复请求
    if (!forceRefresh) {
      final cached = _chapterPageCache[cacheKey];
      if (cached != null) {
        setState(() {
          _chapters = cached.list;
          _reversed = _shouldReverseForCurrentPage();
          _chapterTotal = cached.total;
          _chapterPage = page;
          _selectedGroup = targetGroup;
          _loadingChapters = false;
          _keepShowingCachedChapters = false;
          _selectionMode = false;
          _selectedChapterIds.clear();
        });
        await _saveCache();
        await _syncNextBrowseChapter();
        return;
      }
    }

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
      final result = await _api.manga.getChapterList(
        widget.pathWord,
        group: targetGroup,
        offset: page * _pageSize,
      );
      if (!mounted) return;
      _chapterPageCache[cacheKey] = result;
      setState(() {
        _chapters = result.list;
        _reversed = _shouldReverseForCurrentPage();
        _chapterTotal = result.total;
        _chapterPage = page;
        _selectedGroup = targetGroup;
        _loadingChapters = false;
        _keepShowingCachedChapters = false;
      });
      await _saveCache();
      await _syncNextBrowseChapter();
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'comic_detail.load_chapters',
        ),
      );
      if (mounted) {
        setState(() {
          _loadingChapters = false;
          _keepShowingCachedChapters = false;
        });
      }
    }
  }

  int get _totalPages => (_chapterTotal / _pageSize).ceil();

  /// 优先使用阅读记录中的章节列表页；旧记录再按章节名估算分页。
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
    final recordedPage = _lastBrowseChapterListPage;
    if (recordedPage != null) {
      return _normalizeChapterListPage(recordedPage, total);
    }

    if (_lastBrowseName == null || total <= _pageSize) return 0;
    final match = RegExp(r'第(\d+)[话集章回卷]').firstMatch(_lastBrowseName!);
    if (match == null) return 0;

    final num = int.parse(match.group(1)!);
    return _normalizeChapterListPage(((num - 1) / _pageSize).floor(), total);
  }

  int _normalizeChapterListPage(int page, int total) {
    if (page <= 0) return 0;
    if (total <= 0) return page;
    final totalPages = (total / _pageSize).ceil();
    if (page >= totalPages) return totalPages - 1;
    return page;
  }

  Chapter? _chapterByUuid(String? uuid) {
    if (uuid == null || uuid.isEmpty) return null;
    for (final chapter in _chapters) {
      if (chapter.uuid == uuid) return chapter;
    }
    return null;
  }

  /// 根据上次阅读章节在当前页中的位置决定是否逆序。
  /// 仅当章节在当前页的后半部分时才设为逆序，否则正序。
  /// 若上次阅读章节不在当前页，保持当前状态不变。
  bool _shouldReverseForCurrentPage() {
    final lastBrowseId = _lastBrowseId;
    if (lastBrowseId == null || lastBrowseId.isEmpty) return false;
    final index = _chapters.indexWhere((c) => c.uuid == lastBrowseId);
    if (index < 0) return _reversed; // 不在当前页，保持现状
    return index >= _chapters.length / 2;
  }

  bool get _isLastBrowseComplete {
    if (_lastBrowseTotalPage <= 0) return false;
    return _lastBrowsePage / _lastBrowseTotalPage >= 0.8;
  }

  bool get _canShowLastBrowseAction {
    if (_lastBrowseId == null) return false;
    return _usingLocalHistory || _selectedGroup == ReadingHistory.defaultGroup;
  }

  int? get _lastBrowseReaderChapterListPage {
    final recordedPage = _lastBrowseChapterListPage;
    if (recordedPage != null) return recordedPage;
    return _chapterByUuid(_lastBrowseId) != null ? _chapterPage : null;
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

  String _truncateContinueReadingName(String name) {
    return _truncateChapterName(name, maxLength: _continueReadingNameMaxLength);
  }

  String _truncateNextChapterName(String name) {
    return _truncateChapterName(name, maxLength: _nextChapterNameMaxLength);
  }

  String _truncateChapterName(String name, {required int maxLength}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';

    final chars = trimmed.characters;
    if (chars.length <= maxLength) {
      return trimmed;
    }
    return '${chars.take(maxLength).toString()}...';
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
          _nextBrowseChapterListPage = null;
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
          _nextBrowseChapterListPage = _chapterPage;
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
        final cacheKey = '$_selectedGroup:$nextPage';
        final cached = _chapterPageCache[cacheKey];
        final result =
            cached ??
            await _api.manga.getChapterList(
              widget.pathWord,
              group: _selectedGroup,
              offset: nextPage * _pageSize,
            );
        if (cached == null) {
          _chapterPageCache[cacheKey] = result;
        }
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
          _nextBrowseChapterListPage = nextPage;
        });
      } else if (mounted && _lastBrowseId == currentChapter.uuid) {
        setState(() {
          _nextBrowseChapter = null;
          _nextBrowseChapterListPage = null;
        });
      }
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'comic_detail.next_browse_chapter',
        ),
      );
      if (mounted && _nextBrowseChapterSourceId == nextUuid) {
        setState(() {
          _nextBrowseChapter = null;
          _nextBrowseChapterListPage = null;
        });
      }
    } finally {
      if (_nextBrowseChapterSourceId == nextUuid) {
        _loadingNextBrowseChapter = false;
      }
    }
  }

  Future<void> _toggleCollect() async {
    final comicId = _comic?.uuid;
    if (comicId == null || comicId.isEmpty) return;

    final newState = !_isCollected;
    setState(() => _isCollected = newState);
    try {
      await _api.manga.toggleCollect(comicId, collect: newState);
      await _saveCache();
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'comic_detail.toggle_collect',
        ),
      );
      if (!mounted) return;
      setState(() => _isCollected = !newState);
      await _saveCache();
    }
  }

  Future<void> _showComicComments() async {
    final comic = _comic;
    final comicId = comic?.uuid;
    if (comic == null || comicId == null || comicId.isEmpty) {
      showToast(
        context,
        AppLocalizations.of(context)!.comicDetailCommentsUnavailable,
        isError: true,
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width),
      backgroundColor: Colors.transparent,
      builder: (_) =>
          ComicCommentsSheet(comicId: comicId, comicName: comic.name),
    );
  }

  void _openAuthorWorks(Author author) {
    final authorPathWord = author.pathWord.trim();
    if (authorPathWord.isEmpty) {
      showToast(
        context,
        AppLocalizations.of(context)!.comicDetailAuthorUnavailable,
        isError: true,
      );
      return;
    }

    final authorName = author.name.trim().isEmpty
        ? authorPathWord
        : author.name.trim();
    context.pushNamed(
      AppRoutes.ranking,
      extra: RankingExtra(
        authorPathWord: authorPathWord,
        authorName: authorName,
      ),
    );
  }

  void _openThemeWorks(comic_model.Theme theme) {
    final themePathWord = theme.pathWord.trim();
    if (themePathWord.isEmpty) {
      showToast(
        context,
        AppLocalizations.of(context)!.comicDetailThemeUnavailable,
        isError: true,
      );
      return;
    }

    final themeName = theme.name.trim().isEmpty
        ? themePathWord
        : theme.name.trim();
    context.pushNamed(
      AppRoutes.ranking,
      extra: RankingExtra(themePathWord: themePathWord, themeName: themeName),
    );
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

  void _toggleDownloadSelectionMode() {
    if (_selectionMode) {
      _exitSelectionMode();
      return;
    }
    if (_displayChapters.any(_isChapterSelectable)) {
      _enterSelectionMode();
    }
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
      showToast(
        context,
        AppLocalizations.of(context)!.comicDetailSelectUndownloadedChapters,
        isError: true,
      );
      return;
    }

    final added = await _downloads.enqueueChapters(
      pathWord: widget.pathWord,
      comic: _comic!,
      chapters: chapters,
    );
    if (!mounted) return;

    final l10n = AppLocalizations.of(context)!;
    showToast(
      context,
      added > 0
          ? l10n.comicDetailAddedToDownloadQueue(added)
          : l10n.comicDetailSelectedAlreadyDownloadedOrQueued,
    );
    _exitSelectionMode();
  }

  void _openReader(Chapter chapter) {
    context
        .pushNamed(
          AppRoutes.reader,
          pathParameters: {
            'pathWord': widget.pathWord,
            'chapterUuid': chapter.uuid,
          },
          extra: ReaderExtra(
            comicName: _comic?.name,
            group: _selectedGroup,
            chapterName: chapter.name,
            chapterListPage: _chapterPage,
          ),
        )
        .then((_) => _loadLocalHistory());
  }

  /// 通过系统分享面板分享漫画的 https 落地页链接（见 [KiraLinks.comicShareUrl]），
  /// 接收方点击后由系统或落地页拉起 kira 并打开本漫画详情页。
  Future<void> _shareComic() async {
    final l10n = AppLocalizations.of(context)!;
    final name = _comic?.name ?? widget.pathWord;
    // 分享面板关闭时 app 恢复前台会触发剪贴板检测；先把自己分享的链接
    // 记为已处理，避免分享者收到自己刚分享的提示。
    unawaited(SharedLinkRecord.markHandled(widget.pathWord));
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: l10n.comicDetailShareContent(
            name,
            KiraLinks.comicShareUrl(widget.pathWord),
          ),
          subject: name,
        ),
      );
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'comic_detail.share',
        ),
      );
    }
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
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: AppLocalizations.of(context)!.comicDetailShare,
            onPressed: _shareComic,
          ),
        ],
      ),
      body: _loadingComic
          ? const Center(child: ExpressiveLoadingIndicator())
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
                  const SizedBox(height: AppSpacing.md),
                  Text(AppLocalizations.of(context)!.loadingFailed),
                  const SizedBox(height: AppSpacing.sm),
                  FilledButton.tonal(
                    onPressed: _loadComic,
                    child: Text(AppLocalizations.of(context)!.retryButton),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                _buildBody(cs, tt),
                if (_canShowLastBrowseAction)
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
                            onPressed: () => context
                                .pushNamed(
                                  AppRoutes.reader,
                                  pathParameters: {
                                    'pathWord': widget.pathWord,
                                    'chapterUuid': _nextBrowseChapter!.uuid,
                                  },
                                  extra: ReaderExtra(
                                    comicName: _comic?.name,
                                    group: _selectedGroup,
                                    chapterName: _nextBrowseChapter!.name,
                                    chapterListPage:
                                        _nextBrowseChapterListPage ??
                                        _chapterPage,
                                  ),
                                )
                                .then((_) => _loadLocalHistory()),
                            icon: const Icon(Icons.skip_next, size: 20),
                            label: Text(
                              _truncateNextChapterName(
                                _nextBrowseChapter!.name,
                              ),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        FloatingActionButton.extended(
                          heroTag: 'continue_reading',
                          onPressed: () => context
                              .pushNamed(
                                AppRoutes.reader,
                                pathParameters: {
                                  'pathWord': widget.pathWord,
                                  'chapterUuid': _lastBrowseId!,
                                },
                                extra: ReaderExtra(
                                  comicName: _comic?.name,
                                  group: _selectedGroup,
                                  chapterName: _lastBrowseName ?? '',
                                  chapterListPage:
                                      _lastBrowseReaderChapterListPage,
                                  initialPage: _lastBrowsePage,
                                ),
                              )
                              .then((_) => _loadLocalHistory()),
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
    _chapterPageCache.clear();
    await _loadLocalHistory();
    await _loadComic();
  }

  Widget _buildGroupSegments(Comic comic) {
    return SegmentedButton<String>(
      showSelectedIcon: false,
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
      onSelectionChanged: (v) async {
        final group = v.first;
        setState(() => _selectedGroup = group);
        await _loadLocalHistory(group: group);
        await _loadChapterPageForHistory(group: group);
      },
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _buildSortButton(ColorScheme cs) {
    return FilledButton.tonal(
      onPressed: () => setState(() => _reversed = !_reversed),
      style: FilledButton.styleFrom(
        minimumSize: const Size(38, 38),
        maximumSize: const Size(38, 38),
        fixedSize: const Size(38, 38),
        padding: EdgeInsets.zero,
        backgroundColor: cs.surfaceContainerHigh,
        foregroundColor: cs.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdR),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Tooltip(
        message: _reversed
            ? AppLocalizations.of(context)!.sortReverse
            : AppLocalizations.of(context)!.sortNormal,
        child: Icon(
          _reversed ? Icons.arrow_downward : Icons.arrow_upward,
          size: 20,
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
                    AppLocalizations.of(
                      context,
                    )!.comicDetailSelectedChapters(_selectedChapterIds.length),
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  OutlinedButton.icon(
                    onPressed: _displayChapters.any(_isChapterSelectable)
                        ? _selectAllVisibleDownloadable
                        : null,
                    icon: const Icon(Icons.select_all, size: 18),
                    label: Text(AppLocalizations.of(context)!.selectAll),
                  ),
                  FilledButton.icon(
                    onPressed: _selectedChapterIds.isEmpty
                        ? null
                        : _downloadSelectedChapters,
                    icon: const Icon(Icons.download_for_offline, size: 18),
                    label: Text(
                      AppLocalizations.of(context)!.animeDetailDownloadSelected,
                    ),
                  ),
                ],
              )
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
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
                      label: Text(
                        AppLocalizations.of(
                          context,
                        )!.comicDetailSequentialDownloading(pendingCount),
                      ),
                    ),
                  if (downloadedCount > 0)
                    Chip(
                      avatar: const Icon(
                        Icons.check_circle,
                        size: 18,
                        color: Colors.green,
                      ),
                      label: Text(
                        AppLocalizations.of(
                          context,
                        )!.downloadedChapterCount(downloadedCount),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildChapterCard(Chapter chapter, ColorScheme cs, TextTheme tt) {
    final isLastRead = _lastBrowseId == chapter.uuid;
    final isRead = _readChapterUuids.contains(chapter.uuid);
    final isDownloaded = _isChapterDownloaded(chapter.uuid);
    final isQueued = _isChapterQueued(chapter.uuid);
    final isDownloading = _downloads.isDownloading(
      widget.pathWord,
      chapter.uuid,
    );
    final progress = _downloads.progressOf(widget.pathWord, chapter.uuid);
    final isSelected = _selectedChapterIds.contains(chapter.uuid);
    final brightness = Theme.of(context).brightness;

    final backgroundColor = isSelected
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
    final foregroundColor = isSelected
        ? cs.onSecondaryContainer
        : isLastRead
        ? cs.onPrimaryContainer
        : isRead
        ? cs.onSurface.withValues(
            alpha: brightness == Brightness.dark ? 0.70 : 0.62,
          )
        : cs.onSurface;
    final subtitleColor = isSelected
        ? foregroundColor.withValues(alpha: 0.8)
        : isRead && !isLastRead
        ? cs.onSurfaceVariant.withValues(
            alpha: brightness == Brightness.dark ? 0.72 : 0.62,
          )
        : cs.onSurfaceVariant;

    final statusText = isDownloaded
        ? AppLocalizations.of(context)!.downloadedStatus
        : isDownloading && progress != null
        ? AppLocalizations.of(
            context,
          )!.comicDetailDownloadProgress(progress.completed, progress.total)
        : isQueued
        ? AppLocalizations.of(context)!.comicDetailQueued
        : '${chapter.size}P';
    final subtitle = isRead && !isLastRead
        ? AppLocalizations.of(context)!.comicDetailReadWithStatus(statusText)
        : statusText;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: AppRadius.mdR,
        border: Border.all(
          color: isSelected
              ? cs.primary
              : cs.outlineVariant.withValues(
                  alpha: brightness == Brightness.dark ? 0.22 : 0.45,
                ),
          width: isSelected ? 1.4 : 0.6,
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
      child: Stack(
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: AppRadius.mdR,
            child: InkWell(
              borderRadius: AppRadius.mdR,
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
                          color: subtitleColor,
                          fontSize: 12,
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

  Widget _hero(String Function(String base) tagOf, Widget child) {
    final base = widget.heroTagBase;
    if (base == null) return child;
    return Hero(
      tag: tagOf(base),
      createRectTween: ComicHeroTags.createRectTween,
      placeholderBuilder: _buildHeroPlaceholder,
      child: child,
    );
  }

  Widget _buildHeroPlaceholder(
    BuildContext context,
    Size heroSize,
    Widget child,
  ) {
    return SizedBox(width: heroSize.width, height: heroSize.height);
  }

  Widget _buildDetailActions(Comic comic) {
    final buttonStyle = FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );

    return Row(
      children: [
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed:
                _selectionMode || _displayChapters.any(_isChapterSelectable)
                ? _toggleDownloadSelectionMode
                : null,
            icon: Icon(
              _selectionMode
                  ? Icons.close
                  : Icons.download_for_offline_outlined,
              size: 18,
            ),
            label: Text(
              _selectionMode
                  ? AppLocalizations.of(context)!.cancelButton
                  : AppLocalizations.of(context)!.animeDetailDownloadButton,
            ),
            style: buttonStyle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: comic.uuid == null || comic.uuid!.isEmpty
                ? null
                : _showComicComments,
            icon: const Icon(Icons.forum_outlined, size: 18),
            label: Text(AppLocalizations.of(context)!.chapterCommentsComment),
            style: buttonStyle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: comic.uuid == null || comic.uuid!.isEmpty
                ? null
                : _toggleCollect,
            icon: Icon(
              _isCollected ? Icons.bookmark : Icons.bookmark_border,
              size: 18,
            ),
            label: Text(
              _isCollected
                  ? AppLocalizations.of(context)!.animeDetailCollected
                  : AppLocalizations.of(context)!.collectButton,
            ),
            style: buttonStyle,
          ),
        ),
      ],
    );
  }

  Widget _buildBody(ColorScheme cs, TextTheme tt) {
    final comic = _comic!;
    final authors = comic.authors
        .where((author) => author.name.trim().isNotEmpty)
        .toList();
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
                  _hero(
                    ComicHeroTags.cover,
                    ClipRRect(
                      borderRadius: AppRadius.mdR,
                      child: CoverBrightnessFilter(
                        child: CachedNetworkImage(
                          imageUrl: comic.cover,
                          width: 120,
                          height: 160,
                          fit: BoxFit.cover,
                          fadeInDuration: Duration.zero,
                          fadeOutDuration: Duration.zero,
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
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          comic.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        if (authors.isNotEmpty ||
                            comic.status != null ||
                            comic.region != null ||
                            comic.themes.isNotEmpty)
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final author in authors)
                                _AuthorChip(
                                  author: author,
                                  onTap: () => _openAuthorWorks(author),
                                ),
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
                              for (final theme in comic.themes)
                                _ThemeChip(
                                  theme: theme,
                                  onTap: () => _openThemeWorks(theme),
                                  color: cs.tertiaryContainer,
                                  textColor: cs.onTertiaryContainer,
                                ),
                            ],
                          ),
                        if (comic.popular > 0) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(
                                Icons.local_fire_department,
                                size: 14,
                                color: cs.primary,
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Text(
                                _formatPopular(context, comic.popular),
                                style: tt.labelSmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (comic.datetimeUpdated != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Row(
                            children: [
                              Icon(
                                Icons.update,
                                size: 14,
                                color: cs.onSurfaceVariant,
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Text(
                                TimeFormat.relativeOf(
                                  comic.datetimeUpdated!,
                                  AppLocalizations.of(context)!,
                                ),
                                style: tt.labelSmall?.copyWith(
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
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _buildDetailActions(comic),
            ),
          ),
          // ── 分组切换 ──
          if (comic.groups != null && comic.groups!.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _totalPages <= 1
                    // 无分页时把排序按钮放到分组按钮后面，节省空间
                    ? Row(
                        children: [
                          Expanded(child: _buildGroupSegments(comic)),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 160),
                            child: _refreshingComic
                                ? const Padding(
                                    key: ValueKey('comic_detail_refreshing'),
                                    padding: EdgeInsets.only(left: 8),
                                    child: SizedBox.square(
                                      dimension: 38,
                                      child: Center(
                                        child: SizedBox.square(
                                          dimension: 22,
                                          child: ExpressiveLoadingIndicator(),
                                        ),
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(
                                    key: ValueKey(
                                      'comic_detail_not_refreshing',
                                    ),
                                  ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: _buildSortButton(cs),
                          ),
                        ],
                      )
                    : _buildGroupSegments(comic),
              ),
            ),
          // ── 章节标题 + 排序 + 分页（单页时排序按钮已合并到分组行）──
          if (_totalPages > 1)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: List.generate(_totalPages, (i) {
                            final isSelected = i == _chapterPage;
                            final pageButtonShape = RoundedRectangleBorder(
                              borderRadius: AppRadius.mdR,
                            );
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              child: isSelected
                                  ? FilledButton(
                                      onPressed: () {},
                                      style: FilledButton.styleFrom(
                                        minimumSize: const Size(38, 38),
                                        maximumSize: const Size(38, 38),
                                        fixedSize: const Size(38, 38),
                                        padding: EdgeInsets.zero,
                                        backgroundColor: cs.primary,
                                        foregroundColor: cs.onPrimary,
                                        disabledBackgroundColor: cs.primary,
                                        disabledForegroundColor: cs.onPrimary,
                                        shape: pageButtonShape,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: Text('${i + 1}'),
                                    )
                                  : FilledButton.tonal(
                                      onPressed: () => _loadChapterPage(i),
                                      style: FilledButton.styleFrom(
                                        minimumSize: const Size(38, 38),
                                        maximumSize: const Size(38, 38),
                                        fixedSize: const Size(38, 38),
                                        padding: EdgeInsets.zero,
                                        backgroundColor:
                                            cs.surfaceContainerHigh,
                                        foregroundColor: cs.onSurfaceVariant,
                                        shape: pageButtonShape,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: Text('${i + 1}'),
                                    ),
                            );
                          }),
                        ),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      child: _refreshingComic
                          ? const Padding(
                              key: ValueKey('comic_detail_refreshing'),
                              padding: EdgeInsets.only(left: 8),
                              child: SizedBox.square(
                                dimension: 38,
                                child: Center(
                                  child: SizedBox.square(
                                    dimension: 22,
                                    child: ExpressiveLoadingIndicator(),
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(
                              key: ValueKey('comic_detail_not_refreshing'),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: _buildSortButton(cs),
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
                child: Center(child: ExpressiveLoadingIndicator()),
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

  static String _formatPopular(BuildContext context, int n) {
    final l10n = AppLocalizations.of(context)!;
    if (n >= 100000000) {
      return l10n.hundredMillionUnit((n / 100000000).toStringAsFixed(1));
    }
    if (n >= 10000) {
      return l10n.tenThousandUnit((n / 10000).toStringAsFixed(1));
    }
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
      decoration: BoxDecoration(color: color, borderRadius: AppRadius.lgR),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: textColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthorChip extends StatelessWidget {
  final Author author;
  final VoidCallback onTap;

  const _AuthorChip({required this.author, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.primaryContainer,
      borderRadius: AppRadius.lgR,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.lgR,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_search_outlined,
                size: 12,
                color: cs.onPrimaryContainer,
              ),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  author.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeChip extends StatelessWidget {
  final comic_model.Theme theme;
  final VoidCallback onTap;
  final Color color;
  final Color textColor;

  const _ThemeChip({
    required this.theme,
    required this.onTap,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: AppRadius.lgR,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.lgR,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.label_outline, size: 12, color: textColor),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  theme.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: textColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DownloadedBadge extends StatelessWidget {
  const _DownloadedBadge();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle),
      child: Padding(
        padding: EdgeInsets.all(2),
        child: Icon(Icons.check, size: 12, color: Colors.white),
      ),
    );
  }
}
