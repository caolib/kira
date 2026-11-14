import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';

import '../../api/novel/novel_api.dart' show novelErrorMessage;
import '../../l10n/app_localizations.dart';
import '../../models/novel.dart';
import '../../models/user_manager.dart';
import '../../theme/app_spacing.dart';
import '../../theme/reader_chrome.dart';
import '../../utils/adaptive_motion.dart';
import '../../utils/app_logger.dart';
import '../../utils/reader_system_ui.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/error_retry_view.dart';
import '../../widgets/pinch_zoomable.dart';
import '../../widgets/settings_section.dart';
import '../reader/reader_image_viewer.dart';
import '../reader/reader_long_press_zoom.dart';

/// A scrollable or paged gallery, deliberately independent of reader
/// navigation, text anchors and persisted reading progress.
///
/// Reuses the manga reader's viewing gestures (pinch zoom, one-finger pan while
/// zoomed, long-press magnifier, double-tap viewer) without any manga-only
/// chrome such as comments, chapter navigation, bookmarks or history.
class NovelReaderIllustrations extends StatefulWidget {
  NovelReaderIllustrations({
    super.key,
    required this.volumeName,
    required this.illustrations,
    required this.loadBytes,
    this.onClosed,
  }) : assert(illustrations.isNotEmpty);

  final String volumeName;
  final List<NovelContentEntry> illustrations;

  /// The novel API's credential-free content client, not the manga image client.
  final Future<List<int>> Function(String url) loadBytes;

  /// Restores the host reader's existing toolbar/system-bar state on exit.
  /// A contents sheet can omit it to return to its normal visible system bars.
  final VoidCallback? onClosed;

  @override
  State<NovelReaderIllustrations> createState() =>
      _NovelReaderIllustrationsState();
}

class _IllustrationResult {
  const _IllustrationResult({this.bytes, this.aspectRatio, this.error});

  final Uint8List? bytes;
  final double? aspectRatio;
  final Object? error;
}

class _NovelReaderIllustrationsState extends State<NovelReaderIllustrations> {
  /// Matches the manga reader's scroll-mode zoom limit.
  static const _scrollZoomMaxScale = 3.0;
  static const _preloadRadius = 2;

  final _user = UserManager();
  final _systemUi = ReaderSystemUi();
  bool _toolbarVisible = true;
  bool _closed = false;
  bool _userScrolling = false;
  bool _paged = false;
  int _direction = 2;
  bool get _vertical => _direction == 2;
  bool _pageZoomed = false;
  int _currentIndex = 0;
  final _scrollController = ScrollController();
  PageController? _pageController;
  final _galleryKey = GlobalKey();
  final _rowKeys = <int, GlobalKey>{};
  int _lastScrollIndex = 0;
  double _lastScrollOffset = 0;

  /// Scroll-mode viewport zoom: pinching scales the whole list, and once zoomed
  /// a one-finger horizontal drag pans the viewport (vertical drags stay with
  /// the list). The raw pointer listener below drives the pan because the
  /// list's drag gesture wins the arena first.
  final _scrollZoomController = PinchZoomController(
    maxScale: _scrollZoomMaxScale,
  );
  bool _zoomed = false;
  int _scrollTouchFingers = 0;
  VelocityTracker _panVelocityTracker = VelocityTracker.withKind(
    PointerDeviceKind.touch,
  );
  bool _scrollPanGestureActive = false;

  /// Loaded bytes keyed by URL, shared by rows, preloading and the viewer so a
  /// rebuild never refetches an illustration.
  final _images = <String, Future<_IllustrationResult>>{};

  /// Completed data must also be available synchronously when lazy rows are
  /// recreated: a cached Future still starts FutureBuilder in a waiting frame.
  final _loadedImages = <String, _IllustrationResult>{};

  @override
  void initState() {
    super.initState();
    _user.reader.addListener(_onSettingsChanged);
    _systemUi.setToolbarVisible(_toolbarVisible);
    _preloadAround(0);
  }

  @override
  void dispose() {
    _restoreHostUi();
    _user.reader.removeListener(_onSettingsChanged);
    _scrollZoomController.dispose();
    _scrollController.dispose();
    _pageController?.dispose();
    super.dispose();
  }

  void _restoreHostUi() {
    if (_closed) return;
    _closed = true;
    final onClosed = widget.onClosed;
    if (onClosed != null) {
      onClosed();
    } else {
      // This gallery is an overlay of an existing reader, not a new cutout
      // session: do not disable the host reader's immersive window support.
      _systemUi.setToolbarVisible(true);
    }
  }

