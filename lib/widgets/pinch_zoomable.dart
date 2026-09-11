import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart' show FrictionSimulation;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/widgets.dart';

/// 双指捏合缩放容器：捏合调整 [child] 的视图大小，放大后可平移视野。
///
/// 与 InteractiveViewer 的关键差异在手势竞技场：自定义识别器在第二根手指
/// 落下的瞬间即赢下竞技场。若沿用默认竞技规则，非对称捏合（一根手指基本
/// 不动）时滚动/翻页手势的拖动阈值（18px）先于缩放阈值（36px）生效，捏合
/// 会被识别成滑动。
///
/// 单指手势沿用竞技场默认规则：未放大时输给父级的滚动/翻页手势（拖动阈值
/// 更小）；放大后在无竞争的场景（如翻页模式锁定翻页手势后）自由平移。
/// 单击、双击等手势始终传给子树中的 GestureDetector。
///
/// 缩放被硬夹紧在 [PinchZoomController.minScale]（默认 1，即不小于适配尺寸）
/// 与 [PinchZoomController.maxScale] 之间，平移始终保证子内容覆盖视口，因此
/// scale 回到 1 时视图自动复位，无需回弹动画。
class PinchZoomable extends StatefulWidget {
  const PinchZoomable({
    super.key,
    this.controller,
    this.active = true,
    this.onZoomChanged,
    required this.child,
  });

  /// 缩放状态控制器。不传时内部自建（仅手势驱动）。
  ///
  /// 需要从外部平移/读取缩放状态时必须传入，例如滚动模式：列表的拖动手势
  /// 按总位移赢下所有单指拖动，放大后的横向平移只能用原始指针事件的分量
  /// 调用 [PinchZoomController.pan] 驱动。
  final PinchZoomController? controller;

  /// 是否为当前活跃实例。由 true 变为 false 时自动复位缩放
  /// （例如翻页模式切走当前页后，回到该页不再保留放大状态）。
  final bool active;

  /// 跨过放大阈值时回调，放大/复原各触发一次。
  final ValueChanged<bool>? onZoomChanged;

  final Widget child;

  @override
  State<PinchZoomable> createState() => _PinchZoomableState();
}

/// 第二根手指落下时立即接管手势竞技场的缩放识别器。
class _PinchAwareScaleGestureRecognizer extends ScaleGestureRecognizer {
  /// 手势真正结束（所有指针抬起/取消）时触发。
  ///
  /// 快速双指抬起时 [onEnd] 只会在第一根手指抬起时触发一次，且此时
  /// [ScaleEndDetails.pointerCount] 仍大于 0，因此不能仅凭 [onEnd]
  /// 判断手势结束。
  VoidCallback? onGestureEnded;

  @override
  void addPointer(PointerDownEvent event) {
    // pointerCount 读的是 handleEvent 时才入队的指针队列，此刻本次 down
    // 还未入队：队列非空说明这是第二根（及以上）手指，立即赢下竞技场，
    // 否则非对称捏合会被滚动/翻页拖动手势（18px 阈值）抢先识别成滑动。
    final bool isAdditionalPointer = pointerCount > 0;
    super.addPointer(event);
    if (isAdditionalPointer) {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    super.handleEvent(event);
    // 最后一根指针抬起时队列已清空，无论 onEnd 是否触发（快速多指抬起
    // 只触发一次）都能在此感知手势结束。
    if ((event is PointerUpEvent || event is PointerCancelEvent) &&
        pointerCount == 0) {
      onGestureEnded?.call();
    }
  }
}

/// [PinchZoomable] 的缩放状态：缩放系数、平移量与边界。
///
/// 手势与外部调用（[pan]）共用同一份状态并做同样的边界夹紧。
class PinchZoomController extends ChangeNotifier {
  PinchZoomController({this.minScale = 1.0, this.maxScale = 5.0});

  /// 视为"已放大"的缩放阈值：略大于 1，避免捏合抖动在 1.0 附近反复触发回调。
  static const zoomedThreshold = 1.01;

  /// 惯性滑行摩擦系数：速度每秒衰减为 drag 倍，总滑行距离 ≈ 初速 / ln(1/drag)。
  /// 取 0.052 与系统列表滚动（ClampingScrollPhysics）一致，滑行距离约为
  /// 初速的三分之一；调小滑得更远，调大刹车更急。
  static const flingDrag = 0.052;

