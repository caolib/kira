import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/app_update.dart';

/// The update decision must be platform-scoped: a release without an
/// installable asset for the running platform (e.g. APK-only checked from
/// Windows) must never surface as an update.
void main() {
  ReleaseAsset asset(
    String name, {
    required AssetPlatform platform,
    List<int>? versionParts,
  }) {
    return ReleaseAsset(
      name: name,
      downloadUrl: 'https://example.com/$name',
      mirrorUrl: 'https://mirror.example.com/$name',
      size: 1024,
      platform: platform,
      createdAt: DateTime.utc(2026),
      versionParts: versionParts ?? const [],
    );
  }

  group('buildStableUpdateInfo', () {
    const base = (
      tagName: 'v1.5.0',
      releaseName: 'App v1.5.0',
      notes: 'notes',
      pageUrl: 'https://github.com/caolib/kira/releases/tag/v1.5.0',
    );

    AppUpdateInfo? check({
      required String currentVersion,
      required List<ReleaseAsset> assets,
      AssetPlatform platform = AssetPlatform.windows,
      String? skippedVersion,
    }) {
      return AppUpdateService.buildStableUpdateInfo(
        currentVersion: currentVersion,
        tagName: base.tagName,
        releaseName: base.releaseName,
        releaseNotes: base.notes,
        releasePageUrl: base.pageUrl,
        assets: assets,
        currentPlatform: platform,
        skippedVersion: skippedVersion,
      );
    }

    test('newer release with no asset for the platform is not an update', () {
      final info = check(
        currentVersion: '1.4.0',
        assets: [
          asset('kira-v1.5.0-arm64-v8a.apk', platform: AssetPlatform.android),
        ],
      );
      expect(info, isNotNull);
      expect(info!.noAssetForPlatform, isTrue);
      expect(info.isCurrentVersion, isFalse);
      expect(info.latestVersion, '1.5.0');
    });

    test(
      'newer release with a platform asset is an update, platform first',
      () {
        final info = check(
          currentVersion: '1.4.0',
          assets: [
            asset('kira-v1.5.0-arm64-v8a.apk', platform: AssetPlatform.android),
            asset('kira-v1.5.0-windows.exe', platform: AssetPlatform.windows),
          ],
        );
        expect(info, isNotNull);
        expect(info!.noAssetForPlatform, isFalse);
        expect(info.assets.first.platform, AssetPlatform.windows);
      },
    );

    test('tag equal to installed version reports current version', () {
      final info = check(
        currentVersion: '1.5.0',
        assets: [
          asset('kira-v1.5.0-windows.exe', platform: AssetPlatform.windows),
        ],
      );
      expect(info, isNotNull);
      expect(info!.isCurrentVersion, isTrue);
      expect(info.noAssetForPlatform, isFalse);
    });

    test('skipped version suppresses the update', () {
      final info = check(
        currentVersion: '1.4.0',
        assets: [
          asset('kira-v1.5.0-windows.exe', platform: AssetPlatform.windows),
        ],
        skippedVersion: '1.5.0',
      );
      expect(info, isNull);
    });

    test('empty tag yields nothing', () {
      final info = AppUpdateService.buildStableUpdateInfo(
        currentVersion: '1.4.0',
        tagName: '  ',
        releaseName: '',
        releaseNotes: '',
        releasePageUrl: '',
        assets: [
          asset('kira-v1.5.0-windows.exe', platform: AssetPlatform.windows),
        ],
        currentPlatform: AssetPlatform.windows,
      );
      expect(info, isNull);
    });
  });

  group('buildBetaUpdateInfo', () {
    const tagName = 'CI';

    AppUpdateInfo? check({
      required String currentBuildNumber,
      required List<ReleaseAsset> assets,
      AssetPlatform platform = AssetPlatform.windows,
      String? lastBetaAssetName,
    }) {
      return AppUpdateService.buildBetaUpdateInfo(
        currentVersion: '1.3.2',
        currentBuildNumber: currentBuildNumber,
        tagName: tagName,
        releaseName: 'CI APK',
        releaseNotes: '',
        releasePageUrl: '',
        assets: assets,
        currentPlatform: platform,
        lastBetaAssetName: lastBetaAssetName,
      );
    }

    test(
      'a newer APK build does not prompt a Windows install (regression)',
      () {
        final info = check(
          currentBuildNumber: '370',
          assets: [
            asset(
              'kira-1.3.2+371-arm64-v8a.apk',
              platform: AssetPlatform.android,
              versionParts: [1, 3, 2, 371],
            ),
            asset(
              'kira-1.3.1+368-windows.exe',
              platform: AssetPlatform.windows,
              versionParts: [1, 3, 1, 368],
            ),
          ],
        );
        expect(info, isNotNull);
        expect(info!.isCurrentVersion, isTrue);
        expect(info.noAssetForPlatform, isFalse);
      },
    );

    test('newer platform build is an update, platform asset first', () {
      final info = check(
        currentBuildNumber: '370',
        assets: [
          asset(
            'kira-1.3.2+372-arm64-v8a.apk',
            platform: AssetPlatform.android,
            versionParts: [1, 3, 2, 372],
          ),
          asset(
            'kira-1.3.3+371-windows.exe',
            platform: AssetPlatform.windows,
            versionParts: [1, 3, 3, 371],
          ),
        ],
      );
      expect(info, isNotNull);
      expect(info!.isCurrentVersion, isFalse);
      expect(info.isBetaChannel, isTrue);
      expect(info.assets.first.platform, AssetPlatform.windows);
    });

    test('auto check dedupes on the newest platform asset name', () {
      final info = check(
        currentBuildNumber: '370',
        assets: [
          asset(
            'kira-1.3.3+371-windows.exe',
            platform: AssetPlatform.windows,
            versionParts: [1, 3, 3, 371],
          ),
        ],
        lastBetaAssetName: 'kira-1.3.3+371-windows.exe',
      );
      expect(info, isNull);
    });

    test('dedupe ignores non-platform asset names', () {
      final info = check(
        currentBuildNumber: '370',
        assets: [
          asset(
            'kira-1.3.3+371-windows.exe',
            platform: AssetPlatform.windows,
            versionParts: [1, 3, 3, 371],
          ),
          asset(
            'kira-1.3.3+372-arm64-v8a.apk',
            platform: AssetPlatform.android,
            versionParts: [1, 3, 3, 372],
          ),
        ],
        lastBetaAssetName: 'kira-1.3.3+372-arm64-v8a.apk',
      );
      expect(info, isNotNull);
    });

    test('no platform asset at all is not an update', () {
      final info = check(
        currentBuildNumber: '370',
        assets: [
          asset(
            'kira-1.3.3+371-arm64-v8a.apk',
            platform: AssetPlatform.android,
            versionParts: [1, 3, 3, 371],
          ),
        ],
      );
      expect(info, isNotNull);
      expect(info!.noAssetForPlatform, isTrue);
      expect(info.isBetaChannel, isTrue);
    });
  });
}
