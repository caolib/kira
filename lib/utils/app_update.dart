import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/app_localizations.dart';
import '../models/user_manager.dart';
import 'app_dio.dart';
import 'app_logger.dart';
import 'time_format.dart';
import 'toast.dart';

enum AssetPlatform {
  android('Android', Icons.android),
  windows('Windows', Icons.desktop_windows),
  macos('macOS', Icons.laptop_mac),
  ios('iOS', Icons.phone_iphone),
  linux('Linux', Icons.desktop_mac),
  web('Web', Icons.public),
  unknown('Other', Icons.insert_drive_file);

  final String label;
  final IconData icon;
  const AssetPlatform(this.label, this.icon);
}

class ReleaseAsset {
  final String name;
  final String downloadUrl;
  final String mirrorUrl;
  final int size;
  final AssetPlatform platform;
  final DateTime createdAt;
  // Version parts parsed from filename, e.g. 1.1.3+205 -> [1,1,3,205].
  // Empty when parsing fails; sorting falls back to build time.
  final List<int> versionParts;

  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.mirrorUrl,
    required this.size,
    required this.platform,
    required this.createdAt,
    this.versionParts = const [],
  });

  String get sizeLabel {
    if (size <= 0) return '';
    const kb = 1024;
    const mb = 1024 * 1024;
    const gb = 1024 * 1024 * 1024;
    if (size >= gb) return '${(size / gb).toStringAsFixed(2)} GB';
    if (size >= mb) return '${(size / mb).toStringAsFixed(1)} MB';
    if (size >= kb) return '${(size / kb).toStringAsFixed(1)} KB';
    return '$size B';
  }

  /// Relative description of build time. Falls back to "just now" when
  /// no [AppLocalizations] is provided (e.g. tests).
  String relativeCreatedLabel(AppLocalizations? l10n) {
    if (l10n == null) return TimeFormat.relativeFallback(createdAt);
    return TimeFormat.relative(createdAt, l10n);
  }
}

class AppUpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String releaseName;
  final String releaseNotes;
  final String releasePageUrl;
  final List<ReleaseAsset> assets;
  final bool isBetaChannel;

  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseName,
    required this.releaseNotes,
    required this.releasePageUrl,
    required this.assets,
    this.isBetaChannel = false,
  });
}

/// Observable state for the update flow. The About page listens to
/// [AppUpdateService.state] to render an inline update card.
/// Entry dots use [AppUpdateService.hasUnseenUpdate] instead, so visiting
/// About can dismiss the badge without clearing the update card.
class AppUpdateState {
  final AppUpdateStatus status;
  final AppUpdateInfo? info;
  const AppUpdateState._({required this.status, this.info});
  const AppUpdateState.idle() : this._(status: AppUpdateStatus.idle);
  const AppUpdateState.checking() : this._(status: AppUpdateStatus.checking);
  const AppUpdateState.available(AppUpdateInfo info)
    : this._(status: AppUpdateStatus.available, info: info);
  const AppUpdateState.latest() : this._(status: AppUpdateStatus.latest);
  const AppUpdateState.failed() : this._(status: AppUpdateStatus.failed);
}

enum AppUpdateStatus { idle, checking, available, latest, failed }

