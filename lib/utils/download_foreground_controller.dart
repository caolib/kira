import 'dart:async';
import 'dart:io' show Platform;

import 'package:clock/clock.dart' show clock;
import 'package:flutter/widgets.dart';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../l10n/app_localizations.dart';
import '../models/user_manager.dart';
import 'app_logger.dart';
import 'download_manager.dart';

/// 漫画下载的前台服务保活。
///
/// 下载任务跑在主 isolate 里（见 [DownloadManager]）。应用退到后台后进程会被
/// 系统冻结或回收，导致下载立即停止。本控制器在队列存在可运行任务时拉起
/// `dataSync` 类型前台服务持有进程，通知栏展示聚合进度；队列排空或全部暂停
/// 时停止服务，避免常驻通知空跑。
///
/// 保障范围：按 Home / 切应用 / 熄屏期间下载不中断。划掉任务卡片、进程被系统
/// 杀死不在范围内——队列状态已持久化，下次启动会自动续传。
class DownloadForegroundController {
  DownloadForegroundController({
    Listenable? listenable,
    List<ComicDownloadTaskInfo> Function()? tasks,
    DownloadForegroundGateway? gateway,
    bool? supported,
  }) : _listenable = listenable ?? DownloadManager(),
       _tasksOf = tasks ?? _defaultTasks,
       _gateway = gateway ?? FlutterForegroundTaskGateway(),
       _supported = supported ?? Platform.isAndroid;

  static List<ComicDownloadTaskInfo> _defaultTasks() => DownloadManager().tasks;

  /// 通知刷新的最小间隔；进度事件远密于系统允许的通知更新频率。
  static const Duration _minUpdateInterval = Duration(milliseconds: 800);

  final Listenable _listenable;
  final List<ComicDownloadTaskInfo> Function() _tasksOf;
  final DownloadForegroundGateway _gateway;
  final bool _supported;

  bool _attached = false;
  bool _alignChecked = false;
  bool _serviceWanted = false;
  bool _serviceRunning = false;
  String? _lastText;
  String? _pendingText;
  DateTime _lastUpdateAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _trailing;
  Future<void> _tail = Future<void>.value();

  /// 队列中是否存在可运行任务（全局或单独暂停的任务不算）。
  @visibleForTesting
  static bool serviceShouldRun(List<ComicDownloadTaskInfo> tasks) =>
      tasks.any((t) => t.status != ComicDownloadTaskStatus.paused);

  /// 由队列快照聚合出通知正文：在飞章节数、待下载数、在飞章节的图片进度。
  @visibleForTesting
  static String composeText(
    AppLocalizations l10n,
    List<ComicDownloadTaskInfo> tasks,
  ) {
    var active = 0, pending = 0, done = 0, total = 0;
    for (final t in tasks) {
      switch (t.status) {
        case ComicDownloadTaskStatus.downloading:
          active++;
          final p = t.progress;
          if (p != null) {
            done += p.completed;
            total += p.total;
          }
        case ComicDownloadTaskStatus.pending:
          pending++;
        case ComicDownloadTaskStatus.paused:
          break;
      }
    }
    final body = l10n.downloadForegroundBody(active, pending);
    return total > 0
        ? '$body · ${l10n.downloadForegroundImages(done, total)}'
        : body;
  }

  /// 订阅下载队列并立即对齐一次服务状态。非 Android 平台为空操作。
  void attach() {
    if (_attached || !_supported) return;
    _attached = true;
    _listenable.addListener(_onChanged);
    unawaited(sync());
  }

  /// 仅用于测试：解除订阅并取消待发计时器。
  @visibleForTesting
  void detach() {
    if (!_attached) return;
    _attached = false;
    _trailing?.cancel();
    _trailing = null;
    _listenable.removeListener(_onChanged);
  }

  /// 等待挂起的服务操作完成；仅用于测试。
  @visibleForTesting
  Future<void> flush() => _tail;

  void _onChanged() => unawaited(sync());

  /// 根据当前队列状态对齐前台服务：该启则启、该刷则刷、该停则停。
  @visibleForTesting
  Future<void> sync() async {
    if (!_supported) return;
    final tasks = _tasksOf();
    final l10n = _resolveL10n();
    final want = serviceShouldRun(tasks);

    if (want) {
      final text = composeText(l10n, tasks);
      if (!_serviceWanted) {
        _serviceWanted = true;
        _pendingText = null;
        _trailing?.cancel();
        _trailing = null;
        _enqueue(() => _start(l10n, text));
        return;
      }
      _pendingText = text;
      _scheduleUpdate();
      return;
    }

    // 队列无可运行任务。
    if (_serviceWanted) {
      _serviceWanted = false;
      _pendingText = null;
      _trailing?.cancel();
      _trailing = null;
      _enqueue(_stop);
    } else if (!_alignChecked) {
      // 冷启动对齐：上次退出/被系统重建的服务可能仍在空跑，停掉它。
      _alignChecked = true;
      _enqueue(_stopZombie);
    }
  }