  void _setToolbarVisible(bool visible) {
    if (_closed || !mounted || _toolbarVisible == visible) return;
    setState(() => _toolbarVisible = visible);
    _systemUi.setToolbarVisible(visible);
  }

  void _toggleToolbar() => _setToolbarVisible(!_toolbarVisible);

  int _visibleIllustration() {
    final gallery = _galleryKey.currentContext?.findRenderObject();
    if (gallery is! RenderBox || !gallery.hasSize) return _currentIndex;
    final origin = gallery.localToGlobal(Offset.zero);
    final center = (_vertical ? gallery.size.height : gallery.size.width) / 2;
    var nearest = _currentIndex;
    var distance = double.infinity;
    for (final entry in _rowKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final position = box.localToGlobal(Offset.zero) - origin;
      final top = _vertical ? position.dy : position.dx;
      final bottom = top + (_vertical ? box.size.height : box.size.width);
      if (top <= center && center < bottom) return entry.key;
      final nextDistance = (center - (top + bottom) / 2).abs();
      if (nextDistance < distance) {
        nearest = entry.key;
        distance = nextDistance;
      }
    }
    return nearest;
  }

  void _setViewingMode(bool paged, int direction) {
    if (_paged == paged && _direction == direction) return;
    final directionChanged = _direction != direction;
    if (!_paged) {
      _currentIndex = _visibleIllustration();
      _lastScrollIndex = _currentIndex;
      _lastScrollOffset = _scrollController.offset;
    }
    _scrollZoomController.reset();
    final oldPageController = _pageController;
    _pageController = paged ? PageController(initialPage: _currentIndex) : null;
    _userScrolling = false;
    _pageZoomed = false;
    setState(() {
      _paged = paged;
      _direction = direction;
    });
    if (!paged && (directionChanged || _currentIndex != _lastScrollIndex)) {
      // Target the current illustration, using the same dimensions as the rows.
      final viewport = MediaQuery.sizeOf(context);
      _lastScrollOffset = 0;
      for (var i = 0; i < _currentIndex; i++) {
        final ratio =
            _loadedImages[widget.illustrations[i].content]?.aspectRatio ?? 1;
        _lastScrollOffset +=
            (_vertical ? viewport.width / ratio : viewport.height * ratio) +
            _user.readerImageGap;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldPageController?.dispose();
      if (!mounted || _paged || !_scrollController.hasClients) return;
      _scrollController.jumpTo(
        _lastScrollOffset.clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        ),
      );
    });
  }

  Future<void> _showSettings() async {
    await showAppSheet<void>(
      context,
      maxHeightFactor: 0.7,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: StatefulBuilder(
        builder: (context, updatePanel) {
          final l10n = AppLocalizations.of(context)!;
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.readerSettingsTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.lg),
                SettingsSection(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SegmentedButton<bool>(
                        key: const ValueKey('novel-illustrations-mode'),
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: false,
                            icon: const Icon(Icons.view_day),
                            label: Text(l10n.readerScrollMode),
                          ),
                          ButtonSegment(
                            value: true,
                            icon: const Icon(Icons.auto_stories),
                            label: Text(l10n.readerPageMode),
                          ),
                        ],
                        selected: {_paged},
                        onSelectionChanged: (values) {
                          _setViewingMode(values.single, _direction);
                          updatePanel(() {});
                        },
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      SegmentedButton<int>(
                        key: const ValueKey('novel-illustrations-direction'),
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: 0,
                            icon: const Icon(Icons.arrow_forward),
                            label: Text(l10n.readerLeftToRight),
                          ),
                          ButtonSegment(
                            value: 1,
                            icon: const Icon(Icons.arrow_back),
                            label: Text(l10n.readerRightToLeft),
                          ),
                          ButtonSegment(
                            value: 2,
                            icon: const Icon(Icons.arrow_downward),
                            label: Text(l10n.readerTopToBottom),
                          ),
                        ],
                        selected: {_direction},
                        onSelectionChanged: (values) {
                          _setViewingMode(_paged, values.single);
                          updatePanel(() {});
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (mounted && !_closed) _systemUi.setToolbarVisible(_toolbarVisible);
  }

  void _handlePageTap(Offset position) {
    if (_toolbarVisible || _pageZoomed) {
      _toggleToolbar();
      return;
    }
    final size = MediaQuery.sizeOf(context);
    final fraction = _vertical
        ? position.dy / size.height
        : position.dx / size.width;
    if (fraction >= 1 / 3 && fraction <= 2 / 3) {
      _toggleToolbar();
      return;
    }
    var forward = fraction > 2 / 3;
    if (_direction == 1) forward = !forward;
    final target = _currentIndex + (forward ? 1 : -1);
    final controller = _pageController;
    if (target < 0 ||
        target >= widget.illustrations.length ||
        controller == null ||
        !controller.hasClients) {
      return;
    }
    unawaited(
      controller.animateToPage(
        target,
        duration: adaptiveDuration(context, const Duration(milliseconds: 300)),
        curve: adaptiveCurve(context, Curves.easeInOut),
      ),
    );
  }

  Widget _buildPages(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: PageView.builder(
          key: ValueKey('novel-illustrations-pages-$_direction'),
          controller: _pageController,
          scrollDirection: _vertical ? Axis.vertical : Axis.horizontal,
          reverse: _direction == 1,
          physics: _pageZoomed ? const NeverScrollableScrollPhysics() : null,
          itemCount: widget.illustrations.length,
          onPageChanged: (index) {
            setState(() {
              _currentIndex = index;
              _pageZoomed = false;
            });
            _setToolbarVisible(false);
            _preloadAround(index);
          },
          itemBuilder: (context, index) => PinchZoomable(
            active: index == _currentIndex,
            onZoomChanged: (zoomed) {
              if (index == _currentIndex && mounted) {
                setState(() => _pageZoomed = zoomed);
              }
            },
            child: ReaderLongPressZoomSurface(
              enabled: _user.reader.longPressZoomEnabled,
              panSensitivity: _user.reader.longPressZoomPanSensitivity,
              contentScrollAxis: _vertical ? Axis.vertical : Axis.horizontal,
              canStart: () => !_pageZoomed,
              child: _IllustrationImage(
                key: ValueKey('novel-illustration-page-$index'),
                entry: widget.illustrations[index],
                initialResult:
                    _loadedImages[widget.illustrations[index].content],
                load: () =>
                    _imageFor(widget.illustrations[index].content ?? ''),
                onRetry: () =>
                    _retry(widget.illustrations[index].content ?? ''),
                onDoubleTap: () => unawaited(_openViewer(index)),
                fitPage: true,
                onTap: _handlePageTap,
              ),
            ),
          ),
        ),
      );

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _userScrolling = true;
    } else if (notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle) {
      _userScrolling = true;
    } else if (notification is ScrollEndNotification) {
      _userScrolling = false;
    }
    if (notification is ScrollUpdateNotification &&
        (notification.scrollDelta ?? 0) != 0 &&
        (_userScrolling || notification.dragDetails != null)) {
      _setToolbarVisible(false);
    }
    return false;
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  Future<_IllustrationResult> _imageFor(String url) {
    return _images.putIfAbsent(url, () => _load(url));
  }

  Future<_IllustrationResult> _load(String url) async {
    if (url.isEmpty) {
      return const _IllustrationResult(
        error: FormatException('Missing illustration URL'),
      );
    }
    try {
      final bytes = Uint8List.fromList(await widget.loadBytes(url));
      // Read encoded dimensions without retaining decoded pixels. The row then
      // keeps its real height even if Flutter evicts its decoded image cache.
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      late final double aspectRatio;
      try {
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        try {
          aspectRatio = descriptor.width / descriptor.height;
        } finally {
          descriptor.dispose();
        }
      } finally {
        buffer.dispose();
      }
      final result = _IllustrationResult(
        bytes: bytes,
        aspectRatio: aspectRatio,
      );
      _loadedImages[url] = result;
      return result;
    } catch (error, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          error,
          stackTrace: stack,
          source: 'novel_reader.illustration',
        ),
      );
      final result = _IllustrationResult(error: error);
      _loadedImages[url] = result;
      return result;
    }
  }

  void _retry(String url) {
    setState(() {
      _images.remove(url);
      _loadedImages.remove(url);
    });
  }

  /// Fetch neighbours ahead of time; failures are rendered by their own row.
  void _preloadAround(int index) {
    for (var i = index - _preloadRadius; i <= index + _preloadRadius; i++) {
      if (i < 0 || i >= widget.illustrations.length) continue;
      final url = widget.illustrations[i].content ?? '';
      if (url.isEmpty) continue;
      unawaited(_imageFor(url));
    }
  }

  Future<void> _openViewer(int index) async {
    final result = await _imageFor(widget.illustrations[index].content ?? '');
    final bytes = result.bytes;
    if (!mounted || bytes == null) return;
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => ReaderImageViewer(
          imageBytes: bytes,
          pageNumber: index + 1,
          pageCount: widget.illustrations.length,
        ),
      ),
    );
    if (!mounted) return;
    // Returning from the viewer preserves this gallery's chrome visibility.
    if (!_closed) _systemUi.setToolbarVisible(_toolbarVisible);
  }

  void _handleScrollPointerPan(PointerMoveEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    if (_scrollTouchFingers != 1 || !_scrollZoomController.zoomed) return;
    // The pinch recognizer may still own the gesture (one finger lifted);
    // let it keep driving the pan to avoid applying the same delta twice.
    if (_scrollZoomController.isScaleGestureActive) return;
    _scrollPanGestureActive = true;
    _panVelocityTracker.addPosition(event.timeStamp, event.position);
    _scrollZoomController.pan(
      _vertical ? Offset(event.delta.dx, 0) : Offset(0, event.delta.dy),
    );
  }

  Widget _buildGallery(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        _scrollTouchFingers++;
        _panVelocityTracker = VelocityTracker.withKind(PointerDeviceKind.touch);
        _scrollPanGestureActive = false;
        _scrollZoomController.stopFling();
      },
      onPointerMove: _handleScrollPointerPan,
      onPointerUp: (event) {
        _scrollTouchFingers--;
        if (_scrollTouchFingers == 0 && _scrollPanGestureActive) {
          _scrollPanGestureActive = false;
          final velocity = _panVelocityTracker.getVelocity().pixelsPerSecond;
          _scrollZoomController.beginFling(
            _vertical ? Offset(velocity.dx, 0) : Offset(0, velocity.dy),
          );
        }
      },
      onPointerCancel: (event) {
        _scrollTouchFingers--;
        _scrollPanGestureActive = false;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleToolbar,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: PinchZoomable(
            controller: _scrollZoomController,
            onZoomChanged: (zoomed) => setState(() => _zoomed = zoomed),
            child: SizedBox.expand(
              key: _galleryKey,
              child: ListView.separated(
                key: const ValueKey('novel-illustrations-list'),
                controller: _scrollController,
                scrollDirection: _vertical ? Axis.vertical : Axis.horizontal,
                reverse: _direction == 1,
                padding: EdgeInsets.zero,
                physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
                itemCount: widget.illustrations.length,
                separatorBuilder: (_, _) => SizedBox(
                  height: _vertical ? _user.readerImageGap : null,
                  width: _vertical ? null : _user.readerImageGap,
                ),
                itemBuilder: (context, index) => SizedBox(
                  key: _rowKeys.putIfAbsent(index, GlobalKey.new),
                  child: _IllustrationImage(
                    key: ValueKey('novel-illustration-$index'),
                    entry: widget.illustrations[index],
                    initialResult:
                        _loadedImages[widget.illustrations[index].content],
                    load: () =>
                        _imageFor(widget.illustrations[index].content ?? ''),
                    onRetry: () =>
                        _retry(widget.illustrations[index].content ?? ''),
                    onDoubleTap: () => unawaited(_openViewer(index)),
                    onTap: (_) => _toggleToolbar(),
                    horizontalScroll: !_vertical,
                  ),
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
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final textTheme = theme.textTheme.apply(
      bodyColor: ReaderChrome.onSurface,
      displayColor: ReaderChrome.onSurface,
    );
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(
          brightness: Brightness.dark,
          surface: ReaderChrome.surface,
          onSurface: ReaderChrome.onSurface,
          onSurfaceVariant: ReaderChrome.onSurfaceMuted,
        ),
        textTheme: textTheme,
      ),
      child: PopScope(
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) _restoreHostUi();
        },
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: _toolbarVisible
              ? ReaderChrome.systemUiToolbar
              : ReaderChrome.systemUiImmersive,
          child: Dialog.fullscreen(
            backgroundColor: ReaderChrome.surface,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Chrome overlays a fixed viewport; showing/hiding it must not
                // resize the list or change the current image's scroll offset.
                if (_paged)
                  _buildPages(context)
                else
                  ReaderLongPressZoomSurface(
                    enabled: _user.reader.longPressZoomEnabled,
                    panSensitivity: _user.reader.longPressZoomPanSensitivity,
                    contentScrollAxis: _vertical
                        ? Axis.vertical
                        : Axis.horizontal,
                    canStart: () => !_scrollZoomController.zoomed,
                    child: _buildGallery(context),
                  ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    ignoring: !_toolbarVisible,
                    child: ExcludeSemantics(
                      excluding: !_toolbarVisible,
                      child: AnimatedSlide(
                        duration: adaptiveDuration(
                          context,
                          const Duration(milliseconds: 200),
                        ),
                        curve: adaptiveCurve(context, Curves.easeOutCubic),
                        offset: Offset(0, _toolbarVisible ? 0 : -1),
                        child: ColoredBox(
                          color: ReaderChrome.surface,
                          child: SafeArea(
                            bottom: false,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                AppSpacing.lg,
                                AppSpacing.sm,
                                AppSpacing.sm,
                                AppSpacing.sm,
                              ),
                              child: Row(
                                children: [
                                  IconButton(
                                    key: const ValueKey(
                                      'novel-illustrations-back',
                                    ),
                                    tooltip: MaterialLocalizations.of(
                                      context,
                                    ).backButtonTooltip,
                                    color: ReaderChrome.onSurface,
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                    icon: const Icon(Icons.arrow_back),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Text(
                                      widget.volumeName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: textTheme.labelMedium?.copyWith(
                                        color: ReaderChrome.onSurfaceMuted,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    key: const ValueKey(
                                      'novel-illustrations-settings',
                                    ),
                                    tooltip: l10n.readerSettingsTitle,
                                    color: ReaderChrome.onSurface,
                                    onPressed: _showSettings,
                                    icon: const Icon(Icons.settings_outlined),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
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
}

class _IllustrationImage extends StatefulWidget {
  const _IllustrationImage({
    super.key,
    required this.entry,
    required this.initialResult,
    required this.load,
    required this.onRetry,
    required this.onDoubleTap,
    this.fitPage = false,
    this.horizontalScroll = false,
    this.onTap,
  });

  final ValueChanged<Offset>? onTap;
  final bool fitPage;
  final bool horizontalScroll;
  final NovelContentEntry entry;
  final _IllustrationResult? initialResult;
  final Future<_IllustrationResult> Function() load;

  /// Drops the shared cache entry so [load] fetches the bytes again.
  final VoidCallback onRetry;
  final VoidCallback onDoubleTap;

  @override
  State<_IllustrationImage> createState() => _IllustrationImageState();
}

class _IllustrationImageState extends State<_IllustrationImage> {
  // Keep unloaded rows non-zero until decoding finishes, so a lazy list does
  // not request every illustration while their intrinsic sizes are unknown.
  Widget _placeholder(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: Center(
      child: ExpressiveLoadingIndicator(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );

  late Future<_IllustrationResult> _image = widget.load();

  @override
  void didUpdateWidget(_IllustrationImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.content != widget.entry.content) {
      _image = widget.load();
    }
  }

  void _retry() {
    widget.onRetry();
    setState(() {
      _image = widget.load();
    });
  }

  Widget _error(BuildContext context, Object? error) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ErrorRetryView(
        icon: Icons.broken_image_outlined,
        message: error == null
            ? l10n.novelReaderImageFailed
            : '${l10n.novelReaderImageFailed}：${novelErrorMessage(error)}',
        onRetry: _retry,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<_IllustrationResult>(
      key: ObjectKey(_image),
      future: _image,
      initialData: widget.initialResult,
      builder: (context, snapshot) {
        final result = snapshot.data;
        if (result == null) return _placeholder(context);
        final bytes = result.bytes;
        if (bytes == null) return _error(context, result.error);
        Offset? tapPosition;
        final image = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: widget.onTap == null
              ? null
              : (details) => tapPosition = details.globalPosition,
          onTap: widget.onTap == null
              ? null
              : () {
                  if (tapPosition != null) widget.onTap!(tapPosition!);
                },
          onDoubleTap: widget.onDoubleTap,
          child: Image.memory(
            bytes,
            width: widget.horizontalScroll ? null : double.infinity,
            height: widget.fitPage || widget.horizontalScroll
                ? double.infinity
                : null,
            fit: widget.fitPage
                ? BoxFit.contain
                : widget.horizontalScroll
                ? BoxFit.fitHeight
                : BoxFit.fitWidth,
            semanticLabel: widget.entry.name.isEmpty
                ? l10n.novelReaderIllustration
                : widget.entry.name,
            frameBuilder: (context, child, frame, synchronous) =>
                synchronous || frame != null
                ? child
                : Center(
                    child: ExpressiveLoadingIndicator(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
            errorBuilder: (context, error, stack) => _error(context, error),
          ),
        );
        if (widget.fitPage) return image;
        // Reserve the real aspect ratio during decoding as well as on every
        // lazy-row rebuild, so scrolling back never changes the row's height.
        return AspectRatio(aspectRatio: result.aspectRatio!, child: image);
      },
    );
  }
}
