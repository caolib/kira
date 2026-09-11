import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind, VelocityTracker;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:gal/gal.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../api/ai_api.dart';
import '../api/api_client.dart';
import '../l10n/app_localizations.dart';
import '../models/chapter.dart';
import '../models/chapter_comment.dart';
import '../models/user_manager.dart';
import '../repositories/comic_detail_repository.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/reader_chrome.dart';
import '../utils/adaptive_motion.dart';
import '../utils/app_logger.dart';
import '../utils/bookmark_store.dart';
import '../utils/chapter_summary_cache.dart';
import '../utils/download_manager.dart';
import '../utils/fling_brake_tap_guard.dart';
import '../utils/image_load_stats.dart';
import '../utils/network_error.dart';
import '../utils/reading_history.dart';
import '../utils/reading_stats.dart';
import '../utils/toast.dart';
import '../widgets/image_reveal_hold.dart';
import '../widgets/pinch_zoomable.dart';
import '../widgets/reader_status_overlay.dart';
import 'chapter_comment_display.dart';
import 'chapter_comments_sheet.dart';

part 'reader/reader_auto_scroll.dart';
part 'reader/reader_bottom_bar.dart';
part 'reader/reader_chain.dart';
part 'reader/reader_chapter_data.dart';
part 'reader/reader_chapter_widgets.dart';
part 'reader/reader_comments_data.dart';
part 'reader/reader_image_cache.dart';
part 'reader/reader_image_pipeline.dart';
part 'reader/reader_image_viewer.dart';
part 'reader/reader_page_mode.dart';
part 'reader/reader_scroll_item.dart';
part 'reader/reader_scroll_mode.dart';
part 'reader/reader_settings_panel.dart';
part 'reader/reader_top_bar.dart';
part 'reader/reader_widgets.dart';

/// 阅读统计：图片 URL → 归属（漫画 + 章节）。章节加载时登记，图片网络加载
/// 完成时（`_ReaderImageFileService`）按 URL 反查归属计数。命中缓存不会走到
/// 请求层，天然不计入。每次整章加载时清空重建，长度有界。
final Map<String, ({String pathWord, String chapterUuid})>
_statsImageOwnerByUrl = {};

