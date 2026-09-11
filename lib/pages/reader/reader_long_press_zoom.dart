import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

enum ReaderLongPressZoomTarget { page, viewport }

ReaderLongPressZoomTarget readerLongPressZoomTargetForMode({
  required bool isPageMode,
}) => isPageMode
    ? ReaderLongPressZoomTarget.page
    : ReaderLongPressZoomTarget.viewport;

/// Keeps slider movement local and commits once when the drag ends, avoiding
/// repeated reader viewport rebuilds while the user is still adjusting it.
class ReaderLongPressZoomSensitivityControl extends StatefulWidget {
  const ReaderLongPressZoomSensitivityControl({
    super.key,
    required this.title,
    required this.value,
    required this.onCommitted,
  });

  final String title;
  final double value;
  final ValueChanged<double> onCommitted;

  @override
  State<ReaderLongPressZoomSensitivityControl> createState() =>
      _ReaderLongPressZoomSensitivityControlState();
}

class _ReaderLongPressZoomSensitivityControlState
    extends State<ReaderLongPressZoomSensitivityControl> {
  late double _value = widget.value;

  @override
  void didUpdateWidget(ReaderLongPressZoomSensitivityControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _value = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = '${_value.toStringAsFixed(1)}×';
    return Padding(
      padding: const EdgeInsets.only(left: 24),
      child: Column(
        children: [
          Row(
            children: [
              Text(widget.title, style: theme.textTheme.bodyMedium),
              const Spacer(),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          Slider(
            value: _value,
            min: 1.0,
            max: 3.0,
            divisions: 8,
            label: label,
            onChanged: (value) => setState(() => _value = value),
            onChangeEnd: widget.onCommitted,
          ),
        ],
      ),
    );
  }
}

/// Adds an optional one-finger magnifier interaction without changing the
/// reader's existing tap and double-tap behavior.
class ReaderLongPressZoomSurface extends StatefulWidget {
  const ReaderLongPressZoomSurface({
    super.key,
    required this.enabled,
    required this.child,
    this.canStart,
    this.onZoomStarted,
    this.onZoomEnded,
    this.holdDuration = const Duration(milliseconds: 250),
    this.zoomScale = 1.75,
    this.panSensitivity = 2.0,
    this.contentScrollAxis,
  });

  final bool enabled;
  final Widget child;
  final bool Function()? canStart;
  final VoidCallback? onZoomStarted;
  final VoidCallback? onZoomEnded;
  final Duration holdDuration;
  final double zoomScale;
  final double panSensitivity;

  /// When set, long press detection stays outside the gesture arena so the
  /// underlying scrollable can keep rendering content along its native axis.
  final Axis? contentScrollAxis;

  @override
  State<ReaderLongPressZoomSurface> createState() =>
      _ReaderLongPressZoomSurfaceState();
}

class _ReaderLongPressZoomSurfaceState extends State<ReaderLongPressZoomSurface>
    with SingleTickerProviderStateMixin {
  var _active = false;
  var _pointerCount = 0;
  var _multitouchDisqualified = false;
  var _focalPoint = Offset.zero;
  var _dragOffset = Offset.zero;
  late final AnimationController _zoomAnimationController;
  Tween<double> _scaleTween = Tween(begin: 1.0, end: 1.0);
  Timer? _holdTimer;
  int? _trackedPointer;
  var _pointerDownPosition = Offset.zero;
  var _blockTapOnRelease = false;

  bool get _usesNativeContentScroll => widget.contentScrollAxis != null;

  double get _scale => _scaleTween.evaluate(_zoomAnimationController);

  @override
  void initState() {
    super.initState();
    _zoomAnimationController = AnimationController(vsync: this, value: 1.0);
  }

  @override
  void didUpdateWidget(ReaderLongPressZoomSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) {
      _finishZoom();
    }
    if (oldWidget.contentScrollAxis != widget.contentScrollAxis) {
      _finishZoom();
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_pointerCount == 0) {
      _multitouchDisqualified = false;
      _blockTapOnRelease = false;
    }
    _pointerCount += 1;
    if (_pointerCount > 1) {
      _multitouchDisqualified = true;
      _holdTimer?.cancel();
      _finishZoom();
      return;
    }
    if (widget.enabled && _usesNativeContentScroll) {
      _trackedPointer = event.pointer;
      _pointerDownPosition = event.localPosition;
      _holdTimer?.cancel();
      _holdTimer = Timer(widget.holdDuration, () {
        if (!mounted ||
            _trackedPointer != event.pointer ||
            _pointerCount != 1 ||
            _multitouchDisqualified) {
          return;
        }
        _startZoom(_pointerDownPosition);
      });
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_usesNativeContentScroll || event.pointer != _trackedPointer) return;
    final offset = event.localPosition - _pointerDownPosition;
    if (!_active) {
      if (offset.distance > kTouchSlop) {
        _holdTimer?.cancel();
      }
      return;
    }
    if (_pointerCount != 1) return;
    final crossAxisOffset = switch (widget.contentScrollAxis) {
      Axis.vertical => Offset(offset.dx, 0),
      Axis.horizontal => Offset(0, offset.dy),
      null => offset,
    };
    if (crossAxisOffset == _dragOffset) return;
    setState(() => _dragOffset = crossAxisOffset);
  }

  void _handlePointerFinished(PointerEvent event) {
    if (event.pointer == _trackedPointer) {
      _trackedPointer = null;
      _holdTimer?.cancel();
    }
    _pointerCount = (_pointerCount - 1).clamp(0, 2);
    _finishZoom();
    if (_pointerCount == 0) {
      _multitouchDisqualified = false;
      scheduleMicrotask(() => _blockTapOnRelease = false);
    }
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    _startZoom(details.localPosition);
  }

  void _startZoom(Offset focalPoint) {
    if (!widget.enabled || _pointerCount != 1 || _multitouchDisqualified) {
      return;
    }
    if (!(widget.canStart?.call() ?? true)) {
      _blockTapOnRelease = _usesNativeContentScroll;
      return;
    }

    setState(() {
      _active = true;
      _focalPoint = focalPoint;
      _dragOffset = Offset.zero;
    });
    _animateScaleTo(widget.zoomScale);
    _blockTapOnRelease = _usesNativeContentScroll;
    widget.onZoomStarted?.call();
  }

  void _handleLongPressMove(LongPressMoveUpdateDetails details) {
    if (!_active || _pointerCount != 1) return;
    setState(() {
      _dragOffset = details.offsetFromOrigin;
    });
  }

  void _finishZoom() {
    _holdTimer?.cancel();
    if (!_active) return;
    setState(() {
      _active = false;
    });
    _animateScaleTo(1.0);
    widget.onZoomEnded?.call();
  }

  void _animateScaleTo(double target) {
    _scaleTween = Tween(begin: _scale, end: target);
    _zoomAnimationController
      ..stop()
      ..value = 0.0
      ..fling(velocity: 0.4);
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    if (_active) {
      widget.onZoomEnded?.call();
    }
    _zoomAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerFinished,
      onPointerCancel: _handlePointerFinished,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: !widget.enabled
            ? const {}
            : _usesNativeContentScroll
            ? {
                _LongPressTapBlockerRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      _LongPressTapBlockerRecognizer
                    >(
                      _LongPressTapBlockerRecognizer.new,
                      (recognizer) =>
                          recognizer.shouldBlockTap = () => _blockTapOnRelease,
                    ),
              }
            : {
                LongPressGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      LongPressGestureRecognizer
                    >(
                      () => LongPressGestureRecognizer(
                        duration: widget.holdDuration,
                      ),
                      (recognizer) {
                        recognizer
                          ..onLongPressStart = _handleLongPressStart
                          ..onLongPressMoveUpdate = _handleLongPressMove
                          ..onLongPressEnd = (_) {
                            _finishZoom();
                          }
                          ..onLongPressCancel = _finishZoom;
                      },
                    ),
              },
        child: LayoutBuilder(
          builder: (context, constraints) => AnimatedBuilder(
            animation: _zoomAnimationController,
            child: widget.child,
            builder: (context, child) {
              final scale = _scale;
              final progress = widget.zoomScale == 1
                  ? 0.0
                  : ((scale - 1) / (widget.zoomScale - 1)).clamp(0.0, 1.0);
              var pan = _dragOffset * widget.panSensitivity * progress;
              pan = _clampPanToViewport(
                pan: pan,
                scale: scale,
                focalPoint: _focalPoint,
                viewportSize: constraints.biggest,
              );
              final matrix = Matrix4.identity()
                ..translateByDouble(pan.dx, pan.dy, 0, 1)
                ..translateByDouble(_focalPoint.dx, _focalPoint.dy, 0, 1)
                ..scaleByDouble(scale, scale, scale, 1)
                ..translateByDouble(-_focalPoint.dx, -_focalPoint.dy, 0, 1);

              return ClipRect(
                child: Transform(
                  key: const ValueKey('reader-long-press-zoom-transform'),
                  transform: matrix,
                  child: child,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Stays pending while the raw long-press detector waits. It only claims a
/// stationary hold on release, preventing a button or image tap without taking
/// the scrollable's main-axis drag away from it.
class _LongPressTapBlockerRecognizer extends OneSequenceGestureRecognizer {
  ValueGetter<bool> shouldBlockTap = () => false;

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent) {
      resolvePointer(
        event.pointer,
        shouldBlockTap()
            ? GestureDisposition.accepted
            : GestureDisposition.rejected,
      );
    } else if (event is PointerCancelEvent) {
      resolvePointer(event.pointer, GestureDisposition.rejected);
    }
    stopTrackingIfPointerNoLongerDown(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'long press tap blocker';
}

Offset _clampPanToViewport({
  required Offset pan,
  required double scale,
  required Offset focalPoint,
  required Size viewportSize,
}) {
  if (!viewportSize.width.isFinite || !viewportSize.height.isFinite) {
    return pan;
  }
  final overflowScale = (scale - 1).clamp(0.0, double.infinity);
  final focalX = focalPoint.dx.clamp(0.0, viewportSize.width);
  final focalY = focalPoint.dy.clamp(0.0, viewportSize.height);
  final minX = -overflowScale * (viewportSize.width - focalX);
  final maxX = overflowScale * focalX;
  final minY = -overflowScale * (viewportSize.height - focalY);
  final maxY = overflowScale * focalY;
  return Offset(pan.dx.clamp(minX, maxX), pan.dy.clamp(minY, maxY));
}