class AppUpdateService {
  static const _latestReleaseUrl =
      'https://api.github.com/repos/caolib/kira/releases/latest';
  static const _ciReleaseUrl =
      'https://api.github.com/repos/caolib/kira/releases/tags/CI';
  static final Dio _dio = AppDio.create(
    source: 'app_update',
    options: BaseOptions(
      headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'Kira-App',
      },
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  /// App-wide observable update state. About page update card listens here.
  static final ValueNotifier<AppUpdateState> state = ValueNotifier(
    const AppUpdateState.idle(),
  );

  /// Profile "About" entry / bottom-nav badge. Set when an update becomes
  /// available; cleared when the user opens the About page (or update is gone).
  static final ValueNotifier<bool> hasUnseenUpdate = ValueNotifier(false);

  static AppUpdateInfo? get availableUpdate => state.value.info;

  /// Dismiss entry dots without clearing [state] (update card stays visible).
  ///
  /// Deferred to the next frame so callers (e.g. AboutPage.initState) do not
  /// notify [ValueListenableBuilder]s while the tree is still building.
  static void markUpdateBadgeSeen() {
    if (!hasUnseenUpdate.value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hasUnseenUpdate.value) {
        hasUnseenUpdate.value = false;
      }
    });
  }

  static Future<AppUpdateInfo?> checkForUpdate({
    bool respectSkippedVersion = true,
  }) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;
    final user = UserManager();
    final isBeta = user.isBetaUpdateChannel;
    final url = isBeta ? _ciReleaseUrl : _latestReleaseUrl;
    final response = await _dio.get(url);
    final data = Map<String, dynamic>.from(response.data as Map);

    final tagName = data['tag_name']?.toString() ?? '';
    final releaseName = data['name']?.toString().trim() ?? '';
    final releaseNotes = data['body']?.toString().trim() ?? '';
    final releasePageUrl = data['html_url']?.toString() ?? '';

    final assets = _parseAssets(data['assets'] as List? ?? const []);
    if (assets.isEmpty) return null;

    final currentPlatform = _currentPlatform();

    if (isBeta) {
      return _buildBetaUpdateInfo(
        user: user,
        currentVersion: currentVersion,
        currentBuildNumber: packageInfo.buildNumber,
        tagName: tagName,
        releaseName: releaseName,
        releaseNotes: releaseNotes,
        releasePageUrl: releasePageUrl,
        assets: assets,
        currentPlatform: currentPlatform,
        autoCheck: respectSkippedVersion,
      );
    }

    final latestVersion = _normalizeVersion(tagName);
    if (latestVersion.isEmpty) return null;
    if (_compareVersions(latestVersion, currentVersion) <= 0) return null;

    if (respectSkippedVersion && user.skippedUpdateVersion == latestVersion) {
      return null;
    }

    assets.sort((a, b) {
      final aMatch = a.platform == currentPlatform ? 0 : 1;
      final bMatch = b.platform == currentPlatform ? 0 : 1;
      if (aMatch != bMatch) return aMatch - bMatch;
      return a.platform.index.compareTo(b.platform.index);
    });

    return AppUpdateInfo(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      releaseName: releaseName.isNotEmpty
          ? releaseName
          : 'New version available',
      releaseNotes: releaseNotes,
      releasePageUrl: releasePageUrl,
      assets: assets,
    );
  }

  /// Beta channel points to the CI tag. New CI runs append assets.
  /// Assets are sorted by internal build number descending, falling back to time.
  /// Update checks compare build numbers and use latest asset name to dedupe auto prompts.
  static AppUpdateInfo? _buildBetaUpdateInfo({
    required UserManager user,
    required String currentVersion,
    required String currentBuildNumber,
    required String tagName,
    required String releaseName,
    required String releaseNotes,
    required String releasePageUrl,
    required List<ReleaseAsset> assets,
    required AssetPlatform currentPlatform,
    required bool autoCheck,
  }) {
    // Highest version is the latest build for comparison and auto-check dedupe.
    final newest = _maxByVersion(assets);

    // Compare internal build number: current >= latest means no update.
    if (newest.versionParts.isNotEmpty) {
      final latestBuild = newest.versionParts.last;
      final currentBuild = int.tryParse(currentBuildNumber) ?? 0;
      if (currentBuild >= latestBuild) return null;
    }

    if (autoCheck && user.lastBetaAssetName == newest.name) {
      return null;
    }

    assets.sort((a, b) {
      final aMatch = a.platform == currentPlatform ? 0 : 1;
      final bMatch = b.platform == currentPlatform ? 0 : 1;
      if (aMatch != bMatch) return aMatch - bMatch;
      return _compareByVersionDesc(a, b);
    });

    return AppUpdateInfo(
      currentVersion: currentVersion,
      latestVersion: tagName.isNotEmpty ? tagName : 'CI',
      releaseName: releaseName.isNotEmpty ? releaseName : 'CI build',
      releaseNotes: releaseNotes,
      releasePageUrl: releasePageUrl,
      assets: assets,
      isBetaChannel: true,
    );
  }

  /// Parses internal version like `1.1.3+205` into [major, minor, patch, build].
  static List<int> _parseVersionFromName(String name) {
    final match = RegExp(r'(\d+)\.(\d+)\.(\d+)\+(\d+)').firstMatch(name);
    if (match == null) return const [];
    return [
      int.tryParse(match.group(1)!) ?? 0,
      int.tryParse(match.group(2)!) ?? 0,
      int.tryParse(match.group(3)!) ?? 0,
      int.tryParse(match.group(4)!) ?? 0,
    ];
  }

  /// Compares by internal version descending, falling back to build time.
  static int _compareByVersionDesc(ReleaseAsset a, ReleaseAsset b) {
    if (a.versionParts.isEmpty && b.versionParts.isEmpty) {
      return b.createdAt.compareTo(a.createdAt);
    }
    if (a.versionParts.isEmpty) return 1;
    if (b.versionParts.isEmpty) return -1;
    final length = a.versionParts.length > b.versionParts.length
        ? a.versionParts.length
        : b.versionParts.length;
    for (var i = 0; i < length; i++) {
      final av = i < a.versionParts.length ? a.versionParts[i] : 0;
      final bv = i < b.versionParts.length ? b.versionParts[i] : 0;
      if (av != bv) return bv.compareTo(av); // Descending
    }
    return 0;
  }

  /// Returns the newest asset by version, falling back to build time.
  static ReleaseAsset _maxByVersion(List<ReleaseAsset> assets) {
    return assets.reduce((a, b) => _compareByVersionDesc(a, b) <= 0 ? a : b);
  }

  static List<ReleaseAsset> _parseAssets(List rawAssets) {
    final user = UserManager();
    final assets = <ReleaseAsset>[];
    for (final item in rawAssets) {
      if (item is! Map) continue;
      final asset = Map<String, dynamic>.from(item);
      final name = asset['name']?.toString() ?? '';
      final url = asset['browser_download_url']?.toString() ?? '';
      if (name.isEmpty || url.isEmpty) continue;
      final createdAtStr = asset['created_at']?.toString() ?? '';
      final createdAt =
          DateTime.tryParse(createdAtStr) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      assets.add(
        ReleaseAsset(
          name: name,
          downloadUrl: url,
          mirrorUrl: '${user.updateMirrorPrefix}$url',
          size: (asset['size'] as num?)?.toInt() ?? 0,
          platform: _detectPlatform(name),
          versionParts: _parseVersionFromName(name),
          createdAt: createdAt,
        ),
      );
    }
    return assets;
  }

  /// Checks for an update and writes the result to [state]. No dialog.
  /// [auto] = true: silent background check, only surfaces an available update.
  /// [auto] = false: manual check from the About page — shows a toast on
  /// latest/failed so the user gets feedback for their tap.
  static Future<void> checkAndPrompt(
    BuildContext context, {
    bool auto = false,
  }) async {
    state.value = const AppUpdateState.checking();
    try {
      final updateInfo = await checkForUpdate(respectSkippedVersion: auto);
      if (updateInfo == null) {
        state.value = const AppUpdateState.latest();
        hasUnseenUpdate.value = false;
        if (!auto && context.mounted) {
          showToast(context, AppLocalizations.of(context)!.updateAlreadyLatest);
        }
        return;
      }

      // Record latest beta build to dedupe auto-check prompts.
      if (updateInfo.isBetaChannel && updateInfo.assets.isNotEmpty) {
        await UserManager().setLastBetaAssetName(updateInfo.assets.first.name);
      }

      state.value = AppUpdateState.available(updateInfo);
      // Manual check is only triggered from About; keep the badge off so
      // leaving the page does not re-light a dot the user already saw.
      hasUnseenUpdate.value = auto;
    } catch (_) {
      state.value = const AppUpdateState.failed();
      hasUnseenUpdate.value = false;
      if (!context.mounted || auto) return;
      showToast(
        context,
        AppLocalizations.of(context)!.updateCheckFailedRetryLater,
        isError: true,
      );
    }
  }

  static AssetPlatform _detectPlatform(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.apk')) return AssetPlatform.android;
    if (lower.endsWith('.aab')) return AssetPlatform.android;
    if (lower.endsWith('.exe') || lower.endsWith('.msi')) {
      return AssetPlatform.windows;
    }
    if (lower.contains('windows') || lower.contains('win-')) {
      return AssetPlatform.windows;
    }
    if (lower.endsWith('.dmg') || lower.endsWith('.pkg')) {
      return AssetPlatform.macos;
    }
    if (lower.contains('macos') || lower.contains('darwin')) {
      return AssetPlatform.macos;
    }
    if (lower.endsWith('.ipa')) return AssetPlatform.ios;
    if (lower.endsWith('.deb') ||
        lower.endsWith('.rpm') ||
        lower.endsWith('.appimage')) {
      return AssetPlatform.linux;
    }
    if (lower.contains('linux')) return AssetPlatform.linux;
    if (lower.contains('web')) return AssetPlatform.web;
    return AssetPlatform.unknown;
  }

  static AssetPlatform _currentPlatform() {
    if (Platform.isAndroid) return AssetPlatform.android;
    if (Platform.isIOS) return AssetPlatform.ios;
    if (Platform.isWindows) return AssetPlatform.windows;
    if (Platform.isMacOS) return AssetPlatform.macos;
    if (Platform.isLinux) return AssetPlatform.linux;
    return AssetPlatform.unknown;
  }

  static String _normalizeVersion(String value) {
    return value.trim().replaceFirst(RegExp(r'^[vV]'), '');
  }

  static int _compareVersions(String a, String b) {
    final aParts = a.split(RegExp(r'[.+-]')).map(int.tryParse).toList();
    final bParts = b.split(RegExp(r'[.+-]')).map(int.tryParse).toList();
    final length = aParts.length > bParts.length
        ? aParts.length
        : bParts.length;
    for (var i = 0; i < length; i++) {
      final av = i < aParts.length ? (aParts[i] ?? 0) : 0;
      final bv = i < bParts.length ? (bParts[i] ?? 0) : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }
}

