import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
import '../api/dandanplay_api.dart';
import '../l10n/app_localizations.dart';
import '../models/anime.dart';
import '../routing/app_router.dart';
import '../utils/anime_download_manager.dart';
import '../utils/anime_playback_history.dart';
import '../utils/chinese_converter.dart';
import '../utils/cover_brightness_filter.dart';
import '../utils/dandanplay_binding_store.dart';
import '../utils/dandanplay_episode_binding.dart';
import '../utils/data_cache.dart';
import '../utils/toast.dart';
import '../widgets/comic_cover_card.dart' show ComicCoverCard;
import 'bangumi_comments_section.dart';

part 'anime_detail/anime_detail_models.dart';
part 'anime_detail/anime_detail_widgets.dart';
part 'anime_detail/anime_episode_widgets.dart';
part 'anime_detail/dandanplay_alignment_dialog.dart';
part 'anime_detail/dandanplay_binding_dialog.dart';

class AnimeDetailPage extends StatefulWidget {
  final String pathWord;
  final Anime? initialAnime;

  const AnimeDetailPage({super.key, required this.pathWord, this.initialAnime});

  @override
  State<AnimeDetailPage> createState() => _AnimeDetailPageState();
}

class _AnimeDetailPageState extends State<AnimeDetailPage>
    with TickerProviderStateMixin {
  static const _watchedCompleteRemainingThreshold = Duration(minutes: 3);
  static const _detailCacheTtl = Duration(days: 3);
  static const _commentsScrollToTopThreshold = 480.0;
  static const _tabIntro = 0;
  static const _tabEpisodes = 1;
  static const _tabComments = 2;

  final _api = ApiClient();
  final _cache = DataCache();
  final _downloads = AnimeDownloadManager();
  final _dandanplayBindingStore = DandanplayBindingStore();
  final _bangumiCommentsKey = GlobalKey<BangumiCommentsSectionState>();
  final _scrollController = ScrollController();
  TabController? _tabController;
  Anime? _anime;
  List<AnimeChapter> _chapters = [];
  int _chapterTotal = 0;
  int _currentTab = _tabEpisodes;
  bool _loadingDetail = false;
  bool _detailReady = false;
  bool _loadingChapters = true;
  bool _briefExpanded = false;
  bool _isCollected = false;
  bool _collectSubmitting = false;
  DateTime? _refreshedAt;
  AnimePlaybackRecord? _latestPlaybackRecord;
  DandanplayBindingRecord? _dandanplayBinding;
  DandanplayBangumi? _dandanplayBangumi;
  bool _loadingDandanplayBangumi = false;
  Map<String, int?> _danmakuEpisodeBindings = {};
  int _dandanplayBangumiSerial = 0;
  String? _detailError;
  String? _chapterError;

  // 批量下载选择
  final Set<String> _selectedUuids = {};
  bool _selectionMode = false;
  bool _showCommentsScrollToTop = false;
  StreamSubscription<String>? _errorSub;

  String get _detailCacheKey => 'anime_detail_info_v2_${widget.pathWord}';
  bool get _showCommentsTab =>
      _dandanplayBinding?.bangumiId.trim().isNotEmpty == true;
  List<int> get _tabKinds => _showCommentsTab
      ? const [_tabIntro, _tabEpisodes, _tabComments]
      : const [_tabIntro, _tabEpisodes];
  bool get _isIntroTab => _currentTab == _tabIntro;
  bool get _isCommentsTab => _currentTab == _tabComments;
  bool get _isEpisodeTab => _currentTab == _tabEpisodes;
  bool get _useDandanplayIntro => _dandanplayBangumi != null;
  _AnimeIntroViewData? get _introViewData => _useDandanplayIntro
      ? _AnimeIntroViewData.fromDandanplay(
          _dandanplayBangumi!,
          l10n: AppLocalizations.of(context)!,
          fallbackAnime: _anime ?? widget.initialAnime,
        )
      : (_anime == null
            ? null
            : _AnimeIntroViewData.fromAnime(
                _anime!,
                AppLocalizations.of(context)!,
              ));

  @override
  void initState() {
    super.initState();
    _syncTabController();
    _anime = widget.initialAnime;
    _scrollController.addListener(_onScrollChanged);
    _downloads.addListener(_onDownloadsChanged);
    _errorSub = _downloads.onError.listen((msg) {
      if (mounted) showToast(context, msg, isError: true);
    });
    unawaited(_initializeDetailSources());
    unawaited(_loadChapters());
  }

  Future<void> _initializeDetailSources() async {
    await _loadDandanplayBinding();
    // 始终加载详情以获取 uuid，确保收藏功能可用
    await _loadDetail();
  }

  void _syncTabController() {
    final tabs = _tabKinds;
    final nextTab = tabs.contains(_currentTab) ? _currentTab : _tabEpisodes;
    final nextIndex = tabs.indexOf(nextTab);
    final previousController = _tabController;
    _tabController = TabController(
      length: tabs.length,
      vsync: this,
      initialIndex: nextIndex,
    )..addListener(_onTabChanged);
    _currentTab = nextTab;
    if (previousController != null) {
      previousController.removeListener(_onTabChanged);
      previousController.dispose();
    }
  }

  @override
  void dispose() {
    _tabController?.removeListener(_onTabChanged);
    _tabController?.dispose();
    _scrollController.removeListener(_onScrollChanged);
    _scrollController.dispose();
    _errorSub?.cancel();
    _downloads.removeListener(_onDownloadsChanged);
    super.dispose();
  }

  void _onDownloadsChanged() {
    if (mounted) setState(() {});
  }

  void _onScrollChanged() {
    _updateCommentsScrollToTopVisibility();
  }

  void _updateCommentsScrollToTopVisibility() {
    final shouldShow =
        _isCommentsTab &&
        _scrollController.hasClients &&
        _scrollController.offset >= _commentsScrollToTopThreshold;
    if (shouldShow == _showCommentsScrollToTop) return;
    if (!mounted) return;
    setState(() => _showCommentsScrollToTop = shouldShow);
  }

  void _onTabChanged() {
    final controller = _tabController;
    if (controller == null) return;
    final tabs = _tabKinds;
    if (controller.index >= tabs.length) return;
    final nextTab = tabs[controller.index];
    if (_currentTab == nextTab) return;
    _currentTab = nextTab;
    if (_currentTab == _tabIntro) {
      unawaited(_ensureDetailLoaded());
    }
    if (_currentTab != _tabEpisodes && _selectionMode) {
      _exitSelectionMode();
      return;
    }
    _updateCommentsScrollToTopVisibility();
    if (mounted) setState(() {});
  }

  Future<void> _saveDetailCache() async {
    final anime = _anime;
    if (anime == null) return;
    await _cache.put(_detailCacheKey, {
      'anime': anime.toJson(),
      'isCollected': _isCollected,
      if (_refreshedAt != null) 'refreshedAt': _refreshedAt!.toIso8601String(),
    }, ttl: _detailCacheTtl);
  }

  Future<void> _ensureDetailLoaded() async {
    if (_useDandanplayIntro || _detailReady || _loadingDetail) return;
    await _loadDetail();
  }

  Future<void> _loadDetail({bool forceRefresh = false}) async {
    if (_loadingDetail) return;
    try {
      if (!forceRefresh) {
        final cached = await _cache.get(_detailCacheKey);
        if (cached is Map) {
          final animeJson = cached['anime'];
          if (animeJson is Map) {
            if (!mounted) return;
            setState(() {
              _anime = Anime.fromJson(Map<String, dynamic>.from(animeJson));
              _isCollected = cached['isCollected'] == true;
              _refreshedAt = DateTime.tryParse(
                cached['refreshedAt']?.toString() ?? '',
              );
              _detailReady = true;
              _detailError = null;
            });
            return;
          }
        }
      }

      setState(() {
        _loadingDetail = true;
        _detailError = null;
      });
      final detail = await _api.anime.getAnimeDetail(widget.pathWord);
      AnimeQuery? query;
      try {
        query = await _api.anime.getAnimeQuery(widget.pathWord);
      } catch (_) {
        query = null;
      }

      if (!mounted) return;
      final refreshedAt = DateTime.now();
      setState(() {
        _anime = detail;
        _isCollected = query?.isCollected ?? _isCollected;
        _refreshedAt = refreshedAt;
        _detailReady = true;
        _loadingDetail = false;
        _detailError = null;
      });
      await _saveDetailCache();
    } catch (e) {
      debugPrint('AnimeDetailPage load detail error: $e');
      if (!mounted) return;
      setState(() {
        _loadingDetail = false;
        _detailError = e.toString();
      });
      if (_detailReady) {
        final l10n = AppLocalizations.of(context)!;
        showToast(context, l10n.animeDetailIntroRefreshFailed, isError: true);
      }
    }
  }

  Future<void> _loadChapters() async {
    setState(() {
      _loadingChapters = true;
      _chapterError = null;
    });
    try {
      final chapters = await _api.anime.getAnimeChapters(widget.pathWord);
      if (!mounted) return;
      setState(() {
        _chapters = chapters.list;
        _chapterTotal = chapters.total;
        _loadingChapters = false;
        _chapterError = null;
      });
      unawaited(_loadLatestPlaybackRecord());
      _syncDandanplayBindingsAfterChaptersLoaded();
    } catch (e) {
      debugPrint('AnimeDetailPage load chapters error: $e');
      if (!mounted) return;
      setState(() {
        _loadingChapters = false;
        _chapterError = e.toString();
      });
      if (_chapters.isNotEmpty) {
        final l10n = AppLocalizations.of(context)!;
        showToast(context, l10n.animeDetailEpisodeRefreshFailed, isError: true);
      }
    }
  }

  Future<void> _refreshCurrentTab() async {
    _exitSelectionMode();
    if (_isIntroTab) {
      if (_useDandanplayIntro) {
        final binding = _dandanplayBinding;
        if (binding != null) {
          await DandanplayApi().clearBangumiCache(binding.animeId);
          await _loadDandanplayBangumi(binding, applySequentialIfEmpty: true);
        }
        return;
      }
      await _loadDetail(forceRefresh: true);
      return;
    }
    if (_isCommentsTab) {
      await (_bangumiCommentsKey.currentState?.reload() ??
          Future<void>.value());
      return;
    }
    await _clearEpisodeRefreshCaches();
    await _loadChapters();
  }

  Future<void> _clearEpisodeRefreshCaches() async {
    final binding = _dandanplayBinding;
    await _api.anime.clearAnimePlaybackCache(widget.pathWord);
    if (binding != null) {
      await DandanplayApi().clearBangumiCache(binding.animeId);
    }
    if (!mounted) return;
    setState(() {
      _dandanplayBangumi = null;
    });
  }

  String? get _refreshedAtText {
    final refreshedAt = _refreshedAt;
    if (refreshedAt == null) return null;
    return _formatRefreshTime(refreshedAt);
  }

  String _formatRefreshTime(DateTime time) {
    final local = time.toLocal();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }

  Future<void> _loadLatestPlaybackRecord() async {
    final records = await AnimePlaybackHistory.progressRecordsForAnime(
      pathWord: widget.pathWord,
    );
    if (!mounted) return;
    final record = _selectLatestChapterPlaybackRecord(records);
    setState(() => _latestPlaybackRecord = record);
  }

  AnimePlaybackRecord? _selectLatestChapterPlaybackRecord(
    List<AnimePlaybackRecord> records,
  ) {
    if (records.isEmpty) return null;
    final byChapterUuid = {
      for (final record in records) record.chapterUuid: record,
    };
    for (var i = _chapters.length - 1; i >= 0; i--) {
      final record = byChapterUuid[_chapters[i].uuid];
      if (record != null) return record;
    }
    records.sort((a, b) {
      final aTime = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
    return records.first;
  }

  Future<void> _loadDandanplayBinding() async {
    final binding = await _dandanplayBindingStore.getByPathWord(
      widget.pathWord,
    );
    if (!mounted) return;
    setState(() {
      _dandanplayBinding = binding;
      _syncTabController();
    });
    if (binding != null) {
      unawaited(_loadDandanplayBangumi(binding, applySequentialIfEmpty: true));
    }
  }

  String get _currentAnimeTitle {
    final title = _anime?.name ?? widget.initialAnime?.name ?? widget.pathWord;
    return title.trim().isEmpty ? widget.pathWord : title.trim();
  }

  Future<String> _simplifiedDandanplayKeyword(String text) async {
    try {
      return await ChineseConverter.convertToSimplifiedChinese(text);
    } catch (_) {
      return text;
    }
  }

  Future<void> _showDandanplayBindingDialog() async {
    final animeTitle = _currentAnimeTitle;
    final initialKeyword = await _simplifiedDandanplayKeyword(animeTitle);
    if (!mounted) return;

    final result = await showDialog<_DandanplayBindingDialogResult>(
      context: context,
      builder: (_) => _DandanplayBindingDialog(
        initialKeyword: initialKeyword,
        currentBinding: _dandanplayBinding,
        pathWord: widget.pathWord,
        localTitle: animeTitle,
        localUuid: _anime?.uuid ?? widget.initialAnime?.uuid,
      ),
    );
    if (!mounted || result == null) return;

    if (result.clear) {
      await _dandanplayBindingStore.removeByPathWord(widget.pathWord);
      await _clearDandanplayChapterBindings();
      if (!mounted) return;
      setState(() {
        _dandanplayBinding = null;
        _dandanplayBangumi = null;
        _danmakuEpisodeBindings = {};
        _syncTabController();
      });
      final l10n = AppLocalizations.of(context)!;
      showToast(context, l10n.animeDetailDandanplayBindingCleared);
      return;
    }

    final record = result.record;
    if (record == null) return;
    await _dandanplayBindingStore.save(record);
    if (!mounted) return;
    final l10n2 = AppLocalizations.of(context)!;
    setState(() {
      _dandanplayBinding = record;
      _dandanplayBangumi = null;
      _danmakuEpisodeBindings = {};
      _syncTabController();
    });
    await _loadDandanplayBangumi(record, applySequential: true);
    if (!mounted) return;
    showToast(context, l10n2.animeDetailDandanplayBound(record.animeTitle));
  }

  void _syncDandanplayBindingsAfterChaptersLoaded() {
    final binding = _dandanplayBinding;
    if (binding == null || _chapters.isEmpty) return;
    unawaited(_loadDandanplayBangumi(binding, applySequentialIfEmpty: true));
  }

  Future<void> _loadDandanplayBangumi(
    DandanplayBindingRecord binding, {
    bool applySequential = false,
    bool applySequentialIfEmpty = false,
  }) async {
    final serial = ++_dandanplayBangumiSerial;
    setState(() {
      _loadingDandanplayBangumi = true;
    });

    final bangumi = await DandanplayApi().getBangumi(binding.animeId);
    if (!mounted ||
        serial != _dandanplayBangumiSerial ||
        _dandanplayBinding?.animeId != binding.animeId) {
      return;
    }

    if (bangumi == null) {
      setState(() {
        _dandanplayBangumi = null;
        _loadingDandanplayBangumi = false;
      });
      return;
    }

    setState(() {
      _dandanplayBangumi = bangumi;
      _loadingDandanplayBangumi = false;
    });

    if (_chapters.isEmpty) return;
    if (binding.hasAlignment &&
        await _applyStoredDandanplayAlignment(binding, bangumi.episodes)) {
      return;
    }
    if (applySequential) {
      await _applySequentialDandanplayBindings(bangumi.episodes);
      return;
    }
    await _loadDandanplayEpisodeBindings(
      bangumi,
      binding: binding,
      applySequentialIfEmpty: applySequentialIfEmpty,
    );
  }

  Future<void> _loadDandanplayEpisodeBindings(
    DandanplayBangumi bangumi, {
    required DandanplayBindingRecord binding,
    bool applySequentialIfEmpty = false,
  }) async {
    if (binding.hasAlignment &&
        await _applyStoredDandanplayAlignment(binding, bangumi.episodes)) {
      return;
    }
    final bindings = await _readDandanplayEpisodeBindings();
    if (!mounted) return;
    if (applySequentialIfEmpty &&
        bangumi.episodes.isNotEmpty &&
        await _applySequentialDandanplayBindingGaps(
          bangumi.episodes,
          bindings,
        )) {
      return;
    }
    setState(() => _danmakuEpisodeBindings = bindings);
  }

  Future<bool> _applyStoredDandanplayAlignment(
    DandanplayBindingRecord binding,
    List<DandanplayBangumiEpisode> episodes,
  ) async {
    final chapterUuid = binding.alignmentChapterUuid;
    final episodeId = binding.alignmentEpisodeId;
    if (chapterUuid == null || episodeId == null) return false;

    final chapterStartIndex = _chapters.indexWhere(
      (chapter) => chapter.uuid == chapterUuid,
    );
    final validEpisodes = _uniqueDandanplayEpisodes(episodes);
    final episodeStartIndex = validEpisodes.indexWhere(
      (episode) => episode.episodeId == episodeId,
    );
    if (chapterStartIndex < 0 || episodeStartIndex < 0) return false;

    await _applyAlignedDandanplayBindings(
      validEpisodes,
      chapterStartIndex: chapterStartIndex,
      episodeStartIndex: episodeStartIndex,
    );
    return true;
  }

  Future<Map<String, int?>> _readDandanplayEpisodeBindings() async {
    final entries = await Future.wait(
      _chapters.map((chapter) async {
        final record = await AnimePlaybackHistory.get(
          pathWord: widget.pathWord,
          chapterUuid: chapter.uuid,
        );
        return MapEntry(chapter.uuid, record?.danmakuEpisodeId);
      }),
    );
    return Map<String, int?>.fromEntries(entries);
  }

  Future<void> _applySequentialDandanplayBindings(
    List<DandanplayBangumiEpisode> episodes,
  ) async {
    final validEpisodes = _uniqueDandanplayEpisodes(episodes);
    final nextBindings = <String, int?>{};

    await Future.wait(
      _chapters.indexed.map((entry) async {
        final index = entry.$1;
        final chapter = entry.$2;
        final episode = index < validEpisodes.length
            ? validEpisodes[index]
            : null;
        nextBindings[chapter.uuid] = episode?.episodeId;
        if (episode == null) {
          await AnimePlaybackHistory.clearDanmakuEpisode(
            pathWord: widget.pathWord,
            chapterUuid: chapter.uuid,
            chapterName: chapter.name,
          );
          return;
        }
        await AnimePlaybackHistory.saveDanmakuEpisode(
          pathWord: widget.pathWord,
          chapterUuid: chapter.uuid,
          chapterName: chapter.name,
          episodeId: episode.episodeId,
        );
      }),
    );

    if (!mounted) return;
    setState(() => _danmakuEpisodeBindings = nextBindings);
  }

  Future<bool> _applySequentialDandanplayBindingGaps(
    List<DandanplayBangumiEpisode> episodes,
    Map<String, int?> currentBindings,
  ) async {
    final validEpisodes = _uniqueDandanplayEpisodes(episodes);
    final nextEpisodeIds = inferSequentialDandanplayEpisodeBindings(
      currentEpisodeIds: [
        for (final chapter in _chapters) currentBindings[chapter.uuid],
      ],
      availableEpisodeIds: [
        for (final episode in validEpisodes) episode.episodeId,
      ],
    );
    final nextBindings = <String, int?>{};
    var changed = false;

    for (final entry in _chapters.indexed) {
      final index = entry.$1;
      final chapter = entry.$2;
      final currentEpisodeId = currentBindings[chapter.uuid];
      final nextEpisodeId = nextEpisodeIds[index];
      nextBindings[chapter.uuid] = nextEpisodeId;
      if (nextEpisodeId == currentEpisodeId) continue;

      changed = true;
      if (nextEpisodeId == null) {
        await AnimePlaybackHistory.clearDanmakuEpisode(
          pathWord: widget.pathWord,
          chapterUuid: chapter.uuid,
          chapterName: chapter.name,
        );
        continue;
      }
      await AnimePlaybackHistory.saveDanmakuEpisode(
        pathWord: widget.pathWord,
        chapterUuid: chapter.uuid,
        chapterName: chapter.name,
        episodeId: nextEpisodeId,
      );
    }

    if (!changed) return false;
    if (!mounted) return true;
    setState(() => _danmakuEpisodeBindings = nextBindings);
    return true;
  }

  Future<void> _showDandanplayAlignmentDialog(
    List<DandanplayBangumiEpisode> episodes,
  ) async {
    final binding = _dandanplayBinding;
    if (binding == null) return;
    final validEpisodes = _uniqueDandanplayEpisodes(episodes);
    if (_chapters.isEmpty || validEpisodes.isEmpty) return;
    final result = await showDialog<_DandanplayAlignmentResult>(
      context: context,
      builder: (_) => _DandanplayAlignmentDialog(
        chapters: _chapters,
        episodes: validEpisodes,
        initialChapterIndex: _defaultAlignmentChapterIndex(binding),
        initialEpisodeIndex: _defaultAlignmentEpisodeIndex(
          validEpisodes,
          binding,
        ),
        hasExistingAlignment: binding.hasAlignment,
      ),
    );
    if (!mounted || result == null) return;

    if (result.clear) {
      final updatedBinding = binding.withoutAlignment();
      await _dandanplayBindingStore.save(updatedBinding);
      if (!mounted) return;
      setState(() => _dandanplayBinding = updatedBinding);
      await _applySequentialDandanplayBindings(validEpisodes);
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        showToast(context, l10n.animeDetailAlignmentCleared);
      }
      return;
    }

    final chapterIndex = result.chapterIndex;
    final episodeIndex = result.episodeIndex;
    if (chapterIndex == null || episodeIndex == null) return;
    final updatedBinding = binding.withAlignment(
      chapterUuid: _chapters[chapterIndex].uuid,
      episodeId: validEpisodes[episodeIndex].episodeId,
    );
    await _dandanplayBindingStore.save(updatedBinding);
    if (!mounted) return;
    setState(() => _dandanplayBinding = updatedBinding);
    await _applyAlignedDandanplayBindings(
      validEpisodes,
      chapterStartIndex: chapterIndex,
      episodeStartIndex: episodeIndex,
    );
    if (mounted) {
      final l10n = AppLocalizations.of(context)!;
      showToast(context, l10n.animeDetailRealigned);
    }
  }

  int _defaultAlignmentChapterIndex(DandanplayBindingRecord binding) {
    final chapterUuid = binding.alignmentChapterUuid;
    if (chapterUuid != null) {
      final savedIndex = _chapters.indexWhere(
        (chapter) => chapter.uuid == chapterUuid,
      );
      if (savedIndex >= 0) return savedIndex;
    }
    final index = _chapters.indexWhere(
      (chapter) => RegExp(r'第\s*0*1\s*[集话話]').hasMatch(chapter.name),
    );
    return index < 0 ? 0 : index;
  }

  int _defaultAlignmentEpisodeIndex(
    List<DandanplayBangumiEpisode> episodes,
    DandanplayBindingRecord binding,
  ) {
    final episodeId = binding.alignmentEpisodeId;
    if (episodeId != null) {
      final savedIndex = episodes.indexWhere(
        (episode) => episode.episodeId == episodeId,
      );
      if (savedIndex >= 0) return savedIndex;
    }
    final index = episodes.indexWhere(
      (episode) => RegExp(
        r'第\s*0*1\s*[集话話]',
      ).hasMatch(_formatDandanplayEpisodeLabel(episode)),
    );
    return index < 0 ? 0 : index;
  }

  Future<void> _applyAlignedDandanplayBindings(
    List<DandanplayBangumiEpisode> episodes, {
    required int chapterStartIndex,
    required int episodeStartIndex,
  }) async {
    final nextBindings = <String, int?>{};

    await Future.wait(
      _chapters.indexed.map((entry) async {
        final chapterIndex = entry.$1;
        final chapter = entry.$2;
        final episodeIndex =
            episodeStartIndex + chapterIndex - chapterStartIndex;
        final episode =
            chapterIndex >= chapterStartIndex &&
                episodeIndex >= 0 &&
                episodeIndex < episodes.length
            ? episodes[episodeIndex]
            : null;
        nextBindings[chapter.uuid] = episode?.episodeId;
        if (episode == null) {
          await AnimePlaybackHistory.clearDanmakuEpisode(
            pathWord: widget.pathWord,
            chapterUuid: chapter.uuid,
            chapterName: chapter.name,
          );
          return;
        }
        await AnimePlaybackHistory.saveDanmakuEpisode(
          pathWord: widget.pathWord,
          chapterUuid: chapter.uuid,
          chapterName: chapter.name,
          episodeId: episode.episodeId,
        );
      }),
    );

    if (!mounted) return;
    setState(() => _danmakuEpisodeBindings = nextBindings);
  }

  Future<void> _clearDandanplayChapterBindings() async {
    await Future.wait(
      _chapters.map(
        (chapter) => AnimePlaybackHistory.clearDanmakuEpisode(
          pathWord: widget.pathWord,
          chapterUuid: chapter.uuid,
          chapterName: chapter.name,
        ),
      ),
    );
  }

  Future<void> _updateDandanplayEpisodeBinding(
    AnimeChapter chapter,
    int? episodeId,
  ) async {
    setState(() {
      _danmakuEpisodeBindings = {
        ..._danmakuEpisodeBindings,
        chapter.uuid: episodeId,
      };
    });
    if (episodeId == null) {
      await AnimePlaybackHistory.clearDanmakuEpisode(
        pathWord: widget.pathWord,
        chapterUuid: chapter.uuid,
        chapterName: chapter.name,
      );
      return;
    }
    await AnimePlaybackHistory.saveDanmakuEpisode(
      pathWord: widget.pathWord,
      chapterUuid: chapter.uuid,
      chapterName: chapter.name,
      episodeId: episodeId,
    );
  }

  List<DandanplayBangumiEpisode> _uniqueDandanplayEpisodes(
    List<DandanplayBangumiEpisode> episodes,
  ) {
    final seen = <int>{};
    return episodes
        .where(
          (episode) => episode.episodeId > 0 && seen.add(episode.episodeId),
        )
        .toList();
  }

  DandanplayBangumiEpisode? _findDandanplayEpisode(
    List<DandanplayBangumiEpisode> episodes,
    int? episodeId,
  ) {
    if (episodeId == null) return null;
    for (final episode in episodes) {
      if (episode.episodeId == episodeId) return episode;
    }
    return null;
  }

  AnimeChapter? get _latestPlaybackChapter {
    final record = _latestPlaybackRecord;
    if (record == null) return null;
    for (final chapter in _chapters) {
      if (chapter.uuid == record.chapterUuid) return chapter;
    }
    return null;
  }

  Future<void> _openChapter(AnimeChapter chapter) async {
    final line = _resolveChapterLine(chapter);
    if (line == null || line.isEmpty) {
      final l10n = AppLocalizations.of(context)!;
      showToast(context, l10n.animeDetailNoAvailableLine, isError: true);
      return;
    }

    await context.pushNamed(
      AppRoutes.animePlayer,
      pathParameters: {
        'pathWord': widget.pathWord,
        'chapterUuid': chapter.uuid,
      },
      extra: AnimePlayerExtra(
        animeName: widget.initialAnime?.name ?? _anime?.name ?? widget.pathWord,
        chapterName: chapter.name,
        line: line,
        chapters: _chapters,
      ),
    );
    if (!mounted) return;
    await _loadLatestPlaybackRecord();
  }

  Future<void> _continueWatching() async {
    final chapter = _latestPlaybackChapter;
    if (chapter == null) {
      final l10n = AppLocalizations.of(context)!;
      showToast(
        context,
        l10n.animeDetailPlaybackEpisodeUnavailable,
        isError: true,
      );
      return;
    }
    await _openChapter(chapter);
  }

  Future<void> _openNextPlaybackChapter() async {
    final chapter = _nextChapterAfterLatestPlayback;
    if (chapter == null) return;
    await _openChapter(chapter);
  }

  AnimeChapter? get _nextChapterAfterLatestPlayback {
    final chapter = _latestPlaybackChapter;
    if (chapter == null) return null;
    final index = _chapters.indexWhere((item) => item.uuid == chapter.uuid);
    if (index < 0 || index + 1 >= _chapters.length) return null;
    return _chapters[index + 1];
  }

  bool _isPlaybackRecordNearEnd(AnimePlaybackRecord record) {
    final duration = record.duration;
    if (duration <= Duration.zero) return false;
    return duration - record.position < _watchedCompleteRemainingThreshold;
  }

  String? _resolveChapterLine(AnimeChapter chapter) {
    for (final line in chapter.lines) {
      if (line.config && line.pathWord.isNotEmpty) return line.pathWord;
    }
    for (final line in chapter.lines) {
      if (line.pathWord.isNotEmpty) return line.pathWord;
    }
    return null;
  }

  void _toggleSelection(String uuid) {
    setState(() {
      if (_selectedUuids.contains(uuid)) {
        _selectedUuids.remove(uuid);
        if (_selectedUuids.isEmpty) _selectionMode = false;
      } else {
        _selectedUuids.add(uuid);
      }
    });
  }

  void _enterSelectionMode(String uuid) {
    setState(() {
      _selectionMode = true;
      _selectedUuids.add(uuid);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedUuids.clear();
    });
  }

  void _selectAll() {
    setState(() {
      _selectedUuids.addAll(
        _chapters
            .where(
              (c) =>
                  !_downloads.isDownloaded(widget.pathWord, c.uuid) &&
                  !_downloads.isInQueue(widget.pathWord, c.uuid),
            )
            .map((c) => c.uuid),
      );
    });
  }

  Future<Anime?> _ensureAnimeForDownload() async {
    final anime = _anime;
    if (anime != null) return anime;
    await _loadDetail(forceRefresh: true);
    return _anime;
  }

  Future<void> _batchDownload() async {
    if (_selectedUuids.isEmpty) return;
    final anime = await _ensureAnimeForDownload();
    if (anime == null) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        showToast(
          context,
          l10n.animeDetailInfoLoadFailedForDownload,
          isError: true,
        );
      }
      return;
    }

    await _downloads.init();
    if (!mounted) return;

    // 用第一个选中章节的线路
    final first = _chapters.firstWhere(
      (c) => _selectedUuids.contains(c.uuid),
      orElse: () => _chapters.first,
    );
    final line = _resolveChapterLine(first);
    if (line == null || line.isEmpty) {
      final l10n = AppLocalizations.of(context)!;
      showToast(context, l10n.animeDetailNoLineForDownload, isError: true);
      return;
    }

    final toDownload = _chapters
        .where((c) => _selectedUuids.contains(c.uuid))
        .toList();

    final added = await _downloads.enqueueChapters(
      pathWord: widget.pathWord,
      anime: anime,
      chapters: toDownload,
      line: line,
    );

    if (mounted) {
      final l10n = AppLocalizations.of(context)!;
      showToast(context, l10n.animeDetailDownloadTasksAdded(added));
    }
    _exitSelectionMode();
  }

  Future<void> _toggleCollect() async {
    final anime = _anime;
    final cartoonId = anime?.uuid;
    if (anime == null || cartoonId == null || cartoonId.isEmpty) {
      final l10n = AppLocalizations.of(context)!;
      showToast(context, l10n.animeDetailCannotCollect, isError: true);
      return;
    }
    if (_collectSubmitting) return;

    final nextState = !_isCollected;
    setState(() {
      _isCollected = nextState;
      _collectSubmitting = true;
    });

    try {
      await _api.anime.toggleAnimeCollect(cartoonId, collect: nextState);
      await _saveDetailCache();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      showToast(
        context,
        nextState
            ? l10n.animeDetailCollected
            : l10n.animeDetailCollectCancelled,
      );
    } catch (e) {
      debugPrint('AnimeDetailPage toggleCollect error: $e');
      if (!mounted) return;
      setState(() => _isCollected = !nextState);
      await _saveDetailCache();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      showToast(context, l10n.animeDetailCollectFailed, isError: true);
    } finally {
      if (mounted) setState(() => _collectSubmitting = false);
    }
  }

  Widget? _buildDownloadFab(ColorScheme cs) {
    final l10n = AppLocalizations.of(context)!;
    final count = _downloads.tasks
        .where((t) => t.pathWord == widget.pathWord)
        .length;
    if (count == 0) return null;
    return FloatingActionButton.extended(
      heroTag: 'anime_download_tasks_${widget.pathWord}',
      onPressed: () => context.pushNamed(
        AppRoutes.downloadCenter,
        queryParameters: {'tab': '2'},
      ),
      icon: const Icon(Icons.downloading_outlined),
      label: Text(l10n.animeDetailDownloadTaskCount(count)),
    );
  }

  Widget? _buildFloatingActions(ColorScheme cs) {
    final rows = <Widget>[];
    final availableWidth = MediaQuery.sizeOf(context).width - 32;
    final maxButtonWidth = availableWidth.clamp(112.0, 320.0).toDouble();
    final maxLabelWidth = (maxButtonWidth - 76).clamp(36.0, 240.0).toDouble();
    final downloadFab = _buildDownloadFab(cs);
    if (downloadFab != null) {
      rows.add(downloadFab);
    }

    final playbackRecord = _latestPlaybackRecord;
    if (playbackRecord != null) {
      final chapterName =
          _latestPlaybackChapter?.name ?? playbackRecord.chapterName;
      final nextChapter = _isPlaybackRecordNearEnd(playbackRecord)
          ? _nextChapterAfterLatestPlayback
          : null;
      rows.add(
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: availableWidth),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.end,
            children: [
              if (nextChapter != null)
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxButtonWidth),
                  child: FloatingActionButton.extended(
                    heroTag: 'anime_next_watching_${widget.pathWord}',
                    onPressed: () => unawaited(_openNextPlaybackChapter()),
                    icon: const Icon(Icons.skip_next_rounded, size: 20),
                    label: _FabLabel(
                      text: _truncateChapterName(
                        nextChapter.name,
                        maxLength: 12,
                      ),
                      maxWidth: maxLabelWidth,
                    ),
                  ),
                ),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxButtonWidth),
                child: FloatingActionButton.extended(
                  heroTag: 'anime_continue_watching_${widget.pathWord}',
                  onPressed: () => unawaited(_continueWatching()),
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: _FabLabel(
                    text: _continueWatchingLabel(chapterName, playbackRecord),
                    maxWidth: maxLabelWidth,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (rows.isEmpty) return null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          rows[i],
        ],
      ],
    );
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Widget? _buildCommentsScrollToTopFab() {
    if (!_showCommentsScrollToTop) return null;
    return FloatingActionButton.small(
      heroTag: 'anime_comments_back_to_top_${widget.pathWord}',
      onPressed: () => unawaited(_scrollToTop()),
      tooltip: AppLocalizations.of(context)!.backToTop,
      child: const Icon(Icons.arrow_upward_rounded),
    );
  }

  String _continueWatchingLabel(
    String chapterName,
    AnimePlaybackRecord record,
  ) {
    final name = _truncateChapterName(chapterName, maxLength: 12);
    final progress = record.duration > Duration.zero
        ? '${_formatDuration(record.position)} / ${_formatDuration(record.duration)}'
        : _formatDuration(record.position);
    return name.isEmpty ? progress : '$name · $progress';
  }

  String _truncateChapterName(String name, {required int maxLength}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';

    final chars = trimmed.characters;
    if (chars.length <= maxLength) return trimmed;
    return '${chars.take(maxLength).toString()}...';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '${duration.inMinutes}:$seconds';
  }

  List<Widget> _buildIntroSlivers(double hp, TextTheme tt, ColorScheme cs) {
    final l10n = AppLocalizations.of(context)!;
    final intro = _introViewData;
    if (intro == null) {
      if (_loadingDetail) {
        return const [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        ];
      }
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(
                _detailError == null
                    ? l10n.animeDetailNoIntroInfo
                    : l10n.animeDetailIntroLoadFailed,
                style: tt.bodyMedium,
              ),
            ),
          ),
        ),
      ];
    }

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(hp, 18, hp, 0),
          child: _AnimeInfoPanel(
            intro: intro,
            isCollected: _isCollected,
            collectSubmitting: _collectSubmitting,
            briefExpanded: _briefExpanded,
            refreshedAtText: _refreshedAtText,
            onToggleCollect: _toggleCollect,
            onToggleBrief: () {
              setState(() => _briefExpanded = !_briefExpanded);
            },
          ),
        ),
      ),
      if (_detailError != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(hp, 12, hp, 0),
            child: Text(
              l10n.animeDetailIntroRefreshFailedCached,
              style: tt.bodySmall?.copyWith(color: cs.error),
            ),
          ),
        ),
    ];
  }

  List<Widget> _buildEpisodeSlivers(double hp, TextTheme tt, ColorScheme cs) {
    final l10n = AppLocalizations.of(context)!;
    final boundEpisodes = _dandanplayBangumi == null
        ? const <DandanplayBangumiEpisode>[]
        : _uniqueDandanplayEpisodes(_dandanplayBangumi!.episodes);

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(hp, 12, hp, 12),
          child: _selectionMode
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        l10n.animeDetailSelectedEpisodes(_selectedUuids.length),
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextButton(
                        onPressed: _selectAll,
                        child: Text(l10n.animeDetailSelectAllUndownloaded),
                      ),
                      FilledButton.tonal(
                        onPressed: _selectedUuids.isEmpty
                            ? null
                            : _batchDownload,
                        child: Text(l10n.animeDetailDownloadSelected),
                      ),
                      IconButton(
                        onPressed: _exitSelectionMode,
                        icon: const Icon(Icons.close),
                        tooltip: l10n.cancelButton,
                      ),
                    ],
                  ),
                )
              : _buildEpisodeActionBar(boundEpisodes),
        ),
      ),
      if (_chapterError != null && _chapters.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(
                l10n.animeDetailEpisodeLoadFailed,
                style: tt.bodyMedium,
              ),
            ),
          ),
        )
      else if (_loadingChapters)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
        )
      else if (_chapters.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(l10n.animeDetailNoEpisodes, style: tt.bodyMedium),
            ),
          ),
        )
      else if (_dandanplayBinding != null)
        ..._buildBoundEpisodeSlivers(hp, tt, cs)
      else ...[
        if (_chapterError != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(hp, 0, hp, 12),
              child: Text(
                l10n.animeDetailEpisodeRefreshFailedCached,
                style: tt.bodySmall?.copyWith(color: cs.error),
              ),
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: hp),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate((_, i) {
              final chapter = _chapters[i];
              final selected = _selectedUuids.contains(chapter.uuid);
              final downloaded = _downloads.isDownloaded(
                widget.pathWord,
                chapter.uuid,
              );
              final taskInfo = _downloads.taskInfo(
                widget.pathWord,
                chapter.uuid,
              );
              final inQueue = taskInfo != null;

              return _AnimeChapterCard(
                chapter: chapter,
                selected: selected,
                selectionMode: _selectionMode,
                isDownloaded: downloaded,
                isDownloading:
                    taskInfo?.status == DownloadTaskStatus.downloading,
                isQueued:
                    inQueue &&
                    taskInfo.status != DownloadTaskStatus.downloading,
                progress: _downloads.progressOf(widget.pathWord, chapter.uuid),
                onTap: () {
                  if (_selectionMode) {
                    _toggleSelection(chapter.uuid);
                    return;
                  }
                  _openChapter(chapter);
                },
                onLongPress: () => _enterSelectionMode(chapter.uuid),
              );
            }, childCount: _chapters.length),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 120,
              mainAxisExtent: 52,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
          ),
        ),
      ],
    ];
  }

  List<Widget> _buildCommentsSlivers(double hp, TextTheme tt, ColorScheme cs) {
    final l10n = AppLocalizations.of(context)!;
    final binding = _dandanplayBinding;
    final bangumiId = binding?.bangumiId.trim() ?? '';
    if (bangumiId.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(hp, 24, hp, 0),
            child: Center(
              child: Text(
                l10n.animeDetailBindToViewComments,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ),
        ),
      ];
    }

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(hp, 12, hp, 0),
          child: BangumiCommentsSection(
            key: _bangumiCommentsKey,
            bangumiId: bangumiId,
            animeTitle: binding?.animeTitle ?? _currentAnimeTitle,
          ),
        ),
      ),
    ];
  }

  ButtonStyle _episodeActionButtonStyle() {
    return FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildEpisodeActionBar(List<DandanplayBangumiEpisode> boundEpisodes) {
    final l10n = AppLocalizations.of(context)!;
    final buttons = <({int flex, Widget child})>[
      if (_dandanplayBinding == null)
        (
          flex: 3,
          child: FilledButton.tonalIcon(
            onPressed: _showDandanplayBindingDialog,
            icon: const Icon(Icons.link_rounded, size: 18),
            label: Text(
              l10n.animeDetailBindDanmaku,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            style: _episodeActionButtonStyle(),
          ),
        )
      else ...[
        (
          flex: 3,
          child: FilledButton.tonalIcon(
            onPressed: _showDandanplayBindingDialog,
            icon: const Icon(Icons.manage_search_rounded, size: 18),
            label: Text(
              l10n.animeDetailRebind,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            style: _episodeActionButtonStyle(),
          ),
        ),
        (
          flex: 2,
          child: FilledButton.tonalIcon(
            onPressed: boundEpisodes.isEmpty
                ? null
                : () => _showDandanplayAlignmentDialog(boundEpisodes),
            icon: const Icon(Icons.align_horizontal_left_rounded, size: 18),
            label: Text(
              l10n.animeDetailAlign,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            style: _episodeActionButtonStyle(),
          ),
        ),
      ],
      if (_chapters.isNotEmpty)
        (
          flex: 2,
          child: FilledButton.tonalIcon(
            onPressed: () => setState(() => _selectionMode = true),
            icon: const Icon(Icons.download_for_offline_outlined, size: 18),
            label: Text(
              l10n.animeDetailDownloadButton,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            style: _episodeActionButtonStyle(),
          ),
        ),
    ];

    return Row(
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(flex: buttons[i].flex, child: buttons[i].child),
        ],
      ],
    );
  }

  List<Widget> _buildBoundEpisodeSlivers(
    double hp,
    TextTheme tt,
    ColorScheme cs,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final bangumi = _dandanplayBangumi;
    final episodes = bangumi == null
        ? const <DandanplayBangumiEpisode>[]
        : _uniqueDandanplayEpisodes(bangumi.episodes);

    return [
      if (_chapterError != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(hp, 0, hp, 12),
            child: Text(
              l10n.animeDetailEpisodeRefreshFailedCached,
              style: tt.bodySmall?.copyWith(color: cs.error),
            ),
          ),
        ),
      if (_loadingDandanplayBangumi && episodes.isEmpty)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
        )
      else
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: hp),
          sliver: SliverList.separated(
            itemCount: _chapters.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, index) {
              final chapter = _chapters[index];
              final selectedEpisodeId = _danmakuEpisodeBindings[chapter.uuid];
              final selectedEpisode = _findDandanplayEpisode(
                episodes,
                selectedEpisodeId,
              );
              return _BoundAnimeChapterRow(
                chapter: chapter,
                selected: _selectedUuids.contains(chapter.uuid),
                selectionMode: _selectionMode,
                isDownloaded: _downloads.isDownloaded(
                  widget.pathWord,
                  chapter.uuid,
                ),
                episodes: episodes,
                selectedEpisodeId: selectedEpisode?.episodeId,
                onTap: () {
                  if (_selectionMode) {
                    _toggleSelection(chapter.uuid);
                    return;
                  }
                  _openChapter(chapter);
                },
                onLongPress: () => _enterSelectionMode(chapter.uuid),
                onEpisodeChanged: (episodeId) =>
                    _updateDandanplayEpisodeBinding(chapter, episodeId),
              );
            },
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final anime = _anime;
    final intro = _introViewData;
    final tabController = _tabController;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth < 900 ? screenWidth : 900.0;
    final hp = (screenWidth - contentWidth) / 2 + 16;

    if (_loadingChapters && anime == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_chapterError != null && anime == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 64, color: cs.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                l10n.animeDetailEpisodeLoadFailedShort,
                style: tt.titleMedium,
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: _loadChapters,
                child: Text(l10n.retryButton),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      floatingActionButton: _isCommentsTab
          ? _buildCommentsScrollToTopFab()
          : _buildFloatingActions(cs),
      body: RefreshIndicator(
        onRefresh: _refreshCurrentTab,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 280,
              foregroundColor: Colors.white,
              title: Text(
                intro?.title ?? anime?.name ?? l10n.animeDetailTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              flexibleSpace: intro == null
                  ? null
                  : FlexibleSpaceBar(
                      background: _AnimeDetailHeader(
                        intro: intro,
                        isCollected: _isCollected,
                      ),
                    ),
            ),
            if (_loadingDetail)
              const SliverToBoxAdapter(child: LinearProgressIndicator()),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(hp, 0, hp, 0),
                child: TabBar(
                  controller: tabController,
                  tabs: [
                    Tab(text: l10n.animeDetailIntroTab),
                    Tab(text: l10n.animeDetailEpisodesTab(_chapterTotal)),
                    if (_showCommentsTab)
                      Tab(text: l10n.chapterCommentsComment),
                  ],
                ),
              ),
            ),
            ...(_isIntroTab
                ? _buildIntroSlivers(hp, tt, cs)
                : _isCommentsTab
                ? _buildCommentsSlivers(hp, tt, cs)
                : _buildEpisodeSlivers(hp, tt, cs)),
            SliverPadding(
              padding: EdgeInsets.only(bottom: _isEpisodeTab ? 120 : 24),
            ),
          ],
        ),
      ),
    );
  }
}
