import 'package:flutter_test/flutter_test.dart';
import 'package:kira/backup/backup_category.dart';
import 'package:kira/backup/backup_schedule.dart';
import 'package:kira/backup/backup_settings.dart';
import 'package:kira/models/secure_credential_store.dart';

import 'backup_test_support.dart';

void main() {
  test('interval follows the unit, and days is the default', () {
    expect(const BackupSchedule().interval, const Duration(days: 1));
    expect(
      const BackupSchedule(value: 3, unit: BackupIntervalUnit.hours).interval,
      const Duration(hours: 3),
    );
    expect(
      const BackupSchedule(
        value: 30,
        unit: BackupIntervalUnit.minutes,
      ).interval,
      const Duration(minutes: 30),
    );
    expect(BackupSchedule.tryFromName('hours'), BackupIntervalUnit.hours);
    expect(BackupSchedule.tryFromName('seconds'), isNull);
    expect(BackupSchedule.tryFromName(null), isNull);
    expect(BackupSchedule.clampValue(0), BackupSchedule.minValue);
    expect(BackupSchedule.clampValue(99999), BackupSchedule.maxValue);
  });

  test('schedule and last run survive a reload', () async {
    final prefs = MemoryBackupPreferences();
    final settings = BackupSettings(
      preferences: prefs,
      secrets: InMemorySecureCredentialStore(),
    );
    expect((await settings.load()).schedule, const BackupSchedule());
    expect((await settings.load()).lastAutoBackupAt, isNull);

    const schedule = BackupSchedule(
      enabled: true,
      value: 45,
      unit: BackupIntervalUnit.minutes,
    );
    await settings.saveSchedule(schedule);
    final at = DateTime(2026, 9, 20, 16, 30);
    await settings.markAutoBackup(at);

    final data = await settings.load();
    expect(data.schedule, schedule);
    expect(data.lastAutoBackupAt, at);
    // 定时备份是本地配置，不随备份文件走。
    for (final key in [
      BackupSettings.scheduleEnabledKey,
      BackupSettings.scheduleValueKey,
      BackupSettings.scheduleUnitKey,
      BackupSettings.lastAutoBackupKey,
    ]) {
      expect(BackupSchema.categoryOf(key), isNull, reason: key);
    }
  });

  test('a session password feeds the scheduler without being stored', () async {
    final secrets = InMemorySecureCredentialStore();
    final settings = BackupSettings(
      preferences: MemoryBackupPreferences(),
      secrets: secrets,
    );
    await settings.saveEncryption(
      encrypted: true,
      remember: false,
      password: 'pw',
    );
    expect(await settings.activePassword(), 'pw');
    expect(await secrets.readBackupPassword(), isNull);
    expect((await settings.load()).rememberedPassword, isNull);

    await settings.saveEncryption(
      encrypted: true,
      remember: true,
      password: 'saved',
    );
    expect(await secrets.readBackupPassword(), 'saved');
    expect(await settings.activePassword(), 'saved');
  });
}
