import 'dart:io';
import 'package:flutter/services.dart';

class AppIconSwitcher {
  static const _channel = MethodChannel('io.github.caolib.kira/app_icon');

  static Future<void> setAppIcon(int index) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await _channel.invokeMethod<void>('setAppIcon', {'index': index});
  }

  static Future<int> getAppIconIndex() async {
    if (!Platform.isAndroid && !Platform.isIOS) return 0;
    final index = await _channel.invokeMethod<int>('getAppIconIndex');
    return index ?? 0;
  }
}
