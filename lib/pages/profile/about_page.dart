part of '../profile_page.dart';

class DisclaimerPage extends StatelessWidget {
  const DisclaimerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.disclaimerTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        children: [
          Text(
            l10n.appDisclaimerIntro,
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.lg),
          Card(
            color: cs.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final item in _appDisclaimerItems(l10n)) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• ', style: tt.bodyMedium),
                        Expanded(child: Text(item, style: tt.bodyMedium)),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    l10n.appDisclaimerFooter,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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

  @override
  void initState() {
    super.initState();
    _user.addListener(_onChanged);
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
    final formKey = GlobalKey<FormState>();
    final l10n = AppLocalizations.of(context)!;

    // 控制器交给 TextControllerScope 托管：弹窗退出动画期间子树仍会重建，
    // 提前 dispose 会命中 “used after being disposed” 断言。
    final result = await showDialog<String>(
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

    if (result == null) return;
    await _user.setUpdateMirrorPrefix(result);
    if (!mounted) return;
    showToast(context, l10n.aboutMirrorPrefixSavedToast);
  }

  Widget _buildUpdateChannelChip(ColorScheme cs) {
    final l10n = AppLocalizations.of(context)!;
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
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            children: [
              Image.asset(_user.appLogoPath, width: 80, height: 80),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Kira',
                textAlign: TextAlign.center,
                style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                version,
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
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
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Card(
                color: cs.surfaceContainerLow,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.system_update_alt),
                      title: Text(l10n.aboutCheckUpdateTitle),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildUpdateChannelChip(cs),
                          const SizedBox(width: AppSpacing.xs),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      onTap: () => AppUpdateService.checkAndPrompt(context),
                    ),
                    Divider(
                      height: 1,
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.autorenew),
                      title: Text(l10n.aboutAutoCheckUpdateTitle),
                      value: _user.autoCheckUpdate,
                      onChanged: _user.setAutoCheckUpdate,
                    ),
                    Divider(
                      height: 1,
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                    ListTile(
                      leading: const Icon(Icons.public),
                      title: Text(l10n.aboutMirrorPrefixTitle),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _editUpdateMirrorPrefix,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Card(
                color: cs.surfaceContainerLow,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.gavel_outlined),
                      title: Text(l10n.disclaimerTitle),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.pushNamed(AppRoutes.disclaimer),
                    ),
                    Divider(
                      height: 1,
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                    ListTile(
                      leading: const Icon(Icons.bug_report_outlined),
                      title: Text(l10n.aboutLogTitle),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.pushNamed(AppRoutes.appLog),
                    ),
                    Divider(
                      height: 1,
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                    ListTile(
                      leading: const Icon(Icons.favorite_outline),
                      title: Text(l10n.aboutAcknowledgementTitle),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.pushNamed(AppRoutes.acknowledgement),
                    ),
                    Divider(
                      height: 1,
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                    ListTile(
                      leading: const Icon(Icons.copyright_outlined),
                      title: Text(l10n.aboutLicenseTitle),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.pushNamed(AppRoutes.license),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
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
