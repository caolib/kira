import 'package:flutter/foundation.dart';

/// Shared capability checks for native integrations and their settings.
///
/// Uses Flutter's target platform so widget tests can exercise iOS without
/// pretending that the Windows test host implements iOS plugins.
abstract final class AppPlatform {
  static bool get isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get supportsReaderVolumeKeys => isAndroid;
  static bool get supportsReaderCutout => isAndroid;

  // iOS external folders need persisted security-scoped bookmarks, not just a
  // path string. Downloads stay in the app's own container until supported.
  static bool get supportsCustomDownloadDirectory => !kIsWeb && !isIOS;

  // The current dynamic-color plugin has no iOS palette implementation.
  static bool get supportsDynamicColor => !kIsWeb && !isIOS;

  // Update checks are cross-platform; automatic package installation is not.
  static bool get supportsAutomaticPackageInstall => isAndroid;
}
