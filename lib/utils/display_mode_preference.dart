import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';

class DisplayModePreference {
  const DisplayModePreference._();

  static const MethodChannel _windowChannel = MethodChannel(
    'io.github.caolib.kira/display_mode',
  );
  static const _manualRefreshRates = <int>[60, 90, 120, 144, 165];

  static bool get isSupportedPlatform => !kIsWeb && Platform.isAndroid;

  static Future<DisplayModeData> load() async {
    final modes = await FlutterDisplayMode.supported;
    final active = await FlutterDisplayMode.active;
    return DisplayModeData(modes: modes, active: active);
  }

  static List<int> refreshRates(List<DisplayMode> modes) {
    final rates = <int>{};
    var maxRate = 0;
    for (final mode in modes) {
      final rate = mode.refreshRate.round();
      if (rate > maxRate) {
        maxRate = rate;
      }
      // Sub-60Hz modes are usually VRR/LTPO power-saving targets, not useful
      // manual preferences for an app-wide setting.
      if (rate >= 60) {
        rates.add(rate);
      }
    }
    for (final rate in _manualRefreshRates) {
      if (rate <= maxRate) {
        rates.add(rate);
      }
    }
    return rates.toList()..sort((a, b) => b.compareTo(a));
  }

  static Future<bool> applyRefreshRate(
    int refreshRate, {
    List<DisplayMode>? modes,
    DisplayMode? active,
  }) async {
    if (!isSupportedPlatform) return false;

    try {
      if (refreshRate == 0) {
        await FlutterDisplayMode.setPreferredMode(DisplayMode.auto);
        await _setWindowPreferredRefreshRate(0);
        return true;
      }

      final supportedModes = modes ?? await FlutterDisplayMode.supported;
      final activeMode = active ?? await FlutterDisplayMode.active;
      final matches = supportedModes
          .where((mode) => mode.refreshRate.round() == refreshRate)
          .toList();
      if (matches.isEmpty) {
        await FlutterDisplayMode.setPreferredMode(DisplayMode.auto);
        return _setWindowPreferredRefreshRate(refreshRate);
      }

      final picked = matches.firstWhere(
        (mode) =>
            mode.width == activeMode.width && mode.height == activeMode.height,
        orElse: () => matches.first,
      );
      await _setWindowPreferredRefreshRate(0);
      await FlutterDisplayMode.setPreferredMode(picked);
      return true;
    } catch (error) {
      debugPrint(
        '[DisplayModePreference] Failed to apply refresh rate: $error',
      );
      return false;
    }
  }

  static Future<bool> _setWindowPreferredRefreshRate(int refreshRate) async {
    if (!isSupportedPlatform) return false;

    try {
      await _windowChannel.invokeMethod<void>('setPreferredRefreshRate', {
        'refreshRate': refreshRate.toDouble(),
      });
      return true;
    } catch (error) {
      debugPrint(
        '[DisplayModePreference] Failed to set window refresh rate: $error',
      );
      return false;
    }
  }
}

class DisplayModeData {
  final List<DisplayMode> modes;
  final DisplayMode active;

  const DisplayModeData({required this.modes, required this.active});
}
