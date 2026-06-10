import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/user_manager.dart';
import 'network_error.dart';
import 'toast.dart';

enum AssetPlatform {
  android('Android', Icons.android),
  windows('Windows', Icons.desktop_windows),
  macos('macOS', Icons.laptop_mac),
  ios('iOS', Icons.phone_iphone),
  linux('Linux', Icons.desktop_mac),
  web('Web', Icons.public),
  unknown('其他', Icons.insert_drive_file);

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

  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.mirrorUrl,
    required this.size,
    required this.platform,
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
}

class AppUpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String releaseName;
  final String releaseNotes;
  final String releasePageUrl;
  final List<ReleaseAsset> assets;

  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseName,
    required this.releaseNotes,
    required this.releasePageUrl,
    required this.assets,
  });
}

class AppUpdateService {
  static const _latestReleaseUrl =
      'https://api.github.com/repos/caolib/kira/releases/latest';
  static final Dio _dio = Dio(
    BaseOptions(
      headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'Kira-App',
      },
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  )..interceptors.add(NetworkError.rateLimitInterceptor());

  static Future<AppUpdateInfo?> checkForUpdate({
    bool respectSkippedVersion = true,
  }) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;
    final response = await _dio.get(_latestReleaseUrl);
    final data = Map<String, dynamic>.from(response.data as Map);
    final tagName = data['tag_name']?.toString() ?? '';
    final latestVersion = _normalizeVersion(tagName);
    if (latestVersion.isEmpty) return null;
    if (_compareVersions(latestVersion, currentVersion) <= 0) return null;

    final user = UserManager();
    if (respectSkippedVersion && user.skippedUpdateVersion == latestVersion) {
      return null;
    }

    final rawAssets = (data['assets'] as List?) ?? const [];
    final assets = <ReleaseAsset>[];
    for (final item in rawAssets) {
      if (item is! Map) continue;
      final asset = Map<String, dynamic>.from(item);
      final name = asset['name']?.toString() ?? '';
      final url = asset['browser_download_url']?.toString() ?? '';
      if (name.isEmpty || url.isEmpty) continue;
      assets.add(
        ReleaseAsset(
          name: name,
          downloadUrl: url,
          mirrorUrl: '${user.updateMirrorPrefix}$url',
          size: (asset['size'] as num?)?.toInt() ?? 0,
          platform: _detectPlatform(name),
        ),
      );
    }
    if (assets.isEmpty) return null;

    final currentPlatform = _currentPlatform();
    assets.sort((a, b) {
      final aMatch = a.platform == currentPlatform ? 0 : 1;
      final bMatch = b.platform == currentPlatform ? 0 : 1;
      if (aMatch != bMatch) return aMatch - bMatch;
      return a.platform.index.compareTo(b.platform.index);
    });

    return AppUpdateInfo(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      releaseName: data['name']?.toString() ?? '发现新版本',
      releaseNotes: data['body']?.toString().trim() ?? '',
      releasePageUrl: data['html_url']?.toString() ?? '',
      assets: assets,
    );
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
          showToast(context, '当前已是最新版本');
        }
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => _UpdateDialog(updateInfo: updateInfo),
      );
    } catch (_) {
      if (!context.mounted || auto) return;
      showToast(context, '检查更新失败，请稍后重试', isError: true);
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

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!launched) {
      showToast(context, '无法打开下载链接', isError: true);
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
    final lines = notes.split('\n');
    final children = <Widget>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('## ')) {
        if (children.isNotEmpty) children.add(const SizedBox(height: 10));
        children.add(
          Text(
            trimmed.substring(3),
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        );
      } else if (trimmed.startsWith('- ')) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• ', style: TextStyle(color: cs.onSurfaceVariant)),
                Expanded(
                  child: Text(
                    trimmed
                        .substring(2)
                        .replaceFirst(RegExp(r'^\[.*?\]\s*'), '')
                        .replaceFirst(RegExp(r'^\S+\s+\w+:\s*'), ''),
                    style: TextStyle(color: cs.onSurfaceVariant, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              trimmed,
              style: TextStyle(color: cs.onSurfaceVariant, height: 1.5),
            ),
          ),
        );
      }
    }

    if (children.isEmpty) {
      return Text(
        '暂无更新说明',
        style: TextStyle(color: cs.onSurfaceVariant, height: 1.5),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _buildAssetTile(ReleaseAsset asset, ColorScheme cs, TextTheme tt) {
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
                Text(
                  asset.name,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (asset.sizeLabel.isNotEmpty)
                  Text(
                    '${asset.platform.label} · ${asset.sizeLabel}',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: '下载',
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
            tooltip: '镜像下载',
            visualDensity: VisualDensity.compact,
            onPressed: _submitting ? null : () => _openUrl(asset.mirrorUrl),
            icon: Icon(Icons.public, size: 20, color: cs.primary),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final notes = widget.updateInfo.releaseNotes.isEmpty
        ? '暂无更新说明'
        : widget.updateInfo.releaseNotes;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      title: Row(
        children: [
          const Expanded(child: Text('有更新')),
          IconButton(
            tooltip: '打开发布页',
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
                  '安装包',
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
                  children: [
                    for (final asset in widget.updateInfo.assets)
                      _buildAssetTile(asset, cs, tt),
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
                TextButton(
                  onPressed: _submitting ? null : _skipVersion,
                  child: const Text('跳过此版本'),
                ),
                TextButton(
                  onPressed: _submitting ? null : _disableAutoCheck,
                  child: const Text('取消自动检查更新'),
                ),
                TextButton(
                  onPressed: _submitting ? null : () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