  Future<void> _start(AppLocalizations l10n, String text) async {
    if (!_serviceWanted) return;
    try {
      if (await _gateway.isRunning()) {
        _serviceRunning = true;
        _lastText = text;
        await _gateway.update(title: l10n.downloadForegroundTitle, text: text);
        _lastUpdateAt = clock.now();
        return;
      }
      await _gateway.ensureNotificationPermission();
      if (!_serviceWanted) return;
      await _gateway.start(
        title: l10n.downloadForegroundTitle,
        text: text,
        channelName: l10n.downloadForegroundChannel,
      );
      _serviceRunning = true;
      _lastText = text;
      _lastUpdateAt = clock.now();
    } catch (e, st) {
      _serviceRunning = false;
      unawaited(
        AppLogger.instance.recordWarning(
          '下载前台服务启动失败: $e',
          stackTrace: st,
          source: 'download_foreground',
        ),
      );
    }
  }

  void _scheduleUpdate() {
    final sinceLast = clock.now().difference(_lastUpdateAt);
    if (sinceLast >= _minUpdateInterval) {
      _flushUpdate();
      return;
    }
    _trailing ??= Timer(_minUpdateInterval - sinceLast, () {
      _trailing = null;
      _flushUpdate();
    });
  }

  void _flushUpdate() {
    final text = _pendingText;
    _pendingText = null;
    if (text == null || !_serviceWanted || !_serviceRunning) return;
    if (text == _lastText) return;
    _lastText = text;
    _lastUpdateAt = clock.now();
    final l10n = _resolveL10n();
    _enqueue(() async {
      if (!_serviceWanted || !_serviceRunning) return;
      await _gateway.update(title: l10n.downloadForegroundTitle, text: text);
    });
  }

  Future<void> _stop() async {
    _serviceRunning = false;
    try {
      if (await _gateway.isRunning()) await _gateway.stop();
    } catch (e, st) {
      unawaited(
        AppLogger.instance.recordWarning(
          '下载前台服务停止失败: $e',
          stackTrace: st,
          source: 'download_foreground',
        ),
      );
    }
  }

  Future<void> _stopZombie() async {
    try {
      if (await _gateway.isRunning()) await _gateway.stop();
    } catch (e, st) {
      unawaited(
        AppLogger.instance.recordWarning(
          '下载前台服务清理失败: $e',
          stackTrace: st,
          source: 'download_foreground',
        ),
      );
    }
  }

  void _enqueue(Future<void> Function() op) {
    _tail = _tail.then((_) async {
      try {
        await op();
      } catch (e, st) {
        unawaited(
          AppLogger.instance.recordWarning(
            '下载前台服务操作异常: $e',
            stackTrace: st,
            source: 'download_foreground',
          ),
        );
      }
    });
  }

  AppLocalizations _resolveL10n() {
    final configured = UserManager().locale;
    final Locale locale = switch (configured) {
      'zh' => const Locale('zh'),
      'zh-Hant' => const Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hant',
      ),
      _ => _systemLocale(),
    };
    return lookupAppLocalizations(locale);
  }

  // 仅支持简繁两种语言；系统其它语言按简体中文兜底。
  static Locale _systemLocale() {
    final sys = WidgetsBinding.instance.platformDispatcher.locale;
    if (sys.languageCode == 'zh') {
      final script = sys.scriptCode;
      final country = sys.countryCode?.toUpperCase();
      if (script == 'Hant' ||
          country == 'TW' ||
          country == 'HK' ||
          country == 'MO') {
        return const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
      }
    }
    return const Locale('zh');
  }
}

/// 与前台服务插件的交互面；真实实现基于 flutter_foreground_task。
abstract interface class DownloadForegroundGateway {
  Future<bool> isRunning();

  Future<void> ensureNotificationPermission();

  Future<void> start({
    required String title,
    required String text,
    required String channelName,
  });

  Future<void> update({required String title, required String text});

  Future<void> stop();
}

class FlutterForegroundTaskGateway implements DownloadForegroundGateway {
  static const int _serviceId = 420435;
  bool _optionsReady = false;

  void _ensureOptions(String channelName) {
    if (_optionsReady) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'kira_comic_download',
        channelName: channelName,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWifiLock: true,
        // 默认 allowWakeLock/allowAutoRestart 为 true：dataSync 超时或服务被回收后
        // 自动重启保住长时任务；进程死亡时重启的服务为无主状态，通知点击回到
        // 应用后由控制器自动对齐。
      ),
    );
    _optionsReady = true;
  }

  @override
  Future<bool> isRunning() => FlutterForegroundTask.isRunningService;

  @override
  Future<void> ensureNotificationPermission() async {
    if (await FlutterForegroundTask.checkNotificationPermission() ==
        NotificationPermission.granted) {
      return;
    }
    await FlutterForegroundTask.requestNotificationPermission();
  }

  @override
  Future<void> start({
    required String title,
    required String text,
    required String channelName,
  }) async {
    _ensureOptions(channelName);
    final result = await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      serviceTypes: const [ForegroundServiceTypes.dataSync],
      notificationTitle: title,
      notificationText: text,
    );
    if (result is ServiceRequestFailure) throw result.error;
  }

  @override
  Future<void> update({required String title, required String text}) async {
    final result = await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
    );
    if (result is ServiceRequestFailure) throw result.error;
  }

  @override
  Future<void> stop() async {
    final result = await FlutterForegroundTask.stopService();
    if (result is ServiceRequestFailure) throw result.error;
  }
}
