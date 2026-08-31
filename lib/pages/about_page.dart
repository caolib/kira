import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../models/user_manager.dart';
import '../routing/app_router.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/app_update.dart';
import '../utils/screen_layout.dart';
import '../utils/toast.dart';
import '../widgets/github_markdown.dart';
import '../widgets/text_controller_scope.dart';

class SettingIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const SettingIcon({super.key, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: AppRadius.mdR,
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

// ── 关于页 ──

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  final _user = UserManager();

  static const _repoUrl = 'https://github.com/caolib/kira';
  static const _qqGroupUrl = 'https://qm.qq.com/q/rezw7xWuK4';
  static const _qqGroupNumber = '1025321453';

  void _showQQGroupDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset(
                'assets/qq.svg',
                width: 64,
                height: 64,
                colorFilter: const ColorFilter.mode(
                  Color(0xFF1EBAFC),
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                l10n.aboutQqGroupTitle,
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppSpacing.xl),
              InkWell(
                onTap: () async {
                  await launchUrl(
                    Uri.parse(_qqGroupUrl),
                    mode: LaunchMode.externalApplication,
                  );
                },
                borderRadius: AppRadius.mdR,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.08),
                    borderRadius: AppRadius.mdR,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.open_in_new, size: 18, color: cs.primary),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        l10n.aboutJoinGroupButton,
                        style: tt.bodyLarge?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              InkWell(
                onTap: () async {
                  await Clipboard.setData(
                    const ClipboardData(text: _qqGroupNumber),
                  );
                  if (dialogContext.mounted) {
                    showToast(dialogContext, l10n.aboutGroupNumberCopiedToast);
                  }
                },
                borderRadius: AppRadius.mdR,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: AppRadius.mdR,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _qqGroupNumber,
                        style: tt.titleMedium?.copyWith(
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Icon(
                        Icons.copy_rounded,
                        size: 18,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.closeButton),
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _user.addListener(_onChanged);
    // Entry dots (profile "About" + bottom-nav) clear on open; update card keeps state.
    AppUpdateService.markUpdateBadgeSeen();
    // If no check has run yet, silently fetch so the About page can show the
    // current version's changelog (and surface an available update). auto=true
    // keeps it badge-free and toast-free.
    if (AppUpdateService.state.value.status == AppUpdateStatus.idle) {
      AppUpdateService.checkAndPrompt(context, auto: true);
    }
  }

  @override
  void dispose() {
    _user.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  bool _isValidUpdateMirrorPrefix(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.hasScheme &&
        uri.hasAuthority &&
        (uri.scheme == 'http' || uri.scheme == 'https');
  }

  Future<void> _editUpdateMirrorPrefix() async {
    final l10n = AppLocalizations.of(context)!;
    final formKey = GlobalKey<FormState>();

    // 控制器交给 TextControllerScope 托管：弹窗退出动画期间子树仍会重建，
    // 提前 dispose 会命中 “used after being disposed” 断言。
    final mirrorPrefix = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final cs = Theme.of(dialogContext).colorScheme;
        final tt = Theme.of(dialogContext).textTheme;

        return TextControllerScope(
          initialText: _user.updateMirrorPrefix,
          builder: (dialogContext, controller) => AlertDialog(
            title: Text(l10n.aboutMirrorPrefixTitle),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.aboutMirrorPrefixDesc,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: controller,
                      autofocus: true,
                      keyboardType: TextInputType.url,
                      inputFormatters: [
                        FilteringTextInputFormatter.deny(RegExp(r'\s')),
                      ],
                      decoration: InputDecoration(
                        labelText: l10n.aboutMirrorPrefixLabel,
                        hintText: UserManager.defaultUpdateMirrorPrefix,
                        helperText: l10n.aboutMirrorPrefixHelper,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final trimmed = value?.trim() ?? '';
                        if (trimmed.isEmpty) return null;
                        if (!_isValidUpdateMirrorPrefix(trimmed)) {
                          return l10n.aboutInvalidMirrorPrefix;
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  UserManager.defaultUpdateMirrorPrefix,
                ),
                child: Text(l10n.aboutRestoreDefaultButton),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(l10n.cancelButton),
              ),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState?.validate() ?? false) {
                    Navigator.pop(dialogContext, controller.text);
                  }
                },
                child: Text(l10n.aboutSaveButton),
              ),
            ],
          ),
        );
      },
    );

    if (mirrorPrefix == null) return;
    await _user.setUpdateMirrorPrefix(mirrorPrefix);
    if (!mounted) return;
    showToast(context, l10n.aboutMirrorPrefixSavedToast);
  }

  Widget _buildUpdateChannelChip(ColorScheme cs, AppLocalizations l10n) {
    final isBeta = _user.isBetaUpdateChannel;
    final fg = isBeta ? Colors.amber.shade900 : cs.onSurfaceVariant;
    return InkWell(
      onTap: _showUpdateChannelDialog,
      borderRadius: AppRadius.xlR,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isBeta
              ? Colors.amber.withValues(alpha: 0.14)
              : cs.surfaceContainerHighest,
          borderRadius: AppRadius.xlR,
          border: Border.all(color: isBeta ? Colors.amber : cs.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isBeta ? Icons.science_outlined : Icons.flag_outlined,
              size: 14,
              color: fg,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              isBeta ? 'Beta' : l10n.aboutStableChannelShort,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showUpdateChannelDialog() async {
    final l10n = AppLocalizations.of(context)!;
    var selected = _user.updateChannel;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: Text(l10n.aboutUpdateChannelTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioGroup<String>(
                    groupValue: selected,
                    onChanged: (value) {
                      if (value != null) setState(() => selected = value);
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          value: 'stable',
                          title: Text(l10n.aboutStableChannelTitle),
                          subtitle: Text(l10n.aboutStableChannelDesc),
                        ),
                        RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          value: 'beta',
                          title: Text(l10n.aboutBetaChannelTitle),
                          subtitle: Text(l10n.aboutBetaChannelDesc),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n.cancelButton),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, selected),
                  child: Text(l10n.confirmButton),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null && result != _user.updateChannel) {
      await _user.setUpdateChannel(result);
      if (!mounted) return;
      if (result == 'beta') {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.aboutBetaChannelSwitchedTitle),
            content: Text(l10n.aboutBetaChannelSwitchedContent),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.aboutGotItButton),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutTitle)),
      body: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snapshot) {
          final version = snapshot.hasData
              ? '${snapshot.data!.version}+${snapshot.data!.buildNumber}'
              : '...';

          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            children: [
              // Compact horizontal brand header: logo + name/version.
              Row(
                children: [
                  ClipRRect(
                    borderRadius: AppRadius.lgR,
                    child: Image.asset(
                      _user.appLogoPath,
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Kira',
                          style: tt.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          version,
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              _UpdateCard(
                onCheckUpdate: () => AppUpdateService.checkAndPrompt(context),
              ),
              const SizedBox(height: AppSpacing.lg),
              Card(
                color: cs.surfaceContainerLow,
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      Expanded(
                        child: _LinkAction(
                          icon: SvgPicture.asset(
                            'assets/github.svg',
                            width: 24,
                            height: 24,
                            colorFilter: ColorFilter.mode(
                              cs.onSurfaceVariant,
                              BlendMode.srcIn,
                            ),
                          ),
                          label: l10n.aboutRepositoryLabel,
                          onTap: () async {
                            await launchUrl(
                              Uri.parse(_repoUrl),
                              mode: LaunchMode.externalApplication,
                            );
                          },
                        ),
                      ),
                      VerticalDivider(
                        width: 1,
                        color: cs.outlineVariant.withValues(alpha: 0.5),
                      ),
                      Expanded(
                        child: _LinkAction(
                          icon: const Icon(Icons.feedback_outlined),
                          label: l10n.aboutFeedbackLabel,
                          onTap: () async {
                            await launchUrl(
                              Uri.parse(
                                'https://github.com/caolib/kira/issues/new/choose',
                              ),
                              mode: LaunchMode.externalApplication,
                            );
                          },
                        ),
                      ),
                      VerticalDivider(
                        width: 1,
                        color: cs.outlineVariant.withValues(alpha: 0.5),
                      ),
                      Expanded(
                        child: _LinkAction(
                          icon: SvgPicture.asset(
                            'assets/qq.svg',
                            width: 24,
                            height: 24,
                            colorFilter: const ColorFilter.mode(
                              Color(0xFF1EBAFC),
                              BlendMode.srcIn,
                            ),
                          ),
                          label: l10n.aboutCommunityLabel,
                          onTap: () => _showQQGroupDialog(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              // 宽屏：更新设置与法律/致谢两卡双列并排；窄屏纵向堆叠。
              if (ScreenLayout.contentWidth(MediaQuery.sizeOf(context).width) >=
                  ScreenLayout.wideBreakpoint)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildUpdateSettingsCard(cs, l10n)),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(child: _buildLegalCard(cs, l10n)),
                  ],
                )
              else ...[
                _buildUpdateSettingsCard(cs, l10n),
                const SizedBox(height: AppSpacing.lg),
                _buildLegalCard(cs, l10n),
              ],
            ],
          );
        },
      ),
    );
  }

  /// 更新设置卡：检查更新 / 自动检查 / 更新镜像。
  Widget _buildUpdateSettingsCard(ColorScheme cs, AppLocalizations l10n) {
    return Card(
      color: cs.surfaceContainerLow,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.system_update_alt),
            title: Text(l10n.aboutCheckUpdateTitle),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildUpdateChannelChip(cs, l10n),
                const SizedBox(width: AppSpacing.xs),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () => AppUpdateService.checkAndPrompt(context),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          SwitchListTile(
            secondary: const Icon(Icons.autorenew),
            title: Text(l10n.aboutAutoCheckUpdateTitle),
            value: _user.autoCheckUpdate,
            onChanged: _user.setAutoCheckUpdate,
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          ListTile(
            leading: const Icon(Icons.public),
            title: Text(l10n.aboutMirrorPrefixTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: _editUpdateMirrorPrefix,
          ),
        ],
      ),
    );
  }

  /// 法律/致谢卡：免责声明 / 日志 / 鸣谢 / 许可证。
  Widget _buildLegalCard(ColorScheme cs, AppLocalizations l10n) {
    return Card(
      color: cs.surfaceContainerLow,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: Text(l10n.disclaimerTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.pushNamed(AppRoutes.disclaimer),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: Text(l10n.aboutLogTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.pushNamed(AppRoutes.appLog),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          ListTile(
            leading: const Icon(Icons.favorite_outline),
            title: Text(l10n.aboutAcknowledgementTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.pushNamed(AppRoutes.acknowledgement),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          ListTile(
            leading: const Icon(Icons.copyright_outlined),
            title: Text(l10n.aboutLicenseTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.pushNamed(AppRoutes.license),
          ),
        ],
      ),
    );
  }
}

class _LinkAction extends StatelessWidget {
  const _LinkAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Widget icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 16,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                label,
                style: tt.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Inline update card rendered on the About page. Replaces the old modal
/// update dialog — listens to [AppUpdateService.state] and surfaces an
/// available update as an embedded card.
class _UpdateCard extends StatefulWidget {
  const _UpdateCard({required this.onCheckUpdate});

  final VoidCallback onCheckUpdate;

  @override
  State<_UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends State<_UpdateCard> {
  /// Available-update body starts open so notes/actions are visible; user can fold to save space.
  bool _cardExpanded = true;
  late bool _useMirror;
  // Tracks the last install status we surfaced a toast for, so the error
  // toast fires once per failure instead of on every rebuild.
  InstallStatus? _lastSurfacedInstallStatus;

  @override
  void initState() {
    super.initState();
    _useMirror = UserManager().useUpdateMirror;
    AppUpdateService.state.addListener(_onStateChanged);
    InAppInstaller.instance.state.addListener(_onInstallStateChanged);
  }

  @override
  void dispose() {
    AppUpdateService.state.removeListener(_onStateChanged);
    InAppInstaller.instance.state.removeListener(_onInstallStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  void _onInstallStateChanged() {
    final s = InAppInstaller.instance.state.value;
    // Surface a toast exactly once when entering the error/done states.
    if (_lastSurfacedInstallStatus != s.status) {
      _lastSurfacedInstallStatus = s.status;
      if (s.status == InstallStatus.error && mounted) {
        final l10n = AppLocalizations.of(context)!;
        showToast(
          context,
          s.needsPermission
              ? l10n.updateInstallPermissionNeeded
              : (s.assetName != null && s.assetName!.isNotEmpty
                    ? l10n.updateInstallFailed
                    : l10n.updateDownloadFailed),
          isError: true,
        );
      }
    }
    if (mounted) setState(() {});
  }

  bool get _isInstalling => InAppInstaller.instance.state.value.isBusy;

  Future<void> _openUrl(String url) async {
    final launched = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!mounted) return;
    if (!launched) {
      showToast(
        context,
        AppLocalizations.of(context)!.updateOpenDownloadFailed,
        isError: true,
      );
    }
  }

  Future<void> _installInApp(ReleaseAsset asset) async {
    if (_isInstalling) return;
    _lastSurfacedInstallStatus = null;
    await InAppInstaller.instance.downloadAndInstall(
      asset,
      useMirror: _useMirror,
    );
  }

  /// In-app download+install is wired for Android APKs only; every other
  /// platform falls back to the asset tile's browser download links.
  bool _canInstallInApp(ReleaseAsset asset) =>
      Platform.isAndroid && asset.platform == AssetPlatform.android;

  /// Beta / single-asset releases render their newest (or only) asset inline:
  /// install buttons for an Android APK, the regular asset tile (with
  /// GitHub/mirror browser-download buttons) otherwise.
  Widget _buildInlineAsset(ReleaseAsset asset, ColorScheme cs, TextTheme tt) {
    return _canInstallInApp(asset)
        ? _buildInstallButtons(asset, cs, tt)
        : _buildAssetTile(asset, cs, tt);
  }

  Future<void> _skipVersion() async {
    final info = AppUpdateService.state.value.info;
    if (info == null) return;
    await UserManager().setSkippedUpdateVersion(info.latestVersion);
    // Clear so the card disappears and any entry dots stay off.
    AppUpdateService.state.value = const AppUpdateState.latest();
    AppUpdateService.markUpdateBadgeSeen();
  }

  void _setMirror(bool value) {
    if (_useMirror == value) return;
    setState(() => _useMirror = value);
    UserManager().setUseUpdateMirror(value);
  }

  Widget _buildReleaseNotes(String notes, ColorScheme cs) {
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

  /// Compact card showing the changelog for the *currently installed* version.
  /// Rendered when the update check found no update but still returned release
  /// notes. No download/skip/mirror controls — just notes + release page link.
  Widget _buildCurrentVersionCard(
    ColorScheme cs,
    TextTheme tt,
    AppUpdateInfo info,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      color: cs.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _cardExpanded = !_cardExpanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l10n.updateCurrentVersionNotes,
                            style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            info.latestVersion,
                            style: tt.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.updateOpenReleasePage,
                      iconSize: 20,
                      visualDensity: VisualDensity.compact,
                      onPressed: _isInstalling
                          ? null
                          : () => _openUrl(info.releasePageUrl),
                      icon: Icon(
                        Icons.open_in_new,
                        size: 20,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    Icon(
                      _cardExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: _buildReleaseNotes(info.releaseNotes, cs),
                ),
              ),
            ),
            crossFadeState: _cardExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
            sizeCurve: Curves.easeInOut,
          ),
        ],
      ),
    );
  }

  Widget _buildInstallButtons(
    ReleaseAsset asset,
    ColorScheme cs,
    TextTheme tt,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final s = InAppInstaller.instance.state.value;
    final isThisAsset = s.assetName == asset.name;

    // Progress view when this asset is the active install.
    if (isThisAsset && s.isBusy) {
      final downloading = s.status == InstallStatus.downloading;
      final label = downloading
          ? (InAppInstaller.instance.progressLabel().isNotEmpty
                ? '${InAppInstaller.instance.progressLabel()}  ·  ${l10n.updateDownloading(s.total > 0 ? (s.received * 100 / s.total).round().clamp(0, 100) : 0)}'
                : l10n.updateDownloadPreparing)
          : (s.status == InstallStatus.preparing
                ? l10n.updateDownloadPreparing
                : l10n.updateInstalling);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: AppRadius.xsR,
            child: LinearProgressIndicator(
              value: downloading && s.total > 0 ? s.received / s.total : null,
              minHeight: 6,
              color: cs.primary,
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: tt.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }

    final disabled = _isInstalling;
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: disabled ? null : () => _installInApp(asset),
            icon: _sourceIcon(cs, cs.onPrimary),
            label: Text(l10n.updateButtonUpdate),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              textStyle: tt.labelMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: disabled
                ? null
                : () => _openUrl(
                    _useMirror ? asset.mirrorUrl : asset.downloadUrl,
                  ),
            icon: _sourceIcon(cs, cs.primary),
            label: Text(l10n.updateManualDownload),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              textStyle: tt.labelMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  /// Shared source icon for update/download buttons. GitHub mark when using
  /// the direct URL, network icon when the mirror checkbox is ticked.
  Widget _sourceIcon(ColorScheme cs, Color color, {double size = 16}) {
    if (_useMirror) {
      return Icon(Icons.public, size: size + 2, color: color);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: SvgPicture.asset(
        'assets/github.svg',
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      ),
    );
  }

  Widget _buildAssetTile(
    ReleaseAsset asset,
    ColorScheme cs,
    TextTheme tt, {
    String? badge,
  }) {
    final subtitleParts = <String>[asset.platform.label];
    if (asset.sizeLabel.isNotEmpty) subtitleParts.add(asset.sizeLabel);
    final canInstallInApp = _canInstallInApp(asset);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: AppRadius.mdR,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(asset.platform.icon, size: 20, color: cs.primary),
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
                                fontSize: 12,
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
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (canInstallInApp) ...[
            const SizedBox(height: 10),
            _buildInstallButtons(asset, cs, tt),
          ] else ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: AppLocalizations.of(
                    context,
                  )!.animeDetailDownloadButton,
                  visualDensity: VisualDensity.compact,
                  onPressed: _isInstalling
                      ? null
                      : () => _openUrl(asset.downloadUrl),
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
                  onPressed: _isInstalling
                      ? null
                      : () => _openUrl(asset.mirrorUrl),
                  icon: Icon(Icons.public, size: 20, color: cs.primary),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final state = AppUpdateService.state.value;

    // Idle: a silent fetch is triggered on entering About; render nothing
    // while it resolves (fast), then latest/available/failed cards appear.
    if (state.status == AppUpdateStatus.idle) {
      return const SizedBox.shrink();
    }

    // Latest with current-version release notes: show a compact changelog
    // card so the user can see what's in the version they're running.
    if (state.status == AppUpdateStatus.latest && state.info != null) {
      return _buildCurrentVersionCard(cs, tt, state.info!);
    }

    // Latest without info (e.g. assets empty) or other non-available states
    // below fall through to the checking/failed/available branches.
    if (state.status == AppUpdateStatus.latest) {
      return const SizedBox.shrink();
    }

    if (state.status == AppUpdateStatus.checking) {
      return Card(
        color: cs.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(l10n.updateCardChecking, style: tt.bodyMedium),
            ],
          ),
        ),
      );
    }

    if (state.status == AppUpdateStatus.failed) {
      final detail = state.errorDetail;
      return Card(
        color: cs.surfaceContainerLow,
        child: InkWell(
          onTap: widget.onCheckUpdate,
          borderRadius: AppRadius.mdR,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 20, color: cs.error),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.updateCardFailed, style: tt.bodyMedium),
                      if (detail != null && detail.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            detail,
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: widget.onCheckUpdate,
                  child: Text(l10n.updateCardRetry),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final info = state.info!;
    final isBeta = info.isBetaChannel;
    final notes = info.releaseNotes.isEmpty
        ? (isBeta ? l10n.updateCiBuildUnstable : l10n.updateNoReleaseNotes)
        : info.releaseNotes;
    final assets = info.assets;

    return Card(
      color: cs.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tappable header: version + open release + expand/collapse.
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _cardExpanded = !_cardExpanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        info.latestVersion,
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.updateOpenReleasePage,
                      iconSize: 20,
                      visualDensity: VisualDensity.compact,
                      onPressed: _isInstalling
                          ? null
                          : () => _openUrl(info.releasePageUrl),
                      icon: Icon(
                        Icons.open_in_new,
                        size: 20,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    Icon(
                      _cardExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: SingleChildScrollView(
                      child: _buildReleaseNotes(notes, cs),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // Beta channel: don't list packages — just offer the newest
                  // build via the same install buttons stable uses for a
                  // single-asset release (browser links on non-Android).
                  if (isBeta) ...[
                    if (assets.isNotEmpty)
                      _buildInlineAsset(assets.first, cs, tt),
                  ] else if (assets.length <= 1) ...[
                    if (assets.isNotEmpty)
                      _buildInlineAsset(assets.first, cs, tt),
                  ] else ...[
                    Text(
                      l10n.updatePackages,
                      style: tt.labelLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final a in assets) _buildAssetTile(a, cs, tt),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      _buildMirrorCheckbox(cs, tt),
                      const Spacer(),
                      TextButton(
                        onPressed: _isInstalling ? null : _skipVersion,
                        child: Text(
                          isBeta
                              ? l10n.updateDisableAutoCheck
                              : l10n.updateSkipVersion,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            crossFadeState: _cardExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
            sizeCurve: Curves.easeInOut,
          ),
        ],
      ),
    );
  }

  Widget _buildMirrorCheckbox(
    ColorScheme cs,
    TextTheme tt, {
    bool dense = false,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return InkWell(
      onTap: _isInstalling ? null : () => _setMirror(!_useMirror),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: dense ? 2 : 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: Checkbox(
                value: _useMirror,
                onChanged: _isInstalling ? null : (v) => _setMirror(v ?? false),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              l10n.updateUseMirror,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
