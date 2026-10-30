import 'dart:async';

import '../models/network_settings.dart';
import 'app_logger.dart';
import 'network_latency_tester.dart';

/// 进程内定时测速，不驻留后台服务。冷启动与恢复前台时按持久化时间补测一次。
class NetworkAutoTestScheduler {
  static const startupDelay = Duration(seconds: 5);
  static final _instances = <NetworkAutoTestScheduler>{};

  final NetworkSettings settings;
  final NetworkLatencyTester tester;
  final DateTime Function() now;
  final Timer Function(Duration delay, void Function() callback) timerFactory;
  Timer? _timer;
  Future<void>? _checking;
  bool _started = false;
  bool _disposed = false;
  bool _suspended = false;
  int _revision = 0;
  late Object _schedule;

  NetworkAutoTestScheduler({
    required this.settings,
    required this.tester,
    DateTime Function()? now,
    Timer Function(Duration delay, void Function() callback)? timerFactory,
  }) : now = now ?? DateTime.now,
       timerFactory =
           timerFactory ?? ((delay, callback) => Timer(delay, callback)) {
    _schedule = _scheduleSnapshot;
    settings.addListener(refreshSettings);
    _instances.add(this);
  }

  bool get _canRun =>
      _started && !_disposed && !_suspended && settings.autoTestEnabled;
  Object get _scheduleSnapshot => (
    settings.autoTestEnabled,
    settings.autoTestIntervalHours,
    settings.autoTestRevision,
  );

  void start() {
    if (_started || _disposed) return;
    _started = true;
    _arm(startupDelay);
  }

  void poke() => _arm(Duration.zero);

  void refreshSettings() {
    final schedule = _scheduleSnapshot;
    if (_schedule == schedule) return;
    _schedule = schedule;
    _revision++;
    poke();
  }

  void _arm(Duration delay) {
    _timer?.cancel();
    _timer = null;
    if (!_canRun || _checking != null) return;
    _timer = timerFactory(delay, () => unawaited(checkNow()));
  }

  Future<void> checkNow() {
    return _checking ??= Future.microtask(_check).whenComplete(() {
      _checking = null;
      _schedule = _scheduleSnapshot;
      if (!_canRun) return;
      final last = settings.lastAutoTestAt;
      final moment = now();
      final due = (last ?? moment).add(settings.autoTestInterval);
      _arm(due.isAfter(moment) ? due.difference(moment) : Duration.zero);
    });
  }

  Future<void> _check() async {
    if (!_canRun) return;
    final revision = _revision;
    final moment = now();
    final last = settings.lastAutoTestAt;
    try {
      if (last == null || last.isAfter(moment)) {
        await settings.markAutoTest(moment);
        return;
      }
      if (last.add(settings.autoTestInterval).isAfter(moment)) return;
      // 失败也记本次尝试时间，离线时不会在每次回前台时重复请求。
      await settings.markAutoTest(moment);
      _schedule = _scheduleSnapshot;
      if (!_canRun || revision != _revision) return;
      await tester.testAndSelect(
        shouldApply: () => _canRun && revision == _revision,
      );
    } catch (error, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          error,
          stackTrace: stack,
          source: 'network.auto_test',
        ),
      );
    }
  }

  /// 备份恢复先停排期并排空写入，避免线路与时间戳覆盖恢复事务。
  static Future<void> pauseForRestore() async {
    await Future.wait([
      for (final scheduler in _instances) scheduler._pauseForRestore(),
    ]);
  }

  Future<void> _pauseForRestore() async {
    _suspended = true;
    _revision++;
    _timer?.cancel();
    await _checking;
    await tester.pauseForRestore();
    await settings.flushAutoTestWrites();
  }

  static void resumeAfterRestore() {
    for (final scheduler in _instances) {
      scheduler.tester.resumeAfterRestore();
      scheduler._suspended = false;
      scheduler.poke();
    }
  }

  void dispose() {
    _disposed = true;
    _revision++;
    _timer?.cancel();
    settings.removeListener(refreshSettings);
    _instances.remove(this);
  }
}
