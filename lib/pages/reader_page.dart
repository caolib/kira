import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../api/api_client.dart';
import '../models/chapter.dart';
import '../models/user_manager.dart';
import '../utils/download_manager.dart';
import '../utils/image_load_stats.dart';
import '../utils/toast.dart';
import '../utils/reading_history.dart';
import 'chapter_comments_sheet.dart';

class ReaderPage extends StatefulWidget {
  final String pathWord;
  final String chapterUuid;
  final String chapterName;
  final int initialPage;

  const ReaderPage({
    super.key,
    required this.pathWord,
    required this.chapterUuid,
    required this.chapterName,
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
  final _downloads = DownloadManager();
  final _user = UserManager();
  final _scrollController = ScrollController();
  PageController _pageController = PageController();
  ChapterDetail? _detail;
  bool _loading = true;
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
  bool _jumpingScroll = false;
  bool _isDraggingSlider = false;
  bool _autoAdvancingChapter = false;
  double _pageModeChapterOverscroll = 0;
  bool _volumeChannelAvailable = true;
  final Map<int, int> _imageReloadVersions = {};
  final Map<int, int> _imageRetryCounts = {};
  final Map<int, String> _imageRetryTokens = {};

  bool get _isPageMode => _user.readerMode == 1;
  bool get _isVerticalPageMode => _isPageMode && _user.readerPageVertical;
  bool get _isDarkMode => Theme.of(context).brightness == Brightness.dark;
  bool get _isHorizontalScrollMode =>
      !_isPageMode && _user.readerScrollDirection != 2;
  bool get _isReversedScrollMode =>
      !_isPageMode && _user.readerScrollDirection == 1;

  bool _isFirstLoad = true;

  @override
  void initState() {
    super.initState();
    _currentUuid = widget.chapterUuid;
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
    _scrollController.dispose();
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

  Future<void> _loadChapter() async {
    setState(() => _loading = true);
    try {
      final detail =
          await _downloads.getDownloadedChapterDetail(
            widget.pathWord,
            _currentUuid,
          ) ??
          await _api.getChapterDetail(widget.pathWord, _currentUuid);
      if (detail.contents.isEmpty) {
        throw StateError('Chapter has no readable pages');
      }
      if (!mounted) return;
      // 首次加载且有 initialPage 参数时跳到指定页
      final startPage = _isFirstLoad && widget.initialPage > 1
          ? widget.initialPage.clamp(1, detail.contents.length)
          : 1;
      _isFirstLoad = false;
      setState(() {
        _detail = detail;
        _loading = false;
        _currentPage = startPage;
        _pageModeChapterOverscroll = 0;
        _imageReloadVersions.clear();
        _imageRetryCounts.clear();
        _imageRetryTokens.clear();
      });
      if (_isPageMode) {
        _pageController.dispose();
        _pageController = PageController(initialPage: startPage - 1);
      } else {
        if (startPage > 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _jumpToScrollPage(startPage, totalPages: detail.contents.length);
          });
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(0);
            }
          });
        }
      }
      _autoAdvancingChapter = false;
      _saveReadingHistory();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _preloadImages(startPage - 1);
      });
    } catch (_) {
      _autoAdvancingChapter = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  void _saveReadingHistory() {
    ReadingHistory.save(
      pathWord: widget.pathWord,
      chapterUuid: _currentUuid,
      chapterName: _detail?.name ?? widget.chapterName,
      page: _currentPage,
    );
  }

  void _goChapter(String? uuid) {
    if (uuid == null) return;
    _currentUuid = uuid;
    _loadChapter();
  }

  void _prevPage() {
    if (_detail == null) return;
    if (_currentPage > 1) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
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
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _onSettingsChanged() {
    final page = _currentPage;
    _updateVolumeIntercept();
    setState(() {});
    if (_isPageMode) {
      _pageController.dispose();
      _pageController = PageController(initialPage: page - 1);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _jumpToScrollPage(page);
      });
    }
  }

  void _showSettingsPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      builder: (_) => _ReaderSettingsPanel(onChanged: _onSettingsChanged),
    );
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
        onError: (_, __) {},
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

  double _scrollModeEffectiveMaxExtent(ScrollMetrics metrics) {
    final effectiveMax =
        metrics.maxScrollExtent - _scrollModeTailExtent(context);
    return effectiveMax > 0 ? effectiveMax : metrics.maxScrollExtent;
  }

  void _jumpToScrollPage(int page, {int? totalPages}) {
    if (!_scrollController.hasClients) return;
    final imageCount = totalPages ?? _detail?.contents.length ?? 0;
    if (imageCount <= 0) return;

    final ratio = (page - 1) / imageCount;
    final maxExtent = _scrollModeEffectiveMaxExtent(_scrollController.position);
    _jumpingScroll = true;
    _scrollController.jumpTo(ratio * maxExtent);
    _jumpingScroll = false;
  }

  bool _shouldAutoAdvanceScrollChapter(ScrollNotification notification) {
    if (_detail?.next == null || _loading || _autoAdvancingChapter) {
      return false;
    }

    final reachedBottom =
        notification.metrics.pixels >= notification.metrics.maxScrollExtent - 8;
    if (!reachedBottom) return false;

    if (notification is ScrollUpdateNotification) {
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
    return Offset(_user.readerPageRTL ? offset : -offset, 0);
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
    return GestureDetector(
      onTap: () => _toggleToolbar(),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (_jumpingScroll || _isDraggingSlider) return false;
          if (n is ScrollUpdateNotification &&
              _showToolbar &&
              (n.scrollDelta ?? 0).abs() > 0) {
            SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
            setState(() => _showToolbar = false);
          }
          if (n.metrics.pixels > 0 && n.metrics.maxScrollExtent > 0) {
            final effectiveMax = _scrollModeEffectiveMaxExtent(n.metrics);
            final effectivePixels = n.metrics.pixels
                .clamp(0.0, effectiveMax)
                .toDouble();
            final page = (imageCount * effectivePixels / effectiveMax)
                .ceil()
                .clamp(1, imageCount);
            if (page != _currentPage) {
              setState(() => _currentPage = page);
              _saveReadingHistory();
              _preloadImages(page - 1);
            }
          }
          if (_shouldAutoAdvanceScrollChapter(n)) {
            _autoAdvanceToNextChapter();
          }
          return false;
        },
        child: ListView.separated(
          controller: _scrollController,
          scrollDirection: scrollDirection,
          padding: EdgeInsets.zero,
          reverse: _isReversedScrollMode,
          cacheExtent: _isHorizontalScrollMode
              ? MediaQuery.sizeOf(context).width
              : MediaQuery.sizeOf(context).height,
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
              final image = _buildImage(imageIndex);
              if (_isHorizontalScrollMode) {
                final viewportSize = MediaQuery.sizeOf(context);
                return SizedBox(height: viewportSize.height, child: image);
              }
              return image;
            }
            return _buildNextChapterTail();
          },
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
          label: const Text('评论'),
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
                    label: const Text('评论'),
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

    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width),
      backgroundColor: Colors.transparent,
      builder: (_) => ChapterCommentsSheet(
        chapterUuid: detail.uuid,
        chapterName: detail.name,
        initialComments: detail.isDownloaded ? detail.comments : null,
        initialTotal: detail.isDownloaded ? detail.commentTotal : null,
        hasNextChapter: detail.next != null,
        onNextChapter: detail.next == null
            ? null
            : () {
                Navigator.of(context).maybePop();
                _goChapter(detail.next);
              },
      ),
    );

    if (action == 'back_to_catalog' && mounted) {
      Navigator.of(context).maybePop();
    }
  }

  // ── 翻页模式 ──

  void _handlePageModeTap(TapUpDetails details) {
    if (_isVerticalPageMode) {
      final screenHeight = MediaQuery.of(context).size.height;
      final y = details.globalPosition.dy;
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
    final x = details.globalPosition.dx;
    if (x < screenWidth / 3) {
      _user.readerPageRTL ? _nextPage() : _prevPage();
    } else if (x > screenWidth * 2 / 3) {
      _user.readerPageRTL ? _prevPage() : _nextPage();
    } else {
      setState(() => _showToolbar = !_showToolbar);
    }
  }

  Widget _buildPageMode() {
    final imageCount = _detail!.contents.length;
    return GestureDetector(
      onTapUp: _handlePageModeTap,
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
          reverse: !_isVerticalPageMode && _user.readerPageRTL,
          allowImplicitScrolling: true,
          itemCount: imageCount,
          onPageChanged: (index) {
            setState(() {
              _currentPage = index + 1;
              if (!_isDraggingSlider) {
                _showToolbar = false;
                SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
              }
            });
            _resetPageModeChapterOverscroll();
            _saveReadingHistory();
            _preloadImages(index);
          },
          itemBuilder: (_, i) {
            if (i < imageCount - 1) return Center(child: _buildImage(i));

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
                  Center(child: _buildImage(i)),
                  _buildPageModeEndActions(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ── 工具栏 ──

  Widget _buildTopBar() {
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
                    // 滚动条 Slider
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
                              activeTrackColor: cs.primary,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: cs.primary,
                              overlayColor: cs.primary.withValues(alpha: 0.2),
                            ),
                            child: Slider(
                              value: _currentPage.toDouble(),
                              min: 1,
                              max: total.toDouble(),
                              onChangeStart: (_) {
                                _isDraggingSlider = true;
                                _jumpingScroll = true;
                              },
                              onChangeEnd: (_) {
                                _isDraggingSlider = false;
                                // 延迟恢复，避免 jumpTo 后的惯性通知隐藏工具栏
                                Future.delayed(
                                  const Duration(milliseconds: 100),
                                  () => _jumpingScroll = false,
                                );
                              },
                              onChanged: (v) {
                                final page = v.round();
                                setState(() => _currentPage = page);
                                if (_isPageMode) {
                                  _pageController.jumpToPage(page - 1);
                                } else if (_scrollController.hasClients) {
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
                      children: [
                        TextButton.icon(
                          onPressed: _detail!.prev != null
                              ? () => _goChapter(_detail!.prev)
                              : null,
                          icon: const Icon(Icons.chevron_left),
                          label: const Text('上一章'),
                          style: TextButton.styleFrom(
                            foregroundColor: _detail!.prev != null
                                ? Colors.white
                                : Colors.white38,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.list, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                          tooltip: '目录',
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.forum_outlined,
                            color: Colors.white,
                          ),
                          onPressed: _showChapterComments,
                          tooltip: '章节评论',
                        ),
                        IconButton(
                          icon: const Icon(Icons.settings, color: Colors.white),
                          onPressed: _showSettingsPanel,
                          tooltip: '阅读设置',
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _detail!.next != null
                              ? () => _goChapter(_detail!.next)
                              : null,
                          icon: const Text('下一章'),
                          label: const Icon(Icons.chevron_right),
                          style: TextButton.styleFrom(
                            foregroundColor: _detail!.next != null
                                ? Colors.white
                                : Colors.white38,
                          ),
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
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.transparent,
            ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_detail != null)
              _isPageMode ? _buildPageMode() : _buildScrollMode(),
            _buildTopBar(),
            if (_detail != null) _buildBottomBar(cs),
          ],
        ),
      ),
    );
  }
}

class _ReaderImageFileService extends FileService {
  _ReaderImageFileService(this.timeout)
    : _httpClient = HttpClient()..connectionTimeout = timeout;

  final Duration timeout;
  final HttpClient _httpClient;

  static const _defaultHeaders = {
    'user-agent':
        'Mozilla/5.0 (Linux; Android 12; 23117RK66C Build/V417IR; wv) '
        'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 '
        'Chrome/110.0.5481.154 Mobile Safari/537.36',
    'accept':
        'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
    'x-requested-with': 'com.manga2020.app',
    'sec-fetch-site': 'cross-site',
    'sec-fetch-mode': 'no-cors',
    'sec-fetch-dest': 'image',
    'accept-encoding': 'gzip, deflate',
    'accept-language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
  };

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final stopwatch = Stopwatch()..start();
    final request = await _httpClient.getUrl(Uri.parse(url)).timeout(timeout);
    _defaultHeaders.forEach(request.headers.set);
    headers?.forEach(request.headers.add);

    final response = await request.close().timeout(timeout);
    return _ReaderImageFileServiceResponse(response, timeout, stopwatch);
  }
}

class _ReaderImageFileServiceResponse implements FileServiceResponse {
  static const Map<String, String> _imageExtensions = {
    'image/jpeg': '.jpg',
    'image/png': '.png',
    'image/gif': '.gif',
    'image/webp': '.webp',
    'image/bmp': '.bmp',
    'image/svg+xml': '.svg',
    'image/tiff': '.tiff',
    'image/vnd.microsoft.icon': '.ico',
  };

  _ReaderImageFileServiceResponse(
    this._response,
    this._timeout,
    this._stopwatch,
  );

  final HttpClientResponse _response;
  final Duration _timeout;
  final Stopwatch _stopwatch;
  final DateTime _receivedTime = DateTime.now();
  bool _recorded = false;

  @override
  Stream<List<int>> get content {
    return _response
        .timeout(_timeout)
        .transform(
          StreamTransformer<List<int>, List<int>>.fromHandlers(
            handleDone: (sink) {
              if (!_recorded) {
                _recorded = true;
                _stopwatch.stop();
                ImageLoadStats().record(_stopwatch.elapsed);
              }
              sink.close();
            },
            handleError: (error, stackTrace, sink) {
              _recorded = true;
              sink.addError(error, stackTrace);
            },
          ),
        );
  }

  @override
  int? get contentLength =>
      _response.contentLength >= 0 ? _response.contentLength : null;

  @override
  int get statusCode => _response.statusCode;

  @override
  DateTime get validTill {
    var ageDuration = const Duration(days: 7);
    final controlHeader = _response.headers.value(
      HttpHeaders.cacheControlHeader,
    );
    if (controlHeader != null) {
      final controlSettings = controlHeader.split(',');
      for (final setting in controlSettings) {
        final sanitizedSetting = setting.trim().toLowerCase();
        if (sanitizedSetting == 'no-cache') {
          ageDuration = Duration.zero;
        }
        if (sanitizedSetting.startsWith('max-age=')) {
          final validSeconds =
              int.tryParse(sanitizedSetting.split('=')[1]) ?? 0;
          if (validSeconds > 0) {
            ageDuration = Duration(seconds: validSeconds);
          }
        }
      }
    }

    return _receivedTime.add(ageDuration);
  }

  @override
  String? get eTag => _response.headers.value(HttpHeaders.etagHeader);

  @override
  String get fileExtension {
    final contentTypeHeader = _response.headers.value(
      HttpHeaders.contentTypeHeader,
    );
    if (contentTypeHeader == null) return '';

    try {
      final contentType = ContentType.parse(contentTypeHeader);
      return _imageExtensions[contentType.mimeType] ??
          '.${contentType.subType}';
    } catch (_) {
      return '';
    }
  }
}

// ── 设置面板 ──

class _ReaderSettingsPanel extends StatefulWidget {
  final VoidCallback onChanged;
  const _ReaderSettingsPanel({required this.onChanged});

  @override
  State<_ReaderSettingsPanel> createState() => _ReaderSettingsPanelState();
}

class _ReaderSettingsPanelState extends State<_ReaderSettingsPanel> {
  final _user = UserManager();
  final _stats = ImageLoadStats();
  static const _scrollDirectionLabels = ['左到右', '右到左', '上到下'];

  @override
  void initState() {
    super.initState();
    _stats.addListener(_onStatsChanged);
  }

  @override
  void dispose() {
    _stats.removeListener(_onStatsChanged);
    super.dispose();
  }

  void _onStatsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isPageMode = _user.readerMode == 1;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '阅读设置',
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Text('阅读模式', style: tt.bodyMedium),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                      value: 0,
                      icon: Icon(Icons.view_day),
                      label: Text('滚动'),
                    ),
                    ButtonSegment(
                      value: 1,
                      icon: Icon(Icons.auto_stories),
                      label: Text('翻页'),
                    ),
                  ],
                  selected: {_user.readerMode},
                  onSelectionChanged: (v) {
                    _user.setReaderMode(v.first);
                    setState(() {});
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(height: 16),
              // 图片间距（仅滚动模式）
              if (!isPageMode) ...[
                Text('滚动方向', style: tt.bodyMedium),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(
                        value: 0,
                        icon: Icon(Icons.arrow_forward),
                        label: Text('左到右'),
                      ),
                      ButtonSegment(
                        value: 1,
                        icon: Icon(Icons.arrow_back),
                        label: Text('右到左'),
                      ),
                      ButtonSegment(
                        value: 2,
                        icon: Icon(Icons.arrow_downward),
                        label: Text('上到下'),
                      ),
                    ],
                    selected: {_user.readerScrollDirection},
                    onSelectionChanged: (v) {
                      _user.setReaderScrollDirection(v.first);
                      setState(() {});
                      widget.onChanged();
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('图片间距', style: tt.bodyMedium),
                    const Spacer(),
                    Text(
                      '${_scrollDirectionLabels[_user.readerScrollDirection]} · ${_user.readerImageGap.round()} px',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
                Slider(
                  value: _user.readerImageGap,
                  min: 0,
                  max: 20,
                  divisions: 20,
                  onChanged: (v) {
                    _user.setReaderImageGap(v);
                    setState(() {});
                    widget.onChanged();
                  },
                ),
              ],
              // 翻页设置（仅翻页模式）
              if (isPageMode) ...[
                Text('翻页轴向', style: tt.bodyMedium),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.swap_horiz),
                        label: Text('左右'),
                      ),
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.swap_vert),
                        label: Text('上下'),
                      ),
                    ],
                    selected: {_user.readerPageVertical},
                    onSelectionChanged: (v) {
                      _user.setReaderPageVertical(v.first);
                      setState(() {});
                      widget.onChanged();
                    },
                  ),
                ),
                const SizedBox(height: 8),
                if (!_user.readerPageVertical) ...[
                  Text('翻页方向', style: tt.bodyMedium),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          icon: Icon(Icons.arrow_forward),
                          label: Text('左到右'),
                        ),
                        ButtonSegment(
                          value: true,
                          icon: Icon(Icons.arrow_back),
                          label: Text('右到左'),
                        ),
                      ],
                      selected: {_user.readerPageRTL},
                      onSelectionChanged: (v) {
                        _user.setReaderPageRTL(v.first);
                        setState(() {});
                        widget.onChanged();
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                // 音量键翻页
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('音量键翻页'),
                  subtitle: const Text('音量+上一页，音量-下一页'),
                  value: _user.readerVolumeKey,
                  onChanged: (v) {
                    _user.setReaderVolumeKey(v);
                    setState(() {});
                    widget.onChanged();
                  },
                ),
              ],
              // 亮度遮罩（仅深色模式）
              if (isDark) ...[
                Row(
                  children: [
                    const Icon(Icons.brightness_low, size: 18),
                    const SizedBox(width: 8),
                    Text('降低亮度', style: tt.bodyMedium),
                    const Spacer(),
                    Text(
                      '${(_user.readerDimming * 100).round()}%',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
                Slider(
                  value: _user.readerDimming,
                  min: 0,
                  max: 0.7,
                  divisions: 14,
                  onChanged: (v) {
                    _user.setReaderDimming(v);
                    setState(() {});
                    widget.onChanged();
                  },
                ),
              ],
              const SizedBox(height: 8),
              Text(
                '图片加载',
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.timer_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text('超时时间', style: tt.bodyMedium),
                  const Spacer(),
                  Text(
                    '${_user.imageLoadTimeout} s',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              Slider(
                value: _user.imageLoadTimeout.toDouble(),
                min: 3,
                max: 60,
                divisions: 57,
                label: '${_user.imageLoadTimeout} s',
                onChanged: (v) {
                  _user.setImageLoadTimeout(v.round());
                  setState(() {});
                  widget.onChanged();
                },
              ),
              Text(
                '设置太小可能导致图片加载失败，太大可能导致长时间转圈',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              Builder(
                builder: (_) {
                  final avg = _stats.averageMs;
                  final count = _stats.sampleCount;
                  if (avg == null) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '暂无加载记录（阅读图片后此处显示平均耗时供参考）',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '最近10分钟内加载了 $count 张，平均 ${(avg / 1000).toStringAsFixed(1)} s',
                      style: tt.bodySmall?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.refresh, size: 18),
                  const SizedBox(width: 8),
                  Text('重试次数', style: tt.bodyMedium),
                  const Spacer(),
                  Text(
                    _user.imageRetryCount == 0
                        ? '关闭'
                        : '${_user.imageRetryCount} 次',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              Slider(
                value: _user.imageRetryCount.toDouble(),
                min: 0,
                max: 5,
                divisions: 5,
                label: _user.imageRetryCount == 0
                    ? '关闭'
                    : '${_user.imageRetryCount} 次',
                onChanged: (v) {
                  _user.setImageRetryCount(v.round());
                  setState(() {});
                  widget.onChanged();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
