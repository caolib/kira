import 'dart:async';

import 'package:flutter/services.dart';

import 'app_logger.dart';

/// 阅读会话的系统栏与刘海区状态。退出开始时释放，dispose 只做兜底，
/// 避免返回页已经显示后才改变窗口尺寸，也避免退场回调重新隐藏系统栏。
class ReaderSystemUi {
  static const _channel = MethodChannel('io.github.caolib.kira/volume');
  bool _restored = false;

  void enter() {
    if (_restored) return;
    unawaited(_setCutoutMode('enableImmersive'));
  }

  void setToolbarVisible(bool visible) {
    if (_restored) return;
    unawaited(_setSystemBars(visible));
  }

  /// 同一轮中发出两项恢复请求，不等待退场动画或平台消息返回。
  void restore() {
    if (_restored) return;
    _restored = true;
    unawaited(_setSystemBars(true));
    unawaited(_setCutoutMode('disableImmersive'));
  }

  Future<void> _setSystemBars(bool visible) async {
    try {
      await SystemChrome.setEnabledSystemUIMode(
        visible ? SystemUiMode.manual : SystemUiMode.immersiveSticky,
        overlays: visible ? SystemUiOverlay.values : null,
      );
    } catch (error, stack) {
      _warn(error, stack, 'system_bars');
    }
  }

  Future<void> _setCutoutMode(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // 非 Android 平台没有刘海区通道，系统栏仍由 SystemChrome 控制。
      return;
    } catch (error, stack) {
      _warn(error, stack, 'cutout');
    }
  }

  void _warn(Object error, StackTrace stack, String action) {
    unawaited(
      AppLogger.instance.recordWarning(
        error,
        stackTrace: stack,
        source: 'reader.system_ui.$action',
      ),
    );
  }
}
