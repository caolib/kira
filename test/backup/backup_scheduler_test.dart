import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/backup/backup_codec.dart';
import 'package:kira/backup/backup_controller.dart';
import 'package:kira/backup/backup_schedule.dart';
import 'package:kira/backup/backup_scheduler.dart';
import 'package:kira/backup/backup_settings.dart';
import 'package:kira/backup/webdav_config.dart';
import 'package:kira/models/secure_credential_store.dart';
import 'package:kira/utils/settings_backup.dart';

import 'backup_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final config = WebDavConfig(serverUrl: 'https://dav.example/dav/');
  const credentials = WebDavCredentials(username: 'user', password: 'secret');
  const hourly = BackupSchedule(enabled: true, unit: BackupIntervalUnit.hours);

  late MemoryBackupPreferences prefs;
  late BackupSettings settings;
  late BackupController controller;
  late List<EncodedBackup> uploads;
  late DateTime clock;

  setUp(() {
    prefs = MemoryBackupPreferences();
    settings = BackupSettings(
      preferences: prefs,
      secrets: InMemorySecureCredentialStore(),
    );
    controller = BackupController(
      service: SettingsBackupService(
        preferences: prefs,
        journal: MemoryBackupJournal(),
        runtime: TestBackupRuntime(),
      ),
      codec: BackupCodec(),
    );
    uploads = [];
    clock = DateTime(2026, 9, 20, 12);
  });

  tearDown(() => controller.dispose());

  BackupScheduler scheduler({
    DateTime Function()? now,
    Timer Function(Duration delay, void Function() callback)? timerFactory,
  }) => BackupScheduler(
    settings: settings,
    controller: controller,
    upload: (config, credentials, backup) async => uploads.add(backup),
    now: now ?? () => clock,
    timerFactory: timerFactory,
  );

  test(
    'turning it on starts the clock instead of backing up at once',
    () async {
      await settings.saveConnection(config, credentials);
      await settings.saveSchedule(hourly);
      final subject = scheduler();

      await subject.checkNow();

      expect(uploads, isEmpty);
      expect((await settings.load()).lastAutoBackupAt, clock);
      subject.dispose();
    },
  );

  test('a disabled schedule never uploads', () async {
    await settings.saveConnection(config, credentials);
    await settings.saveSchedule(hourly.copyWith(enabled: false));
    await settings.markAutoBackup(clock.subtract(const Duration(days: 3)));
    final subject = scheduler();

    await subject.checkNow();

    expect(uploads, isEmpty);
    subject.dispose();
  });

  test('an unconfigured server is skipped', () async {
    await settings.saveSchedule(hourly);
    await settings.markAutoBackup(clock.subtract(const Duration(hours: 2)));
    final subject = scheduler();

    await subject.checkNow();

    expect(uploads, isEmpty);
    subject.dispose();
  });

  test(
    'two hours away catch up once, then once an hour while in use',
    () async {
      await settings.saveConnection(config, credentials);
      await settings.saveEncryption(
        encrypted: false,
        remember: false,
        password: '',
      );
      await settings.saveSchedule(hourly);
      await settings.markAutoBackup(clock.subtract(const Duration(hours: 2)));
      final subject = scheduler();

      // 退出应用 2 小时后打开：补一次。
      await subject.checkNow();
      expect(uploads, hasLength(1));
      expect((await settings.load()).lastAutoBackupAt, clock);

      // 连续使用 3.5 小时：其中 3 次到期，最后半小时不够间隔。
      for (final minutes in [60, 60, 60, 30]) {
        clock = clock.add(Duration(minutes: minutes));
        await subject.checkNow();
      }
      expect(uploads, hasLength(4));
      subject.dispose();
    },
  );

  test('past-due checks without an interval never re-upload', () async {
    await settings.saveConnection(config, credentials);
    await settings.saveEncryption(
      encrypted: false,
      remember: false,
      password: '',
    );
    await settings.saveSchedule(hourly);
    await settings.markAutoBackup(clock.subtract(const Duration(minutes: 90)));
    final subject = scheduler();

    await subject.checkNow();
    await subject.checkNow();

    expect(uploads, hasLength(1));
    subject.dispose();
  });

  test('encryption without a usable password is skipped', () async {
    await settings.saveConnection(config, credentials);
    await settings.saveEncryption(
      encrypted: true,
      remember: false,
      password: '',
    );
    await settings.saveSchedule(hourly);
    await settings.markAutoBackup(clock.subtract(const Duration(hours: 2)));
    final subject = scheduler();

    await subject.checkNow();

    expect(uploads, isEmpty);
    subject.dispose();
  });

  test('an unencrypted upload leaves out account and AI keys', () async {
    await settings.saveConnection(config, credentials);
    await settings.saveEncryption(
      encrypted: false,
      remember: false,
      password: '',
    );
    await settings.saveSchedule(hourly);
    await settings.markAutoBackup(clock.subtract(const Duration(hours: 2)));
    final subject = scheduler();

    await subject.checkNow();

    expect(uploads, hasLength(1));
    final document = await BackupCodec().decode(uploads.single.bytes);
    expect(document.categories, contains(BackupCategory.readingHistory));
    expect(document.categories, isNot(contains(BackupCategory.account)));
    expect(document.categories, isNot(contains(BackupCategory.aiConnection)));
    subject.dispose();
  });

  test('a remembered password encrypts the scheduled upload', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await settings.saveConnection(config, credentials);
    await settings.saveEncryption(
      encrypted: true,
      remember: true,
      password: 'backup-pw',
    );
    await settings.saveSchedule(hourly);
    await settings.markAutoBackup(clock.subtract(const Duration(hours: 2)));
    final subject = scheduler();

    await subject.checkNow();

    expect(uploads, hasLength(1));
    expect(uploads.single.encrypted, isTrue);
    expect(BackupCodec.isEncrypted(uploads.single.bytes), isTrue);
    subject.dispose();
  });

  // 真实计时器链路用假计时器驱动：排期 → 触发 → 备份 → 按间隔重新排期。
  test('the armed timer fires on its own and re-arms', () async {
    await settings.saveConnection(config, credentials);
    await settings.saveEncryption(
      encrypted: false,
      remember: false,
      password: '',
    );
    await settings.saveSchedule(hourly);
    await settings.markAutoBackup(clock.subtract(const Duration(hours: 2)));
    final delays = <Duration>[];
    void Function()? fire;
    final subject = scheduler(
      timerFactory: (delay, callback) {
        delays.add(delay);
        fire = callback;
        return _FakeTimer();
      },
    );

    subject.poke();
    expect(delays.single, Duration.zero);

    fire!();
    await _waitFor(() => uploads.isNotEmpty);
    expect(uploads, hasLength(1));
    // 成功后按定时间隔重新排期，而不是立刻再跑。
    expect(delays.last, const Duration(hours: 1));
    subject.dispose();
  });
}

/// 不真的计时的 Timer 替身，触发由测试手动控制。
class _FakeTimer implements Timer {
  @override
  int get tick => 0;

  @override
  bool get isActive => false;

  @override
  void cancel() {}
}

Future<void> _waitFor(
  bool Function() done, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!done() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