/// Native bridge + downloader for in-app APK self-update (Android only).
/// Downloads the release APK to the app cache dir and asks the system
/// PackageInstaller to install it. Non-Android platforms throw on use;
/// callers gate the UI behind `Platform.isAndroid`.
class ApkInstaller {
  static const _channel = MethodChannel('io.github.caolib.kira/install_apk');

  /// Downloads [url] into the temp cache as [fileName], reporting progress.
  /// Returns the absolute path of the downloaded file.
  static Future<String> downloadToCache(
    String url,
    String fileName, {
    void Function(int received, int total)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final savePath = '${dir.path}/$fileName';
    final file = File(savePath);
    if (await file.exists()) {
      await file.delete();
    }
    await AppUpdateService._dio.download(
      url,
      savePath,
      onReceiveProgress: (received, total) => onProgress?.call(received, total),
    );
    return savePath;
  }

  /// Returns true if the app is allowed to request package installs
  /// (Android O+ "install unknown apps"). Always true on older Android.
  static Future<bool> ensureInstallPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      final granted = await _channel.invokeMethod<bool>(
        'canRequestInstallPackages',
      );
      if (granted == true) return true;
      await _channel.invokeMethod<void>('openInstallPermissionSettings');
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Hands the downloaded APK at [path] to the system installer.
  static Future<void> install(String path) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('In-app install is Android-only');
    }
    await _channel.invokeMethod<void>('installApk', {'path': path});
  }
}

