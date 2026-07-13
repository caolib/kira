import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../models/user_manager.dart';
import '../routing/app_router.dart';
import '../utils/app_update.dart';
import '../utils/toast.dart';

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
        borderRadius: BorderRadius.circular(12),
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
              const SizedBox(height: 16),
              Text(
                l10n.aboutQqGroupTitle,
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              InkWell(
                onTap: () async {
                  await launchUrl(
                    Uri.parse(_qqGroupUrl),
                    mode: LaunchMode.externalApplication,
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.open_in_new, size: 18, color: cs.primary),
                      const SizedBox(width: 8),
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
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  await Clipboard.setData(
                    const ClipboardData(text: _qqGroupNumber),
                  );
                  if (dialogContext.mounted) {
                    showToast(dialogContext, l10n.aboutGroupNumberCopiedToast);
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
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
                      const SizedBox(width: 8),
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
    final controller = TextEditingController(text: _user.updateMirrorPrefix);
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final cs = Theme.of(dialogContext).colorScheme;
        final tt = Theme.of(dialogContext).textTheme;

        return AlertDialog(
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
                  const SizedBox(height: 12),
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
        );
      },
    );

    final mirrorPrefix = result;
    // Dispose after the dialog route finishes unmounting its TextFormField.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });

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
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isBeta
              ? Colors.amber.withValues(alpha: 0.14)
              : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
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
            const SizedBox(width: 4),
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
      } else {
        showToast(context, l10n.aboutStableChannelSwitchedToast);
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
              const SizedBox(height: 16),
              Text(
                'Kira',
                textAlign: TextAlign.center,
                style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                version,
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
              Card(
                color: cs.surfaceContainerLow,
                shadowColor: Colors.black.withValues(alpha: 0.20),
                elevation: 8,
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
              const SizedBox(height: 16),
              Card(
                color: cs.surfaceContainerLow,
                shadowColor: Colors.black.withValues(alpha: 0.20),
                elevation: 8,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.system_update_alt),
                      title: Text(l10n.aboutCheckUpdateTitle),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildUpdateChannelChip(cs, l10n),
                          const SizedBox(width: 4),
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
              const SizedBox(height: 16),
              Card(
                color: cs.surfaceContainerLow,
                shadowColor: Colors.black.withValues(alpha: 0.20),
                elevation: 8,
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 12),
            Text(label, style: tt.bodyLarge),
          ],
        ),
      ),
    );
  }
}
