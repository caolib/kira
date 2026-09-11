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
import '../widgets/setting_tile_group.dart';
import '../widgets/text_controller_scope.dart';

part 'about/update_card_actions.dart';
part 'about/update_card_builders.dart';
part 'about/update_settings.dart';
part 'about/widgets.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  final _user = UserManager();

  static const _repoUrl = 'https://github.com/caolib/kira';

  /// extension part 文件里的成员不是 State 子类成员，不能直接调用受保护的
  /// [setState]，统一经由这个转发方法。
  void _setState(VoidCallback fn) => setState(fn);

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
              // Compact horizontal brand header: logo + name/version/tagline.
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
                          style: tt.titleMedium?.copyWith(
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
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          l10n.aboutBrandTagline,
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
              IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: _LinkTile(
                        background: cs.surfaceBright,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(AppRadius.lg),
                          bottomLeft: Radius.circular(AppRadius.lg),
                          topRight: Radius.circular(AppRadius.xs),
                          bottomRight: Radius.circular(AppRadius.xs),
                        ),
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
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: _LinkTile(
                        background: cs.surfaceBright,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(AppRadius.xs),
                        ),
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
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: _LinkTile(
                        background: cs.surfaceBright,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(AppRadius.xs),
                          bottomLeft: Radius.circular(AppRadius.xs),
                          topRight: Radius.circular(AppRadius.lg),
                          bottomRight: Radius.circular(AppRadius.lg),
                        ),
                        child: _LinkAction(
                          icon: const Icon(Icons.bug_report_outlined),
                          label: l10n.aboutLogTitle,
                          onTap: () => context.pushNamed(AppRoutes.appLog),
                        ),
                      ),
                    ),
                  ],
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
}

class _UpdateCardState extends State<_UpdateCard> {
  /// Available-update body starts open so notes/actions are visible; user can fold to save space.
  bool _cardExpanded = true;

  /// 非当前设备的安装包列表默认折叠。
  bool _otherAssetsExpanded = false;
  late bool _useMirror;
  // Tracks the last install status we surfaced a toast for, so the error
  // toast fires once per failure instead of on every rebuild.
  InstallStatus? _lastSurfacedInstallStatus;

  /// extension part 文件里的成员不是 State 子类成员，不能直接调用受保护的
  /// [setState]，统一经由这个转发方法。
  void _setState(VoidCallback fn) => setState(fn);

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
        color: cs.surfaceBright,
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
        color: cs.surfaceBright,
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
    // 当前设备可用的安装包置顶展示，其余默认折叠进「其他安装包」。
    final deviceAsset = _deviceAsset(assets);
    final otherAssets = deviceAsset == null
        ? assets
        : assets.where((a) => !identical(a, deviceAsset)).toList();

    return Card(
      color: cs.surfaceBright,
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
                    TextButton(
                      onPressed: () => _showNotesFullscreen(cs, notes),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        textStyle: tt.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: Text(l10n.updateViewNotes),
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
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 更新说明不再内联渲染，通过头部「更新说明」按钮全屏查看。
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
                    if (deviceAsset != null) ...[
                      _buildAssetTile(deviceAsset, cs, tt, minimal: true),
                      AnimatedCrossFade(
                        firstChild: const SizedBox(width: double.infinity),
                        secondChild: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 260),
                          child: NotificationListener<OverscrollNotification>(
                            onNotification: _handOffOverscroll,
                            child: SingleChildScrollView(
                              physics: const ClampingScrollPhysics(),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final a in otherAssets)
                                    _buildAssetTile(a, cs, tt, minimal: true),
                                ],
                              ),
                            ),
                          ),
                        ),
                        crossFadeState: _otherAssetsExpanded
                            ? CrossFadeState.showSecond
                            : CrossFadeState.showFirst,
                        duration: const Duration(milliseconds: 200),
                        sizeCurve: Curves.easeInOut,
                      ),
                    ] else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 260),
                        child: NotificationListener<OverscrollNotification>(
                          onNotification: _handOffOverscroll,
                          child: SingleChildScrollView(
                            physics: const ClampingScrollPhysics(),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final a in assets)
                                  _buildAssetTile(a, cs, tt, minimal: true),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            crossFadeState: _cardExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
            sizeCurve: Curves.easeInOut,
          ),
          // 底部操作行常驻在折叠区之外：镜像 / 跳过 / 其他安装包折叠开关。
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
            child: Row(
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
                // 仅「当前设备包 + 其他包」的分支显示；长按提示数量。
                if (deviceAsset != null)
                  IconButton(
                    tooltip: l10n.updateOtherPackages(otherAssets.length),
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      _otherAssetsExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 20,
                      color: cs.onSurfaceVariant,
                    ),
                    onPressed: () => setState(
                      () => _otherAssetsExpanded = !_otherAssetsExpanded,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
