import 'dart:async';

import 'package:flutter/foundation.dart';

import '../utils/app_logger.dart';
import 'backup_category.dart';
import 'backup_codec.dart';
import 'backup_controller.dart';
import 'backup_settings.dart';
import 'webdav_config.dart';

typedef BackupUpload =
    Future<void> Function(
      WebDavConfig config,
      WebDavCredentials credentials,
      EncodedBackup backup,
    );

/// 尽力而为的定时备份：进程被杀后不再运行，也不驻留后台服务。启动与设置变化时
/// 复查一次「距上次成功备份是否已超过间隔」，到了就补一次。
class BackupScheduler {
  /// 启动时先让位给首帧与初始化，避免和冷启动的网络请求抢带宽。
  static const startupDelay = Duration(seconds: 5);

  /// 失败（含控制器被手动操作占用）后的重试间隔，比定时间隔短。
  static const retryDelay = Duration(minutes: 10);

  final BackupSettings settings;
  final BackupController controller;
  final DateTime Function() now;
  final BackupUpload upload;

  /// 测试用的计时器工厂：注入后可不依赖真实时间驱动排期。
  final Timer Function(Duration delay, void Function() callback) timerFactory;

  Timer? _timer;
  bool _disposed = false;

  BackupScheduler({
    required this.settings,
    required BackupController controller,
    BackupUpload? upload,
    DateTime Function()? now,
    Timer Function(Duration delay, void Function() callback)? timerFactory,
  }) : controller = controller,
       upload =
           upload ??
           ((config, credentials, backup) =>
               controller.upload(config, credentials, backup)),
       now = now ?? DateTime.now,
       timerFactory =
           timerFactory ?? ((delay, callback) => Timer(delay, callback));

  /// 冷启动后做一次到期检查。
  void start() => _arm(startupDelay);

  /// 设置变化或回到前台时立刻复查（不等下一个定时点）。
  void poke() => _arm(Duration.zero);

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }

  void _arm(Duration delay) {
    if (_disposed) return;
    _timer?.cancel();
    _timer = timerFactory(delay, () => unawaited(checkNow()));
  }

  /// 到期就备份，否则把定时器排到下一个到期时刻。
  @visibleForTesting
  Future<void> checkNow() async {
    if (_disposed) return;
    final data = await settings.load();
    final schedule = data.schedule;
    // 总开关关掉后整条链路暂停，已配置的定时备份也一并停摆；重新打开时由
    // poke() 按原有到期判断复查（间隔已过则照常补一次）。
    if (!schedule.enabled || !data.webDavEnabled) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    final moment = now();
    final last = data.lastAutoBackupAt;
    if (last == null) {
      // 刚打开开关：从此刻开始计时，不立刻产生一次备份。
      await settings.markAutoBackup(moment);
      _arm(schedule.interval);
      return;
    }
    final due = last.add(schedule.interval);
    if (due.isAfter(moment)) {
      _arm(due.difference(moment));
      return;
    }
    if (controller.busy) {
      _arm(retryDelay);
    } else if (await _backup(data)) {
      _arm(schedule.interval);
    } else {
      _arm(retryDelay);
    }
  }

  Future<bool> _backup(BackupSettingsData data) async {
    try {
      final config = data.connection;
      if (config == null) return false;
      final password = data.encrypted ? await settings.activePassword() : null;
      if (data.encrypted && (password == null || password.isEmpty)) {
        return false;
      }
      final prepared = await controller.prepare(_categories(data.encrypted));
      final encoded = await controller.encode(prepared, password: password);
      await upload(config, data.credentials, encoded);
      await settings.markAutoBackup(now());
      return true;
    } catch (error, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          error,
          stackTrace: stack,
          source: 'backup.auto',
        ),
      );
      return false;
    }
  }

  /// 关闭总开关后取消已排期的定时器：没有这一步，关闭前已武装的那一次仍会在
  /// 开关关闭后触发上传。
  void suspend() {
    _timer?.cancel();
    _timer = null;
  }

  /// 未加密的定时上传没有二次确认，跳过账号与 AI 密钥。
  Set<BackupCategory> _categories(bool encrypted) => {
    for (final category in BackupCategory.values)
      if (encrypted || !category.isSensitive) category,
  };
}
