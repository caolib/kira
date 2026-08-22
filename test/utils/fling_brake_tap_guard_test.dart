import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/fling_brake_tap_guard.dart';

void main() {
  late FlingBrakeTapGuard guard;
  final t0 = DateTime.utc(2026, 1, 1, 12);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  setUp(() => guard = FlingBrakeTapGuard());

  /// 甩动一下：先拖动，抬手后是几帧惯性滚动。
  void fling({int from = 0}) {
    guard.recordScroll(isDrag: true, at: at(from));
    guard.recordScroll(isDrag: false, at: at(from + 16));
    guard.recordScroll(isDrag: false, at: at(from + 32));
  }

  test('tap that stops an in-flight fling is treated as a brake', () {
    fling();
    guard.onPointerDown(at(40));
    expect(guard.consumeTap(), isTrue);
  });

  test('the next tap after a brake toggles normally', () {
    fling();
    guard.onPointerDown(at(40));
    expect(guard.consumeTap(), isTrue);

    guard.onPointerDown(at(600));
    expect(guard.consumeTap(), isFalse);
  });

  test('tap after the fling already settled toggles normally', () {
    fling();
    guard.onPointerDown(at(1000));
    expect(guard.consumeTap(), isFalse);
  });

  test('dragging without releasing into a fling never arms the brake', () {
    guard.recordScroll(isDrag: true, at: at(0));
    guard.recordScroll(isDrag: true, at: at(16));
    guard.onPointerDown(at(30));
    expect(guard.consumeTap(), isFalse);
  });

  test('programmatic scrolling without a preceding drag is ignored', () {
    // 自动滚动、滑块拖动、换章跳转：非拖动滚动且前面没有手指拖动。
    guard.recordScroll(isDrag: false, at: at(0));
    guard.recordScroll(isDrag: false, at: at(16));
    guard.onPointerDown(at(30));
    expect(guard.consumeTap(), isFalse);
  });

  test('auto scrolling long after a drag is ignored', () {
    guard.recordScroll(isDrag: true, at: at(0));
    guard.recordScroll(isDrag: false, at: at(5000));
    guard.onPointerDown(at(5010));
    expect(guard.consumeTap(), isFalse);
  });

  test('a drag started after the pointer went down disarms the brake', () {
    fling();
    guard.onPointerDown(at(40));
    // 按下后手指继续拖动 → 这次触摸不是「点一下刹车」。
    guard.recordScroll(isDrag: true, at: at(60));
    expect(guard.consumeTap(), isFalse);
  });
}
