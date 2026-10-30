import 'dart:async';

import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// 可暂停时间戳落盘，复现设置快速操作与调度通知的竞态。
class DelayedNetworkPreferences extends SharedPreferencesStorePlatform {
  final Map<String, Object> values;
  final writeStarted = Completer<void>();
  Completer<void>? writeGate;

  DelayedNetworkPreferences([Map<String, Object>? initial])
    : values = {...?initial};

  @override
  Future<Map<String, Object>> getAll() async => {...values};

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key.endsWith('network_last_auto_test_at') && writeGate != null) {
      if (!writeStarted.isCompleted) writeStarted.complete();
      await writeGate!.future;
    }
    values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    values.clear();
    return true;
  }
}
