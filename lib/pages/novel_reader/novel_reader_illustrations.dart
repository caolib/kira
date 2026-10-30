import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';

import '../../api/novel/novel_api.dart' show novelErrorMessage;
import '../../l10n/app_localizations.dart';
import '../../models/novel.dart';
import '../../models/user_manager.dart';
import '../../theme/app_spacing.dart';
import '../../theme/reader_chrome.dart';
import '../../utils/app_logger.dart';
import '../../widgets/error_retry_view.dart';
import '../../widgets/pinch_zoomable.dart';
import '../reader/reader_image_viewer.dart';
import '../reader/reader_long_press_zoom.dart';

/// A continuous gallery over the contents sheet, deliberately independent of
/// reader navigation, text anchors and persisted reading progress.
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
  }) : assert(illustrations.isNotEmpty);

  final String volumeName;
  final List<NovelContentEntry> illustrations;

  /// The novel API's credential-free content client, not the manga image client.
  final Future<List<int>> Function(String url) loadBytes;

  @override
  State<NovelReaderIllustrations> createState() =>
      _NovelReaderIllustrationsState();
}

class _IllustrationResult {
  const _IllustrationResult({this.bytes, this.error});

  final Uint8List? bytes;
  final Object? error;
}

class _NovelReaderIllustrationsState extends State<NovelReaderIllustrations> {
  /// Matches the manga reader's scroll-mode zoom limit.
  static const _scrollZoomMaxScale = 3.0;
  static const _preloadRadius = 2;

  final _user = UserManager();

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

  @override
  void initState() {
    super.initState();
    _user.reader.addListener(_onSettingsChanged);
    _preloadAround(0);
  }

  @override
  void dispose() {
    _user.reader.removeListener(_onSettingsChanged);
    _scrollZoomController.dispose();
    super.dispose();
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
      return _IllustrationResult(
        bytes: Uint8List.fromList(await widget.loadBytes(url)),
      );
    } catch (error, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          error,
          stackTrace: stack,
          source: 'novel_reader.illustration',
        ),
      );
      return _IllustrationResult(error: error);
    }
  }

  void _retry(String url) {
    setState(() {
      _images.remove(url);
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
    // The viewer enters immersive mode; restore the system bars for the sheet.
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      ),
    );
  }

  void _handleScrollPointerPan(PointerMoveEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    if (_scrollTouchFingers != 1 || !_scrollZoomController.zoomed) return;
    // The pinch recognizer may still own the gesture (one finger lifted);
    // let it keep driving the pan to avoid applying the same delta twice.
    if (_scrollZoomController.isScaleGestureActive) return;
    _scrollPanGestureActive = true;
    _panVelocityTracker.addPosition(event.timeStamp, event.position);
    _scrollZoomController.pan(Offset(event.delta.dx, 0));
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
          _scrollZoomController.beginFling(Offset(velocity.dx, 0));
        }
      },
      onPointerCancel: (event) {
        _scrollTouchFingers--;
        _scrollPanGestureActive = false;
      },
      child: PinchZoomable(
        controller: _scrollZoomController,
        onZoomChanged: (zoomed) => setState(() => _zoomed = zoomed),
        child: ListView.separated(
          key: const ValueKey('novel-illustrations-list'),
          padding: EdgeInsets.zero,
          physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
          itemCount: widget.illustrations.length,
          separatorBuilder: (_, _) => SizedBox(height: _user.readerImageGap),
          itemBuilder: (context, index) => _IllustrationImage(
            key: ValueKey('novel-illustration-$index'),
            entry: widget.illustrations[index],
            load: () => _imageFor(widget.illustrations[index].content ?? ''),
            onRetry: () => _retry(widget.illustrations[index].content ?? ''),
            onDoubleTap: () => unawaited(_openViewer(index)),
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
      child: Dialog.fullscreen(
        backgroundColor: ReaderChrome.surface,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.sm,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: [
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
                      key: const ValueKey('novel-illustrations-close'),
                      tooltip: l10n.closeButton,
                      color: ReaderChrome.onSurface,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ReaderLongPressZoomSurface(
                  enabled: _user.reader.longPressZoomEnabled,
                  panSensitivity: _user.reader.longPressZoomPanSensitivity,
                  contentScrollAxis: Axis.vertical,
                  canStart: () => !_scrollZoomController.zoomed,
                  child: _buildGallery(context),
                ),
              ),
            ],
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
    required this.load,
    required this.onRetry,
    required this.onDoubleTap,
  });

  final NovelContentEntry entry;
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
  static const _placeholder = AspectRatio(
    aspectRatio: 1,
    child: Center(
      child: ExpressiveLoadingIndicator(color: ReaderChrome.onSurface),
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
      future: _image,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _placeholder;
        }
        final bytes = snapshot.data?.bytes;
        if (bytes == null) return _error(context, snapshot.data?.error);
        // Only the loaded image opens the viewer; the retry button keeps its
        // own tap handling without a competing double-tap recognizer.
        return GestureDetector(
          onDoubleTap: widget.onDoubleTap,
          child: Image.memory(
            bytes,
            width: double.infinity,
            fit: BoxFit.fitWidth,
            semanticLabel: widget.entry.name.isEmpty
                ? l10n.novelReaderIllustration
                : widget.entry.name,
            frameBuilder: (context, child, frame, synchronous) =>
                synchronous || frame != null ? child : _placeholder,
            errorBuilder: (context, error, stack) => _error(context, error),
          ),
        );
      },
    );
  }
}
