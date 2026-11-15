import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/app_platform.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('iOS exposes only supported integrations', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(AppPlatform.isIOS, isTrue);
    expect(AppPlatform.supportsReaderVolumeKeys, isFalse);
    expect(AppPlatform.supportsReaderCutout, isFalse);
    expect(AppPlatform.supportsCustomDownloadDirectory, isFalse);
    expect(AppPlatform.supportsDynamicColor, isFalse);
    expect(AppPlatform.supportsAutomaticPackageInstall, isFalse);
  });

  test('Android retains native reader and directory capabilities', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(AppPlatform.supportsReaderVolumeKeys, isTrue);
    expect(AppPlatform.supportsReaderCutout, isTrue);
    expect(AppPlatform.supportsCustomDownloadDirectory, isTrue);
    expect(AppPlatform.supportsDynamicColor, isTrue);
    expect(AppPlatform.supportsAutomaticPackageInstall, isTrue);
  });

  test('desktop never attempts Android volume interception', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(AppPlatform.supportsReaderVolumeKeys, isFalse);
    expect(AppPlatform.supportsReaderCutout, isFalse);
    expect(AppPlatform.supportsCustomDownloadDirectory, isTrue);
  });
}
