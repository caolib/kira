import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kira/backup/backup_category.dart';
import 'package:kira/models/network_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../utils/network_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final settings = NetworkSettings();

  Future<SharedPreferences> load(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    final prefs = await SharedPreferences.getInstance();
    await settings.initFromPrefs(prefs);
    return prefs;
  }

  test(
    'automatic tests default to disabled with a one-hour interval',
    () async {
      await load({});
      expect(settings.autoTestEnabled, isFalse);
      expect(settings.autoTestInterval, const Duration(hours: 1));
      expect(settings.lastAutoTestAt, isNull);
    },
  );

  test('settings and the last attempt survive reinitialization', () async {
    final prefs = await load({});
    await settings.setAutoTestEnabled(true);
    await settings.setAutoTestIntervalHours(6);
    final time = DateTime(2026, 10, 29, 12);
    await settings.markAutoTest(time);
    await settings.initFromPrefs(prefs);
    expect(settings.autoTestEnabled, isTrue);
    expect(settings.autoTestInterval, const Duration(hours: 6));
    expect(settings.lastAutoTestAt, time);
    expect(prefs.getBool('network_auto_test_enabled'), isTrue);
    expect(prefs.getInt('network_auto_test_interval_hours'), 6);
    expect(
      prefs.getInt('network_last_auto_test_at'),
      time.millisecondsSinceEpoch,
    );
  });

  test('only the four supported intervals are accepted', () async {
    await load({});
    for (final hours in NetworkSettings.autoTestIntervalOptions) {
      await settings.setAutoTestIntervalHours(hours);
      expect(settings.autoTestIntervalHours, hours);
    }
    await settings.setAutoTestIntervalHours(2);
    expect(settings.autoTestIntervalHours, 1);
    await load({'network_auto_test_interval_hours': -1});
    expect(settings.autoTestIntervalHours, 1);
  });

  test(
    'rapid enable then disable persists the final state across restart',
    () async {
      await load({});
      final backend = DelayedNetworkPreferences()
        ..writeGate = Completer<void>();
      SharedPreferencesStorePlatform.instance = backend;
      settings.resetPrefsCache();
      await settings.initFromPrefs(await SharedPreferences.getInstance());
      final enabling = settings.setAutoTestEnabled(true);
      await backend.writeStarted.future;
      final disabling = settings.setAutoTestEnabled(false);
      expect(settings.autoTestEnabled, isFalse);
      backend.writeGate!.complete();
      await Future.wait([enabling, disabling]);

      SharedPreferences.setMockInitialValues({});
      SharedPreferencesStorePlatform.instance = backend;
      settings.resetPrefsCache();
      await settings.initFromPrefs(await SharedPreferences.getInstance());
      expect(settings.autoTestEnabled, isFalse);
      expect(backend.values['flutter.network_auto_test_enabled'], isFalse);
      SharedPreferences.setMockInitialValues({});
    },
  );

  test('re-enabling starts a fresh interval', () async {
    await load({});
    await settings.setAutoTestEnabled(true);
    final oldTime = DateTime(2020);
    await settings.markAutoTest(oldTime);
    await settings.setAutoTestEnabled(false);
    await settings.setAutoTestEnabled(true);
    expect(settings.lastAutoTestAt!.isAfter(oldTime), isTrue);
  });

  test('configuration is backed up, but the runtime timestamp is excluded', () {
    expect(
      BackupSchema.categoryOf('network_auto_test_enabled'),
      BackupCategory.settings,
    );
    expect(
      BackupSchema.categoryOf('network_auto_test_interval_hours'),
      BackupCategory.settings,
    );
    expect(BackupSchema.categoryOf('network_last_auto_test_at'), isNull);
  });
}