/// State of an in-app APK install, decoupled from any widget lifecycle.
/// Lives in [InAppInstaller.state] so the download survives leaving the
/// About page; re-entering the page re-binds to the same progress.
class InstallState {
  final InstallStatus status;
  final String? assetName;
  final int received; // bytes
  final int total; // bytes, -1 when unknown
  final bool needsPermission; // true when the failure is a missing install perm

  const InstallState._({
    required this.status,
    this.assetName,
    this.received = 0,
    this.total = -1,
    this.needsPermission = false,
  });

  const InstallState.idle() : this._(status: InstallStatus.idle);
  const InstallState.preparing(String name)
    : this._(status: InstallStatus.preparing, assetName: name);
  const InstallState.downloading(
    String name, {
    int received = 0,
    int total = -1,
  }) : this._(
         status: InstallStatus.downloading,
         assetName: name,
         received: received,
         total: total,
       );
  const InstallState.installing(String name)
    : this._(status: InstallStatus.installing, assetName: name);
  const InstallState.done() : this._(status: InstallStatus.done);
  const InstallState.error(String name, {bool needsPermission = false})
    : this._(
        status: InstallStatus.error,
        assetName: name,
        needsPermission: needsPermission,
      );

  bool get isBusy =>
      status == InstallStatus.preparing ||
      status == InstallStatus.downloading ||
      status == InstallStatus.installing;
}

