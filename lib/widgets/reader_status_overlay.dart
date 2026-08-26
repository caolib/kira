import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/reader_settings.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/reader_chrome.dart';
import '../utils/app_logger.dart';

/// 阅读器沉浸式状态显示：时间 / 电量 / 网络 / 页码 / 帧率。
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

class _ReaderStatusOverlayState extends State<ReaderStatusOverlay>
    with SingleTickerProviderStateMixin {
  final Battery _battery = Battery();
  StreamSubscription<BatteryState>? _batteryStateSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _clockTimer;
  Ticker? _fpsTicker;
  Timer? _fpsTimer;

  TimeOfDay _time = TimeOfDay.now();
  int? _batteryLevel;
  bool _charging = false;
  int _frameCount = 0;
  double _fps = 0;

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
    _startFps();
    _initBattery();
    _initConnectivity();
  }

  /// 帧率统计：Ticker 驱动连续渲染并每秒结算一次帧数。
  /// 空闲时显示刷新率上限，滚动/翻页卡顿时数值随之下降。
  void _startFps() {
    _fpsTicker = createTicker((_) => _frameCount++);
    _fpsTicker!.start();
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _fps = _frameCount.toDouble();
        _frameCount = 0;
      });
    });
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
    _fpsTicker?.dispose();
    _fpsTimer?.cancel();
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

    for (final id in settings.statusOverlayOrder) {
      switch (id) {
        case 'time':
          if (settings.statusOverlayTime) {
            add(Text(_timeLabel, style: textStyle));
          }
          break;
        case 'network':
          if (settings.statusOverlayNetwork) {
            add(Icon(_networkIcon, color: color, size: iconSize));
          }
          break;
        case 'battery':
          if (settings.statusOverlayBattery && _hasBattery) {
            add(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_charging)
                    const Icon(Icons.bolt, color: color, size: iconSize),
                  Text('$_batteryLevel%', style: textStyle),
                ],
              ),
            );
          }
          break;
        case 'page':
          if (settings.statusOverlayPage && widget.totalPages > 0) {
            add(
              Text(
                '${widget.currentPage}/${widget.totalPages}',
                style: textStyle,
              ),
            );
          }
          break;
        case 'fps':
          if (settings.statusOverlayFps) {
            add(Text('${_fps.round()} FPS', style: textStyle));
          }
          break;
      }
    }

    // 真机上打孔/刘海状态栏高度可达 48+，组件用固定内边距保持轻薄，
    // 不随系统状态栏高度膨胀。
    // 圆角朝向屏幕中心：依位置选择对应角，其余三角保持直角。
    final pos = settings.statusOverlayPosition;
    final corner = switch (pos) {
      0 => BorderRadius.only(bottomRight: Radius.circular(AppRadius.md)), // 左上
      1 => const BorderRadius.only(
        bottomLeft: Radius.circular(AppRadius.md),
        bottomRight: Radius.circular(AppRadius.md),
      ), // 顶部中间
      2 => const BorderRadius.only(
        bottomLeft: Radius.circular(AppRadius.md),
      ), // 右上（默认）
      3 => BorderRadius.only(topLeft: Radius.circular(AppRadius.md)), // 右下
      4 => const BorderRadius.only(
        topLeft: Radius.circular(AppRadius.md),
        topRight: Radius.circular(AppRadius.md),
      ), // 底部中间
      5 => BorderRadius.only(topRight: Radius.circular(AppRadius.md)), // 左下
      _ => const BorderRadius.only(bottomLeft: Radius.circular(AppRadius.md)),
    };
    // 角落位：靠屏幕一侧给较大边距（lg=16），内侧给较小边距（10）。
    // 中间位：紧凑居中浮动，左右对称给较大边距（lg=16）。
    final isLeft = pos == 0 || pos == 5;
    final isCenter = pos == 1 || pos == 4;
    return IgnorePointer(
      child: Container(
        padding: EdgeInsets.only(
          top: 2,
          right: isCenter ? AppSpacing.lg : (isLeft ? 10 : AppSpacing.lg),
          bottom: AppSpacing.xs,
          left: isCenter ? AppSpacing.lg : (isLeft ? AppSpacing.lg : 10),
        ),
        decoration: BoxDecoration(
          // 黑底，不透明度由设置控制（0=透明，1=全黑）
          color: Color(
            0xFF000000,
          ).withValues(alpha: settings.statusOverlayOpacity),
          borderRadius: corner,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: segments,
        ),
      ),
    );
  }
}
