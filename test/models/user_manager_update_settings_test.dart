import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/secure_credential_store.dart';
import 'package:kira/models/user_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../account_storage_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AccountPreferencesPlatform platform;
  final user = UserManager();
  final now = DateTime.utc(2026, 11, 6, 12);

  Future<void> reload() async {
    SharedPreferences.resetStatic();
    SecureCredentialStore.resetInstance();
    await user.init(persistMigrations: false);
  }

  setUp(() async {
    platform = AccountPreferencesPlatform()..install();
    SecureCredentialStore.resetInstance();
    await user.init(persistMigrations: false);
  });

  tearDown(() {
    platform.dispose();
    SecureCredentialStore.resetInstance();
  });

  test('fresh install defaults to startup without writing a migration', () {
    expect(user.updateCheckFrequency, UpdateCheckFrequency.startup);
    expect(user.isUpdateCheckDue(now: now), isTrue);
    expect(
      platform.values.containsKey('flutter.auto_check_update_frequency'),
      isFalse,
    );
  });

  for (final enabled in [false, true]) {
    test('legacy $enabled survives reload and a new selection wins', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('auto_check_update', enabled);
      await reload();
      expect(
        user.updateCheckFrequency,
        enabled ? UpdateCheckFrequency.startup : UpdateCheckFrequency.never,
      );
      await user.setUpdateCheckFrequency(UpdateCheckFrequency.monthly);
      await reload();
      expect(user.updateCheckFrequency, UpdateCheckFrequency.monthly);
      expect(platform.values['flutter.auto_check_update_frequency'], 'monthly');
    });
  }

  test(
    'frequency and channel timestamps survive preference recreation',
    () async {
      await user.setUpdateCheckFrequency(UpdateCheckFrequency.weekly);
      await user.recordUpdateCheckSuccess('stable', at: now);
      await reload();
      expect(user.updateCheckFrequency, UpdateCheckFrequency.weekly);
      expect(
        user.isUpdateCheckDue(now: now.add(const Duration(days: 6))),
        isFalse,
      );
      expect(
        user.isUpdateCheckDue(now: now.add(const Duration(days: 7))),
        isTrue,
      );
      await user.setUpdateChannel('beta');
      expect(user.isUpdateCheckDue(now: now), isTrue);
      await user.recordUpdateCheckSuccess(
        'beta',
        at: now.add(const Duration(days: 1)),
      );
      await reload();
      expect(
        user.isUpdateCheckDue(now: now.add(const Duration(days: 7))),
        isFalse,
      );
      await user.setUpdateChannel('stable');
      expect(
        user.isUpdateCheckDue(now: now.add(const Duration(days: 7))),
        isTrue,
      );
    },
  );

  test('changing frequency preserves last success and notifies once', () async {
    await user.recordUpdateCheckSuccess(
      'stable',
      at: now.subtract(const Duration(days: 2)),
    );
    var notifications = 0;
    void listener() => notifications++;
    user.addListener(listener);
    addTearDown(() => user.removeListener(listener));
    await user.setUpdateCheckFrequency(UpdateCheckFrequency.weekly);
    expect(notifications, 1);
    expect(user.isUpdateCheckDue(now: now), isFalse);
    await user.setUpdateCheckFrequency(UpdateCheckFrequency.never);
    expect(user.isUpdateCheckDue(now: now), isFalse);
    await user.setUpdateCheckFrequency(UpdateCheckFrequency.daily);
    expect(user.isUpdateCheckDue(now: now), isTrue);
  });

  for (final throws in [false, true]) {
    test(
      'frequency write failure (throws: $throws) preserves durable state',
      () async {
        await user.setUpdateCheckFrequency(UpdateCheckFrequency.weekly);
        platform
          ..failKey = 'auto_check_update_frequency'
          ..failValue = 'never'
          ..throwOnFailure = throws;
        await expectLater(
          user.setUpdateCheckFrequency(UpdateCheckFrequency.never),
          throwsA(anything),
        );
        expect(user.updateCheckFrequency, UpdateCheckFrequency.weekly);
        expect(
          (await SharedPreferences.getInstance()).getString(
            'auto_check_update_frequency',
          ),
          'weekly',
        );
        await reload();
        expect(user.updateCheckFrequency, UpdateCheckFrequency.weekly);
      },
    );

    test(
      'timestamp write failure (throws: $throws) leaves check due',
      () async {
        await user.setUpdateCheckFrequency(UpdateCheckFrequency.daily);
        final old = now.subtract(const Duration(days: 2));
        await user.recordUpdateCheckSuccess('stable', at: old);
        platform
          ..failKey = 'auto_check_update_last_success_stable'
          ..failValue = now.millisecondsSinceEpoch
          ..throwOnFailure = throws;
        await expectLater(
          user.recordUpdateCheckSuccess('stable', at: now),
          throwsA(anything),
        );
        expect(user.isUpdateCheckDue(now: now), isTrue);
        expect(
          (await SharedPreferences.getInstance()).getInt(
            'auto_check_update_last_success_stable',
          ),
          old.millisecondsSinceEpoch,
        );
        await reload();
        expect(user.isUpdateCheckDue(now: now), isTrue);
      },
    );
  }
}
