import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../models/user_manager.dart';
import '../widgets/github_markdown.dart';
import 'app_dio.dart';
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

  static Future<void> checkAndPrompt(
    BuildContext context, {
    bool auto = false,
  }) async {
    try {
      final updateInfo = await checkForUpdate(respectSkippedVersion: auto);
      if (!context.mounted) return;

      if (updateInfo == null) {
        if (!auto) {
          showToast(context, AppLocalizations.of(context)!.updateAlreadyLatest);
        }
        return;
      }

      // Record latest beta build to dedupe auto-check prompts.
      if (updateInfo.isBetaChannel && updateInfo.assets.isNotEmpty) {
        await UserManager().setLastBetaAssetName(updateInfo.assets.first.name);
      }

      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => _UpdateDialog(updateInfo: updateInfo),
      );
    } catch (_) {
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

class _UpdateDialog extends StatefulWidget {
  final AppUpdateInfo updateInfo;

  const _UpdateDialog({required this.updateInfo});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _submitting = false;
  bool _betaAssetsExpanded = false;

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!launched) {
      showToast(
        context,
        AppLocalizations.of(context)!.updateOpenDownloadFailed,
        isError: true,
      );
      return;
    }
    Navigator.pop(context);
  }

  Future<void> _skipVersion() async {
    setState(() => _submitting = true);
    await UserManager().setSkippedUpdateVersion(
      widget.updateInfo.latestVersion,
    );
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _disableAutoCheck() async {
    setState(() => _submitting = true);
    await UserManager().setAutoCheckUpdate(false);
    if (!mounted) return;
    Navigator.pop(context);
  }

  Widget _buildReleaseNotes(String notes, ColorScheme cs, TextTheme tt) {
    if (notes.trim().isEmpty) {
      return Text(
        AppLocalizations.of(context)!.updateNoReleaseNotes,
        style: TextStyle(color: cs.onSurfaceVariant, height: 1.5),
      );
    }

    return GitHubMarkdown(
      data: notes,
      styleSheet: githubMarkdownStyleSheet(
        context,
        foreground: cs.onSurfaceVariant,
      ),
    );
  }

  Widget _buildAssetTile(
    ReleaseAsset asset,
    ColorScheme cs,
    TextTheme tt, {
    bool showCreated = false,
    String? badge,
    AppLocalizations? l10n,
  }) {
    final subtitleParts = <String>[asset.platform.label];
    if (asset.sizeLabel.isNotEmpty) subtitleParts.add(asset.sizeLabel);
    if (showCreated) {
      subtitleParts.add(asset.relativeCreatedLabel(l10n));
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(asset.platform.icon, size: 22, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        asset.name,
                        style: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: cs.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badge,
                          style: tt.labelSmall?.copyWith(
                            color: cs.onPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 10,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (subtitleParts.isNotEmpty)
                  Text(
                    subtitleParts.join(' · '),
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: AppLocalizations.of(context)!.animeDetailDownloadButton,
            visualDensity: VisualDensity.compact,
            onPressed: _submitting ? null : () => _openUrl(asset.downloadUrl),
            icon: SvgPicture.asset(
              'assets/github.svg',
              width: 18,
              height: 18,
              colorFilter: ColorFilter.mode(cs.primary, BlendMode.srcIn),
            ),
          ),
          IconButton(
            tooltip: AppLocalizations.of(context)!.updateMirrorDownload,
            visualDensity: VisualDensity.compact,
            onPressed: _submitting ? null : () => _openUrl(asset.mirrorUrl),
            icon: Icon(Icons.public, size: 20, color: cs.primary),
          ),
        ],
      ),
    );
  }

  /// Beta channel: latest build is pinned and other builds are collapsed by default.
  List<Widget> _buildBetaAssetWidgets(
    List<ReleaseAsset> assets,
    ColorScheme cs,
    TextTheme tt,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final widgets = <Widget>[];
    if (assets.isEmpty) return widgets;
    widgets.add(
      _buildAssetTile(
        assets.first,
        cs,
        tt,
        showCreated: true,
        badge: l10n.updateLatestBadge,
        l10n: l10n,
      ),
    );
    if (assets.length > 1) {
      widgets.add(_buildBetaExpandToggle(cs, tt, assets.length - 1));
      if (_betaAssetsExpanded) {
        for (final asset in assets.skip(1)) {
          widgets.add(
            _buildAssetTile(asset, cs, tt, showCreated: true, l10n: l10n),
          );
        }
      }
    }
    return widgets;
  }

  Widget _buildBetaExpandToggle(ColorScheme cs, TextTheme tt, int count) {
    return InkWell(
      onTap: _submitting
          ? null
          : () => setState(() => _betaAssetsExpanded = !_betaAssetsExpanded),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _betaAssetsExpanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              _betaAssetsExpanded
                  ? AppLocalizations.of(context)!.updateCollapseOtherVersions
                  : AppLocalizations.of(context)!.updateViewMoreVersions(count),
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isBeta = widget.updateInfo.isBetaChannel;
    final notes = widget.updateInfo.releaseNotes.isEmpty
        ? (isBeta
              ? AppLocalizations.of(context)!.updateCiBuildUnstable
              : AppLocalizations.of(context)!.updateNoReleaseNotes)
        : widget.updateInfo.releaseNotes;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      title: Row(
        children: [
          Expanded(child: Text(AppLocalizations.of(context)!.hasUpdate)),
          IconButton(
            tooltip: AppLocalizations.of(context)!.updateOpenReleasePage,
            visualDensity: VisualDensity.compact,
            onPressed: _submitting
                ? null
                : () => _openUrl(widget.updateInfo.releasePageUrl),
            icon: const Icon(Icons.open_in_new, size: 20),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.updateInfo.releaseName, style: tt.titleSmall),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: _buildReleaseNotes(notes, cs, tt),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  isBeta
                      ? AppLocalizations.of(context)!.updatePackagesBeta
                      : AppLocalizations.of(context)!.updatePackages,
                  style: tt.labelLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Divider(
                    color: cs.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: isBeta
                      ? _buildBetaAssetWidgets(widget.updateInfo.assets, cs, tt)
                      : [
                          for (final asset in widget.updateInfo.assets)
                            _buildAssetTile(
                              asset,
                              cs,
                              tt,
                              l10n: AppLocalizations.of(context)!,
                            ),
                        ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                if (!isBeta)
                  TextButton(
                    onPressed: _submitting ? null : _skipVersion,
                    child: Text(
                      AppLocalizations.of(context)!.updateSkipVersion,
                    ),
                  ),
                TextButton(
                  onPressed: _submitting ? null : _disableAutoCheck,
                  child: Text(
                    AppLocalizations.of(context)!.updateDisableAutoCheck,
                  ),
                ),
                TextButton(
                  onPressed: _submitting ? null : () => Navigator.pop(context),
                  child: Text(AppLocalizations.of(context)!.closeButton),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