enum InstallStatus { idle, preparing, downloading, installing, done, error }

/// App-wide singleton driving the in-app update install flow. Decoupled from
/// widget lifecycle — download continues if the user leaves the About page,
/// and the system installer is launched automatically on completion.
class InAppInstaller {
  InAppInstaller._();
  static final instance = InAppInstaller._();

  final ValueNotifier<InstallState> state = ValueNotifier(
    const InstallState.idle(),
  );

  bool _busy = false;

  /// Formats a byte count as a human-readable size.
  static String formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const kb = 1024;
    const mb = 1024 * 1024;
    const gb = 1024 * 1024 * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  /// "received / total" progress label, or a plain "preparing" fallback when
  /// total size is still unknown.
  String progressLabel() {
    final s = state.value;
    if (s.total > 0) {
      return '${formatSize(s.received)} / ${formatSize(s.total)}';
    }
    return '';
  }

  /// Runs the full download → permission → install pipeline. Safe to call
  /// without a [BuildContext]; UI listens via [state]. Re-entrant calls are
  /// ignored while a task is in flight.
  Future<void> downloadAndInstall(
    ReleaseAsset asset, {
    bool useMirror = false,
  }) async {
    if (_busy) return;
    if (!Platform.isAndroid) return;
    _busy = true;
    state.value = InstallState.preparing(asset.name);
    try {
      final path = await ApkInstaller.downloadToCache(
        useMirror ? asset.mirrorUrl : asset.downloadUrl,
        asset.name,
        onProgress: (received, total) {
          state.value = InstallState.downloading(
            asset.name,
            received: received,
            total: total,
          );
        },
      );
      state.value = InstallState.installing(asset.name);
      final granted = await ApkInstaller.ensureInstallPermission();
      if (!granted) {
        // Permission flow is async; user returns from settings later. Mark
        // so UI can prompt; the download itself already finished.
        state.value = InstallState.error(asset.name, needsPermission: true);
        return;
      }
      await ApkInstaller.install(path);
      state.value = const InstallState.done();
    } catch (e, st) {
      await AppLogger.instance.recordWarning(
        'in-app update install failed: $e',
        stackTrace: st,
        source: 'app_update',
      );
      state.value = InstallState.error(
        asset.name,
        needsPermission: e is PlatformException,
      );
    } finally {
      _busy = false;
    }
  }

  /// Resets to idle. Called when the user dismisses a finished/error state.
  void reset() {
    if (state.value.isBusy) return;
    state.value = const InstallState.idle();
  }
}
