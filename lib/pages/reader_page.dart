import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../api/api_client.dart';
import '../api/ai_api.dart';
import '../models/chapter.dart';
import '../models/chapter_comment.dart';
import '../models/user_manager.dart';
import '../utils/chapter_summary_cache.dart';
import '../utils/download_manager.dart';
import '../utils/image_load_stats.dart';
import '../utils/network_error.dart';
import '../utils/toast.dart';
import '../utils/reading_history.dart';
import 'chapter_comment_display.dart';
import 'chapter_comments_sheet.dart';

part 'reader/reader_image_cache.dart';
part 'reader/reader_image_viewer.dart';
part 'reader/reader_settings_panel.dart';
part 'reader/reader_widgets.dart';

class ReaderPage extends StatefulWidget {
  final String pathWord;
  final String? comicName;
  final String? group;
  final String chapterUuid;
  final String chapterName;
  final int? chapterListPage;
  final int initialPage;

  const ReaderPage({
    super.key,
    required this.pathWord,
    this.comicName,
    this.group,
    required this.chapterUuid,
    required this.chapterName,
    this.chapterListPage,
    this.initialPage = 1,
  });

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  static const _volumeChannel = MethodChannel('io.github.caolib.kira/volume');
  static const _hiddenToolbarSlideOffset = 1.05;
  static CacheManager? _cachedImageManager;
  static int _cachedImageManagerTimeout = -1;

  CacheManager get _readerImageCacheManager {
    final seconds = _user.imageLoadTimeout;
    if (_cachedImageManager == null || _cachedImageManagerTimeout != seconds) {
      _cachedImageManager = CacheManager(
        Config(
          'readerImageCache',
          fileService: _ReaderImageFileService(Duration(seconds: seconds)),
        ),
      );
      _cachedImageManagerTimeout = seconds;
    }
    return _cachedImageManager!;
  }

  final _api = ApiClient();
  final _aiSettings = AiSettings();
  final _aiApi = AiApi();
  final _downloads = DownloadManager();
  final _user = UserManager();
  final _itemScrollController = ItemScrollController();
  final _itemPositionsListener = ItemPositionsListener.create();
  final _scrollOffsetController = ScrollOffsetController();
  bool _autoScrollEnabled = false;
  bool _autoScrollActive = false;
  Timer? _autoScrollResumeTimer;
  // 每次重启/打断滚动时自增，用于丢弃在途的旧滚动回调，避免章节切换后多条链并行。
  int _autoScrollGeneration = 0;
  // 覆盖层（设置面板/评论面板）打开期间暂停自动滚动
  bool _autoScrollPausedForOverlay = false;
  PageController _pageController = PageController();
  ChapterDetail? _detail;
  bool _loading = true;
  bool _refreshingChapter = false;
  bool _showToolbar = false;

  void _toggleToolbar() {
    _showToolbar = !_showToolbar;
    if (_showToolbar) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
      SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    setState(() {});
  }

  late String _currentUuid;
  int _currentPage = 1;
  bool _isDraggingSlider = false;
  bool _autoAdvancingChapter = false;
  double _pageModeChapterOverscroll = 0;
  // 无动画翻页：拖动过程中的累计位移与是否已翻页标记。
  double _instantTurnDragDelta = 0;
  bool _instantTurnCommitted = false;
  bool _volumeChannelAvailable = true;
  int _scrollModeInitialIndex = 0;
  int _scrollWidgetVersion = 0;
  final Map<int, int> _imageReloadVersions = {};
  final Map<int, int> _imageRetryCounts = {};
  final Map<int, String> _imageRetryTokens = {};

  List<ChapterComment>? _cachedComments;
  int _cachedCommentTotal = 0;
  String? _cachedCommentChapterUuid;

  bool get _isPageMode => _user.readerMode == 1;
  bool get _isVerticalPageMode => _isPageMode && _user.readerScrollDirection == 2;
  bool get _isDarkMode => Theme.of(context).brightness == Brightness.dark;
  bool get _isHorizontalScrollMode =>
      !_isPageMode && _user.readerScrollDirection != 2;
  bool get _isReversedScrollMode =>
      !_isPageMode && _user.readerScrollDirection == 1;

  int get _commentCount {
    if (_detail == null) return 0;
    if (_detail!.isDownloaded) return _detail!.commentTotal;
    if (_hasCommentCacheFor(_detail!.uuid)) return _cachedCommentTotal;
    return 0;
  }

  bool _hasCommentCacheFor(String chapterUuid) =>
      _cachedCommentChapterUuid == chapterUuid && _cachedComments != null;

  void _updateCommentCache(
    String chapterUuid,
    List<ChapterComment> comments,
    int total, {
    bool rebuild = false,
  }) {
    var nextComments = List<ChapterComment>.from(comments);
    var nextTotal = total < nextComments.length ? nextComments.length : total;

    if (_cachedCommentChapterUuid == chapterUuid && _cachedComments != null) {
      if (_cachedComments!.length > nextComments.length) {
        nextComments = List<ChapterComment>.from(_cachedComments!);
      }
      if (_cachedCommentTotal > nextTotal) {
        nextTotal = _cachedCommentTotal;
      }
    }

    void apply() {
      _cachedComments = nextComments;
      _cachedCommentTotal = nextTotal;
      _cachedCommentChapterUuid = chapterUuid;
    }

    if (rebuild && mounted) {
      setState(apply);
      return;
    }
    apply();
  }

  void _clearCommentCache() {
    _cachedComments = null;
    _cachedCommentTotal = 0;
    _cachedCommentChapterUuid = null;
  }

  bool _isFirstLoad = true;

  @override
  void initState() {
    super.initState();
    _currentUuid = widget.chapterUuid;
    _itemPositionsListener.itemPositions.addListener(_onItemPositionsChanged);
    _loadChapter();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _volumeChannel.invokeMethod('enableImmersive').catchError((_) {});
    _volumeChannel.setMethodCallHandler(_handleVolumeMethod);
    _updateVolumeIntercept();
  }

