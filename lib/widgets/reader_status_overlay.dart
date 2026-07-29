import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../models/reader_settings.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/reader_chrome.dart';
import '../utils/app_logger.dart';

/// 阅读器沉浸式状态显示：时间 / 电量 / 网络 / 页码。
///
/// 设计上刻意保持低调：小字号、黑色半透明圆角底、不可点击，
/// 仅提供系统状态与阅读进度的一眼速览，不打扰阅读。
class ReaderStatusOverlay extends StatefulWidget {
  final int currentPage;
  final int totalPages;

  const ReaderStatusOverlay({
    super.key,
    this.currentPage = 0,
    this.totalPages = 0,
  });

  @override
  State<ReaderStatusOverlay> createState() => _ReaderStatusOverlayState();
}

class _ReaderStatusOverlayState extends State<ReaderStatusOverlay> {
  final Battery _battery = Battery();
  StreamSubscription<BatteryState>? _batteryStateSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _clockTimer;

  TimeOfDay _time = TimeOfDay.now();
  int? _batteryLevel;
  bool _charging = false;

  /// 桌面设备（Windows/Linux 无电池）可能返回 -1，此类设备直接隐藏电量段
  bool get _hasBattery => _batteryLevel != null && _batteryLevel! >= 0;
  List<ConnectivityResult> _connectivity = const [];

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final now = TimeOfDay.now();
      if (now != _time && mounted) setState(() => _time = now);
    });
    _initBattery();
    _initConnectivity();
  }

  void _applyBatteryState(BatteryState state, int level) {
    if (!mounted) return;
    setState(() {
      _batteryLevel = level;
      _charging = state == BatteryState.charging || state == BatteryState.full;
    });
  }

  Future<void> _initBattery() async {
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      _applyBatteryState(state, level);
      _batteryStateSub = _battery.onBatteryStateChanged.listen((state) async {
        _applyBatteryState(state, await _battery.batteryLevel);
      });
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'reader_status_overlay.battery',
        ),
      );
    }
  }

  Future<void> _initConnectivity() async {
    try {
      _connectivity = await Connectivity().checkConnectivity();
      if (mounted) setState(() {});
      _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
        if (!mounted) return;
        setState(() => _connectivity = result);
      });
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'reader_status_overlay.connectivity',
        ),
      );
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _batteryStateSub?.cancel();
    _connectivitySub?.cancel();
    super.dispose();
  }

  IconData get _networkIcon {
    if (_connectivity.contains(ConnectivityResult.wifi) ||
        _connectivity.contains(ConnectivityResult.ethernet)) {
      return Icons.wifi;
    }
    if (_connectivity.contains(ConnectivityResult.mobile)) {
      return Icons.signal_cellular_alt;
    }
    if (_connectivity.isEmpty ||
        _connectivity.contains(ConnectivityResult.none)) {
      return Icons.wifi_off;
    }
    // vpn / bluetooth / other：按有网处理
    return Icons.wifi;
  }

  String get _timeLabel {
    final h = _time.hour.toString().padLeft(2, '0');
    final m = _time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    const color = ReaderChrome.onSurfaceMuted;
    const fontSize = 11.0;
    const iconSize = 14.0;
    const textStyle = TextStyle(
      color: color,
      fontSize: fontSize,
      fontFeatures: [FontFeature.tabularFigures()],
    );

    final settings = ReaderSettings();
    final segments = <Widget>[];
    void add(Widget w) {
      if (segments.isNotEmpty) {
        segments.add(const SizedBox(width: AppSpacing.sm));
      }
      segments.add(w);
    }

    if (settings.statusOverlayTime) add(Text(_timeLabel, style: textStyle));
    if (settings.statusOverlayNetwork) {
      add(Icon(_networkIcon, color: color, size: iconSize));
    }
    if (settings.statusOverlayBattery && _hasBattery) {
      add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_charging) const Icon(Icons.bolt, color: color, size: iconSize),
            Text('$_batteryLevel%', style: textStyle),
          ],
        ),
      );
    }
    if (settings.statusOverlayPage && widget.totalPages > 0) {
      add(Text('${widget.currentPage}/${widget.totalPages}', style: textStyle));
    }

    // 真机上打孔/刘海状态栏高度可达 48+，组件用固定内边距保持轻薄，
    // 不随系统状态栏高度膨胀。
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.only(
          top: 2,
          right: AppSpacing.lg,
          bottom: AppSpacing.xs,
          left: 10,
        ),
        decoration: const BoxDecoration(
          color: Color(0xB3000000), // 黑 70% 半透明底
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(AppRadius.md),
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: segments),
      ),
    );
  }
}
