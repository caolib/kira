import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/adaptive_motion.dart';

/// [imageScale] applies to the image only; captions and the frame stay fixed.
typedef CrossfadeCarouselItemBuilder =
    Widget Function(BuildContext context, int index, double imageScale);

/// An endless, fixed-frame carousel with interruptible, drag-driven crossfades.
class CrossfadeCarousel extends StatefulWidget {
  const CrossfadeCarousel({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.onPageChanged,
    this.interval = const Duration(seconds: 5),
    this.duration = const Duration(milliseconds: 320),
  }) : assert(itemCount >= 0),
       assert(interval > Duration.zero),
       assert(duration >= Duration.zero);

  final int itemCount;
  final CrossfadeCarouselItemBuilder itemBuilder;
  final ValueChanged<int>? onPageChanged;
  final Duration interval;
  final Duration duration;

  @override
  State<CrossfadeCarousel> createState() => _CrossfadeCarouselState();
}

class _CrossfadeCarouselState extends State<CrossfadeCarousel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _transition;
  Timer? _timer;
  int _page = 0;
  double _width = 1;
  double _dragOffset = 0;
  double _destination = 0;
  bool _dragging = false;
  bool _settling = false;
  bool _reducedMotion = false;
  bool _tickerEnabled = true;

  @override
  void initState() {
    super.initState();
    _transition = AnimationController(
      vsync: this,
      lowerBound: -1,
      value: 0,
      duration: widget.duration,
      animationBehavior: AnimationBehavior.preserve,
    )..addStatusListener(_onAnimationStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = prefersReducedMotion(context);
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    if (_reducedMotion || !_tickerEnabled) {
      _transition.stop();
      _finish(_transition.value.round());
    } else {
      _restartTimer();
    }
  }

  @override
  void didUpdateWidget(covariant CrossfadeCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _transition.duration = widget.duration;
    if (oldWidget.itemCount != widget.itemCount) {
      _transition.stop();
      _page = 0;
      _settling = _dragging = false;
      _dragOffset = 0;
      _transition.value = 0;
      _notifyPageChanged();
      _restartTimer();
    } else if (oldWidget.interval != widget.interval) {
      _restartTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _transition.dispose();
    super.dispose();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (!mounted ||
        widget.itemCount <= 1 ||
        _reducedMotion ||
        !_tickerEnabled ||
        _dragging ||
        _settling) {
      return;
    }
    _timer = Timer(widget.interval, () => _settle(1));
  }

  void _notifyPageChanged() {
    final page = _page;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _page == page) widget.onPageChanged?.call(page);
    });
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (_settling &&
        (status == AnimationStatus.completed ||
            status == AnimationStatus.dismissed)) {
      _finish(_destination.round());
    }
  }

  void _finish(int step) {
    final changed = step != 0 && widget.itemCount > 1;
    setState(() {
      if (changed) _page = (_page + step) % widget.itemCount;
      _settling = _dragging = false;
      _dragOffset = 0;
      _transition.value = 0;
    });
    if (changed) _notifyPageChanged();
    _restartTimer();
  }

  void _settle(double destination) {
    _timer?.cancel();
    _destination = destination;
    final distance = (destination - _transition.value).abs();
    if (_reducedMotion ||
        widget.duration == Duration.zero ||
        distance < 0.001) {
      _finish(destination.round());
      return;
    }
    _settling = true;
    _transition.animateTo(
      destination,
      duration: widget.duration * distance,
      curve: Curves.easeOutCubic,
    );
  }

  void _onDragStart(DragStartDetails details) {
    _timer?.cancel();
    _settling = false;
    _transition.stop();
    _dragging = true;
    _dragOffset = _transition.value;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_dragging) return;
    _dragOffset = (_dragOffset - (details.primaryDelta ?? 0) / _width).clamp(
      -1.0,
      1.0,
    );
    if (!_reducedMotion) _transition.value = _dragOffset;
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_dragging) return;
    _dragging = false;
    final velocity = -(details.primaryVelocity ?? 0);
    final double destination;
    if (velocity.abs() >= 500) {
      destination = _dragOffset == 0 || velocity.sign == _dragOffset.sign
          ? velocity.sign
          : 0;
    } else {
      destination = _dragOffset.abs() >= 0.2 ? _dragOffset.sign : 0;
    }
    _settle(destination);
  }

  void _onDragCancel() {
    if (!_dragging) return;
    _dragging = false;
    _settle(0);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (widget.itemCount <= 1 ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowLeft &&
        key != LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.ignored;
    }
    _transition.stop();
    _finish(_transition.value.round());
    _settle(key == LogicalKeyboardKey.arrowRight ? 1 : -1);
    return KeyEventResult.handled;
  }

  Widget _frame(BuildContext context, int index, double scale, bool active) {
    return IgnorePointer(
      ignoring: !active,
      child: ExcludeFocus(
        excluding: !active,
        child: ExcludeSemantics(
          excluding: !active,
          child: RepaintBoundary(
            key: ValueKey(index),
            child: widget.itemBuilder(context, index, scale),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.itemCount == 0) return const SizedBox.shrink();
    final draggable = widget.itemCount > 1;
    return Focus(
      canRequestFocus: draggable,
      onKeyEvent: _onKeyEvent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: draggable ? _onDragStart : null,
        onHorizontalDragUpdate: draggable ? _onDragUpdate : null,
        onHorizontalDragEnd: draggable ? _onDragEnd : null,
        onHorizontalDragCancel: draggable ? _onDragCancel : null,
        child: Listener(
          // Accepted drags can receive onEnd on pointer cancellation; retire
          // them before the recognizer can commit a canceled gesture.
          onPointerCancel: (_) => _onDragCancel(),
          child: LayoutBuilder(
            builder: (context, constraints) {
              _width = constraints.maxWidth.isFinite
                  ? constraints.maxWidth.clamp(1.0, double.infinity)
                  : 1;
              return ClipRect(
                child: AnimatedBuilder(
                  animation: _transition,
                  builder: (context, _) {
                    final offset = _transition.value;
                    final progress = offset.abs();
                    final next =
                        (_page + (offset < 0 ? -1 : 1)) % widget.itemCount;
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        // Keep the base opaque so the crossfade never exposes a
                        // dimmed background between two fully opaque pictures.
                        _frame(context, _page, 1, progress < 0.5),
                        if (progress > 0)
                          Opacity(
                            opacity: progress,
                            child: _frame(
                              context,
                              next,
                              1 + 0.02 * (1 - progress),
                              progress >= 0.5,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
