import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api_client.dart';
import '../l10n/app_localizations.dart';
import '../models/chapter.dart';
import '../models/comic.dart' as comic_model;
import '../models/comic.dart' hide Theme;
import '../models/reader_settings.dart';
import '../repositories/comic_detail_repository.dart';
import '../routing/app_router.dart';
import '../theme/app_icon_sizes.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/adaptive_motion.dart';
import '../utils/app_logger.dart';
import '../utils/bookmark_store.dart';
import '../utils/cover_brightness_filter.dart';
import '../utils/download_manager.dart';
import '../utils/kira_links.dart';
import '../utils/network_error.dart';
import '../utils/novel_download_manager.dart';
import '../utils/reading_history.dart';
import '../utils/share_origin.dart';
import '../utils/time_format.dart';
import '../utils/toast.dart';
import '../widgets/app_hero.dart';
import '../widgets/comic_hero_tags.dart';
import '../widgets/comic_info_chips.dart';
import '../widgets/cover_image.dart';
import '../widgets/download_settings_sheet.dart';
import '../widgets/error_retry_view.dart';
import 'comic_comments_sheet.dart';
import 'comic_detail/reading_actions.dart';

part 'comic_detail/comic_detail_actions.dart';
part 'comic_detail/comic_detail_auto_locate.dart';
part 'comic_detail/comic_detail_build.dart';
part 'comic_detail/comic_detail_chapter_card.dart';
part 'comic_detail/comic_detail_last_browse.dart';
part 'comic_detail/comic_detail_reading_actions.dart';
part 'comic_detail/comic_detail_slivers.dart';

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
  final _readerSettings = ReaderSettings();
  final _chapterGridKey = GlobalKey();
  late final _chapterControlsKey = GlobalKey();
  final _comicInfoKey = GlobalKey();
  final _detailScrollController = ScrollController();
  bool _showBackToTop = false;
  bool _savingAutoLocate = false;
  int _locateRequest = 0;
  String? _locateHighlightedId;
  Timer? _locateHighlightTimer;
  Comic? _comic;
  List<Chapter> _chapters = [];
  String? _chapterListGroup;
  final Set<String> _selectedChapterIds = {};
  String _selectedGroup = 'default';
  bool _loadingComic = true;
  bool _refreshingComic = false;
  String? _comicError;
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

  /// 服务端收藏态是否仍在加载。与轻小说详情一致：未确认前按钮禁用，
  /// 不能拿缓存里的旧值直接就当权威状态去翻转。
  bool _collectStateLoading = true;

  /// 收藏请求是否在飞：防止连点发出多个切换请求。
  bool _collecting = false;
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

  /// extension part 文件里的成员不是 State 子类成员，不能直接调用受保护的
  /// [setState]，统一经由这个转发方法。
  void _setState(VoidCallback fn) => setState(fn);

  final _readingActionsKey = GlobalKey();
  double _readingActionsHeight = 0;

  final _bookmarkStore = BookmarkStore();

  /// 这部漫画是否已出现在书签页（只有分组也算）。
  bool _bookmarkGrouped = false;

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
    _bookmarkStore.addListener(_handleBookmarkChanged);
    _detailScrollController.addListener(_updateBackToTopVisibility);
    unawaited(_loadBookmarkGroup());
    unawaited(_initializePage());
  }

  @override
  void dispose() {
    _bookmarkStore.removeListener(_handleBookmarkChanged);
    _downloads.removeListener(_handleDownloadChanged);
    _locateHighlightTimer?.cancel();
    _detailScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadBookmarkGroup() async {
    await _bookmarkStore.ensureLoaded();
    _handleBookmarkChanged();
  }

  void _handleBookmarkChanged() {
    if (!mounted) return;
    setState(() => _bookmarkGrouped = _bookmarkStore.hasGroup(widget.pathWord));
  }

  /// 右上角书签按钮：把这部漫画加进书签页。只登记分组、不写具体书签，
  /// 所以在书签页里表现为「只有组头、没有条目」。
  ///
  /// 取消书签等于删掉整个书签组，组内还有书签时先弹窗确认。
  Future<void> _toggleBookmarkGroup() async {
    final l10n = AppLocalizations.of(context)!;
    if (_bookmarkStore.hasGroup(widget.pathWord)) {
      final count = _bookmarkStore.bookmarks
          .where((bookmark) => bookmark.pathWord == widget.pathWord)
          .length;
      if (count > 0) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.bookmarkRemove),
            content: Text(l10n.bookmarkRemoveGroupContent(count)),
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
        if (confirmed != true || !mounted) return;
      }
      await _bookmarkStore.removeGroup(widget.pathWord);
      if (!mounted) return;
      showToast(context, l10n.bookmarkRemoved);
      return;
    }
    await _bookmarkStore.addGroup(
      pathWord: widget.pathWord,
      comicName: _comic?.name ?? '',
      cover: _comic?.cover ?? '',
    );
    if (!mounted) return;
    showToast(context, l10n.bookmarkAdded);
  }

  Future<void> _initializePage() async {
    final locateOnEntry = _readerSettings.autoLocateLastReadChapter;
    unawaited(_initializeDownloads());
    await _loadFromCache();
    await _loadLocalHistory();
    await _loadComic(locateAfterLoad: locateOnEntry);
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

  Future<void> _loadLocalHistory({
    String? group,
    bool locateAfterLoad = false,
  }) async {
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
    });
    if (locateAfterLoad) _scheduleLastReadLocation();
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
      _chapterListGroup = canReuseCachedChapters ? cachedGroup : null;
      _chapterTotal = canReuseCachedChapters ? cached.chapterTotal : 0;
      _chapterPage = canReuseCachedChapters ? cached.chapterPage : 0;
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

  Future<void> _loadComic({bool locateAfterLoad = false}) async {
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
      // 详情走 6h TTL 门控：命中缓存时这里不会发网络请求，但章节页与
      // 收藏态在下方照常拉新。
      final data = await _repo.load();
      if (!mounted) return;
      if (_comicError != null) setState(() => _comicError = null);
      final comic = data.comic;
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
      await _loadChapterPageForHistory(
        comic: comic,
        group: selectedGroup,
        locateAfterLoad: locateAfterLoad,
      );
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
          // 加载中途失败时 _loadCollectState 可能压根没跑到，别把按钮锁死。
          _collectStateLoading = false;
          _comicError = NetworkError.message(e);
        });
      }
    }
  }

  Future<void> _loadCollectState() async {
    if (mounted) setState(() => _collectStateLoading = true);
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
    } finally {
      // 失败也要放开：按钮不能被永久禁用。
      if (mounted) setState(() => _collectStateLoading = false);
    }
  }

  Future<void> _loadChapterPage(
    int page, {
    String? group,
    bool keepVisibleDuringLoad = false,
    bool forceRefresh = false,
    bool locateAfterLoad = false,
  }) async {
    if (!mounted || _loadingChapters) return;
    final targetGroup = group ?? _selectedGroup;
    final cacheKey = '$targetGroup:$page';
    final pageChanged =
        _chapterListGroup != targetGroup || _chapterPage != page;
    final previousOffset = pageChanged && _detailScrollController.hasClients
        ? _detailScrollController.offset
        : null;

    // 命中会话内缓存：直接复用，避免重复请求
    if (!forceRefresh) {
      final cached = _chapterPageCache[cacheKey];
      if (cached != null) {
        setState(() {
          _chapters = cached.list;
          _chapterListGroup = targetGroup;
          _chapterTotal = cached.total;
          _chapterPage = page;
          _selectedGroup = targetGroup;
          _loadingChapters = false;
          _keepShowingCachedChapters = false;
          _selectionMode = false;
          _selectedChapterIds.clear();
        });
        if (locateAfterLoad) {
          _scheduleLastReadLocation();
        } else {
          _returnToChapterListStart(previousOffset);
        }
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
        _chapterListGroup = targetGroup;
        _chapterTotal = result.total;
        _chapterPage = page;
        _selectedGroup = targetGroup;
        _loadingChapters = false;
        _keepShowingCachedChapters = false;
      });
      if (locateAfterLoad) {
        _scheduleLastReadLocation();
      } else {
        _returnToChapterListStart(previousOffset);
      }
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
        final locateCachedPage = locateAfterLoad && _loadingChapters;
        setState(() {
          _loadingChapters = false;
          _keepShowingCachedChapters = false;
        });
        if (locateCachedPage) _scheduleLastReadLocation();
      }
    }
  }

  int get _totalPages => (_chapterTotal / _pageSize).ceil();

  /// 优先使用阅读记录中的章节列表页；旧记录再按章节名估算分页。
  Future<void> _loadChapterPageForHistory({
    Comic? comic,
    String? group,
    bool locateAfterLoad = false,
  }) async {
    final targetGroup = group ?? _selectedGroup;
    final total =
        comic?.groups?[targetGroup]?.count ??
        _comic?.groups?[targetGroup]?.count ??
        0;
    final page = _resolveHistoryChapterPage(total);
    await _loadChapterPage(
      page,
      group: targetGroup,
      locateAfterLoad: locateAfterLoad,
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

  List<Chapter> get _displayChapters =>
      _reversed ? _chapters.reversed.toList() : _chapters;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    _syncReadingActionsAfterLayout();

    return Scaffold(
      appBar: AppBar(
        title: Text(_comic?.name ?? ''),
        actions: [
          if (_comic != null &&
              _downloads.downloadedChapterIds(widget.pathWord).isNotEmpty)
            IconButton(
              key: const ValueKey('comic_downloads_action'),
              icon: const Icon(Icons.download_for_offline),
              tooltip: AppLocalizations.of(context)!.downloadCenterTitle,
              onPressed: () => context
                  .pushNamed(AppRoutes.downloadCenter)
                  .then((_) => _handleDownloadChanged()),
            ),
          IconButton(
            key: const ValueKey('comic_detail_bookmark'),
            icon: Icon(
              _bookmarkGrouped
                  ? Icons.bookmark_added
                  : Icons.bookmark_add_outlined,
            ),
            tooltip: _bookmarkGrouped
                ? AppLocalizations.of(context)!.bookmarkRemove
                : AppLocalizations.of(context)!.bookmarkAdd,
            onPressed: _toggleBookmarkGroup,
          ),
          Builder(
            builder: (buttonContext) => IconButton(
              icon: const Icon(Icons.share),
              tooltip: AppLocalizations.of(context)!.comicDetailShare,
              onPressed: () => _shareComic(buttonContext),
            ),
          ),
        ],
      ),
      body: _loadingComic
          ? const Center(child: ExpressiveLoadingIndicator())
          : _comic == null
          ? ErrorRetryView(
              icon: Icons.error_outline,
              message: _comicError,
              onRetry: _loadComic,
            )
          : Stack(
              children: [
                _buildBody(cs, tt),
                if (_canShowLastBrowseAction || _showBackToTop)
                  _buildReadingActions(),
              ],
            ),
    );
  }
}
