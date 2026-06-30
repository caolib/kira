import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
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
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    setState(() {});
  }

  late String _currentUuid;
  int _currentPage = 1;
  bool _isDraggingSlider = false;
  bool _autoAdvancingChapter = false;
  // 无动画翻页：拖动过程中的累计位移与是否已翻页标记。
  double _instantTurnDragDelta = 0;
  bool _instantTurnCommitted = false;
  bool _volumeChannelAvailable = true;
  int _scrollModeInitialIndex = 0;
  int _scrollWidgetVersion = 0;

  // 连续阅读：按阅读顺序拼接的章节链。首项为用户进入时打开的章节。
  // _chainIndex 指向当前"所在章节"（用于导航栏显示与历史记录）。
  // 加载下一话时追加到链尾，不重建视图，从而避免闪屏与状态丢失。
  final List<ChapterDetail> _chain = [];
  int _chainIndex = 0;
  bool _loadingNextChainChapter = false;
  final Map<int, int> _imageReloadVersions = {};
  final Map<int, int> _imageRetryCounts = {};
  final Map<int, String> _imageRetryTokens = {};

  // 评论缓存按章节 uuid 存放，连续阅读链中各章均可独立缓存，
  // 供分隔区评论按钮显示数量并避免重复打开时重新加载。
  final Map<String, List<ChapterComment>> _commentCache = {};
  final Map<String, int> _commentTotalCache = {};

  bool get _isPageMode => _user.readerMode == 1;
  bool get _isVerticalPageMode =>
      _isPageMode && _user.readerScrollDirection == 2;
  bool get _isDarkMode => Theme.of(context).brightness == Brightness.dark;
  bool get _isHorizontalScrollMode =>
      !_isPageMode && _user.readerScrollDirection != 2;
  bool get _isReversedScrollMode =>
      !_isPageMode && _user.readerScrollDirection == 1;

  bool get _continuousReading => _isPageMode || _user.readerContinuousReading;

  /// 链中所有章节图片的累计数量（用于渲染 PageView / 滚动列表的总条目数）。
  int get _chainImageCount =>
      _chain.fold(0, (sum, c) => sum + c.contents.length);

  /// 全局图片索引 -> (章节索引, 章节内图片索引)。
  (int chapterIndex, int imageIndex) _resolveChainImage(int globalIndex) {
    var remaining = globalIndex;
    for (var i = 0; i < _chain.length; i++) {
      final count = _chain[i].contents.length;
      if (remaining < count) return (i, remaining);
      remaining -= count;
    }
    return (_chain.length - 1, _chain.last.contents.length - 1);
  }

  /// 章节索引在链中的起始全局图片索引。
  int _chainChapterStart(int chapterIndex) {
    var start = 0;
    for (var i = 0; i < chapterIndex; i++) {
      start += _chain[i].contents.length;
    }
    return start;
  }

  /// 当前滚动列表的总条目数（仅在 _buildScrollMode 中使用，用于判断是否到达 loadMore）。
  /// 非连续：header(可选) + 图片 + tail。
  /// 连续：header(可选) + 各章(图片+分隔) + tail/loadMore（分隔只在非末章之后）。
  int get _scrollItemCount {
    final firstChapter = _chain.first;
    final hasHeader = firstChapter.prev == null;
    var count = hasHeader ? 1 : 0;
    for (final chapter in _chain) {
      count += chapter.contents.length;
    }
    if (_continuousReading) {
      // N 章之间有 N-1 个分隔 + 末尾 1 个 tail/loadMore = N
      count += _chain.length;
    } else {
      count += 1; // tail
    }
    return count;
  }

  int get _commentCount {
    if (_detail == null) return 0;
    return _commentCountFor(_detail!);
  }

  bool _hasCommentCacheFor(String chapterUuid) =>
      _commentCache.containsKey(chapterUuid);

  List<ChapterComment>? _cachedCommentsFor(String chapterUuid) =>
      _commentCache[chapterUuid];

  int _cachedCommentTotalFor(String chapterUuid) =>
      _commentTotalCache[chapterUuid] ?? 0;

  /// 获取指定章节的评论数：下载章用本地计数；在线章用命中的缓存，否则 0。
  int _commentCountFor(ChapterDetail chapter) {
    if (chapter.isDownloaded) return chapter.commentTotal;
    return _cachedCommentTotalFor(chapter.uuid);
  }

  void _updateCommentCache(
    String chapterUuid,
    List<ChapterComment> comments,
    int total, {
    bool rebuild = false,
  }) {
    var nextComments = List<ChapterComment>.from(comments);
    var nextTotal = total < nextComments.length ? nextComments.length : total;

    final existing = _commentCache[chapterUuid];
    if (existing != null && existing.length > nextComments.length) {
      nextComments = List<ChapterComment>.from(existing);
    }
    final existingTotal = _commentTotalCache[chapterUuid];
    if (existingTotal != null && existingTotal > nextTotal) {
      nextTotal = existingTotal;
    }

    void apply() {
      _commentCache[chapterUuid] = nextComments;
      _commentTotalCache[chapterUuid] = nextTotal;
    }

    if (rebuild && mounted) {
      setState(apply);
      return;
    }
    apply();
  }

  void _clearCommentCache() {
    _commentCache.clear();
    _commentTotalCache.clear();
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
        _scrollModeInitialIndex = _scrollItemIndexFor(
          chainIndex: 0,
          page: startPage,
          hasHeader: hasHeader,
        );
        _scrollWidgetVersion++;
        _imageReloadVersions.clear();
        _imageRetryCounts.clear();
        _imageRetryTokens.clear();
        // 重置连续阅读链：首项即当前章节。
        _chain
          ..clear()
          ..add(detail);
        _chainIndex = 0;
        _loadingNextChainChapter = false;
      });
      if (_isPageMode) {
        _pageController.dispose();
        final initialIndex = _chainChapterStart(_chainIndex) + (startPage - 1);
        _pageController = PageController(initialPage: initialIndex);
      }
      _autoAdvancingChapter = false;
      _saveReadingHistory();
      _preloadComments();
      // 缓存命中且当前无下一话时，后台静默刷新章节导航，用于发现新增的下一话。
      if (!forceRefresh && !detail.isDownloaded && detail.next == null) {
        _refreshChapterMetadata(detail);
      }
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
    await _loadChapter(forceRefresh: true);
  }

  /// 缓存命中后，后台静默刷新章节导航字段（next/prev），用于发现新增的下一话。
  ///
  /// 缓存保存的是上次打开该话时的整份响应，其中 `next` 可能因之后新话上架
  /// 而变得过时（例如曾经没有下一话，如今已有）。这里发一次请求取最新导航：
  /// 仅当 next/prev 发生变化时更新 UI 并刷新缓存，避免无谓重绘打断阅读。
  /// 仅在缓存命中且当前无下一话时触发，已有下一话时导航链完整，无需刷新。
  void _refreshChapterMetadata(ChapterDetail cached) {
    final chapterUuid = cached.uuid;
    _api
        .getChapterDetail(widget.pathWord, chapterUuid, forceRefresh: true)
        .then((fresh) {
          if (!mounted || _currentUuid != chapterUuid || _detail == null) {
            return;
          }
          // 仅当导航字段变化才更新；contents 变化留给手动刷新。
          if (fresh.next == cached.next && fresh.prev == cached.prev) {
            return;
          }
          setState(() {
            final updated = _detail!.copyWith(
              next: fresh.next,
              prev: fresh.prev,
            );
            _detail = updated;
            // 同步链中对应章节，保证连续阅读追加判断使用最新导航
            if (_chainIndex < _chain.length) {
              _chain[_chainIndex] = updated;
            }
          });
        })
        .catchError((Object _) {
          // 后台刷新失败不影响正常阅读流程
        });
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

  Future<void> _preloadComments({ChapterDetail? chapter}) async {
    if (!_user.commentPreload) return;
    final detail = chapter ?? _detail;
    if (detail == null || detail.isDownloaded) return;
    final uuid = detail.uuid;
    if (_hasCommentCacheFor(uuid)) return;

    final chapterUuid = uuid;
    final chapterName = detail.name;

    try {
      final data = await _api.getChapterComments(chapterUuid, limit: 100);
      if (!mounted) return;
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

  /// 连续阅读：在链尾追加下一话。仅滚动/翻页构建逻辑需要在末尾追加更多内容时调用。
  /// 加载完成后触发 setState，由 PageView/ScrollablePositionedList 增量渲染新页。
  Future<void> _appendNextChapterToChain() async {
    if (_loadingNextChainChapter) return;
    final lastChapter = _chain.last;
    final nextUuid = lastChapter.next;
    if (nextUuid == null) return;
    _loadingNextChainChapter = true;
    try {
      final next =
          (await _downloads.getDownloadedChapterDetail(
            widget.pathWord,
            nextUuid,
          )) ??
          await _api.getChapterDetail(
            widget.pathWord,
            nextUuid,
            forceRefresh: false,
          );
      if (next.contents.isEmpty) {
        throw StateError('Chapter has no readable pages');
      }
      if (!mounted) return;
      setState(() {
        _chain.add(next);
        _loadingNextChainChapter = false;
      });
      // 追加后立即预加载该话评论，使分隔区评论按钮能显示数量
      if (_user.commentPreload) _preloadComments(chapter: next);
    } catch (_) {
      _loadingNextChainChapter = false;
      // 追加失败保持链不变，用户可手动重试（继续翻页会再次触发）
    }
  }

  /// 根据全局图片位置更新当前所在章节，用于导航栏显示与历史记录。
  /// 返回章节是否发生变化（需要刷新评论缓存等）。
  bool _syncActiveChapterFromGlobal(int chapterIndex) {
    if (chapterIndex < 0 || chapterIndex >= _chain.length) return false;
    if (chapterIndex == _chainIndex) return false;
    final newDetail = _chain[chapterIndex];
    _chainIndex = chapterIndex;
    _detail = newDetail;
    _currentUuid = newDetail.uuid;
    return true;
  }

  void _prevPage() {
    if (_detail == null) return;
    if (_currentPage > 1 || _chainIndex > 0) {
      // 连续阅读：已到当前章首页但前面还有拼接的章节 -> 回到上一章末页
      if (_currentPage == 1 && _chainIndex > 0 && _continuousReading) {
        final prevChapter = _chain[_chainIndex - 1];
        final prevChapterStart = _chainChapterStart(_chainIndex - 1);
        final targetGlobal = prevChapterStart + prevChapter.contents.length - 1;
        _syncActiveChapterFromGlobal(_chainIndex - 1);
        _currentPage = prevChapter.contents.length;
        _jumpPageControllerTo(targetGlobal);
        setState(() {});
        _saveReadingHistory();
        return;
      }
      _goToPage(_currentPage - 1);
    } else if (_detail!.prev != null && !_continuousReading) {
      _goChapter(_detail!.prev);
    } else if (_detail!.prev != null && _continuousReading) {
      // 链首之前还有上一话：降级为整章跳转（重新加载）
      _goChapter(_detail!.prev);
    } else {
      showToast(context, '当前已无上一话');
    }
  }

  /// 翻页模式辅助：按设置跳转到全局页索引（无动画/带动画），无 client 时静默跳过。
  void _jumpPageControllerTo(int globalIndex) {
    if (!_isPageMode || !_pageController.hasClients) return;
    if (_user.readerInstantPageTurn) {
      _pageController.jumpToPage(globalIndex);
    } else {
      _pageController.animateToPage(
        globalIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _nextPage() {
    if (_detail == null) return;
    final imageCount = _detail!.contents.length;
    if (_currentPage < imageCount) {
      _goToPage(_currentPage + 1);
      return;
    }
    // 已到当前章末页
    if (_continuousReading) {
      // 链中后续章节已拼接 -> 直接进入下一章首页
      if (_chainIndex < _chain.length - 1) {
        final nextChapterStart = _chainChapterStart(_chainIndex + 1);
        _syncActiveChapterFromGlobal(_chainIndex + 1);
        _currentPage = 1;
        if (_isPageMode) {
          _jumpPageControllerTo(nextChapterStart);
        }
        setState(() {});
        _saveReadingHistory();
        return;
      }
      // 链尾且还有下一话 -> 追加后跳到新章首页
      final nextUuid = _chain.last.next;
      if (nextUuid != null && !_loadingNextChainChapter) {
        _appendNextChapterToChain().then((_) {
          if (!mounted) return;
          final newChapterIdx = _chain.length - 1;
          final newStart = _chainChapterStart(newChapterIdx);
          _syncActiveChapterFromGlobal(newChapterIdx);
          _currentPage = 1;
          if (_isPageMode) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _jumpPageControllerTo(newStart);
            });
          }
          setState(() {});
          _saveReadingHistory();
        });
        return;
      }
      if (_loadingNextChainChapter) {
        showToast(context, '正在加载下一话…');
        return;
      }
      showToast(context, '当前已无下一话');
      return;
    }
    if (_detail!.next != null) {
      _goChapter(_detail!.next);
    } else {
      showToast(context, '当前已无下一话');
    }
  }

  /// 翻到指定页码（1-based，当前章内页码）。开启「无动画翻页」时瞬时切换，否则带过渡动画。
  void _goToPage(int page) {
    if (!_pageController.hasClients) return;
    final globalIndex = _continuousReading
        ? _chainChapterStart(_chainIndex) + (page - 1)
        : page;
    if (_user.readerInstantPageTurn) {
      _pageController.jumpToPage(globalIndex);
      return;
    }
    _pageController.animateToPage(
      globalIndex,
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
    // 关闭连续阅读时丢弃已拼接的后续章节，仅保留当前章。
    if (!_continuousReading && _chain.length > 1) {
      _chain
        ..clear()
        ..add(_detail!);
      _chainIndex = 0;
    }
    if (_isPageMode) {
      _pageController.dispose();
      final initialIndex = _chainChapterStart(_chainIndex) + (page - 1);
      _pageController = PageController(initialPage: initialIndex);
    } else {
      // 滚动模式:让 ScrollablePositionedList 带新 initialScrollIndex 重建,保持当前页
      final hasHeader = _chain.first.prev == null;
      _scrollModeInitialIndex = _scrollItemIndexFor(
        chainIndex: _chainIndex,
        page: page,
        hasHeader: hasHeader,
      );
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

  /// 主开关：仅由顶部按钮调用。关闭时取消恢复计时器。
  void _setAutoScroll(bool enabled) {
    if (enabled == _autoScrollEnabled) return;
    _autoScrollEnabled = enabled;
    _autoScrollActive = enabled;
    _autoScrollGeneration++;
    _cancelAutoScrollResumeTimer();
    if (enabled) {
      _continueAutoScroll();
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
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
      Duration(
        milliseconds: (_user.readerAutoScrollResumeDelay * 1000).round(),
      ),
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
    final lastChapter = _chain.last;
    if (lastChapter.next == null) {
      final positions = _itemPositionsListener.itemPositions.value;
      if (positions.isNotEmpty) {
        // 计算链中最后一张图片的列表索引
        final hasHeader = _chain.first.prev == null;
        final lastImageIndex = _continuousReading
            ? _scrollItemIndexFor(
                chainIndex: _chain.length - 1,
                page: lastChapter.contents.length,
                hasHeader: hasHeader,
              )
            : (hasHeader ? 1 : 0) + (_detail!.contents.length - 1);
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
    // 水平滚动模式按视口宽度计算幅度，竖向按高度，避免左右滚动时单段距离不合理。
    final viewportSize = _isHorizontalScrollMode
        ? MediaQuery.sizeOf(context).width
        : MediaQuery.sizeOf(context).height;
    _scrollOffsetController
        .animateScroll(
          offset: (viewportSize * _user.readerAutoScrollDistance).clamp(
            80.0,
            4000.0,
          ),
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

  /// 连续阅读预加载：以 (章节索引, 章节内索引) 为中心，预加载相邻图片（跨章）。
  void _preloadChainImages(int chapterIndex, int localIndex, {int range = 2}) {
    if (_chain.isEmpty) return;
    final chapter = _chain[chapterIndex.clamp(0, _chain.length - 1)];
    if (chapter.isDownloaded) return;
    for (int offset = -range; offset <= range; offset++) {
      var ci = chapterIndex;
      var li = localIndex + offset;
      // 处理跨章回溯/前进
      while (li < 0 && ci > 0) {
        ci--;
        li += _chain[ci].contents.length;
      }
      while (li >= _chain[ci].contents.length && ci < _chain.length - 1) {
        li -= _chain[ci].contents.length;
        ci++;
      }
      if (li < 0 || li >= _chain[ci].contents.length) continue;
      final chap = _chain[ci];
      if (chap.isDownloaded) continue;
      precacheImage(
        CachedNetworkImageProvider(
          chap.contents[li],
          cacheManager: _readerImageCacheManager,
        ),
        context,
        onError: (_, _) {},
      );
    }
  }

  // ── 公共图片组件 ──
  //
  // 为支持连续阅读拼接多章图片，图片构建方法以 (chapter, localIndex) 定位图片，
  // 以 retryKey（非连续时等于 localIndex，连续时为全局索引）作为重试/版本状态键，
  // 避免不同章节的同名索引互相覆盖重试状态。

  void _retryImage(ChapterDetail chapter, int localIndex, int retryKey) {
    setState(() {
      _imageRetryCounts.remove(retryKey);
      _imageRetryTokens.remove(retryKey);
      _imageReloadVersions[retryKey] =
          (_imageReloadVersions[retryKey] ?? 0) + 1;
    });
  }

  void _clearImageRetryState(int retryKey) {
    if (!_imageRetryCounts.containsKey(retryKey) &&
        !_imageRetryTokens.containsKey(retryKey)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _imageRetryCounts.remove(retryKey);
        _imageRetryTokens.remove(retryKey);
      });
    });
  }

  void _scheduleImageRetry(int retryKey) {
    final attempts = _imageRetryCounts[retryKey] ?? 0;
    final retryLimit = _user.imageRetryCount;
    if (attempts >= retryLimit) return;

    final version = _imageReloadVersions[retryKey] ?? 0;
    final token = '$version-$attempts';
    if (_imageRetryTokens[retryKey] == token) return;
    _imageRetryTokens[retryKey] = token;

    Future<void>.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      final currentVersion = _imageReloadVersions[retryKey] ?? 0;
      if (currentVersion != version) return;

      setState(() {
        _imageRetryCounts[retryKey] = attempts + 1;
        _imageRetryTokens.remove(retryKey);
        _imageReloadVersions[retryKey] = currentVersion + 1;
      });
    });
  }

  Future<void> _copyImageUrl(ChapterDetail chapter, int localIndex) async {
    final imageSource = localIndex < chapter.contents.length
        ? chapter.contents[localIndex]
        : null;
    if (imageSource == null || imageSource.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: imageSource));
    if (!mounted) return;
    showToast(context, chapter.isDownloaded ? '图片路径已复制到剪贴板' : '图片链接已复制到剪贴板');
  }

  Future<void> _openImageViewer(ChapterDetail chapter, int localIndex) async {
    if (localIndex < 0 || localIndex >= chapter.contents.length) return;

    // 打开图片查看器期间暂停自动滚动，与设置面板/评论面板保持一致
    _pauseAutoScrollForOverlay();
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        pageBuilder: (_, _, _) => _ReaderImageViewer(
          imageSource: chapter.contents[localIndex],
          isDownloaded: chapter.isDownloaded,
          cacheManager: _readerImageCacheManager,
          pageNumber: localIndex + 1,
          pageCount: chapter.contents.length,
        ),
      ),
    );
    if (!mounted) return;
    _resumeAutoScrollAfterOverlay();
    if (_showToolbar) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  Widget _buildReaderImageGesture(
    ChapterDetail chapter,
    int localIndex, {
    int? retryKey,
  }) {
    final key = retryKey ?? localIndex;
    return _ReaderImageGesture(
      key: ValueKey('reader-image-${chapter.uuid}-$localIndex'),
      onSingleTap: _isPageMode ? _handlePageModeTapAt : (_) => _toggleToolbar(),
      onDoubleTap: () => _openImageViewer(chapter, localIndex),
      child: _buildImage(chapter, localIndex, retryKey: key),
    );
  }

  Widget _buildImage(ChapterDetail chapter, int localIndex, {int? retryKey}) {
    final cs = Theme.of(context).colorScheme;
    final key = retryKey ?? localIndex;
    final imageSource = chapter.contents[localIndex];
    final useFullViewport = _isPageMode || _isHorizontalScrollMode;
    final imageFit = _isHorizontalScrollMode
        ? BoxFit.fitHeight
        : (useFullViewport ? BoxFit.contain : BoxFit.fitWidth);
    final screenSize = MediaQuery.sizeOf(context);
    final memCacheWidth = _isHorizontalScrollMode
        ? (screenSize.height * MediaQuery.devicePixelRatioOf(context)).round()
        : (screenSize.width * MediaQuery.devicePixelRatioOf(context)).round();
    Widget image;

    if (chapter.isDownloaded) {
      _clearImageRetryState(key);
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
                  onPressed: () => _copyImageUrl(chapter, localIndex),
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
          '${chapter.uuid}-$localIndex-${_imageReloadVersions[key] ?? 0}',
        ),
        imageUrl: imageSource,
        cacheManager: _readerImageCacheManager,
        fit: imageFit,
        memCacheWidth: memCacheWidth,
        width: _isHorizontalScrollMode ? null : double.infinity,
        height: useFullViewport ? double.infinity : null,
        imageBuilder: (_, imageProvider) {
          _clearImageRetryState(key);
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
          final attempts = _imageRetryCounts[key] ?? 0;
          final retryLimit = _user.imageRetryCount;
          final canAutoRetry = attempts < retryLimit;
          if (canAutoRetry) {
            _scheduleImageRetry(key);
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
                      onPressed: () => _retryImage(chapter, localIndex, key),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('重新加载'),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      onPressed: () => _copyImageUrl(chapter, localIndex),
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

  /// 计算滚动模式下某章某页对应的列表 item 索引。
  /// 布局：header(可选) + 每章[divider + images]。
  int _scrollItemIndexFor({
    required int chainIndex,
    required int page,
    required bool hasHeader,
  }) {
    // 布局：header(可选) + 各章[图片 + 分隔(非末章)] + tail/loadMore
    // 目标章之前每章贡献：图片数 + 1 个分隔
    var idx = hasHeader ? 1 : 0;
    for (var ci = 0; ci < chainIndex; ci++) {
      idx += _chain[ci].contents.length + 1;
    }
    idx += (page - 1);
    return idx;
  }

  void _jumpToScrollPage(int page, {int? totalPages}) {
    if (!_itemScrollController.isAttached) return;
    final imageCount = totalPages ?? _detail?.contents.length ?? 0;
    if (imageCount <= 0) return;
    final clampedPage = page.clamp(1, imageCount);
    int targetIndex;
    if (_continuousReading) {
      targetIndex = _scrollItemIndexFor(
        chainIndex: _chainIndex,
        page: clampedPage,
        hasHeader: _chain.first.prev == null,
      );
    } else {
      final hasHeader = _detail?.prev == null;
      targetIndex = (hasHeader ? 1 : 0) + (clampedPage - 1);
    }
    _itemScrollController.jumpTo(index: targetIndex);
  }

  void _onItemPositionsChanged() {
    if (!mounted || _detail == null || _isDraggingSlider) return;
    if (_isPageMode) return;

    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    if (_continuousReading) {
      _onItemPositionsChangedContinuous(positions);
      return;
    }

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

  /// 连续阅读滚动模式：根据 item 索引解析所属章节与章内页码，更新导航栏与历史。
  void _onItemPositionsChangedContinuous(Iterable<ItemPosition> positions) {
    // 计算各章在列表中的图片起始 item 索引
    final firstChapter = _chain.first;
    final hasHeader = firstChapter.prev == null;
    var cursor = hasHeader ? 1 : 0;
    final starts = <int>[];
    for (final chapter in _chain) {
      starts.add(cursor);
      cursor += chapter.contents.length + 1; // 图片 + 末尾分隔/tail
    }
    // 找到可见面积最大的图片 item
    int? bestChapterIndex;
    int? bestLocalIndex;
    double bestVisible = -1;
    for (final p in positions) {
      for (var ci = 0; ci < _chain.length; ci++) {
        final s = starts[ci];
        final count = _chain[ci].contents.length;
        if (p.index >= s && p.index < s + count) {
          final top = p.itemLeadingEdge.clamp(0.0, 1.0);
          final bottom = p.itemTrailingEdge.clamp(0.0, 1.0);
          final visible = bottom - top;
          if (visible > bestVisible) {
            bestVisible = visible;
            bestChapterIndex = ci;
            bestLocalIndex = p.index - s;
          }
          break;
        }
      }
    }
    if (bestChapterIndex == null || bestLocalIndex == null) return;
    final chapterChanged = _syncActiveChapterFromGlobal(bestChapterIndex);
    final page = bestLocalIndex + 1;
    if (page == _currentPage && !chapterChanged) return;
    setState(() => _currentPage = page);
    _saveReadingHistory();
    _preloadChainImages(bestChapterIndex, bestLocalIndex);
    if (chapterChanged) _preloadComments();
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

  /// 滚动模式：已无上/下一话时，继续同方向滚动则返回详情页。
  bool _shouldScrollBackToDetail(ScrollNotification notification) {
    if (_detail == null || _loading || _autoAdvancingChapter) return false;

    final hasHeader = _detail!.prev == null;
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return false;

    // 已无下一话：tail 已完全可见且继续向下/向右滚动
    if (_detail!.next == null) {
      final tailIndex = (hasHeader ? 1 : 0) + _detail!.contents.length;
      var tailFullyVisible = false;
      for (final p in positions) {
        if (p.index != tailIndex) continue;
        tailFullyVisible =
            p.itemLeadingEdge >= -0.05 && p.itemTrailingEdge <= 1.05;
        break;
      }
      if (!tailFullyVisible) return false;
      if (notification is ScrollUpdateNotification) {
        return (notification.scrollDelta ?? 0) > 0;
      }
      if (notification is OverscrollNotification) {
        return notification.overscroll > 0;
      }
    }

    // 已无上一话：header 已完全可见且继续向上/向左滚动
    if (hasHeader) {
      var headFullyVisible = false;
      for (final p in positions) {
        if (p.index != 0) continue;
        headFullyVisible =
            p.itemLeadingEdge >= -0.05 && p.itemTrailingEdge <= 1.05;
        break;
      }
      if (!headFullyVisible) return false;
      if (notification is ScrollUpdateNotification) {
        return (notification.scrollDelta ?? 0) < 0;
      }
      if (notification is OverscrollNotification) {
        return notification.overscroll < 0;
      }
    }

    return false;
  }

  void _autoAdvanceToNextChapter() {
    final nextUuid = _detail?.next;
    if (nextUuid == null || _autoAdvancingChapter) return;
    _autoAdvancingChapter = true;
    _goChapter(nextUuid);
  }

  /// 翻页模式：用户滑到开头/结尾空白页时，执行跨章跳转。
  void _handlePageModeBlankPage(bool isEndBlank) {
    if (_detail == null || _autoAdvancingChapter) return;
    _autoAdvancingChapter = true;
    if (isEndBlank) {
      if (_detail!.next != null) {
        _goChapter(_detail!.next);
      } else {
        showToast(context, '当前已无下一话');
        Navigator.pop(context);
      }
    } else {
      if (_detail!.prev != null) {
        _goChapter(_detail!.prev);
      } else {
        showToast(context, '当前已无上一话');
        Navigator.pop(context);
      }
    }
  }

  Widget _buildScrollMode() {
    final firstChapter = _chain.first;
    final hasHeader = firstChapter.prev == null;
    final scrollDirection = _isHorizontalScrollMode
        ? Axis.horizontal
        : Axis.vertical;
    final viewportSize = MediaQuery.sizeOf(context);

    // 连续阅读：将链中各章图片依次拼接，每话末尾追加操作按钮（目录/评论）。
    // 最后一话末尾用 tail（无下一话）或 loadMore（有下一话）替换，两者自带按钮。
    // 非连续阅读：沿用原有 header + 单章图片 + tail 结构。
    final List<_ScrollItem> items = [];
    if (hasHeader) items.add(_ScrollItem.header());
    if (_continuousReading) {
      for (var ci = 0; ci < _chain.length; ci++) {
        final chapter = _chain[ci];
        final start = _chainChapterStart(ci);
        for (var i = 0; i < chapter.contents.length; i++) {
          items.add(_ScrollItem.image(chapter, i, start + i));
        }
        final isLast = ci == _chain.length - 1;
        if (isLast) {
          // 链尾用 tail / loadMore（自带目录/评论/下一章按钮）
          final lastChapter = _chain.last;
          if (lastChapter.next == null) {
            items.add(_ScrollItem.tail());
          } else {
            items.add(_ScrollItem.loadMore());
          }
        } else {
          // 其他话末尾放操作按钮
          items.add(_ScrollItem.chapterDivider(chapter));
        }
      }
    } else {
      final chapter = _detail!;
      final start = 0;
      for (var i = 0; i < chapter.contents.length; i++) {
        items.add(_ScrollItem.image(chapter, i, start + i));
      }
      items.add(_ScrollItem.tail());
    }
    final totalItems = items.length;

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
              SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
              setState(() => _showToolbar = false);
            }
            if (_continuousReading) {
              _maybeAppendNextChainOnScroll();
            } else {
              if (_shouldAutoAdvanceScrollChapter(n)) {
                _autoAdvanceToNextChapter();
              }
              if (_shouldScrollBackToDetail(n)) {
                Navigator.pop(context);
              }
            }
            return false;
          },
          child: ScrollablePositionedList.separated(
            key: ValueKey(
              _continuousReading
                  ? 'scroll-continuous-$_scrollWidgetVersion'
                  : '$_currentUuid-$_scrollWidgetVersion',
            ),
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
              final item = items[i];
              if (item.kind == _ScrollItemKind.image) {
                return _isHorizontalScrollMode
                    ? SizedBox(width: _user.readerImageGap)
                    : SizedBox(height: _user.readerImageGap);
              }
              return const SizedBox.shrink();
            },
            itemBuilder: (_, i) {
              final item = items[i];
              switch (item.kind) {
                case _ScrollItemKind.header:
                  return _buildFirstChapterHead();
                case _ScrollItemKind.chapterDivider:
                  return _buildChapterDivider(item.chapter!);
                case _ScrollItemKind.image:
                  final image = _buildReaderImageGesture(
                    item.chapter!,
                    item.localIndex!,
                    retryKey: item.globalIndex,
                  );
                  if (_isHorizontalScrollMode) {
                    return SizedBox(height: viewportSize.height, child: image);
                  }
                  return image;
                case _ScrollItemKind.tail:
                  return _buildNextChapterTail();
                case _ScrollItemKind.loadMore:
                  return _buildLoadMoreTail();
              }
            },
          ),
        ),
      ),
    );
  }

  /// 连续阅读滚动模式：当链尾章节最后两张图片之一进入视口且有下一话时，
  /// 提前异步追加下一话，使用户滑到底部时下一话图片已就绪，无需等待。
  void _maybeAppendNextChainOnScroll() {
    if (_loadingNextChainChapter) return;
    final lastChapter = _chain.last;
    if (lastChapter.next == null) return;
    if (lastChapter.contents.length < 2) {
      // 章节图片过少：loadMore 进入视口即触发
      final positions = _itemPositionsListener.itemPositions.value;
      for (final p in positions) {
        if (p.index >= _scrollItemCount - 1 &&
            p.itemLeadingEdge < 1.0 &&
            p.itemTrailingEdge > 0) {
          _appendNextChapterToChain();
          return;
        }
      }
      return;
    }
    // 链尾章节最后两张图片的 item 索引
    final hasHeader = _chain.first.prev == null;
    final lastImageIndex = _scrollItemIndexFor(
      chainIndex: _chain.length - 1,
      page: lastChapter.contents.length,
      hasHeader: hasHeader,
    );
    final triggerIndex = lastImageIndex - 1; // 倒数第二张
    final positions = _itemPositionsListener.itemPositions.value;
    for (final p in positions) {
      if ((p.index == triggerIndex || p.index == lastImageIndex) &&
          p.itemLeadingEdge < 1.0 &&
          p.itemTrailingEdge > 0) {
        _appendNextChapterToChain();
        return;
      }
    }
  }

  Widget _buildChapterDivider(ChapterDetail chapter) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [_buildChapterDividerActions(chapter)],
      ),
    );
    if (_isHorizontalScrollMode) {
      return SizedBox(width: _scrollModeTailExtent(context), child: content);
    }
    return ColoredBox(color: Colors.black, child: content);
  }

  /// 章节分隔区的操作按钮：目录、评论（针对该章）。
  Widget _buildChapterDividerActions(ChapterDetail chapter) {
    final buttonStyle = OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
      backgroundColor: Colors.white.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
    final commentCount = _commentCountFor(chapter);
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
          onPressed: () => _showChapterComments(chapter: chapter),
          icon: const Icon(Icons.forum_outlined),
          label: Text(commentCount > 0 ? '$commentCount' : '评论'),
          style: buttonStyle,
        ),
      ],
    );
  }

  Widget _buildLoadMoreTail() {
    final cs = Theme.of(context).colorScheme;
    final chapter = _chain.last;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_loadingNextChainChapter)
              const CircularProgressIndicator(strokeWidth: 2)
            else
              Icon(Icons.expand_more, color: cs.onSurfaceVariant, size: 32),
            const SizedBox(height: 8),
            Text(
              _loadingNextChainChapter ? '正在加载下一话…' : '继续滚动加载下一话',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 16),
            _buildChapterDividerActions(chapter),
          ],
        ),
      ),
    );
    return ColoredBox(
      color: Colors.black,
      child: SizedBox(
        width: _isHorizontalScrollMode ? _scrollModeTailExtent(context) : null,
        height: _isHorizontalScrollMode
            ? null
            : _scrollModeTailExtent(context) * 0.6,
        child: Align(alignment: Alignment.topCenter, child: content),
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
            label: const Text('下一话'),
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
      side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
      backgroundColor: Colors.white.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
    final primaryButtonStyle = FilledButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: Colors.white.withValues(alpha: 0.18),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );

    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 12, 32, 16),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
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
                      label: Text(
                        _commentCount > 0 ? '$_commentCount' : '评论',
                      ),
                      style: buttonStyle,
                    ),
                    if (hasNext)
                      FilledButton.icon(
                        onPressed: () => _goChapter(nextUuid),
                        icon: const Icon(Icons.skip_next),
                        label: const Text('下一话'),
                        style: primaryButtonStyle,
                      ),
                  ],
                ),
                if (hasNext)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '继续翻页进入下一话',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
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
            _detail?.next != null ? '继续下滑或点击按钮进入下一话' : '已经是最后一话',
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

  Future<void> _showChapterComments({ChapterDetail? chapter}) async {
    final detail = chapter ?? _detail;
    if (detail == null) return;

    // 打开评论面板期间暂停自动滚动，与设置面板保持一致
    _pauseAutoScrollForOverlay();
    final useCachedComments = _hasCommentCacheFor(detail.uuid);
    final initialComments = detail.isDownloaded
        ? detail.comments
        : (useCachedComments ? _cachedCommentsFor(detail.uuid) : null);
    final initialTotal = detail.isDownloaded
        ? detail.commentTotal
        : (useCachedComments ? _cachedCommentTotalFor(detail.uuid) : null);

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
      _toggleToolbar();
    }
  }

  /// 拖动位移是否代表"向下一页前进"。
  /// 左到右: 向左拖前进; 右到左: 向右拖前进; 垂直: 向上拖前进（与 PageView 一致）。
  bool _instantTurnForward(double delta) {
    if (_isVerticalPageMode) return delta < 0;
    final rtl = _user.readerScrollDirection == 1;
    return rtl ? delta > 0 : delta < 0;
  }

  void _onInstantTurnDragStart(DragStartDetails details) {
    _instantTurnDragDelta = 0;
    _instantTurnCommitted = false;
  }

  void _onInstantTurnDragUpdate(DragUpdateDetails details) {
    if (_instantTurnCommitted || _detail == null) return;
    _instantTurnDragDelta += _isVerticalPageMode
        ? details.delta.dy
        : details.delta.dx;
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
    final instantTurn = _user.readerInstantPageTurn;
    final horizontalDrag = instantTurn && !_isVerticalPageMode;
    final verticalDrag = instantTurn && _isVerticalPageMode;
    final totalChapters = _chainImageCount;
    final isContinuous = _continuousReading;
    final imageCount = _detail!.contents.length;
    final itemCount = isContinuous ? totalChapters : imageCount + 2;
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
      child: PageView.builder(
        // 连续阅读：章切换不重建 PageView，避免丢位置；用稳定 key。
        key: ValueKey(
          isContinuous
              ? 'page-continuous-$_scrollWidgetVersion'
              : 'page-$_currentUuid',
        ),
        controller: _pageController,
        scrollDirection: _isVerticalPageMode ? Axis.vertical : Axis.horizontal,
        reverse: !_isVerticalPageMode && _user.readerScrollDirection == 1,
        allowImplicitScrolling: true,
        physics: instantTurn ? const NeverScrollableScrollPhysics() : null,
        itemCount: itemCount,
        onPageChanged: (index) {
          if (!isContinuous) {
            if (index == 0) {
              _handlePageModeBlankPage(false);
              return;
            }
            if (index == imageCount + 1) {
              _handlePageModeBlankPage(true);
              return;
            }
          }
          if (isContinuous) {
            final (ci, li) = _resolveChainImage(index);
            final chapterChanged = _syncActiveChapterFromGlobal(ci);
            setState(() {
              _currentPage = li + 1;
              if (!_isDraggingSlider) {
                _showToolbar = false;
                SystemChrome.setEnabledSystemUIMode(
                  SystemUiMode.immersiveSticky,
                );
              }
            });
            _saveReadingHistory();
            _preloadChainImages(ci, li);
            // 接近链尾且有下一话：预加载下一话到链中，翻页时即可无缝衔接
            if (ci == _chain.length - 1 &&
                li >= _chain.last.contents.length - 2 &&
                _chain.last.next != null &&
                !_loadingNextChainChapter) {
              _appendNextChapterToChain();
            }
            if (chapterChanged) {
              _preloadComments();
            }
            return;
          }
          setState(() {
            _currentPage = index;
            if (!_isDraggingSlider) {
              _showToolbar = false;
              SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
            }
          });
          _saveReadingHistory();
          _preloadImages(index - 1);
        },
        itemBuilder: (_, i) {
          if (!isContinuous) {
            if (i == 0 || i == imageCount + 1) {
              return const SizedBox.expand();
            }
            final imageIndex = i - 1;
            if (imageIndex < imageCount - 1) {
              return Center(
                child: _buildReaderImageGesture(_detail!, imageIndex),
              );
            }
            return Column(
              children: [
                Expanded(child: Center(child: _buildReaderImageGesture(_detail!, imageIndex))),
                _buildPageModeEndActions(),
              ],
            );
          }
          // 连续阅读：按全局索引解析章节与章内索引
          final (ci, li) = _resolveChainImage(i);
          final chapter = _chain[ci];
          // 每章末页均显示底部操作（目录/评论/下一章），便于随时切换。
          final isChapterLastPage = li == chapter.contents.length - 1;
          final child = Center(
            child: _buildReaderImageGesture(chapter, li, retryKey: i),
          );
          if (isChapterLastPage) {
            return Column(children: [Expanded(child: child), _buildPageModeEndActions()]);
          }
          return child;
        },
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
                                  final globalIndex = _continuousReading
                                      ? _chainChapterStart(_chainIndex) +
                                            (page - 1)
                                      : page;
                                  _pageController.jumpToPage(globalIndex);
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
                                ? (_autoScrollActive ? '暂停自动滚动' : '自动滚动即将恢复')
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
                            onPressed: () =>
                                _setAutoScroll(!_autoScrollEnabled),
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
                          tooltip: '下一话',
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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _showToolbar
          ? const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
              statusBarBrightness: Brightness.dark,
              systemNavigationBarColor: Colors.black,
              systemNavigationBarIconBrightness: Brightness.light,
            )
          : const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
              statusBarBrightness: Brightness.dark,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarIconBrightness: Brightness.light,
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

enum _ScrollItemKind { header, chapterDivider, image, tail, loadMore }

class _ScrollItem {
  final _ScrollItemKind kind;
  final ChapterDetail? chapter;
  final int? localIndex;
  final int? globalIndex;

  const _ScrollItem._({
    required this.kind,
    this.chapter,
    this.localIndex,
    this.globalIndex,
  });

  factory _ScrollItem.header() =>
      const _ScrollItem._(kind: _ScrollItemKind.header);
  factory _ScrollItem.chapterDivider(ChapterDetail c) =>
      _ScrollItem._(kind: _ScrollItemKind.chapterDivider, chapter: c);
  factory _ScrollItem.image(ChapterDetail c, int local, int global) =>
      _ScrollItem._(
        kind: _ScrollItemKind.image,
        chapter: c,
        localIndex: local,
        globalIndex: global,
      );
  factory _ScrollItem.tail() => const _ScrollItem._(kind: _ScrollItemKind.tail);
  factory _ScrollItem.loadMore() =>
      const _ScrollItem._(kind: _ScrollItemKind.loadMore);
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
