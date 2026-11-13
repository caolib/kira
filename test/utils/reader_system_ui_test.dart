import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/reader_system_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const cutoutChannel = MethodChannel('io.github.caolib.kira/volume');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(cutoutChannel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    messenger.setMockMethodCallHandler(cutoutChannel, null);
  });

  test('退出立即恢复两项窗口状态，重复释放和迟到显隐不再调用平台', () async {
    final ui = ReaderSystemUi();
    ui.enter();
    ui.setToolbarVisible(false);
    await Future<void>.delayed(Duration.zero);
    expect(calls.map((call) => call.method), [
      'enableImmersive',
      'SystemChrome.setEnabledSystemUIMode',
    ]);
    expect(calls.last.arguments, 'SystemUiMode.immersiveSticky');
    calls.clear();

    ui.restore();
    ui.setToolbarVisible(false);
    ui.setToolbarVisible(true);
    ui.enter();
    ui.restore();
    await Future<void>.delayed(Duration.zero);
    expect(calls.map((call) => call.method), [
      'SystemChrome.setEnabledSystemUIOverlays',
      'disableImmersive',
    ]);
    expect(calls.first.arguments, [
      'SystemUiOverlay.top',
      'SystemUiOverlay.bottom',
    ]);
  });

  test('平台旧请求尚未回复时，退出恢复不被旧请求阻塞', () async {
    final pending = Completer<void>();
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
        await pending.future;
      }
      return null;
    });
    final ui = ReaderSystemUi();
    ui.enter();
    ui.setToolbarVisible(false);
    await Future<void>.delayed(Duration.zero);
    ui.restore();
    await Future<void>.delayed(Duration.zero);
    expect(
      calls.map((call) => call.method),
      containsAllInOrder([
        'SystemChrome.setEnabledSystemUIMode',
        'SystemChrome.setEnabledSystemUIOverlays',
        'disableImmersive',
      ]),
    );
    final count = calls.length;
    pending.complete();
    await Future<void>.delayed(Duration.zero);
    expect(calls, hasLength(count));
  });

  test('非 Android 平台缺少刘海通道时仍恢复系统栏', () async {
    messenger.setMockMethodCallHandler(cutoutChannel, null);
    final ui = ReaderSystemUi();
    ui.enter();
    ui.setToolbarVisible(false);
    ui.restore();
    await Future<void>.delayed(Duration.zero);
    expect(calls.last.method, 'SystemChrome.setEnabledSystemUIOverlays');
  });
}
