/// 区分「猛滑之后点一下让页面停住」和「点一下想开控制栏」。
///
/// Flutter 的滚动列表在 pointer-down 那一刻就会 hold 住惯性，
/// 所以刹车这件事根本不需要 `onTap` 参与；那一下点击若再去切换工具栏，
/// 就和用户的手势意图不符。
///
/// 判定放在 pointer-down（而不是 tap 回调）里：图片同时注册了双击手势，
/// 单击回调会被双击超时推迟数百毫秒，用 tap 时刻去比对惯性时间不可靠。
class FlingBrakeTapGuard {
  FlingBrakeTapGuard({
    this.flingTolerance = const Duration(milliseconds: 120),
    this.flingAfterDragWindow = const Duration(seconds: 1),
  });

  /// 按下时刻与最后一次惯性滚动的最大间隔；超过则认为列表本就已经停住。
  final Duration flingTolerance;

  /// 惯性必须紧跟在一次拖动之后才算数，用来排除自动滚动、
  /// 滑块拖动与换章等程序化滚动。
  final Duration flingAfterDragWindow;

  DateTime? _lastDragAt;
  DateTime? _lastFlingAt;
  bool _armed = false;

  /// 记录一次有位移的滚动。[isDrag] 表示手指仍按在屏幕上拖动。
  void recordScroll({required bool isDrag, required DateTime at}) {
    if (isDrag) {
      // 又开始拖动了，说明这一次触摸不是「点一下刹车」。
      _lastDragAt = at;
      _lastFlingAt = null;
      _armed = false;
      return;
    }
    final lastDrag = _lastDragAt;
    if (lastDrag != null && at.difference(lastDrag) < flingAfterDragWindow) {
      _lastFlingAt = at;
    }
  }

  /// 触摸按下：此刻列表若正在惯性滚动，则随后的这次点击只是刹车。
  void onPointerDown(DateTime at) {
    final flingAt = _lastFlingAt;
    _armed = flingAt != null && at.difference(flingAt) <= flingTolerance;
    _lastFlingAt = null;
  }

  /// 这次点击是否只是刹车。消费后失效，紧接着的第二次点击照常生效。
  bool consumeTap() {
    if (!_armed) return false;
    _armed = false;
    return true;
  }
}
