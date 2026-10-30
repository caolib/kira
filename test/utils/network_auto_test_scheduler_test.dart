import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/api/network/network_api.dart';
import 'package:kira/models/network_settings.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/providers/app_providers.dart';
import 'package:kira/utils/network_auto_test_scheduler.dart';
import 'package:kira/utils/network_latency_tester.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../test_helpers.dart';
import 'network_test_support.dart';

class _FakeApi implements NetworkApi {
  int calls = 0;
  Map<int, Map<String, int?>> results = {
    0: {'slow.test': 500},
    1: {'fast.test': 100},
  };
  Completer<void>? pending;

  @override
  List<String> getRouteHosts(int routeIndex) =>
      results[routeIndex]!.keys.toList();

  @override
  Future<Map<String, int?>> testRouteLatency(
    int routeIndex, {
    void Function(String host, int? latency)? onHostResult,
  }) async {
    calls++;
    await pending?.future;
    final result = results[routeIndex]!;
    for (final entry in result.entries) {
      onHostResult?.call(entry.key, entry.value);
    }
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTimer implements Timer {
  final Duration delay;
  final void Function() callback;
  bool _active = true;

  _FakeTimer(this.delay, this.callback);

  void fire() {
    if (!_active) return;
    _active = false;
    callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _active ? 0 : 1;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final settings = NetworkSettings();
  late _FakeApi api;
  late NetworkLatencyTester tester;
  late NetworkAutoTestScheduler scheduler;
  late DateTime clock;
  late List<_FakeTimer> timers;

  setUp(() async {
    setupSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({});
    await settings.initFromPrefs(await SharedPreferences.getInstance());
    clock = DateTime(2026, 10, 29, 12);
    api = _FakeApi();
    tester = NetworkLatencyTester(api: api, settings: settings);
    timers = [];
    scheduler = NetworkAutoTestScheduler(
      settings: settings,
      tester: tester,
      now: () => clock,
      timerFactory: (delay, callback) {
        final timer = _FakeTimer(delay, callback);
        timers.add(timer);
        return timer;
      },
    );
    scheduler.start();
  });

  tearDown(() {
    scheduler.dispose();
    tester.dispose();
    teardownSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> enable({int hours = 1, Duration? elapsed}) async {
    await settings.setAutoTestEnabled(true);
    await settings.setAutoTestIntervalHours(hours);
    await settings.markAutoTest(clock.subtract(elapsed ?? Duration.zero));
  }

  test('disabled by default does not arm timers or probe routes', () async {
    await scheduler.checkNow();
    expect(timers, isEmpty);
    expect(api.calls, 0);
    expect(settings.apiRoute, 0);
  });

  test('enabling waits one interval instead of probing immediately', () async {
    await enable();
    await scheduler.checkNow();
    expect(api.calls, 0);
    expect(timers.last.delay, const Duration(hours: 1));
  });

  for (final hours in NetworkSettings.autoTestIntervalOptions) {
    test('runs only when the $hours-hour interval expires', () async {
      await enable(hours: hours);
      clock = clock
          .add(Duration(hours: hours))
          .subtract(const Duration(seconds: 1));
      await scheduler.checkNow();
      expect(api.calls, 0);
      expect(timers.last.delay, const Duration(seconds: 1));
      clock = clock.add(const Duration(seconds: 1));
      await scheduler.checkNow();
      expect(api.calls, 2);
      expect(settings.apiRoute, 1);
      expect(settings.lastAutoTestAt, clock);
      expect(timers.last.delay, Duration(hours: hours));
    });
  }

  test(
    'cold start or resume catches up once instead of replaying missed runs',
    () async {
      await enable(elapsed: const Duration(days: 2));
      await scheduler.checkNow();
      await scheduler.checkNow();
      expect(api.calls, 2);
      expect(settings.apiRoute, 1);
    },
  );

  test('timer callback probes even without a network page', () async {
    await enable();
    await scheduler.checkNow();
    clock = clock.add(const Duration(hours: 1));
    timers.last.fire();
    await scheduler.checkNow();
    expect(api.calls, 2);
  });

  test('changing interval and disabling update the armed timer', () async {
    await enable(hours: 24);
    await scheduler.checkNow();
    final oldTimer = timers.last;
    await settings.setAutoTestIntervalHours(3);
    expect(oldTimer.isActive, isFalse);
    await scheduler.checkNow();
    expect(timers.last.delay, const Duration(hours: 3));
    await settings.setAutoTestEnabled(false);
    expect(timers.last.isActive, isFalse);
    clock = clock.add(const Duration(days: 2));
    await scheduler.checkNow();
    expect(api.calls, 0);
  });

  test(
    'all timeouts preserve the route and wait until the next interval',
    () async {
      api.results = {
        0: {'slow.test': null},
        1: {'fast.test': null},
      };
      await enable(elapsed: const Duration(hours: 2));
      await scheduler.checkNow();
      expect(settings.apiRoute, 0);
      expect(api.calls, 2);
      await scheduler.checkNow();
      expect(api.calls, 2);
    },
  );

  test(
    'fixed-node mode selects the lowest-latency node without changing mode',
    () async {
      await settings.setSelectionMode(NetworkSelectionMode.fixedNode);
      await settings.setFixedNodeHost('slow.test');
      await enable(elapsed: const Duration(hours: 2));
      await scheduler.checkNow();
      expect(settings.fixedNodeHost, 'fast.test');
      expect(settings.selectionMode, NetworkSelectionMode.fixedNode);
      expect(settings.apiRoute, 0);
    },
  );

  test(
    'manual and scheduled requests share the same in-flight probe',
    () async {
      api.pending = Completer<void>();
      await enable(elapsed: const Duration(hours: 2));
      final checking = scheduler.checkNow();
      await Future<void>.delayed(Duration.zero);
      final manual = tester.testAndSelect();
      expect(api.calls, 2);
      api.pending!.complete();
      await Future.wait([checking, manual]);
      expect(api.calls, 2);
    },
  );

  test('disabling mid-probe prevents switching', () async {
    api.pending = Completer<void>();
    await enable(elapsed: const Duration(hours: 2));
    final checking = scheduler.checkNow();
    await Future<void>.delayed(Duration.zero);
    await settings.setAutoTestEnabled(false);
    api.pending!.complete();
    await checking;
    expect(settings.apiRoute, 0);
    expect(timers.last.isActive, isFalse);
  });

  test(
    'switching away and back mid-probe preserves the final manual route',
    () async {
      api.pending = Completer<void>();
      await enable(elapsed: const Duration(hours: 2));
      final checking = scheduler.checkNow();
      await Future<void>.delayed(Duration.zero);
      await settings.setApiRoute(1);
      await settings.setApiRoute(0);
      api.pending!.complete();
      await checking;
      expect(settings.apiRoute, 0);
    },
  );

  test(
    'theme notifications during timestamp persistence do not skip a due probe',
    () async {
      scheduler.dispose();
      SharedPreferences.setMockInitialValues({});
      final backend = DelayedNetworkPreferences({
        'flutter.network_auto_test_enabled': true,
        'flutter.network_last_auto_test_at': DateTime.now()
            .subtract(const Duration(hours: 2))
            .millisecondsSinceEpoch,
      });
      SharedPreferencesStorePlatform.instance = backend;
      await UserManager().init();
      backend.writeGate = Completer<void>();
      final container = ProviderContainer(
        overrides: [networkApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      final subject = container.read(networkAutoTestSchedulerProvider)..start();
      final checking = subject.checkNow();
      await backend.writeStarted.future;
      final user = UserManager();
      await user.theme.setBannerVisible(!user.bannerVisible);
      backend.writeGate!.complete();
      await checking;
      expect(api.calls, 2);
      expect(settings.apiRoute, 1);
    },
  );

  test('manual selection made mid-probe is not overwritten', () async {
    api.pending = Completer<void>();
    final checking = tester.testAndSelect();
    await Future<void>.delayed(Duration.zero);
    await settings.setSelectionMode(NetworkSelectionMode.fixedNode);
    await settings.setFixedNodeHost('slow.test');
    api.pending!.complete();
    await checking;
    expect(settings.fixedNodeHost, 'slow.test');
  });

  test(
    'equal route latency preserves the current route and excludes extra hosts',
    () {
      final results = {
        0: {'a.test': 100, 'b.test': 300},
        1: {'c.test': 200, 'd.test': null},
        -1: {'copy.test': 1},
      };
      expect(NetworkLatencyTester.bestAverageRoute(results, current: 1), 1);
      expect(NetworkLatencyTester.bestLatencyHost(results), 'a.test');
    },
  );

  test(
    'backup pause drains probes and prevents selection until resumed',
    () async {
      api.pending = Completer<void>();
      await enable(elapsed: const Duration(hours: 2));
      final checking = scheduler.checkNow();
      await Future<void>.delayed(Duration.zero);
      final paused = NetworkAutoTestScheduler.pauseForRestore();
      api.pending!.complete();
      await Future.wait([checking, paused]);
      expect(settings.apiRoute, 0);
      clock = clock.add(const Duration(hours: 2));
      await scheduler.checkNow();
      expect(api.calls, 2);
      NetworkAutoTestScheduler.resumeAfterRestore();
      await scheduler.checkNow();
      expect(api.calls, 4);
      expect(settings.apiRoute, 1);
    },
  );

  test(
    'reload of configuration changes the schedule without restarting',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('network_auto_test_enabled', true);
      await prefs.setInt('network_auto_test_interval_hours', 6);
      await prefs.setInt(
        'network_last_auto_test_at',
        clock.millisecondsSinceEpoch,
      );
      await settings.initFromPrefs(prefs);
      scheduler.refreshSettings();
      await scheduler.checkNow();
      expect(timers.last.delay, const Duration(hours: 6));
    },
  );
}