  @override
  void dispose() {
    _setVolumeIntercept(false);
    _volumeChannel.invokeMethod('disableImmersive').catchError((_) {});
    _volumeChannel.setMethodCallHandler(null);
    _itemPositionsListener.itemPositions.removeListener(
      _onItemPositionsChanged,
    );
    _autoScrollGeneration++;
    _autoScrollResumeTimer?.cancel();
    _pageController.dispose();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  Future<dynamic> _handleVolumeMethod(MethodCall call) async {
    if (!_user.readerVolumeKey || !_isPageMode || _detail == null) return;
    if (call.method == 'volumeUp') _prevPage();
    if (call.method == 'volumeDown') _nextPage();
  }

  void _updateVolumeIntercept() {
    final should = _isPageMode && _user.readerVolumeKey;
    _setVolumeIntercept(should);
  }

  Future<void> _setVolumeIntercept(bool enabled) async {
    if (!_volumeChannelAvailable) return;
    try {
      await _volumeChannel.invokeMethod(enabled ? 'enable' : 'disable');
    } on MissingPluginException {
      _volumeChannelAvailable = false;
    } on PlatformException catch (e) {
      debugPrint('Volume channel unavailable: $e');
      _volumeChannelAvailable = false;
    }
  }

  Future<void> _loadChapter({bool forceRefresh = false}) async {
    if (forceRefresh && _refreshingChapter) return;
    final previousPage = _currentPage;
    setState(() {
      if (forceRefresh) {
        _refreshingChapter = true;
      } else {
        _loading = true;
      }
    });
    try {
      final detail =
          (forceRefresh
              ? null
              : await _downloads.getDownloadedChapterDetail(
                  widget.pathWord,
                  _currentUuid,
                )) ??
          await _api.getChapterDetail(
            widget.pathWord,
            _currentUuid,
            forceRefresh: forceRefresh,
          );
      if (detail.contents.isEmpty) {
        throw StateError('Chapter has no readable pages');
      }
      if (!mounted) return;
      // 首次加载且有 initialPage 参数时跳到指定页
      final startPage = forceRefresh
          ? previousPage.clamp(1, detail.contents.length)
          : (_isFirstLoad && widget.initialPage > 1
                ? widget.initialPage.clamp(1, detail.contents.length)
                : 1);
      _isFirstLoad = false;
      final hasHeader = detail.prev == null;
      setState(() {
        _detail = detail;
        _loading = false;
        _refreshingChapter = false;
        _currentPage = startPage;
        _pageModeChapterOverscroll = 0;
        _scrollModeInitialIndex = (hasHeader ? 1 : 0) + (startPage - 1);
        _scrollWidgetVersion++;
        _imageReloadVersions.clear();
        _imageRetryCounts.clear();
        _imageRetryTokens.clear();
      });
      if (_isPageMode) {
        _pageController.dispose();
        _pageController = PageController(initialPage: startPage - 1);
      }
      _autoAdvancingChapter = false;
      _saveReadingHistory();
      _preloadComments();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _preloadImages(startPage - 1);
        // 章节切换会打断动画接力；列表重建后若仍开启则续滚。
        // 新章节首屏图片尚在加载，先等待再续滚，避免滚过未加载的空白。
        if (_autoScrollEnabled && !_isPageMode) {
          final gen = ++_autoScrollGeneration;
          Future.delayed(const Duration(seconds: 3), () {
            if (gen != _autoScrollGeneration) return;
            if (mounted && _autoScrollEnabled && !_isPageMode) {
              _continueAutoScroll();
            }
          });
        }
      });
      if (forceRefresh && mounted) showToast(context, '图片链接已刷新');
    } catch (e) {
      _autoAdvancingChapter = false;
      if (mounted) {
        setState(() {
          if (!forceRefresh || _detail == null) _loading = false;
          if (forceRefresh) _refreshingChapter = false;
        });
        if (forceRefresh) showToast(context, '刷新失败：${NetworkError.message(e)}');
      }
    }
  }

  Future<void> _refreshChapter() async {
    final detail = _detail;
    if (_loading || _refreshingChapter || detail == null) return;
    if (detail.isDownloaded) {
      showToast(context, '本地章节无需刷新');
      return;
    }
    _resetPageModeChapterOverscroll();
    await _loadChapter(forceRefresh: true);
  }

  void _saveReadingHistory() {
    ReadingHistory.save(
      pathWord: widget.pathWord,
      group: widget.group,
      chapterUuid: _currentUuid,
      chapterName: _detail?.name ?? widget.chapterName,
      chapterListPage: widget.chapterListPage,
      page: _currentPage,
      totalPage: _detail?.contents.length ?? 0,
    );
  }

  Future<void> _preloadComments() async {
    if (!_user.commentPreload) return;
    final detail = _detail;
    if (detail == null || detail.isDownloaded) return;
    if (_hasCommentCacheFor(_currentUuid)) return;

    final chapterUuid = _currentUuid;
    final chapterName = detail.name;

    try {
      final data = await _api.getChapterComments(chapterUuid, limit: 100);
      if (!mounted || _currentUuid != chapterUuid) return;
      _updateCommentCache(chapterUuid, data.list, data.total, rebuild: true);
      await _maybeAutoSummaryAfterPreload(
        chapterUuid: chapterUuid,
        chapterName: chapterName,
        comments: data.list,
      );
    } catch (_) {
      // 预加载失败不影响正常流程
    }
  }

  Future<void> _maybeAutoSummaryAfterPreload({
    required String chapterUuid,
    required String chapterName,
    required List<ChapterComment> comments,
  }) async {
    await _aiSettings.load();
    if (!mounted || _currentUuid != chapterUuid) return;
    if (!_user.commentPreload ||
        !_aiSettings.hasConfig ||
        !_aiSettings.summaryEnabled ||
        !_aiSettings.autoSummary ||
        _aiSettings.autoSummaryTiming != AiAutoSummaryTiming.afterPreload) {
      return;
    }
    if (comments.isEmpty || comments.length < _aiSettings.autoSummaryMin) {
      return;
    }

    final cached = await ChapterSummaryCache.get(chapterUuid);
    if (!mounted || _currentUuid != chapterUuid) return;
    if (cached != null && cached.isNotEmpty) return;
    if (ChapterSummaryCache.isGenerating(chapterUuid)) return;

    final input = _buildPreloadedSummaryInput(comments);
    if (input.snippets.trim().isEmpty) return;

    final comicLine = widget.comicName?.trim().isNotEmpty == true
        ? '漫画：${widget.comicName!.trim()}\n'
        : '';
    final messages = <AiMessage>[
      AiMessage(role: 'system', content: _aiSettings.summaryPrompt),
      AiMessage(
        role: 'user',
        content:
            '$comicLine章节：$chapterName\n共 ${input.count} 条不同评论（相同内容已合并）。每条行首数字为该评论的 id：\n\n${input.snippets}',
      ),
    ];

    final buffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    ChapterSummaryCache.startProgress(chapterUuid);
    try {
      final provider = _aiSettings.activeProvider;
      final stream = _aiApi.streamChatChunks(
        apiKey: provider.apiKey!,
        baseUrl: provider.baseUrl,
        apiFormat: provider.apiFormat,
        model: provider.model,
        messages: messages,
      );
      await for (final chunk in stream) {
        if (!mounted || _currentUuid != chapterUuid) {
          ChapterSummaryCache.clearProgress(chapterUuid);
          return;
        }
        if (chunk.isReasoning) {
          reasoningBuffer.write(chunk.text);
        } else {
          buffer.write(chunk.text);
        }
        ChapterSummaryCache.updateProgress(
          chapterUuid,
          buffer.toString(),
          reasoningContent: reasoningBuffer.toString(),
        );
      }
      final full = buffer.toString();
      if (full.isNotEmpty) {
        await ChapterSummaryCache.set(
          chapterUuid,
          full,
          reasoningContent: reasoningBuffer.isEmpty
              ? null
              : reasoningBuffer.toString(),
        );
      } else {
        ChapterSummaryCache.clearProgress(chapterUuid);
      }
    } catch (e) {
      ChapterSummaryCache.failProgress(
        chapterUuid,
        '后台自动总结失败：${NetworkError.message(e)}',
      );
      // 后台自动总结失败不打断阅读。
    }
  }

  ({String snippets, int count}) _buildPreloadedSummaryInput(
    List<ChapterComment> comments,
  ) {
    const maxChars = 64 * 1024;
    final buffer = StringBuffer();
    final entries = groupChapterComments(comments);
    var truncated = false;

    for (final entry in entries) {
      final text = entry.content.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isEmpty) continue;
      final id = entry.primaryComment.id;
      final line = entry.isMerged
          ? '$id. [${entry.count}人] $text\n'
          : '$id. ${entry.primaryComment.userName}: $text\n';
      if (buffer.length + line.length > maxChars) {
        truncated = true;
        break;
      }
      buffer.write(line);
    }
    if (truncated) {
      buffer.write('…（已截断，共 ${entries.length} 条不同评论）');
    }
    return (snippets: buffer.toString(), count: entries.length);
  }

  void _goChapter(String? uuid) {
    if (uuid == null) return;
    if (_currentUuid != uuid) {
      _clearCommentCache();
    }
    _currentUuid = uuid;
    _loadChapter();
  }

  void _prevPage() {
    if (_detail == null) return;
    if (_currentPage > 1) {
      _goToPage(_currentPage - 1);
    } else if (_detail!.prev != null) {
      _goChapter(_detail!.prev);
    } else {
      showToast(context, '已经是第一页了');
    }
  }

  void _nextPage() {
    if (_detail == null) return;
    final imageCount = _detail!.contents.length;
    final pageIndex = _pageController.page?.round() ?? 0;
    if (pageIndex >= imageCount - 1) {
      // 当前在最后一张图，继续翻页时跳转下一章。
      if (_detail!.next != null) {
        _goChapter(_detail!.next);
      } else {
        showToast(context, '已经是最后一章了');
      }
    } else {
      // 正常翻页。
      _goToPage(_currentPage + 1);
    }
  }

  /// 翻到指定页码（1-based）。开启「无动画翻页」时瞬时切换，否则带过渡动画。
  void _goToPage(int page) {
    if (!_pageController.hasClients) return;
    final index = page - 1;
    if (_user.readerInstantPageTurn) {
      _pageController.jumpToPage(index);
      return;
    }
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _onSettingsChanged() {
    final page = _currentPage;
    _updateVolumeIntercept();
    if (_isPageMode && _autoScrollEnabled) {
      _setAutoScroll(false);
    }
    if (_isPageMode) {
      _pageController.dispose();
      _pageController = PageController(initialPage: page - 1);
    } else {
      // 滚动模式:让 ScrollablePositionedList 带新 initialScrollIndex 重建,保持当前页
      final hasHeader = _detail?.prev == null;
      _scrollModeInitialIndex = (hasHeader ? 1 : 0) + (page - 1);
      _scrollWidgetVersion++;
    }
    setState(() {});
    // 修改滚动设置会重建列表从而打断动画，重建后若仍开启则续滚
    if (_autoScrollEnabled && !_isPageMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _autoScrollEnabled && !_isPageMode) {
          _restartAutoScroll();
        }
      });
    }
  }

  void _showSettingsPanel() {
    // 打开设置面板期间暂停自动滚动，避免调整设置时画面继续滚动
    _pauseAutoScrollForOverlay();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      builder: (_) => _ReaderSettingsPanel(onChanged: _onSettingsChanged),
    ).whenComplete(() {
      if (!mounted) return;
      _resumeAutoScrollAfterOverlay();
    });
  }

  // ── 自动滚动（仅滚动模式） ──

  // 每段滚动时长：配合 easeOutCubic 实现"快速上滑后缓缓停稳"的手感。
  static const _autoScrollSegmentDuration = Duration(milliseconds: 700);
  // 每段滚动距离 = 视口高度 × 该系数，保证停在一个可整屏阅读的画面区域。
  static const _autoScrollSegmentFactor = 0.8;

  /// 主开关：仅由顶部按钮调用。关闭时取消恢复计时器。
  void _setAutoScroll(bool enabled) {
    if (enabled == _autoScrollEnabled) return;
    _autoScrollEnabled = enabled;
    _autoScrollActive = enabled;
    _autoScrollGeneration++;
    _cancelAutoScrollResumeTimer();
    if (enabled) _continueAutoScroll();
    if (mounted) setState(() {});
  }

  /// 触摸开始（按下）：暂停滚动。自动恢复模式下取消计时器，拖动期间不计时。
  void _onAutoScrollTouchStart() {
    if (!_autoScrollEnabled) return;
    if (_user.readerAutoScrollResume) {
      _autoScrollActive = false;
      _cancelAutoScrollResumeTimer();
      if (mounted) setState(() {});
    } else {
      _setAutoScroll(false);
    }
  }

  /// 触摸结束（抬起/取消）：自动恢复模式下开始恢复倒计时。
  void _onAutoScrollTouchEnd() {
    if (!_autoScrollEnabled || !_user.readerAutoScrollResume) return;
    if (!_autoScrollActive) _scheduleAutoScrollResume();
  }

  /// 鼠标滚轮等瞬时交互：暂停并立即开始恢复倒计时。
  void _onAutoScrollWheel() {
    if (!_autoScrollEnabled) return;
    if (_user.readerAutoScrollResume) {
      _autoScrollActive = false;
      _scheduleAutoScrollResume();
      if (mounted) setState(() {});
    } else {
      _setAutoScroll(false);
    }
  }

  void _scheduleAutoScrollResume() {
    _cancelAutoScrollResumeTimer();
    _autoScrollResumeTimer = Timer(
      Duration(milliseconds: (_user.readerAutoScrollResumeDelay * 1000).round()),
      () {
        _autoScrollResumeTimer = null;
        if (!mounted ||
            !_autoScrollEnabled ||
            _isPageMode ||
            _detail == null ||
            _autoScrollPausedForOverlay) {
          return;
        }
        _autoScrollActive = true;
        _restartAutoScroll();
        setState(() {});
      },
    );
  }

  void _cancelAutoScrollResumeTimer() {
    _autoScrollResumeTimer?.cancel();
    _autoScrollResumeTimer = null;
  }

  /// 打开覆盖层（设置面板、评论面板）时暂停自动滚动：
  /// 废弃在途的滚动回调并标记为非活跃，避免覆盖层打开期间画面继续滚动或自动恢复。
  void _pauseAutoScrollForOverlay() {
    _autoScrollGeneration++;
    _autoScrollPausedForOverlay = true;
    _autoScrollActive = false;
    _cancelAutoScrollResumeTimer();
    if (mounted) setState(() {});
  }

  /// 覆盖层关闭后按设置恢复自动滚动。仅当自动滚动仍开启时生效。
  void _resumeAutoScrollAfterOverlay() {
    _autoScrollPausedForOverlay = false;
    if (!_autoScrollEnabled || _isPageMode || _detail == null) return;
    if (_user.readerAutoScrollResume) {
      _scheduleAutoScrollResume();
    } else {
      _autoScrollActive = true;
      _restartAutoScroll();
      if (mounted) setState(() {});
    }
  }

  /// 废弃在途的滚动回调并立即重新开始一段。用于章节切换、设置变更、自动恢复等重启点。
  void _restartAutoScroll() {
    _autoScrollGeneration++;
    _continueAutoScroll();
  }

  void _continueAutoScroll() {
    if (!_autoScrollEnabled ||
        !_autoScrollActive ||
        _detail == null ||
        _isPageMode) {
      return;
    }
    // 没有下一章且最后一张图已进入视口：滑到底后暂停，避免无意义滚动。
    if (_detail!.next == null) {
      final positions = _itemPositionsListener.itemPositions.value;
      if (positions.isNotEmpty) {
        final hasHeader = _detail!.prev == null;
        final imageStart = hasHeader ? 1 : 0;
        final imageCount = _detail!.contents.length;
        final lastImageIndex = imageStart + imageCount - 1;
        final isLastImageFullyVisible = positions.any((p) {
          if (p.index != lastImageIndex) return false;
          return p.itemLeadingEdge >= 0.0 && p.itemTrailingEdge <= 1.0;
        });
        if (isLastImageFullyVisible) {
          _setAutoScroll(false);
          return;
        }
      }
    }
    // 间歇式滚动：快速上滑一段距离 → 停顿阅读 → 再上滑。
    // offset 取正值即沿阅读前进方向滚动（含右到左反向模式）。
    // 用 easeOutCubic 让画面快速启动、缓缓停稳，避免匀速移动带来的眼部追踪疲劳。
    // gen 用于丢弃章节切换等在途的旧回调，避免重启后多条滚动链并行。
    final gen = _autoScrollGeneration;
    final viewportHeight = MediaQuery.sizeOf(context).height;
    _scrollOffsetController
        .animateScroll(
          offset: (viewportHeight * _autoScrollSegmentFactor)
              .clamp(80.0, 4000.0),
          duration: _autoScrollSegmentDuration,
          curve: Curves.easeOutCubic,
        )
        .then((_) {
          if (gen != _autoScrollGeneration || !_autoScrollActive) return;
          // 停顿一段时间供眼睛阅读，随后继续下一段。
          Future.delayed(
            Duration(
              milliseconds: (_user.readerAutoScrollPause * 1000).round(),
            ),
            () {
              if (gen != _autoScrollGeneration || !_autoScrollActive) return;
              _continueAutoScroll();
            },
          );
        })
        .catchError((Object _) {
          // 用户拖动或章节切换会取消动画，链条在此自然中断
        });
  }

  // ── 图片预加载 ──

  void _preloadImages(int centerIndex, {int range = 2}) {
    if (_detail == null || _detail!.isDownloaded) return;
    final count = _detail!.contents.length;
    for (int offset = -range; offset <= range; offset++) {
      final i = centerIndex + offset;
      if (i < 0 || i >= count) continue;
      precacheImage(
        CachedNetworkImageProvider(
          _detail!.contents[i],
          cacheManager: _readerImageCacheManager,
        ),
        context,
        onError: (_, _) {},
      );
    }
  }

  // ── 公共图片组件 ──

  void _retryImage(int index) {
    setState(() {
      _imageRetryCounts.remove(index);
      _imageRetryTokens.remove(index);
      _imageReloadVersions[index] = (_imageReloadVersions[index] ?? 0) + 1;
    });
  }

  void _clearImageRetryState(int index) {
    if (!_imageRetryCounts.containsKey(index) &&
        !_imageRetryTokens.containsKey(index)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _imageRetryCounts.remove(index);
        _imageRetryTokens.remove(index);
      });
    });
  }

  void _scheduleImageRetry(int index) {
    final attempts = _imageRetryCounts[index] ?? 0;
    final retryLimit = _user.imageRetryCount;
    if (attempts >= retryLimit) return;

    final version = _imageReloadVersions[index] ?? 0;
    final token = '$version-$attempts';
    if (_imageRetryTokens[index] == token) return;
    _imageRetryTokens[index] = token;

    Future<void>.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      final currentVersion = _imageReloadVersions[index] ?? 0;
      if (currentVersion != version) return;

      setState(() {
        _imageRetryCounts[index] = attempts + 1;
        _imageRetryTokens.remove(index);
        _imageReloadVersions[index] = currentVersion + 1;
      });
    });
  }

  Future<void> _copyImageUrl(int index) async {
    final imageSource = _detail?.contents[index];
    if (imageSource == null || imageSource.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: imageSource));
    if (!mounted) return;
    showToast(
      context,
      _detail?.isDownloaded == true ? '图片路径已复制到剪贴板' : '图片链接已复制到剪贴板',
    );
  }

  Future<void> _openImageViewer(int index) async {
    final detail = _detail;
    if (detail == null || index < 0 || index >= detail.contents.length) return;

    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        pageBuilder: (_, _, _) => _ReaderImageViewer(
          imageSource: detail.contents[index],
          isDownloaded: detail.isDownloaded,
          cacheManager: _readerImageCacheManager,
          pageNumber: index + 1,
          pageCount: detail.contents.length,
        ),
      ),
    );
    if (!mounted) return;
    if (_showToolbar) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  Widget _buildReaderImageGesture(int index) {
    return _ReaderImageGesture(
      key: ValueKey('reader-image-$_currentUuid-$index'),
      onSingleTap: _isPageMode ? _handlePageModeTapAt : (_) => _toggleToolbar(),
      onDoubleTap: () => _openImageViewer(index),
      child: _buildImage(index),
    );
  }

  Widget _buildImage(int index) {
    final cs = Theme.of(context).colorScheme;
    final imageSource = _detail!.contents[index];
    final useFullViewport = _isPageMode || _isHorizontalScrollMode;
    final imageFit = _isHorizontalScrollMode
        ? BoxFit.fitHeight
        : (useFullViewport ? BoxFit.contain : BoxFit.fitWidth);
    final screenSize = MediaQuery.sizeOf(context);
    final memCacheWidth = _isHorizontalScrollMode
        ? (screenSize.height * MediaQuery.devicePixelRatioOf(context)).round()
        : (screenSize.width * MediaQuery.devicePixelRatioOf(context)).round();
    Widget image;

    if (_detail!.isDownloaded) {
      _clearImageRetryState(index);
      image = Image.file(
        File(imageSource),
        fit: imageFit,
        width: _isHorizontalScrollMode ? null : double.infinity,
        height: useFullViewport ? double.infinity : null,
        errorBuilder: (_, _, _) => Container(
          height: 400,
          color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image, color: cs.onSurfaceVariant, size: 48),
                const SizedBox(height: 8),
                Text(
                  '本地图片损坏或缺失',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () => _copyImageUrl(index),
                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                  label: const Text('复制图片路径'),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      image = CachedNetworkImage(
        key: ValueKey(
          '$_currentUuid-$index-${_imageReloadVersions[index] ?? 0}',
        ),
        imageUrl: imageSource,
        cacheManager: _readerImageCacheManager,
        fit: imageFit,
        memCacheWidth: memCacheWidth,
        width: _isHorizontalScrollMode ? null : double.infinity,
        height: useFullViewport ? double.infinity : null,
        imageBuilder: (_, imageProvider) {
          _clearImageRetryState(index);
          return Image(
            image: imageProvider,
            fit: imageFit,
            width: _isHorizontalScrollMode ? null : double.infinity,
            height: useFullViewport ? double.infinity : null,
          );
        },
        placeholder: (_, _) => Container(
          height: 400,
          color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        errorWidget: (_, _, _) {
          final attempts = _imageRetryCounts[index] ?? 0;
          final retryLimit = _user.imageRetryCount;
          final canAutoRetry = attempts < retryLimit;
          if (canAutoRetry) {
            _scheduleImageRetry(index);
          }

          return Container(
            height: 400,
            color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.broken_image,
                    color: cs.onSurfaceVariant,
                    size: 48,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    canAutoRetry
                        ? '加载失败，正在重试 ${attempts + 1}/$retryLimit'
                        : '加载失败',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                  ),
                  if (!canAutoRetry) ...[
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: () => _retryImage(index),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('重新加载'),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      onPressed: () => _copyImageUrl(index),
                      icon: const Icon(Icons.copy_all_outlined, size: 18),
                      label: const Text('复制图片链接'),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      );
    }
    // 深色模式亮度遮罩
    if (_isDarkMode && _user.readerDimming > 0) {
      image = Stack(
        children: [
          image,
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: _user.readerDimming),
              ),
            ),
          ),
        ],
      );
    }
    return image;
  }

  // ── 滚动模式 ──

  double _scrollModeTailExtent(BuildContext context) {
    final viewportSize = MediaQuery.sizeOf(context);
    final extent = _isHorizontalScrollMode
        ? viewportSize.width
        : viewportSize.height;
    return extent < 280 ? 280 : extent;
  }

  void _jumpToScrollPage(int page, {int? totalPages}) {
    if (!_itemScrollController.isAttached) return;
    final imageCount = totalPages ?? _detail?.contents.length ?? 0;
    if (imageCount <= 0) return;
    final hasHeader = _detail?.prev == null;
    final clampedPage = page.clamp(1, imageCount);
    final targetIndex = (hasHeader ? 1 : 0) + (clampedPage - 1);
    _itemScrollController.jumpTo(index: targetIndex);
  }

  void _onItemPositionsChanged() {
    if (!mounted || _detail == null || _isDraggingSlider) return;
    if (_isPageMode) return;

    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    final hasHeader = _detail!.prev == null;
    final imageStart = hasHeader ? 1 : 0;
    final imageCount = _detail!.contents.length;

    // 取在视口中可见面积最大的 image item 作为当前页
    int? bestImageIndex;
    double bestVisible = -1;
    for (final p in positions) {
      if (p.index < imageStart || p.index >= imageStart + imageCount) continue;
      final top = p.itemLeadingEdge.clamp(0.0, 1.0);
      final bottom = p.itemTrailingEdge.clamp(0.0, 1.0);
      final visible = bottom - top;
      if (visible > bestVisible) {
        bestVisible = visible;
        bestImageIndex = p.index - imageStart;
      }
    }

    if (bestImageIndex == null) return;
    final page = bestImageIndex + 1;
    if (page < 1 || page > imageCount) return;
    if (page == _currentPage) return;

    setState(() => _currentPage = page);
    _saveReadingHistory();
    _preloadImages(page - 1);
  }

  bool _shouldAutoAdvanceScrollChapter(ScrollNotification notification) {
    if (_detail?.next == null || _loading || _autoAdvancingChapter) {
      return false;
    }

    // tail item(下一章按钮区)是否已部分进入视口
    final hasHeader = _detail?.prev == null;
    final tailIndex = (hasHeader ? 1 : 0) + (_detail?.contents.length ?? 0);
    final positions = _itemPositionsListener.itemPositions.value;
    var tailVisible = false;
    var tailFullyVisible = false;
    for (final p in positions) {
      if (p.index != tailIndex) continue;
      tailVisible = p.itemLeadingEdge < 1.0 && p.itemTrailingEdge > 0;
      tailFullyVisible =
          p.itemLeadingEdge >= -0.05 && p.itemTrailingEdge <= 1.05;
      break;
    }
    if (!tailVisible) return false;

    if (notification is ScrollUpdateNotification) {
      // 必须 tail 已完全在视口内,且仍在向下滑,才认为是"看完最后一张图"
      if (!tailFullyVisible) return false;
      return (notification.scrollDelta ?? 0) > 0;
    }
    if (notification is OverscrollNotification) {
      return notification.overscroll > 0;
    }
    return false;
  }

  void _autoAdvanceToNextChapter() {
    final nextUuid = _detail?.next;
    if (nextUuid == null || _autoAdvancingChapter) return;

    _setPageModeChapterOverscroll(0);
    _autoAdvancingChapter = true;
    _goChapter(nextUuid);
  }

  void _setPageModeChapterOverscroll(double value) {
    final nextValue = value < 0 ? 0.0 : value;
    if ((_pageModeChapterOverscroll - nextValue).abs() < 0.5) return;
    if (!mounted) {
      _pageModeChapterOverscroll = nextValue;
      return;
    }
    setState(() => _pageModeChapterOverscroll = nextValue);
  }

  void _resetPageModeChapterOverscroll() {
    _setPageModeChapterOverscroll(0);
  }

  Offset _pageModeChapterTranslation() {
    final offset = _pageModeChapterOverscroll;
    if (offset <= 0) return Offset.zero;
    if (_isVerticalPageMode) return Offset(0, -offset);
    return Offset(_user.readerScrollDirection == 1 ? offset : -offset, 0);
  }

  bool _shouldAutoAdvancePageChapter(ScrollNotification notification) {
    if (_detail?.next == null || _loading || _autoAdvancingChapter) {
      _resetPageModeChapterOverscroll();
      return false;
    }

    final imageCount = _detail?.contents.length ?? 0;
    final currentIndex = (_pageController.page ?? (_currentPage - 1).toDouble())
        .round();
    final isLastPage = imageCount > 0 && currentIndex >= imageCount - 1;
    if (!isLastPage) {
      _resetPageModeChapterOverscroll();
      return false;
    }

    if (notification is ScrollStartNotification ||
        notification is ScrollEndNotification) {
      _resetPageModeChapterOverscroll();
      return false;
    }

    if (notification is! OverscrollNotification) return false;

    final triggerThreshold = notification.metrics.viewportDimension / 3;
    _setPageModeChapterOverscroll(
      (_pageModeChapterOverscroll + notification.overscroll.abs()).clamp(
        0.0,
        triggerThreshold,
      ),
    );
    return _pageModeChapterOverscroll >= triggerThreshold;
  }

  Widget _buildScrollMode() {
    final imageCount = _detail!.contents.length;
    final hasHeader = _detail!.prev == null;
    final totalItems = (hasHeader ? 1 : 0) + imageCount + 1;
    final scrollDirection = _isHorizontalScrollMode
        ? Axis.horizontal
        : Axis.vertical;
    final viewportSize = MediaQuery.sizeOf(context);
    return Listener(
      onPointerDown: (_) => _onAutoScrollTouchStart(),
      onPointerUp: (_) => _onAutoScrollTouchEnd(),
      onPointerCancel: (_) => _onAutoScrollTouchEnd(),
      child: GestureDetector(
        onTap: () => _toggleToolbar(),
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            // 鼠标滚轮等非触摸交互通过 UserScrollNotification 暂停
            if (n is UserScrollNotification && _autoScrollEnabled) {
              _onAutoScrollWheel();
            }
            if (_isDraggingSlider) return false;
            if (n is ScrollUpdateNotification &&
                _showToolbar &&
                (n.scrollDelta ?? 0).abs() > 0) {
              SystemChrome.setEnabledSystemUIMode(
                SystemUiMode.immersiveSticky,
              );
              setState(() => _showToolbar = false);
            }
            if (_shouldAutoAdvanceScrollChapter(n)) {
              _autoAdvanceToNextChapter();
            }
            return false;
          },
          child: ScrollablePositionedList.separated(
            key: ValueKey('$_currentUuid-$_scrollWidgetVersion'),
            itemScrollController: _itemScrollController,
            itemPositionsListener: _itemPositionsListener,
            scrollOffsetController: _scrollOffsetController,
            initialScrollIndex: _scrollModeInitialIndex,
            scrollDirection: scrollDirection,
            reverse: _isReversedScrollMode,
            padding: EdgeInsets.zero,
            physics: _isHorizontalScrollMode
                ? null
                : const AlwaysScrollableScrollPhysics(),
            minCacheExtent: _isHorizontalScrollMode
                ? viewportSize.width
                : viewportSize.height,
            itemCount: totalItems,
            separatorBuilder: (_, i) {
              final imageStart = hasHeader ? 1 : 0;
              final imageEnd = imageStart + imageCount - 1;
              if (i >= imageStart && i < imageEnd) {
                return _isHorizontalScrollMode
                    ? SizedBox(width: _user.readerImageGap)
                    : SizedBox(height: _user.readerImageGap);
              }
              return const SizedBox.shrink();
            },
            itemBuilder: (_, i) {
              if (hasHeader && i == 0) return _buildFirstChapterHead();
              final imageIndex = i - (hasHeader ? 1 : 0);
              if (imageIndex < imageCount) {
                final image = _buildReaderImageGesture(imageIndex);
                if (_isHorizontalScrollMode) {
                  return SizedBox(
                    height: viewportSize.height,
                    child: image,
                  );
                }
                return image;
              }
              return _buildNextChapterTail();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFirstChapterHead() {
    final message = const Center(
      child: Text(
        '已经是第一章',
        style: TextStyle(color: Colors.white54, fontSize: 14),
      ),
    );

    if (_isHorizontalScrollMode) {
      return SizedBox(
        width: _scrollModeTailExtent(context),
        child: Padding(padding: const EdgeInsets.all(32), child: message),
      );
    }

    return Padding(padding: const EdgeInsets.all(32), child: message);
  }

  Widget _buildChapterEndActionsRow() {
    final nextUuid = _detail?.next;
    final hasNext = nextUuid != null;
    final buttonStyle = OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
      backgroundColor: Colors.white.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
    final primaryButtonStyle = FilledButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: Colors.white.withValues(alpha: 0.18),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.list),
          label: const Text('目录'),
          style: buttonStyle,
        ),
        OutlinedButton.icon(
          onPressed: _showChapterComments,
          icon: const Icon(Icons.forum_outlined),
          label: Text(_commentCount > 0 ? '$_commentCount' : '评论'),
          style: buttonStyle,
        ),
        if (hasNext)
          FilledButton.icon(
            onPressed: () => _goChapter(nextUuid),
            icon: const Icon(Icons.skip_next),
            label: const Text('下一章'),
            style: primaryButtonStyle,
          ),
      ],
    );
  }

  Widget _buildPageModeEndActions() {
    final nextUuid = _detail?.next;
    final hasNext = nextUuid != null;
    final buttonStyle = OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: BorderSide(color: Colors.white.withValues(alpha: 0.24)),
      backgroundColor: Colors.black.withValues(alpha: 0.55),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      minimumSize: const Size(0, 40),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final primaryButtonStyle = FilledButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: Colors.white.withValues(alpha: 0.16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      minimumSize: const Size(0, 40),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, _showToolbar ? 46 : 6),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.list_rounded, size: 18),
                    label: const Text('目录'),
                    style: buttonStyle,
                  ),
                  OutlinedButton.icon(
                    onPressed: _showChapterComments,
                    icon: const Icon(Icons.forum_outlined, size: 18),
                    label: Text(_commentCount > 0 ? '$_commentCount' : '评论'),
                    style: buttonStyle,
                  ),
                  if (hasNext)
                    FilledButton.icon(
                      onPressed: () => _goChapter(nextUuid),
                      icon: const Icon(Icons.skip_next_rounded, size: 18),
                      label: const Text('下一章'),
                      style: primaryButtonStyle,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNextChapterTail() {
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(32, 72, 32, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _detail?.next != null ? '继续下滑或点击按钮进入下一章' : '已经是最后一章',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
              height: 1.6,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          _buildChapterEndActionsRow(),
        ],
      ),
    );

    return ColoredBox(
      color: Colors.black,
      child: SizedBox(
        width: _isHorizontalScrollMode ? _scrollModeTailExtent(context) : null,
        height: _isHorizontalScrollMode ? null : _scrollModeTailExtent(context),
        child: Align(alignment: Alignment.topCenter, child: content),
      ),
    );
  }

  Future<void> _showChapterComments() async {
    final detail = _detail;
    if (detail == null) return;

    // 打开评论面板期间暂停自动滚动，与设置面板保持一致
    _pauseAutoScrollForOverlay();
    final useCachedComments = _hasCommentCacheFor(detail.uuid);
    final initialComments = detail.isDownloaded
        ? detail.comments
        : (useCachedComments ? _cachedComments : null);
    final initialTotal = detail.isDownloaded
        ? detail.commentTotal
        : (useCachedComments ? _cachedCommentTotal : null);

    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width),
      backgroundColor: Colors.transparent,
      builder: (_) => ChapterCommentsSheet(
        chapterUuid: detail.uuid,
        comicName: widget.comicName ?? widget.pathWord,
        chapterName: detail.name,
        initialComments: initialComments,
        initialTotal: initialTotal,
        onCommentsUpdated: detail.isDownloaded
            ? null
            : (comments, total) {
                if (!mounted || _currentUuid != detail.uuid) return;
                _updateCommentCache(
                  detail.uuid,
                  comments,
                  total,
                  rebuild: true,
                );
              },
        hasNextChapter: detail.next != null,
        onNextChapter: detail.next == null
            ? null
            : () {
                Navigator.of(context).maybePop();
                _goChapter(detail.next);
              },
      ),
    );

    if (action == 'back_to_catalog') {
      // 返回目录会退出阅读页，无需恢复自动滚动
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    if (mounted) _resumeAutoScrollAfterOverlay();
  }

  // ── 翻页模式 ──

  void _handlePageModeTapAt(Offset globalPosition) {
    if (_isVerticalPageMode) {
      final screenHeight = MediaQuery.of(context).size.height;
      final y = globalPosition.dy;
      if (y < screenHeight / 3) {
        _prevPage();
      } else if (y > screenHeight * 2 / 3) {
        _nextPage();
      } else {
        _toggleToolbar();
      }
      return;
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final x = globalPosition.dx;
    if (x < screenWidth / 3) {
      _user.readerScrollDirection == 1 ? _nextPage() : _prevPage();
    } else if (x > screenWidth * 2 / 3) {
      _user.readerScrollDirection == 1 ? _prevPage() : _nextPage();
    } else {
      setState(() => _showToolbar = !_showToolbar);
    }
  }

  /// 拖动位移是否代表"向下一页前进"。
  /// 左到右: 向左拖前进; 右到左: 向右拖前进; 上下: 向下拖前进。
  bool _instantTurnForward(double delta) {
    if (_isVerticalPageMode) return delta > 0;
    final rtl = _user.readerScrollDirection == 1;
    return rtl ? delta > 0 : delta < 0;
  }

  void _onInstantTurnDragStart(DragStartDetails details) {
    _instantTurnDragDelta = 0;
    _instantTurnCommitted = false;
  }

  void _onInstantTurnDragUpdate(DragUpdateDetails details) {
    if (_instantTurnCommitted || _detail == null) return;
    _instantTurnDragDelta +=
        _isVerticalPageMode ? details.delta.dy : details.delta.dx;
    final viewport = _isVerticalPageMode
        ? MediaQuery.sizeOf(context).height
        : MediaQuery.sizeOf(context).width;
    // 越过视口约五分之一即翻页；一次拖动只翻一页，抬手后才能再翻。
    if (_instantTurnDragDelta.abs() >= viewport * 0.2) {
      _instantTurnCommitted = true;
      if (_instantTurnForward(_instantTurnDragDelta)) {
        _nextPage();
      } else {
        _prevPage();
      }
    }
  }

  void _onInstantTurnDragEnd(DragEndDetails details) {
    _instantTurnDragDelta = 0;
    _instantTurnCommitted = false;
  }

  void _onInstantTurnDragCancel() {
    _instantTurnDragDelta = 0;
    _instantTurnCommitted = false;
  }

  Widget _buildPageMode() {
    final imageCount = _detail!.contents.length;
    final instantTurn = _user.readerInstantPageTurn;
    final horizontalDrag = instantTurn && !_isVerticalPageMode;
    final verticalDrag = instantTurn && _isVerticalPageMode;
    return GestureDetector(
      onTapUp: (details) => _handlePageModeTapAt(details.globalPosition),
      onHorizontalDragStart: horizontalDrag ? _onInstantTurnDragStart : null,
      onHorizontalDragUpdate: horizontalDrag ? _onInstantTurnDragUpdate : null,
      onHorizontalDragEnd: horizontalDrag ? _onInstantTurnDragEnd : null,
      onHorizontalDragCancel: horizontalDrag ? _onInstantTurnDragCancel : null,
      onVerticalDragStart: verticalDrag ? _onInstantTurnDragStart : null,
      onVerticalDragUpdate: verticalDrag ? _onInstantTurnDragUpdate : null,
      onVerticalDragEnd: verticalDrag ? _onInstantTurnDragEnd : null,
      onVerticalDragCancel: verticalDrag ? _onInstantTurnDragCancel : null,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (_shouldAutoAdvancePageChapter(notification)) {
            _autoAdvanceToNextChapter();
          }
          return false;
        },
        child: PageView.builder(
          controller: _pageController,
          scrollDirection: _isVerticalPageMode
              ? Axis.vertical
              : Axis.horizontal,
          reverse: !_isVerticalPageMode && _user.readerScrollDirection == 1,
          allowImplicitScrolling: true,
          // 无动画翻页：禁用 PageView 自带手势，改由上方 drag 回调在越过阈值后瞬时切页。
          physics: instantTurn ? const NeverScrollableScrollPhysics() : null,
          itemCount: imageCount,
          onPageChanged: (index) {
            setState(() {
              _currentPage = index + 1;
              if (!_isDraggingSlider) {
                _showToolbar = false;
                SystemChrome.setEnabledSystemUIMode(
                  SystemUiMode.immersiveSticky,
                );
              }
            });
            _resetPageModeChapterOverscroll();
            _saveReadingHistory();
            _preloadImages(index);
          },
          itemBuilder: (_, i) {
            if (i < imageCount - 1) {
              return Center(child: _buildReaderImageGesture(i));
            }

            final translation = _pageModeChapterTranslation();
            return AnimatedContainer(
              duration: _pageModeChapterOverscroll == 0
                  ? const Duration(milliseconds: 180)
                  : Duration.zero,
              curve: Curves.easeOutCubic,
              transform: Matrix4.translationValues(
                translation.dx,
                translation.dy,
                0,
              ),
              child: Stack(
                children: [
                  Center(child: _buildReaderImageGesture(i)),
                  _buildPageModeEndActions(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRefreshableReader(Widget child) {
    final detail = _detail;
    if (detail == null) return child;

    final canUseNativeRefresh =
        (!_isPageMode && !_isHorizontalScrollMode) ||
        (_isPageMode && _isVerticalPageMode);
    if (canUseNativeRefresh) {
      return RefreshIndicator(
        onRefresh: _refreshChapter,
        notificationPredicate: (notification) => notification.depth == 0,
        color: Colors.white,
        backgroundColor: Colors.black,
        child: child,
      );
    }

    return _ReaderPullToRefresh(
      enabled: !detail.isDownloaded && !_loading,
      onRefresh: _refreshChapter,
      child: child,
    );
  }

  // ── 工具栏 ──

  Widget _buildTopBar(ColorScheme cs) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !_showToolbar,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 200),
          offset: Offset(0, _showToolbar ? 0 : -_hiddenToolbarSlideOffset),
          child: Container(
            color: Colors.black,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        _detail?.name ?? widget.chapterName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(ColorScheme cs) {
    final total = _detail!.contents.length;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !_showToolbar,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 200),
          offset: Offset(0, _showToolbar ? 0 : _hiddenToolbarSlideOffset),
          child: Container(
            color: Colors.black,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 页码进度条（带间隔点）
                    Row(
                      children: [
                        Text(
                          '$_currentPage',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 7,
                              ),
                              tickMarkShape: const RoundSliderTickMarkShape(
                                tickMarkRadius: 2.5,
                              ),
                              activeTrackColor: cs.primary,
                              inactiveTrackColor: Colors.white24,
                              activeTickMarkColor: cs.primary,
                              inactiveTickMarkColor: Colors.white24,
                              thumbColor: cs.primary,
                              overlayColor: cs.primary.withValues(alpha: 0.2),
                            ),
                            child: Slider(
                              value: _currentPage.toDouble(),
                              min: 1,
                              max: total.toDouble(),
                              divisions: total > 1 ? total - 1 : null,
                              onChangeStart: (_) {
                                _isDraggingSlider = true;
                              },
                              onChangeEnd: (_) {
                                _isDraggingSlider = false;
                              },
                              onChanged: (v) {
                                final page = v.round();
                                setState(() => _currentPage = page);
                                if (_isPageMode) {
                                  _pageController.jumpToPage(page - 1);
                                } else {
                                  _jumpToScrollPage(page, totalPages: total);
                                }
                              },
                            ),
                          ),
                        ),
                        Text(
                          '$total',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    // 按钮行
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.skip_previous,
                            color: _detail!.prev != null
                                ? Colors.white
                                : Colors.white38,
                          ),
                          onPressed: _detail!.prev != null
                              ? () => _goChapter(_detail!.prev)
                              : null,
                          tooltip: '上一章',
                        ),
                        IconButton(
                          icon: const Icon(Icons.list, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                          tooltip: '目录',
                        ),
                        if (!_isPageMode && _user.readerAutoScrollEnabled)
                          IconButton(
                            tooltip: _autoScrollEnabled
                                ? (_autoScrollActive
                                    ? '暂停自动滚动'
                                    : '自动滚动即将恢复')
                                : '开启自动滚动',
                            icon: Icon(
                              _autoScrollEnabled
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_outline,
                              color: _autoScrollEnabled
                                  ? (_autoScrollActive
                                      ? cs.primary
                                      : cs.primary.withValues(alpha: 0.4))
                                  : Colors.white,
                            ),
                            onPressed: () => _setAutoScroll(!_autoScrollEnabled),
                          ),
                        IconButton(
                          icon: Badge(
                            isLabelVisible: _commentCount > 0,
                            backgroundColor: Colors.white,
                            textColor: Colors.black,
                            label: Text(
                              '$_commentCount',
                              style: const TextStyle(fontSize: 10),
                            ),
                            child: const Icon(
                              Icons.forum_outlined,
                              color: Colors.white,
                            ),
                          ),
                          onPressed: _showChapterComments,
                          tooltip: '章节评论',
                        ),
                        IconButton(
                          icon: const Icon(Icons.settings, color: Colors.white),
                          onPressed: _showSettingsPanel,
                          tooltip: '阅读设置',
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.skip_next,
                            color: _detail!.next != null
                                ? Colors.white
                                : Colors.white38,
                          ),
                          onPressed: _detail!.next != null
                              ? () => _goChapter(_detail!.next)
                              : null,
                          tooltip: '下一章',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _showToolbar
          ? SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness:
                  isDark ? Brightness.light : Brightness.dark,
              systemNavigationBarColor: Colors.black,
              systemNavigationBarIconBrightness:
                  isDark ? Brightness.light : Brightness.dark,
            )
          : SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness:
                  isDark ? Brightness.light : Brightness.dark,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarIconBrightness:
                  isDark ? Brightness.light : Brightness.dark,
            ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_detail != null)
              _buildRefreshableReader(
                _isPageMode ? _buildPageMode() : _buildScrollMode(),
              ),
            _buildTopBar(cs),
            if (_detail != null) _buildBottomBar(cs),
          ],
        ),
      ),
    );
  }
}

