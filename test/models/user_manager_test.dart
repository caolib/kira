import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/user_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('image viewer auto-rotate settings persist', () async {
    final user = UserManager();
    await user.init();

    expect(user.imageViewerAutoRotateLandscape, isFalse);
    expect(user.imageViewerLandscapeRotation, 1);

    await user.setImageViewerAutoRotateLandscape(true);
    await user.setImageViewerLandscapeRotation(-1);
    await user.init();

    expect(user.imageViewerAutoRotateLandscape, isTrue);
    expect(user.imageViewerLandscapeRotation, -1);
  });

  test('image viewer rotation normalizes to left or right', () async {
    final user = UserManager();
    await user.init();

    await user.setImageViewerLandscapeRotation(0);
    expect(user.imageViewerLandscapeRotation, 1);

    await user.setImageViewerLandscapeRotation(-90);
    expect(user.imageViewerLandscapeRotation, -1);
  });

  test('anime home banner collapsed setting persists', () async {
    final user = UserManager();
    await user.init();

    expect(user.animeHomeBannerCollapsed, isFalse);

    await user.setAnimeHomeBannerCollapsed(true);
    await user.init();

    expect(user.animeHomeBannerCollapsed, isTrue);
  });

  test(
    'anime playback progress setting defaults to enabled and persists',
    () async {
      final user = UserManager();
      await user.init();

      expect(user.animePlaybackProgressEnabled, isTrue);

      await user.setAnimePlaybackProgressEnabled(false);
      await user.init();

      expect(user.animePlaybackProgressEnabled, isFalse);
    },
  );

  test('anime feature setting defaults to enabled and persists', () async {
    final user = UserManager();
    await user.init();

    expect(user.animeFeatureEnabled, isTrue);

    await user.setAnimeFeatureEnabled(false);
    await user.init();

    expect(user.animeFeatureEnabled, isFalse);
  });

  test('network selection mode and fixed node persist', () async {
    final user = UserManager();
    await user.init();

    expect(user.networkSelectionMode, NetworkSelectionMode.route);

    await user.setFixedNodeHost('mapi.hotmangasd.com');
    await user.setNetworkSelectionMode(NetworkSelectionMode.fixedNode);
    await user.init();

    expect(user.networkSelectionMode, NetworkSelectionMode.fixedNode);
    expect(user.fixedNodeHost, 'mapi.hotmangasd.com');
  });

  test(
    'a persisted legacy automatic(==2) selection mode falls back to route on init',
    () async {
      // 历史版本曾持久化索引 2(automatic),该模式已删除,init 后应回落 route。
      SharedPreferences.setMockInitialValues(<String, Object>{
        'network_selection_mode': 2,
      });
      UserManager().network.resetPrefsCache();
      var user = UserManager();
      await user.init();
      expect(user.networkSelectionMode, NetworkSelectionMode.route);

      // 模拟重启:回落后的 route 索引应被持久化,再次 init 仍是 route。
      UserManager().network.resetPrefsCache();
      user = UserManager();
      await user.init();
      expect(user.networkSelectionMode, NetworkSelectionMode.route);
    },
  );

  test('last nav key defaults to comic and persists', () async {
    final user = UserManager();
    await user.init();

    expect(user.lastNavKey, UserManager.defaultNavKey);

    await user.setLastNavKey('search');
    await user.init();

    expect(user.lastNavKey, 'search');
  });

  test('last nav key falls back to comic when saved key is invalid', () async {
    SharedPreferences.setMockInitialValues({'last_nav_key': 'missing'});

    final user = UserManager();
    await user.init();

    expect(user.lastNavKey, UserManager.defaultNavKey);
  });

  test('dark mode cover brightness defaults and persists', () async {
    final user = UserManager();
    await user.init();

    expect(
      user.darkModeCoverBrightness,
      UserManager.defaultDarkModeCoverBrightness,
    );

    await user.setDarkModeCoverBrightness(0.7);
    await user.init();

    expect(user.darkModeCoverBrightness, 0.7);
  });

  test('dark mode cover brightness allows 10 percent minimum', () async {
    final user = UserManager();
    await user.init();

    await user.setDarkModeCoverBrightness(0.1);
    expect(user.darkModeCoverBrightness, 0.1);

    await user.setDarkModeCoverBrightness(0.05);
    expect(
      user.darkModeCoverBrightness,
      UserManager.minDarkModeCoverBrightness,
    );
  });

  test('display mode refresh rate defaults to auto and persists', () async {
    final user = UserManager();
    await user.init();

    expect(
      user.displayModeRefreshRate,
      UserManager.defaultDisplayModeRefreshRate,
    );

    await user.setDisplayModeRefreshRate(120);
    await user.init();

    expect(user.displayModeRefreshRate, 120);
  });

  test('display mode refresh rate falls back to auto when invalid', () async {
    SharedPreferences.setMockInitialValues({
      'pref_display_mode_refresh_rate': -1,
    });

    final user = UserManager();
    await user.init();

    expect(
      user.displayModeRefreshRate,
      UserManager.defaultDisplayModeRefreshRate,
    );
  });
}