  /// 低于该速度（逻辑像素/秒）不启动惯性。
  static const minFlingVelocity = 100.0;

  final double minScale;
  final double maxScale;

  Size _viewportSize = Size.zero;
  double _scale = 1.0;
  Offset _offset = Offset.zero;

  Ticker? _flingTicker;
  FrictionSimulation? _flingSimulation;
  Offset? _flingDirection;
  double _flingLastPosition = 0;

  /// 缩放手势进行中收到的惯性请求（快速双指抬起场景），手势结束后启动。
  Offset? _deferredFlingVelocity;

  double get scale => _scale;
  Offset get offset => _offset;

  bool get zoomed => _scale > zoomedThreshold;

  /// 缩放手势识别器是否正占用当前手势（从起算到所有指针抬起/取消）。
  ///
  /// 由 [PinchZoomable] 维护：外层通过原始指针事件驱动平移等逻辑需要同步
  /// 区分「识别器仍在驱动平移」与「手势已结束」，避免同一帧双份平移。
  /// 不触发 [notifyListeners]，仅供同步读取。
  bool _isScaleGestureActive = false;
  bool get isScaleGestureActive => _isScaleGestureActive;

  Matrix4 get transform => Matrix4.identity()
    ..translateByDouble(_offset.dx, _offset.dy, 0, 1)
    ..scaleByDouble(_scale, _scale, _scale, 1);

  /// 应用一帧手势增量：以焦点为锚点缩放（使焦点下的内容保持原位），
  /// 再叠加焦点位移的平移。由 [PinchZoomable] 内部调用。
  void applyGestureUpdate({
    required double cumulativeScale,
    required Offset focal,
    required Offset focalDelta,
    required double lastCumulativeScale,
  }) {
    final scaleDelta = cumulativeScale / lastCumulativeScale;
    if (scaleDelta > 0 && scaleDelta.isFinite && scaleDelta != 1) {
      final sceneFocal = (focal - _offset) / _scale;
      _scale = (_scale * scaleDelta).clamp(minScale, maxScale);
      _offset = focal - sceneFocal * _scale;
    }
    _offset += focalDelta;
    _clampOffset();
    notifyListeners();
  }

  /// 外部驱动平移（放大后移动视野）。scale 未放大时平移范围为零，
  /// 调用无效果。
  void pan(Offset delta) {
    if (delta == Offset.zero || !zoomed) return;
    _applyPan(delta);
  }

  /// 惯性滑行：沿 [velocity]（逻辑像素/秒）方向按摩擦衰减继续平移。
  /// 顶到边界、速度衰减完毕、再次调用或 [stopFling]/[reset] 时停止；
  /// 未放大时直接忽略。
  ///
  /// [deferred] 为 true 时（缩放手势仍在进行中，例如快速双指抬起时
  /// [onEnd] 先于最后一根手指抬起触发）不立即启动，而是记录速度，
  /// 待手势结束（[endScaleGesture]）后再启动。
  void beginFling(Offset velocity, {bool deferred = false}) {
    if (deferred) {
      _deferredFlingVelocity = velocity;
      return;
    }
    _startFling(velocity);
  }

  /// 通知控制器缩放手势已结束：启动延迟的惯性滑行（若有）。
  /// 由 [PinchZoomable] 在识别器所有指针抬起时调用。
  void endScaleGesture() {
    _isScaleGestureActive = false;
    final velocity = _deferredFlingVelocity;
    if (velocity != null) {
      _deferredFlingVelocity = null;
      _startFling(velocity);
    }
  }

  void _startFling(Offset velocity) {
    final speed = velocity.distance;
    if (speed < minFlingVelocity || !zoomed) return;
    stopFling();
    _flingDirection = velocity / speed;
    _flingSimulation = FrictionSimulation(flingDrag, 0, speed);
    _flingLastPosition = 0;
    _flingTicker = Ticker(_onFlingTick)..start();
  }

  void stopFling() {
    _flingTicker?.stop();
    _flingTicker?.dispose();
    _flingTicker = null;
    _flingSimulation = null;
    _flingDirection = null;
    _deferredFlingVelocity = null;
  }

  void _onFlingTick(Duration elapsed) {
    final simulation = _flingSimulation;
    final direction = _flingDirection;
    if (simulation == null || direction == null) return;
    final t = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final delta = direction * (simulation.x(t) - _flingLastPosition);
    _flingLastPosition = simulation.x(t);
    final before = _offset;
    _applyPan(delta);
    // 顶到边界（本帧有位移但被夹紧）或速度衰减完毕：结束滑行。
    if ((delta != Offset.zero && _offset == before) || simulation.isDone(t)) {
      stopFling();
    }
  }