class _ReaderPullToRefresh extends StatefulWidget {
  final bool enabled;
  final Future<void> Function() onRefresh;
  final Widget child;

  const _ReaderPullToRefresh({
    required this.enabled,
    required this.onRefresh,
    required this.child,
  });

  @override
  State<_ReaderPullToRefresh> createState() => _ReaderPullToRefreshState();
}

class _ReaderPullToRefreshState extends State<_ReaderPullToRefresh> {
  static const _triggerExtent = 90.0;
  double _dragExtent = 0;
  bool _refreshing = false;

  bool get _indicatorVisible => _dragExtent > 0 || _refreshing;

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled || _refreshing) return;
    final nextExtent = (_dragExtent + details.delta.dy).clamp(
      0.0,
      _triggerExtent * 1.4,
    );
    if (nextExtent == _dragExtent) return;
    setState(() => _dragExtent = nextExtent);
  }

  Future<void> _handleDragEnd() async {
    if (!widget.enabled || _refreshing) return;
    if (_dragExtent < _triggerExtent) {
      setState(() => _dragExtent = 0);
      return;
    }

    setState(() {
      _refreshing = true;
      _dragExtent = _triggerExtent;
    });
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
          _dragExtent = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final progress = (_dragExtent / _triggerExtent).clamp(0.0, 1.0);
    return Stack(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragUpdate: _handleDragUpdate,
          onVerticalDragEnd: (_) => _handleDragEnd(),
          onVerticalDragCancel: () {
            if (!_refreshing && mounted) setState(() => _dragExtent = 0);
          },
          child: widget.child,
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: _indicatorVisible ? 1 : 0,
              child: Center(
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(10),
                  child: CircularProgressIndicator(
                    value: _refreshing ? null : progress,
                    strokeWidth: 2.4,
                    color: Colors.white,
                    backgroundColor: Colors.white24,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── 设置面板 ──
