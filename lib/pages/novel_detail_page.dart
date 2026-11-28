import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';

import '../api/novel/novel_api.dart' show novelErrorMessage;
import '../l10n/app_localizations.dart';
import '../models/novel.dart';
import '../models/novel_download.dart';
import '../models/novel_reading_progress.dart';
import '../models/user_manager.dart';
import '../providers/app_providers.dart';
import '../providers/novel_providers.dart';
import '../routing/app_router.dart';
import '../theme/app_icon_sizes.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/app_logger.dart';
import '../utils/cover_brightness_filter.dart';
import '../utils/download_manager.dart';
import '../utils/time_format.dart';
import '../utils/toast.dart';
import '../widgets/app_hero.dart';
import '../widgets/app_sheet.dart';
import '../widgets/comic_info_chips.dart';
import '../widgets/cover_image.dart';
import '../widgets/cover_placeholder.dart';
import '../widgets/download_settings_sheet.dart';
import '../widgets/error_retry_view.dart';
import '../widgets/novel_comments_sheet.dart';
import '../widgets/novel_hero_tags.dart';
import '../widgets/novel_widgets.dart';
import 'comic_detail_page.dart'
    show
        ChapterCard,
        chapterTileExtent,
        comicDetailUsesTwoPane,
        comicDetailInfoPaneWidth;
import 'novel_filter_page.dart';

part 'novel_detail_page_parts/read_button.dart';
part 'novel_detail_page_parts/view.dart';
part 'novel_detail_page_parts/slivers.dart';
part 'novel_detail_page_parts/body.dart';

class NovelDetailPage extends ConsumerStatefulWidget {
  const NovelDetailPage({
    super.key,
    required this.pathWord,
    this.initialBook,
    this.heroTagBase,
  });

  final String pathWord;

  /// 来源卡片携带的书籍数据，首帧立即渲染封面与信息区，
  /// 让进入详情的 Hero 动画有落点（对齐漫画详情的 initialComic）。
  final NovelBook? initialBook;

  /// 非 null 时封面与来源列表卡片参与 Hero 动画。
  final String? heroTagBase;

  @override
  ConsumerState<NovelDetailPage> createState() => _NovelDetailPageState();
}

class _NovelDetailPageState extends ConsumerState<NovelDetailPage> {
  late final UserManager _user = ref.read(userManagerProvider);
  late final _downloads = ref.read(novelDownloadManagerProvider);
  late final _bookmarkStore = ref.read(novelBookmarkStoreProvider);

  /// 这部轻小说是否已出现在书签页（只有分组也算）。
  bool _bookmarkGrouped = false;
  NovelDetail? _detail;
  NovelQuery? _query;
  NovelReadingProgress? _progress;
  List<NovelVolume> _volumes = [];
  final Set<String> _selectedDownloadVolumes = {};
  bool _downloadSelectionMode = false;
  bool _enqueuingDownloads = false;
  bool _detailLoading = true;
  bool _detailFailed = false;
  Object? _detailError;
  bool _refreshingDetail = false;
  bool _volumesLoading = true;
  bool _volumesFailed = false;
  Object? _volumesError;
  bool _refreshingVolumes = false;
  bool _queryLoading = true;
  bool _queryFailed = false;
  Object? _queryError;
  bool _progressLoading = true;
  bool _progressFailed = false;
  Object? _progressError;
  bool? _collected;
  bool _collecting = false;
  bool _opening = false;
  bool _briefExpanded = false;
  String? _token;
  int _detailGeneration = 0;
  int _volumeGeneration = 0;
  int _queryGeneration = 0;
  int _progressGeneration = 0;
  int _accountGeneration = 0;

  @override
  void initState() {
    super.initState();
    // 首帧立即渲染来源卡片带来的书籍信息，Hero 动画才有落点；
    // 缓存与接口数据随后覆盖。
    final initialBook = widget.initialBook;
    if (initialBook != null) {
      _detail = NovelDetail(book: initialBook);
      _detailLoading = false;
    }
    _token = _user.copyToken;
    _user.addListener(_onAccountChanged);
    _downloads.addListener(_onDownloadsChanged);
    _bookmarkStore.addListener(_onBookmarksChanged);
    unawaited(_loadBookmarkGroup());
    unawaited(_initializePage());
  }

  Future<void> _loadBookmarkGroup() async {
    await _bookmarkStore.ensureLoaded();
    _onBookmarksChanged();
  }

  void _onBookmarksChanged() {
    if (!mounted) return;
    setState(() => _bookmarkGrouped = _bookmarkStore.hasGroup(widget.pathWord));
  }

