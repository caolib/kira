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
import '../widgets/comic_info_chips.dart';
import '../widgets/download_settings_sheet.dart';
import 'comic_comments_sheet.dart';

part 'comic_detail/comic_detail_actions.dart';
part 'comic_detail/comic_detail_build.dart';
part 'comic_detail/comic_detail_chapter_card.dart';
part 'comic_detail/comic_detail_last_browse.dart';
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

  /// extension part 文件里的成员不是 State 子类成员，不能直接调用受保护的
  /// [setState]，统一经由这个转发方法。
  void _setState(VoidCallback fn) => setState(fn);

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
                if (_canShowLastBrowseAction ||
                    _downloads.downloadedChapterIds(widget.pathWord).isNotEmpty)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_downloads
                            .downloadedChapterIds(widget.pathWord)
                            .isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: FloatingActionButton(
                              heroTag: 'comic_download_center',
                              tooltip: AppLocalizations.of(
                                context,
                              )!.downloadCenterTitle,
                              onPressed: () => context
                                  .pushNamed(AppRoutes.downloadCenter)
                                  .then((_) => _handleDownloadChanged()),
                              child: const Icon(
                                Icons.download_for_offline,
                                size: 24,
                              ),
                            ),
                          ),
                        if (_nextBrowseChapter != null ||
                            _canShowLastBrowseAction)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_nextBrowseChapter != null)
                                FloatingActionButton.extended(
                                  heroTag: 'next_chapter',
                                  onPressed: () => context
                                      .pushNamed(
                                        AppRoutes.reader,
                                        pathParameters: {
                                          'pathWord': widget.pathWord,
                                          'chapterUuid':
                                              _nextBrowseChapter!.uuid,
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
                              if (_nextBrowseChapter != null &&
                                  _canShowLastBrowseAction)
                                const SizedBox(width: 12),
                              if (_canShowLastBrowseAction)
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
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
