import 'package:flutter/foundation.dart';

/// 阅读器漫画图片加载耗时统计（仅记录真实网络请求，缓存命中不计入）。
class ImageLoadStats extends ChangeNotifier {
  static final ImageLoadStats _instance = ImageLoadStats._();
  factory ImageLoadStats() => _instance;
  ImageLoadStats._();

  static const Duration _window = Duration(minutes: 10);

  final List<_Entry> _entries = [];

  void record(Duration elapsed) {
    final now = DateTime.now();
    _entries.add(_Entry(now, elapsed.inMilliseconds));
    _prune(now);
    notifyListeners();
  }

  int get sampleCount {
    _prune(DateTime.now());
    return _entries.length;
  }

  /// 最近 10 分钟的平均加载耗时（毫秒）。无数据时返回 null。
  double? get averageMs {
    _prune(DateTime.now());
    if (_entries.isEmpty) return null;
    final total = _entries.fold<int>(0, (sum, e) => sum + e.elapsedMs);
    return total / _entries.length;
  }

  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }

  void _prune(DateTime now) {
    final cutoff = now.subtract(_window);
    _entries.removeWhere((e) => e.timestamp.isBefore(cutoff));
  }
}

class _Entry {
  _Entry(this.timestamp, this.elapsedMs);
  final DateTime timestamp;
  final int elapsedMs;
}
