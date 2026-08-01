import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/reader_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ReaderSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = ReaderSettings();
    settings.resetPrefsCache();
    await settings.initFromPrefs(await SharedPreferences.getInstance());
  });

  // ── Default values ────────────────────────────────────────────────────

  group('default values', () {
    test('mode defaults to 0', () {
      expect(settings.mode, 0);
    });

    test('scrollDirection defaults to 2', () {
      expect(settings.scrollDirection, 2);
    });

    test('volumeKey defaults to true', () {
      expect(settings.volumeKey, true);
    });

    test('instantPageTurn defaults to false', () {
      expect(settings.instantPageTurn, false);
    });

    test('pageRTL defaults to false', () {
      expect(settings.pageRTL, false);
    });

    test('dimming defaults to 0.3', () {
      expect(settings.dimming, 0.3);
    });

    test('autoScrollEnabled defaults to false', () {
      expect(settings.autoScrollEnabled, false);
    });

    test('continuousReading defaults to true', () {
      expect(settings.continuousReading, true);
    });

    test('imageLoadTimeout defaults to 15', () {
      expect(settings.imageLoadTimeout, 15);
    });

    test('imageRetryCount defaults to 1', () {
      expect(settings.imageRetryCount, 1);
    });

    test('statusOverlayFps defaults to false', () {
      expect(settings.statusOverlayFps, false);
    });

    test('statusOverlayOrder defaults to time/network/battery/page/fps', () {
      expect(settings.statusOverlayOrder, [
        'time',
        'network',
        'battery',
        'page',
        'fps',
      ]);
    });
  });

  // ── Persistence ──────────────────────────────────────────────────────

  group('persistence', () {
    test('mode persists after re-init', () async {
      await settings.setMode(2);
      expect(settings.mode, 2);

      // Re-init from a fresh prefs instance
      settings.resetPrefsCache();
      final prefs = await SharedPreferences.getInstance();
      await settings.initFromPrefs(prefs);
      expect(settings.mode, 2);
    });

    test('scrollDirection persists after re-init', () async {
      await settings.setScrollDirection(0);
      expect(settings.scrollDirection, 0);

      settings.resetPrefsCache();
      final prefs = await SharedPreferences.getInstance();
      await settings.initFromPrefs(prefs);
      expect(settings.scrollDirection, 0);
    });

    test('volumeKey persists after re-init', () async {
      await settings.setVolumeKey(false);
      expect(settings.volumeKey, false);

      settings.resetPrefsCache();
      final prefs = await SharedPreferences.getInstance();
      await settings.initFromPrefs(prefs);
      expect(settings.volumeKey, false);
    });

    test('instantPageTurn persists after re-init', () async {
      await settings.setInstantPageTurn(true);
      expect(settings.instantPageTurn, true);

      settings.resetPrefsCache();
      final prefs = await SharedPreferences.getInstance();
      await settings.initFromPrefs(prefs);
      expect(settings.instantPageTurn, true);
    });

    test('dimming persists after re-init', () async {
      await settings.setDimming(0.7);
      expect(settings.dimming, 0.7);

      settings.resetPrefsCache();
      final prefs = await SharedPreferences.getInstance();
      await settings.initFromPrefs(prefs);
      expect(settings.dimming, 0.7);
    });

    test('autoScrollEnabled persists after re-init', () async {
      await settings.setAutoScrollEnabled(true);
      expect(settings.autoScrollEnabled, true);

      settings.resetPrefsCache();
      final prefs = await SharedPreferences.getInstance();
      await settings.initFromPrefs(prefs);
      expect(settings.autoScrollEnabled, true);
    });

    test('statusOverlayFps persists after re-init', () async {
      await settings.setStatusOverlayFps(true);
      expect(settings.statusOverlayFps, true);

      settings.resetPrefsCache();
      final prefs = await SharedPreferences.getInstance();
      await settings.initFromPrefs(prefs);
      expect(settings.statusOverlayFps, true);
    });

    test('statusOverlayOrder persists after re-init', () async {
      await settings.setStatusOverlayOrder(['fps', 'time', 'page']);
      expect(settings.statusOverlayOrder, [
        'fps',
        'time',
        'page',
        'network',
        'battery',
      ]);

      settings.resetPrefsCache();
      final prefs = await SharedPreferences.getInstance();
      await settings.initFromPrefs(prefs);
      expect(settings.statusOverlayOrder, [
        'fps',
        'time',
        'page',
        'network',
        'battery',
      ]);
    });

    test(
      'statusOverlayOrder drops unknown ids and appends missing ones',
      () async {
        await settings.setStatusOverlayOrder(['bogus', 'battery', 'time']);
        expect(settings.statusOverlayOrder, [
          'battery',
          'time',
          'network',
          'page',
          'fps',
        ]);
      },
    );

    test('statusOverlayOrder ignores a no-op reorder', () async {
      var callCount = 0;
      settings.addListener(() => callCount++);
      await settings.setStatusOverlayOrder([
        'time',
        'network',
        'battery',
        'page',
        'fps',
      ]);
      expect(callCount, 0);
    });
  });

  // ── notifyListeners ──────────────────────────────────────────────────

  group('notifyListeners', () {
    test('setMode notifies listeners', () async {
      var callCount = 0;
      settings.addListener(() => callCount++);
      await settings.setMode(1);
      expect(callCount, 1);
    });

    test('setScrollDirection notifies listeners', () async {
      var callCount = 0;
      settings.addListener(() => callCount++);
      await settings.setScrollDirection(1);
      expect(callCount, 1);
    });

    test('setVolumeKey notifies listeners', () async {
      var callCount = 0;
      settings.addListener(() => callCount++);
      await settings.setVolumeKey(false);
      expect(callCount, 1);
    });

    test('setDimming notifies listeners', () async {
      var callCount = 0;
      settings.addListener(() => callCount++);
      await settings.setDimming(0.5);
      expect(callCount, 1);
    });

    test('setAutoScrollEnabled notifies listeners', () async {
      var callCount = 0;
      settings.addListener(() => callCount++);
      await settings.setAutoScrollEnabled(true);
      expect(callCount, 1);
    });

    test('setStatusOverlayFps notifies listeners', () async {
      var callCount = 0;
      settings.addListener(() => callCount++);
      await settings.setStatusOverlayFps(true);
      expect(callCount, 1);
    });
  });
}