  /// 右上角书签按钮：把这部轻小说加进书签页。只登记分组、不写具体书签，
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
    final book = _detail?.book;
    await _bookmarkStore.addGroup(
      pathWord: widget.pathWord,
      name: book?.name ?? '',
      cover: book?.cover ?? '',
    );
    if (!mounted) return;
    showToast(context, l10n.bookmarkAdded);
  }

  @override
  void didUpdateWidget(covariant NovelDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pathWord == widget.pathWord) return;
    ++_accountGeneration;
    _detail = null;
    _query = null;
    _progress = null;
    _volumes = [];
    _selectedDownloadVolumes.clear();
    _onBookmarksChanged();
    _downloadSelectionMode = false;
    _collected = null;
    _collecting = false;
    unawaited(_initializePage());
  }

  @override
  void dispose() {
    _bookmarkStore.removeListener(_onBookmarksChanged);
    _user.removeListener(_onAccountChanged);
    _downloads.removeListener(_onDownloadsChanged);
    super.dispose();
  }

  void _onDownloadsChanged() {
    if (!mounted) return;
    setState(() {
      _selectedDownloadVolumes.retainAll(
        _volumes.where(_isVolumeSelectable).map((volume) => volume.id),
      );
    });
  }

  void _onAccountChanged() {
    if (!mounted || _token == _user.copyToken) return;
    _token = _user.copyToken;
    ++_accountGeneration;
    setState(() {
      _query = null;
      _collected = null;
      _collecting = false;
    });
    unawaited(_loadQuery());
    unawaited(_loadDetail(refresh: true));
  }

  /// 对齐漫画详情页：先读持久化缓存秒显界面，再后台拉新覆盖。
  /// 详情接口有 6h TTL 门控，卷目录每次都发；拉新期间显示刷新指示。
  /// 本地阅读进度是 SharedPreferences 即时可读的，不等网络接口：
  /// 与缓存/接口并行加载，本地有记录时继续阅读按钮立刻出现。
  Future<void> _initializePage() async {
    unawaited(_loadProgress());
    await _loadFromCache();
    await _loadQuery();
    unawaited(_loadDetail());
    unawaited(_loadVolumes());
  }

  /// Cache-only first paint; keeps the loading state when nothing is cached.
  Future<void> _loadFromCache() async {
    final repo = ref.read(novelRepositoryProvider);
    final (detail, volumes) = await (
      repo.loadDetailFromCache(widget.pathWord),
      repo.loadVolumesFromCache(widget.pathWord),
    ).wait;
    if (!mounted) return;
    setState(() {
      if (detail != null) {
        _detail = detail;
        _detailLoading = false;
      }
      if (volumes != null) {
        _volumes = volumes;
        _volumesLoading = false;
      }
    });
  }

  Future<void> _refresh({bool refresh = true}) async {
    await Future.wait([
      _loadDetail(refresh: refresh),
      _loadVolumes(refresh: refresh),
      _loadQuery(),
      _loadProgress(),
    ]);
  }

  void _log(Object e, StackTrace stack, String operation) {
    unawaited(
      AppLogger.instance.recordWarning(
        e,
        stackTrace: stack,
        source: 'novel_detail.$operation',
      ),
    );
  }

  Future<void> _loadDetail({bool refresh = false}) async {
    final generation = ++_detailGeneration;
    final hasVisibleDetail = _detail != null;
    setState(() {
      // 已有可见数据时只亮刷新指示，不把界面打回骨架。
      if (hasVisibleDetail) {
        _refreshingDetail = true;
      } else {
        _detailLoading = true;
      }
      _detailFailed = false;
    });
    try {
      final detail = await ref
          .read(novelRepositoryProvider)
          .loadDetail(widget.pathWord, refresh: refresh);
      if (!mounted || generation != _detailGeneration) return;
      setState(() => _detail = detail);
    } catch (e, stack) {
      _log(e, stack, 'load');
      if (mounted && generation == _detailGeneration) {
        setState(() {
          _detailFailed = true;
          _detailError = e;
        });
      }
    } finally {
      if (mounted && generation == _detailGeneration) {
        setState(() {
          _detailLoading = false;
          _refreshingDetail = false;
        });
      }
    }
  }

  Future<void> _loadVolumes({bool refresh = false}) async {
    final generation = ++_volumeGeneration;
    final hasVisibleVolumes = _volumes.isNotEmpty;
    setState(() {
      if (hasVisibleVolumes) {
        _refreshingVolumes = true;
      } else {
        _volumesLoading = true;
      }
      _volumesFailed = false;
    });
    try {
      final volumes = await ref
          .read(novelRepositoryProvider)
          .loadVolumes(widget.pathWord, refresh: refresh);
      if (!mounted || generation != _volumeGeneration) return;
      setState(() {
        _volumes = volumes;
        _selectedDownloadVolumes.retainAll(
          _volumes.where(_isVolumeSelectable).map((volume) => volume.id),
        );
      });
    } catch (e, stack) {
      _log(e, stack, 'volumes');
      if (mounted && generation == _volumeGeneration) {
        setState(() {
          _volumesFailed = true;
          _volumesError = e;
        });
      }
    } finally {
      if (mounted && generation == _volumeGeneration) {
        setState(() {
          _volumesLoading = false;
          _refreshingVolumes = false;
        });
      }
    }
  }

  Future<void> _loadQuery() async {
    final generation = ++_queryGeneration;
    setState(() {
      _queryLoading = true;
      _queryFailed = false;
      _collected = null;
    });
    try {
      final query = await ref.read(novelApiProvider).getQuery(widget.pathWord);
      if (!mounted || generation != _queryGeneration) return;
      setState(() {
        _query = query;
        // collect is a nullable collection association, never a popularity
        // count. A failed/anonymous query must not assert "not collected".
        _collected = _user.isCopyLoggedIn && query.isLoggedIn
            ? query.collect != null
            : null;
      });
    } catch (e, stack) {
      _log(e, stack, 'query');
      if (mounted && generation == _queryGeneration) {
        setState(() {
          _queryFailed = true;
          _queryError = e;
        });
      }
    } finally {
      if (mounted && generation == _queryGeneration) {
        setState(() => _queryLoading = false);
      }
    }
  }

  Future<void> _loadProgress() async {
    final generation = ++_progressGeneration;
    setState(() => _progressLoading = true);
    try {
      final progress = await ref
          .read(novelReadingStoreProvider)
          .readProgress(widget.pathWord);
      if (!mounted || generation != _progressGeneration) return;
      setState(() {
        _progress = progress;
        _progressFailed = false;
      });
    } catch (e, stack) {
      _log(e, stack, 'progress');
      if (mounted && generation == _progressGeneration) {
        setState(() {
          _progressFailed = true;
          _progressError = e;
        });
      }
    } finally {
      if (mounted && generation == _progressGeneration) {
        setState(() => _progressLoading = false);
      }
    }
  }

  Future<void> _login() async {
    await context.pushNamed(
      AppRoutes.login,
      queryParameters: {'copyOnly': 'true'},
    );
    if (mounted) await _loadQuery();
  }

  Future<void> _toggleCollect() async {
    if (_collecting) return;
    if (!_user.isCopyLoggedIn || _query?.isLoggedIn == false) return _login();
    final collected = _collected;
    if (collected == null) return _loadQuery();
    final book = _detail?.book;
    if (book == null || book.uuid.isEmpty) return;
    final account = _accountGeneration;
    ++_queryGeneration;
    setState(() {
      _collecting = true;
      _queryLoading = false;
    });
    try {
      await ref
          .read(novelApiProvider)
          .setCollected(bookUuid: book.uuid, collected: !collected);
    } catch (e, stack) {
      _log(e, stack, 'collect');
      if (mounted && account == _accountGeneration) {
        setState(() => _collecting = false);
        final l10n = AppLocalizations.of(context)!;
        showToast(
          context,
          l10n.novelCollectFailedDetail(novelErrorMessage(e)),
          isError: true,
        );
      }
      return;
    }
    if (!mounted || account != _accountGeneration) return;
    ++_queryGeneration;
    setState(() {
      _collected = !collected;
      _queryLoading = false;
      _collecting = false;
    });
    // Update the visible state as soon as the mutation succeeds. Cache cleanup
    // is independent persistence work and must not delay the user feedback.
    try {
      await ref.read(novelShelfRepoProvider).invalidateCache();
    } catch (e, stack) {
      _log(e, stack, 'invalidate_shelf');
    }
  }

  bool get _hasLocalResume => _progress?.volumeId.isNotEmpty == true;

  /// 读过的卷：历史集合 + 当前进度所在卷（旧记录无集合时兜底）。
  Set<String> get _readVolumeIds => {
    ...?_progress?.readVolumeIds,
    if (_hasLocalResume) _progress!.volumeId,
  };

  String? get _remoteVolumeId {
    final id = _query?.browse?.chapterId;
    return id == null || id.isEmpty ? null : id;
  }

  bool get _canRead =>
      !_opening &&
      (_hasLocalResume ||
          (!_progressLoading &&
              !_queryLoading &&
              (_remoteVolumeId != null || _volumes.isNotEmpty)));

  /// 续读按钮只显示卷名：本地卷名优先，其次远端卷名，最后按目录取名。
  /// API 的章节名自带「第一卷 …」前缀，按钮不再拼接章节名。
  String? get _resumeVolumeName {
    final local = _hasLocalResume ? _progress : null;
    final id = local?.volumeId ?? _remoteVolumeId;
    final names = [
      if (local != null) local.volumeName,
      if (local == null) _query?.browse?.chapterName ?? '',
      _volumes.where((volume) => volume.id == id).firstOrNull?.name ?? '',
    ];
    return names
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .firstOrNull;
  }

  String? get _resumePercent {
    final local = _hasLocalResume ? _progress : null;
    if (local == null) return null;
    // Reader 保存的是整卷段落位置比例（包含插图/空章节占位），不是目录索引。
    // 旧记录缺少 progress 时会解码为 0；非卷首锚点不能据此声称读了 0%。
    final ratio = local.progress;
    if (ratio == 0 &&
        (local.entryIndex > 0 ||
            local.paragraphIndex > 0 ||
            local.paragraphAlignment < 0)) {
      return null;
    }
    if (ratio == 1) return '100.00';
    final percent = ratio * 100;
    // 可以四舍五入到两位小数，但不能把尚未到达结尾的位置显示成已读完。
    final capped = ratio < 1 && percent > 99.99 ? 99.99 : percent;
    return capped.toStringAsFixed(2);
  }

  Future<void> _read({NovelVolume? volume}) async {
    if (_opening) return;
    final local = volume == null && _hasLocalResume ? _progress : null;
    final id =
        volume?.id ??
        local?.volumeId ??
        _remoteVolumeId ??
        (_volumes.isEmpty ? null : _volumes.first.id);
    if (id == null || id.isEmpty) return;
    final book = _detail?.book;
    setState(() => _opening = true);
    try {
      await context.pushNamed(
        AppRoutes.novelReader,
        pathParameters: {'pathWord': widget.pathWord, 'volumeId': id},
        extra: NovelReaderExtra(
          name: local?.name ?? book?.name ?? '',
          cover: local?.cover ?? book?.cover ?? '',
          tags: book?.themeNames ?? const [],
          entryIndex: local?.entryIndex ?? 0,
          resume: volume == null && (local != null || _remoteVolumeId != null),
        ),
      );
      if (mounted) await _loadProgress();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  // 已完成任务会从队列移除，本地卷（含待修复）也必须保留下载中心入口。
  bool get _hasDownloadTasks =>
      _downloads.tasks.any((task) => task.pathWord == widget.pathWord);

  bool get _hasDownloads =>
      _downloads.localVolumeIds(widget.pathWord).isNotEmpty ||
      _hasDownloadTasks;

  bool _isVolumeSelectable(NovelVolume volume) =>
      !_downloads.isVolumeDownloaded(widget.pathWord, volume.id) &&
      !_downloads.isVolumeQueued(widget.pathWord, volume.id);

  void _exitDownloadSelectionMode() {
    setState(() {
      _downloadSelectionMode = false;
      _selectedDownloadVolumes.clear();
    });
  }

  void _toggleBriefExpanded() {
    setState(() => _briefExpanded = !_briefExpanded);
  }

  void _toggleDownloadSelectionMode() {
    if (_enqueuingDownloads) return;
    if (_downloadSelectionMode) {
      _exitDownloadSelectionMode();
    } else if (_volumes.any(_isVolumeSelectable)) {
      // 与漫画详情一致：主按钮只进入空选择态，不自动勾选或入队。
      setState(() {
        _downloadSelectionMode = true;
        _selectedDownloadVolumes.clear();
      });
    }
  }

  void _toggleDownloadSelection(NovelVolume volume) {
    if (_enqueuingDownloads || !_isVolumeSelectable(volume)) return;
    setState(() {
      _downloadSelectionMode = true;
      if (!_selectedDownloadVolumes.add(volume.id)) {
        _selectedDownloadVolumes.remove(volume.id);
      }
      // 清空勾选仍留在选择态，只有确认成功或显式取消才退出。
    });
  }

  void _selectAllDownloadableVolumes() {
    if (_enqueuingDownloads) return;
    final selectable = _volumes
        .where(_isVolumeSelectable)
        .map((volume) => volume.id)
        .toSet();
    final allSelected =
        selectable.isNotEmpty &&
        _selectedDownloadVolumes.containsAll(selectable);
    setState(() {
      // 再点全选只清空勾选，保持选择态，便于重新手动选择。
      _downloadSelectionMode = true;
      _selectedDownloadVolumes
        ..clear()
        ..addAll(allSelected ? const <String>{} : selectable);
    });
  }

  Future<void> _downloadSelectedVolumes() async {
    if (_enqueuingDownloads || !_downloadSelectionMode) return;
    final book = _detail?.book;
    if (book == null) return;
    final selectedVolumes = _volumes
        .where((volume) => _selectedDownloadVolumes.contains(volume.id))
        .where(_isVolumeSelectable)
        .toList(growable: false);
    if (selectedVolumes.isEmpty) return;
    final pathWord = widget.pathWord;
    setState(() => _enqueuingDownloads = true);
    try {
      await _downloads.enqueueVolumes(
        book: book,
        volumes: _volumes,
        selected: selectedVolumes,
      );
      if (!mounted || widget.pathWord != pathWord) return;
      _exitDownloadSelectionMode();
      showToast(context, AppLocalizations.of(context)!.downloadActionButton);
    } catch (error, stack) {
      _log(error, stack, 'download');
      if (mounted && widget.pathWord == pathWord) {
        final l10n = AppLocalizations.of(context)!;
        showToast(
          context,
          l10n.novelDownloadEnqueueFailed(novelErrorMessage(error)),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _enqueuingDownloads = false);
    }
  }

  /// 与漫画详情一致：选择工具栏上的设置按钮，打开统一的下载设置面板。
  Future<void> _showDownloadSettings() async {
    await showDownloadSettingsSheet(
      context,
      downloads: DownloadManager(),
      novelDownloads: _downloads,
    );
  }

  Future<void> _showComments() async {
    final book = _detail?.book;
    if (book == null || book.uuid.isEmpty) return;
    await showAppSheet<void>(
      context,
      heightFactor: 0.85,
      child: NovelCommentsSheet(
        bookUuid: book.uuid,
        bookName: book.name,
        allowPosting: !book.closeComment,
      ),
    );
  }

  void _openTag(NovelTag tag, NovelFilterKind kind) {
    final pathWord = tag.pathWord.trim();
    if (pathWord.isEmpty) return;
    unawaited(
      context.pushNamed(
        AppRoutes.novelFilter,
        pathParameters: {'kind': kind.name, 'pathWord': pathWord},
        queryParameters: {'name': tag.name},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final book = _detail?.book;
    final size = MediaQuery.sizeOf(context);
    final showReadButton = book != null || _canRead;
    final hasDownloads = _hasDownloads;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          book?.name ?? l10n.novelTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            key: const ValueKey('novel_detail_bookmark'),
            icon: Icon(
              _bookmarkGrouped
                  ? Icons.bookmark_added
                  : Icons.bookmark_add_outlined,
            ),
            tooltip: _bookmarkGrouped ? l10n.bookmarkRemove : l10n.bookmarkAdd,
            onPressed: _toggleBookmarkGroup,
          ),
        ],
      ),
      // 继续阅读固定在右下角，与漫画详情页的续读入口同款、同位置。
      body: Stack(
        children: [
          if (book == null)
            (_detailLoading
                ? const Center(child: ExpressiveLoadingIndicator())
                : ErrorRetryView(
                    message: novelErrorMessage(
                      _detailError,
                      fallback: l10n.novelLoadFailed,
                    ),
                    onRetry: () => _loadDetail(refresh: true),
                  ))
          else
            _buildBody(book),
          // 详情拉不到时也要能续读：轻小说进度是本机数据，离线可续。
          if (showReadButton || hasDownloads)
            Positioned(
              left: book != null && comicDetailUsesTwoPane(size)
                  ? comicDetailInfoPaneWidth(size) + 1 + AppSpacing.lg
                  : AppSpacing.lg,
              right: AppSpacing.lg,
              bottom: AppSpacing.lg,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // 与漫画一致，下载中心固定在右下续读按钮上方。
                  if (hasDownloads)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: showReadButton ? AppSpacing.md : 0,
                      ),
                      child: FloatingActionButton(
                        heroTag: 'novel_download_center',
                        tooltip: l10n.downloadCenterTitle,
                        onPressed: () => context
                            .pushNamed(
                              AppRoutes.downloadCenter,
                              queryParameters: {
                                'tab': _hasDownloadTasks ? '2' : '1',
                              },
                            )
                            .then((_) => _onDownloadsChanged()),
                        child: const Icon(
                          Icons.download_for_offline,
                          size: AppIconSize.xl,
                        ),
                      ),
                    ),
                  if (showReadButton) _buildReadButton(),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
