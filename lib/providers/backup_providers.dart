import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backup/backup_codec.dart';
import '../backup/backup_controller.dart';
import '../backup/backup_scheduler.dart';
import '../backup/backup_settings.dart';
import '../utils/settings_backup.dart';

final settingsBackupServiceProvider = Provider<SettingsBackupService>(
  (ref) => SettingsBackupService(),
);
final backupCodecProvider = Provider<BackupCodec>((ref) => BackupCodec());
final backupSettingsProvider = Provider<BackupSettings>(
  (ref) => BackupSettings(),
);

/// 常驻：定时备份与备份页共用同一个控制器，busy 状态与进度因此对两边都可见。
final backupControllerProvider = Provider<BackupController>((ref) {
  final controller = BackupController(
    service: ref.read(settingsBackupServiceProvider),
    codec: ref.read(backupCodecProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

final backupSchedulerProvider = Provider<BackupScheduler>((ref) {
  final scheduler = BackupScheduler(
    settings: ref.read(backupSettingsProvider),
    controller: ref.read(backupControllerProvider),
  );
  ref.onDispose(scheduler.dispose);
  return scheduler;
});