  void _applyPan(Offset delta) {
    _offset += delta;
    _clampOffset();
    notifyListeners();
  }

  /// 平移夹紧在"子内容始终覆盖视口"的范围内；scale == 1 时范围归零，
  /// 视图自动回到原位。
  void _clampOffset() {
    _offset = Offset(
      _offset.dx.clamp(_viewportSize.width * (1 - _scale), 0.0),
      _offset.dy.clamp(_viewportSize.height * (1 - _scale), 0.0),
    );
  }

  /// 复位到初始状态（未缩放、无平移）。
  void reset() {
    stopFling();
    if (_scale == 1 && _offset == Offset.zero) return;
    _scale = 1;
    _offset = Offset.zero;
    notifyListeners();
  }

  @override
  void dispose() {
    stopFling();
    super.dispose();
  }
}

class _PinchZoomableState extends State<PinchZoomable> {
  PinchZoomController? _internalController;
  PinchZoomController get _controller =>
      widget.controller ?? (_internalController ??= PinchZoomController());

  bool _lastZoomed = false;

  void _handleControllerChanged() {
    if (_controller.zoomed != _lastZoomed) {
      _lastZoomed = _controller.zoomed;
      widget.onZoomChanged?.call(_lastZoomed);
    }
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _lastZoomed = _controller.zoomed;
    _controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant PinchZoomable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      (oldWidget.controller ?? _internalController)?.removeListener(
        _handleControllerChanged,
      );
      _controller.addListener(_handleControllerChanged);
      _lastZoomed = _controller.zoomed;
    }
    if (oldWidget.active && !widget.active) {
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _internalController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _controller._viewportSize = constraints.biggest;
        return ClipRect(
          child: RawGestureDetector(
            gestures: {
              _PinchAwareScaleGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    _PinchAwareScaleGestureRecognizer
                  >(() => _PinchAwareScaleGestureRecognizer(), (instance) {
                    instance
                      ..onStart = _handleScaleStart
                      ..onUpdate = _handleScaleUpdate
                      ..onEnd = _handleScaleEnd
                      ..onGestureEnded = _onScaleGestureEnded;
                  }),
            },
            child: Listener(
              // 新手指按下立即刹停惯性滑行（滚动模式由外层 Listener 处理，
              // 这里兜底覆盖翻页模式等没有外层处理的场景）。
              onPointerDown: (_) => _controller.stopFling(),
              child: Transform(
                transform: _controller.transform,
                child: widget.child,
              ),
            ),
          ),
        );
      },
    );
  }

  /// [ScaleUpdateDetails.scale] 自手势开始累计，保存上一次的累计值
  /// 用于换算本帧的增量缩放。
  double _lastCumulativeScale = 1.0;

  void _handleScaleStart(ScaleStartDetails details) {
    _lastCumulativeScale = 1.0;
    // 手势重新启动（含中途抬指后剩余手指继续拖动，识别器从 accepted
    // 重新回到 started 的重启）时刹停遗留的惯性滑行并丢弃未消费的
    // 速度，避免滑行与新平移叠加抖动；正常松手的惯性不经过这里。
    _controller.stopFling();
    _controller._isScaleGestureActive = true;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    _controller.applyGestureUpdate(
      cumulativeScale: details.scale,
      focal: details.localFocalPoint,
      focalDelta: details.focalPointDelta,
      lastCumulativeScale: _lastCumulativeScale,
    );
    _lastCumulativeScale = details.scale;
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    // 抬指瞬间其余手指可能仍在屏上（识别器随 accepted→started 重启继续
    // 驱动平移），惯性须等手势真正结束再启动，否则滑行与残余手指的操控
    // 叠加出双份移动；且此时 velocity 是抬起那根手指的速度，并非松手速度。
    if (details.pointerCount > 0) {
      _controller.beginFling(details.velocity.pixelsPerSecond, deferred: true);
      return;
    }
    // 放大状态下按松手速度启动惯性滑行（未放大时 beginFling 内部忽略），
    // 与图片查看器的松手手感保持一致。
    _controller.beginFling(details.velocity.pixelsPerSecond);
  }

  void _onScaleGestureEnded() {
    _controller.endScaleGesture();
  }
}