/// 阅读统计：漫画 pathWord → 漫画名/标签（懒填充），供图片加载埋点复用，
/// 避免埋点时再读一次漫画详情缓存。
final Map<String, ({String name, List<String> tags})> _statsComicMetaByPath =
    {};

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

  /// 滚动模式整视图缩放上限。放大的是整个阅读视图（图片、间隙、分隔条
  /// 一起变），太大会导致可视内容过少，3x 足够看清细节。
  static const _scrollZoomMaxScale = 3.0;
  static CacheManager? _cachedImageManager;
  static int _cachedImageManagerTimeout = -1;

  /// 滚动模式整视图缩放控制器。放大后的单指横向平移由原始指针事件驱动
  /// （见 _handleScrollPointerPan），纵向滚动仍由列表负责；惯性滑行在
  /// 控制器内部实现。
  final _scrollZoomController = PinchZoomController(
    maxScale: _scrollZoomMaxScale,
  );

  /// 滚动模式阅读区当前按下的手指数（含鼠标），供单指平移判定。
  int _scrollTouchFingers = 0;

  /// 放大后单指平移的速度采样：抬手时交给控制器启动惯性滑行。
  /// 每段触摸（按下）重建实例，避免上一段的旧样本混入本段松手速度。
  VelocityTracker _panVelocityTracker = VelocityTracker.withKind(
    PointerDeviceKind.touch,
  );
  bool _scrollPanGestureActive = false;

  final _api = ApiClient();
  final _aiSettings = AiSettings();
  final _aiApi = AiApi();
  final _downloads = DownloadManager();
  final _user = UserManager();
  final _bookmarks = BookmarkStore();
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
  String? _loadError;

  /// extension part 文件里的成员不是 State 子类成员，不能直接调用受保护的
  /// [setState]，统一经由这个转发方法。
  void _setState(VoidCallback fn) => setState(fn);

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

  /// 猛滑后点一下只是给惯性刹车，这种点击不切换工具栏。
  final _flingBrakeGuard = FlingBrakeTapGuard();

  /// 阅读区域（图片、图片间空白）的单击入口。
  void _handleReadingSurfaceTap() {
    if (_flingBrakeGuard.consumeTap()) return;
    _toggleToolbar();
  }

  late String _currentUuid;
  int _currentPage = 1;
  bool _isDraggingSlider = false;
  bool _autoAdvancingChapter = false;

  /// 滚动模式尾部的 item 索引（-1 表示无尾部/有下一话）。
  int _scrollTailIndex = -1;
  // 无动画翻页：拖动过程中的累计位移与是否已翻页标记。
  double _instantTurnDragDelta = 0;
  bool _instantTurnCommitted = false;
  bool _volumeChannelAvailable = true;
  int _scrollModeInitialIndex = 0;
  // 列表因裁剪重建时保留当前可见项在视口中的相对位置，避免突然顶对齐。
  double _scrollModeInitialAlignment = 0.0;
  int _scrollWidgetVersion = 0;

  // 翻页模式：当前页图片处于捏合放大状态。放大期间单指拖动用于平移图片，
  // 需暂时禁用翻页手势（PageView 滑动/无动画翻页拖拽），否则翻页手势会因
  // slop 更小（18px < 36px）抢先接管拖动。
  bool _pageImageZoomed = false;

  // 连续阅读：按阅读顺序拼接的章节链。首项为用户进入时打开的章节。
  // _chainIndex 指向当前"所在章节"（用于导航栏显示与历史记录）。
  // 加载下一话时追加到链尾，不重建视图，从而避免闪屏与状态丢失。
  // 为避免长会话内存与主线程开销无限增长，仅保留「前1后1」窗口：
  // 当前章 + 前一话 + 后一话（最多 3 章）。
  static const int _maxChainChaptersBehind = 1;
  static const int _maxChainChaptersAhead = 1;
  static const int _maxImageNaturalSizes = 120;

  final List<ChapterDetail> _chain = [];
  int _chainIndex = 0;
  bool _loadingNextChainChapter = false;
  bool _loadingPrevChainChapter = false;
  final Map<int, int> _imageReloadVersions = {};
  final Map<int, int> _imageRetryCounts = {};
  final Map<int, String> _imageRetryTokens = {};

  // 图片原始尺寸缓存：key 为图片 URL / 本地路径。
  // 用于在竖向滚动模式下为占位符和错误 Widget 提供与真实图片一致的预估高度，
  // 避免 placeholder → 真图尺寸不同导致的页面跳动。
  // Map 保持插入序，超限时淘汰最早写入的项。
  final Map<String, Size> _imageNaturalSizes = {};

  // 评论缓存按章节 uuid 存放，连续阅读链中各章均可独立缓存，
  // 供分隔区评论按钮显示数量并避免重复打开时重新加载。
  final Map<String, List<ChapterComment>> _commentCache = {};
  final Map<String, int> _commentTotalCache = {};

  // 滚动列表结构缓存：仅在章节链变化时重建，避免每次 setState 全量 new 列表。
  List<_ScrollItem> _scrollItems = const [];
  // 每章第一张图的全局图片索引 / 滚动 item 索引，支持 O(log n) 定位。
  final List<int> _chapterImageStarts = [];
  final List<int> _chapterScrollStarts = [];
  int _cachedChainImageCount = 0;

  bool get _isPageMode => _user.readerMode == 1;
  bool get _isVerticalPageMode =>
      _isPageMode && _user.readerScrollDirection == 2;
  // 状态组件位置：0左上 1顶中 2右上 3右下 4底中 5左下
  bool get _statusOverlayIsTop => _user.reader.statusOverlayPosition < 3;
  bool get _statusOverlayIsLeft =>
      {
        0: true,
        5: true,
        2: false,
        3: false,
      }[_user.reader.statusOverlayPosition] ??
      false;
  // 顶中/底中时水平铺满（left+right 都为 0）。
  bool get _statusOverlayIsCenter =>
      _user.reader.statusOverlayPosition == 1 ||
      _user.reader.statusOverlayPosition == 4;

  /// 状态组件置顶且为竖向滚动模式时，首图上方预留与组件等高的留白，
  /// 避免状态组件遮挡第一页顶部；横滚/翻页/置底/关闭时留白为 0。
  double get _statusOverlayTopInset =>
      (_user.reader.statusOverlay &&
          _statusOverlayIsTop &&
          !_isHorizontalScrollMode &&
          !_isPageMode)
      ? ReaderStatusOverlay.reservedHeight
      : 0.0;
  bool get _isDarkMode => Theme.of(context).brightness == Brightness.dark;
  bool get _isHorizontalScrollMode =>
      !_isPageMode && _user.readerScrollDirection != 2;
  bool get _isReversedScrollMode =>
      !_isPageMode && _user.readerScrollDirection == 1;

  /// 图片加载过渡时长：fadeIn/fadeOut 与过渡撑块的保持时长共用同一个
  /// 值，撑块在占位符淡出结束的同一时刻移除，item 尺寸只回落一次。
  /// 250ms 在保留柔和淡入的同时缩短灰罩停留，尺寸纠正也更及时。
  static const _imageTransitionDuration = Duration(milliseconds: 250);

  /// 过渡期间真图的对齐方向：贴住已读侧边缘（RTL 横向=右缘，
  /// LTR 横向=左缘，竖向=顶缘）。占位尺寸估算失误时，真图与占位区域
  /// 的差值全部落在未读侧，列表跳动只影响尚未阅读的内容。
  Alignment get _imageRevealAlignment {
    if (_isHorizontalScrollMode) {
      return _isReversedScrollMode
          ? Alignment.centerRight
          : Alignment.centerLeft;
    }
    return Alignment.topCenter;
  }

  bool get _continuousReading => _isPageMode || _user.readerContinuousReading;

  bool _isFirstLoad = true;

  @override
  void initState() {
    super.initState();
    _currentUuid = widget.chapterUuid;
    _bookmarks.addListener(_onBookmarksChanged);
    unawaited(_bookmarks.ensureLoaded());
    // 书签入口不传 group：提前读取详情缓存的分组供历史记录回退。
    if (widget.group == null || widget.group!.trim().isEmpty) {
      unawaited(_loadCachedSelectedGroup());
    }
    _itemPositionsListener.itemPositions.addListener(_onItemPositionsChanged);
    // 放大后平移/惯性滑行期间喂给刹车守卫，让紧跟着的点击视为刹车，
    // 否则横向惯性滑动时点击屏幕会误触工具栏（纵向列表惯性已有此处理）。
    _scrollZoomController.addListener(_onScrollZoomControllerChanged);
    // 阅读器读了 readerMode / 滚动方向 / 音量翻页 / 评论预载等一批设置，
    // 此前只靠设置面板手动回调刷新——从其他入口改设置时阅读页不会更新。
    _user.addListener(_onUserSettingsChanged);
    _loadChapter();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _volumeChannel.invokeMethod('enableImmersive').catchError((_) {});
    _volumeChannel.setMethodCallHandler(_handleVolumeMethod);
    _updateVolumeIntercept();
  }

  @override
  void dispose() {
    // 进度保存是防抖的，离开阅读页必须立刻落盘，否则最后几页会丢。
    unawaited(ReadingHistory.flush());
    _setVolumeIntercept(false);
    _volumeChannel.invokeMethod('disableImmersive').catchError((_) {});
    _volumeChannel.setMethodCallHandler(null);
    _bookmarks.removeListener(_onBookmarksChanged);
    _user.removeListener(_onUserSettingsChanged);
    _scrollZoomController.removeListener(_onScrollZoomControllerChanged);
    _itemPositionsListener.itemPositions.removeListener(
      _onItemPositionsChanged,
    );
    _autoScrollGeneration++;
    _autoScrollResumeTimer?.cancel();
    _pageController.dispose();
    _scrollZoomController.dispose();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  /// 详情本地缓存中的选中分组（_comicMetaFromCache 顺带填充），
  /// 供 widget.group 为空时（书签入口）回退使用。
  String? _cachedSelectedGroup;
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
    _rebuildChainStructure();
    if (_isPageMode) {
      final oldController = _pageController;
      final initialIndex = _chainChapterStart(_chainIndex) + (page - 1);
      _pageController = PageController(initialPage: initialIndex);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        oldController.dispose();
      });
    } else {
      // 滚动模式:让 ScrollablePositionedList 带新 initialScrollIndex 重建,保持当前页
      _scrollModeInitialIndex = _scrollItemIndexFor(
        chainIndex: _chainIndex,
        page: page,
      );
      _scrollModeInitialAlignment = 0.0;
      _bumpScrollWidgetVersion();
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
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _showToolbar
          ? ReaderChrome.systemUiToolbar
          : ReaderChrome.systemUiImmersive,
      child: Scaffold(
        backgroundColor: ReaderChrome.surface,
        body: Stack(
          children: [
            if (_loading)
              const Center(child: ExpressiveLoadingIndicator())
            else if (_detail != null)
              _isPageMode ? _buildPageMode() : _buildScrollMode()
            else
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cloud_off,
                        size: 64,
                        color: ReaderChrome.onSurfaceMuted,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        _loadError ??
                            AppLocalizations.of(context)!.loadingFailed,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: ReaderChrome.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          foregroundColor: ReaderChrome.onSurface,
                          backgroundColor: ReaderChrome.actionPrimaryFill,
                        ),
                        onPressed: () => _loadChapter(),
                        child: Text(AppLocalizations.of(context)!.retryButton),
                      ),
                    ],
                  ),
                ),
              ),
            // 状态显示（时间/电量/网络/页码/帧率）：默认关闭，开启后按设置停在六位之一
            if (_user.reader.statusOverlay)
              Positioned(
                top: _statusOverlayIsTop ? 0 : null,
                bottom: _statusOverlayIsTop ? null : 0,
                left: _statusOverlayIsCenter || _statusOverlayIsLeft ? 0 : null,
                right: _statusOverlayIsCenter || !_statusOverlayIsLeft
                    ? 0
                    : null,
                child: _statusOverlayIsCenter
                    ? Align(
                        alignment: _statusOverlayIsTop
                            ? Alignment.topCenter
                            : Alignment.bottomCenter,
                        child: ReaderStatusOverlay(
                          currentPage: _currentPage,
                          totalPages: _detail?.contents.length ?? 0,
                        ),
                      )
                    : ReaderStatusOverlay(
                        currentPage: _currentPage,
                        totalPages: _detail?.contents.length ?? 0,
                      ),
              ),
            _ReaderTopBar(
              showToolbar: _showToolbar,
              chapterName: _detail?.name ?? widget.chapterName,
              slideOffset: _hiddenToolbarSlideOffset,
              onBack: () => Navigator.pop(context),
              isBookmarked: _bookmarks.isBookmarked(_currentUuid, _currentPage),
              onToggleBookmark: _detail == null ? null : _toggleBookmark,
              isRefreshing: _refreshingChapter,
              onRefresh: _detail == null ? null : _refreshChapter,
            ),
            if (_detail != null)
              _ReaderBottomBar(
                showToolbar: _showToolbar,
                currentPage: _currentPage,
                totalPage: _detail!.contents.length,
                hasPrev: _detail!.prev != null,
                hasNext: _detail!.next != null,
                commentCount: _commentCount,
                isPageMode: _isPageMode,
                autoScrollEnabled: _autoScrollEnabled,
                autoScrollActive: _autoScrollActive,
                showAutoScrollButton:
                    !_isPageMode && _user.readerAutoScrollEnabled,
                slideOffset: _hiddenToolbarSlideOffset,
                colorScheme: cs,
                onPageChanged: (page) {
                  setState(() => _currentPage = page);
                  if (_isPageMode) {
                    final globalIndex = _continuousReading
                        ? _chainChapterStart(_chainIndex) + (page - 1)
                        : page;
                    _pageController.jumpToPage(globalIndex);
                  } else {
                    _jumpToScrollPage(
                      page,
                      totalPages: _detail!.contents.length,
                    );
                  }
                },
                onDragStart: () => _isDraggingSlider = true,
                onDragEnd: () => _isDraggingSlider = false,
                onPrevChapter: _detail!.prev != null
                    ? () => _goChapter(_detail!.prev)
                    : null,
                onCatalog: () => Navigator.pop(context),
                onToggleAutoScroll: () => _setAutoScroll(!_autoScrollEnabled),
                onComments: _showChapterComments,
                onSettings: _showSettingsPanel,
                onNextChapter: _detail!.next != null
                    ? () => _goChapter(_detail!.next)
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

// ── 设置面板 ──
