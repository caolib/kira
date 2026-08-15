import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../api/user/user_api.dart';
import '../l10n/app_localizations.dart';
import '../models/user_manager.dart';
import '../routing/app_router.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../utils/app_logger.dart';
import '../utils/app_update.dart';
import '../utils/remote_notice_service.dart';
import '../utils/toast.dart';
import 'register_page.dart' show RegisterPrefill;

List<String> _appDisclaimerItems(AppLocalizations l10n) => [
  l10n.appDisclaimerItem1,
  l10n.appDisclaimerItem2,
  l10n.appDisclaimerItem3,
  l10n.appDisclaimerItem4,
  l10n.appDisclaimerItem5,
  l10n.appDisclaimerItem6,
];

const _noticeCenterColor = Color(0xFFEB6F92);

/// Profile cards share the app-wide medium shadow token.
List<BoxShadow> _profileCardShadow(ColorScheme cs) => AppShadows.md(cs);

enum _SwitchAccountSheetAction { addAccount }

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _user = UserManager();
  bool _userActionsExpanded = false;

  @override
  void initState() {
    super.initState();
    _user.addListener(_onUserChanged);
  }

  @override
  void dispose() {
    _user.removeListener(_onUserChanged);
    super.dispose();
  }

  void _onUserChanged() {
    if (mounted) setState(() {});
  }

  bool _isCopyCredential(SavedCredential credential) {
    final source = credential.loginSource;
    if (source != null && source.isNotEmpty) {
      return source == 'copy';
    }
    if (credential.username == _user.savedUsername) {
      return _user.loginSource == 'copy';
    }
    return false;
  }

  String _credentialTypeLabel(
    AppLocalizations l10n,
    SavedCredential credential,
  ) {
    return _isCopyCredential(credential)
        ? l10n.profileCopyCredentialLabel
        : l10n.profileHotCredentialLabel;
  }

  IconData _credentialTypeIcon(SavedCredential credential) {
    return _isCopyCredential(credential) ? Icons.language : Icons.phone_android;
  }

  void _goLogin() async {
    final result = await context.pushNamed<bool>(AppRoutes.login);
    if (result == true && mounted) setState(() {});
  }

  void _switchAccount() async {
    final credentials = _user.savedCredentials;
    final otherAccounts = credentials
        .where((c) => c.username != _user.username)
        .toList();
    final hasToken = otherAccounts.any(
      (c) => c.token != null && c.token!.isNotEmpty,
    );

    // 没有其他账号或没有存储令牌，回退到登录页
    if (otherAccounts.isEmpty || !hasToken) {
      final result = await context.pushNamed<bool>(AppRoutes.login);
      if (result == true && mounted) {
        showToast(context, AppLocalizations.of(context)!.accountSwitchedToast);
        setState(() {});
      }
      return;
    }

    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final selected = await showModalBottomSheet<Object>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.switchAccountTitle,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
            ...otherAccounts.map((cred) {
              final displayName = cred.nickname ?? cred.username;
              final showUsername =
                  cred.username.isNotEmpty && displayName != cred.username;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: cs.primaryContainer,
                  child: Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                    style: TextStyle(color: cs.onPrimaryContainer),
                  ),
                ),
                title: Text(displayName),
                subtitle: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showUsername)
                      Text(
                        cred.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (showUsername) const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _isCopyCredential(cred)
                            ? cs.tertiaryContainer
                            : cs.secondaryContainer,
                        borderRadius: AppRadius.fullR,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _credentialTypeIcon(cred),
                            size: 14,
                            color: _isCopyCredential(cred)
                                ? cs.onTertiaryContainer
                                : cs.onSecondaryContainer,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            _credentialTypeLabel(l10n, cred),
                            style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                              color: _isCopyCredential(cred)
                                  ? cs.onTertiaryContainer
                                  : cs.onSecondaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                trailing: const Icon(Icons.swap_horiz),
                onTap: () => Navigator.pop(ctx, cred),
              );
            }),
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () =>
                      Navigator.pop(ctx, _SwitchAccountSheetAction.addAccount),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: Text(l10n.addAccountButton),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (selected == null || !mounted) return;

    if (selected == _SwitchAccountSheetAction.addAccount) {
      final result = await context.pushNamed<bool>(AppRoutes.login);
      if (result == true && mounted) {
        showToast(context, AppLocalizations.of(context)!.accountSwitchedToast);
        setState(() {});
      }
      return;
    }

    if (selected is! SavedCredential) return;

    if (selected.token != null && selected.token!.isNotEmpty) {
      final success = await _user.switchToCredential(selected);
      if (mounted) {
        if (success) {
          showToast(
            context,
            AppLocalizations.of(context)!.accountSwitchedToast,
          );
        } else {
          showToast(
            context,
            AppLocalizations.of(context)!.switchAccountFailedToast,
            isError: true,
          );
        }
      }
    } else {
      // 该账号无令牌，回退到登录页
      final result = await context.pushNamed<bool>(AppRoutes.login);
      if (result == true && mounted) {
        showToast(context, AppLocalizations.of(context)!.accountSwitchedToast);
        setState(() {});
      }
    }
  }

  Future<void> _logout() async {
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.logoutTitle),
        content: Text(l10n.logoutConfirmContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.confirmButton),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await ApiClient().user.logout();
      } catch (e, stack) {
        unawaited(
          AppLogger.instance.recordWarning(
            e,
            stackTrace: stack,
            source: 'profile_page.logout',
          ),
        );
      } finally {
        await _user.logout();
      }
    }
  }

  Future<void> _refreshUserInfo() async {
    try {
      await _user.refreshUserInfo();
      if (mounted) {
        showToast(
          context,
          AppLocalizations.of(context)!.userInfoRefreshedToast,
        );
      }
    } catch (_) {
      if (mounted) {
        showToast(
          context,
          AppLocalizations.of(context)!.userInfoRefreshFailedToast,
          isError: true,
        );
      }
    }
  }

  Future<void> _copyToken() async {
    final token = _user.token;
    if (token == null || token.isEmpty) {
      showToast(
        context,
        AppLocalizations.of(context)!.tokenUnavailableToast,
        isError: true,
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: token));
    if (mounted) {
      showToast(context, AppLocalizations.of(context)!.tokenCopiedToast);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.of(context).padding.top),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _user.isLoggedIn
                  ? _buildUserCard(cs, tt)
                  : _buildLoginCard(cs, tt),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Card(
                    color: cs.surfaceContainerLow,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          ListTile(
                            leading: const _SettingIcon(
                              icon: Icons.tune_rounded,
                              color: Color(0xFF6E9D5B),
                            ),
                            title: Text(l10n.generalTitle),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.pushNamed(AppRoutes.general),
                          ),
                          const Divider(height: 1, indent: 16, endIndent: 16),
                          ListTile(
                            leading: const _SettingIcon(
                              icon: Icons.palette_rounded,
                              color: Color(0xFF7C8CFF),
                            ),
                            title: Text(l10n.appearanceTitle),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () =>
                                context.pushNamed(AppRoutes.appearance),
                          ),
                          const Divider(height: 1, indent: 16, endIndent: 16),
                          ListTile(
                            leading: const _SettingIcon(
                              icon: Icons.dns_rounded,
                              color: Color(0xFF2BB8A5),
                            ),
                            title: Text(l10n.networkTitle),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.pushNamed(AppRoutes.network),
                          ),
                          const Divider(height: 1, indent: 16, endIndent: 16),
                          ListTile(
                            leading: const _SettingIcon(
                              icon: Icons.smart_toy_outlined,
                              color: Color(0xFFE07AD0),
                            ),
                            title: Text(l10n.aiConfigTitle),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.pushNamed(AppRoutes.aiConfig),
                          ),
                          const Divider(height: 1, indent: 16, endIndent: 16),
                          ValueListenableBuilder<int>(
                            valueListenable:
                                RemoteNoticeService.unreadActiveCount,
                            builder: (context, count, _) {
                              return ListTile(
                                leading: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    const _SettingIcon(
                                      icon: Icons.notifications_active_outlined,
                                      color: _noticeCenterColor,
                                    ),
                                    if (count > 0)
                                      Positioned(
                                        right: -1,
                                        top: -1,
                                        child: _NoticeRedDot(
                                          color: _noticeCenterColor,
                                          borderColor: cs.surfaceContainerLow,
                                        ),
                                      ),
                                  ],
                                ),
                                title: Text(l10n.noticeCenterTitle),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () =>
                                    context.pushNamed(AppRoutes.noticeCenter),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Card(
                    color: cs.surfaceContainerLow,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          ListTile(
                            leading: const _SettingIcon(
                              icon: Icons.download_done_rounded,
                              color: Color(0xFFFFA24C),
                            ),
                            title: Text(l10n.downloadCenterTitle),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () =>
                                context.pushNamed(AppRoutes.downloadCenter),
                          ),
                          const Divider(height: 1, indent: 16, endIndent: 16),
                          ListTile(
                            leading: const _SettingIcon(
                              icon: Icons.history_rounded,
                              color: Color(0xFF9B7BFF),
                            ),
                            title: Text(l10n.browseHistoryTitle),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () =>
                                context.pushNamed(AppRoutes.browseHistory),
                          ),
                          const Divider(height: 1, indent: 16, endIndent: 16),
                          ListTile(
                            leading: const _SettingIcon(
                              icon: Icons.bookmark_outline_rounded,
                              color: Color(0xFF4CAF7D),
                            ),
                            title: Text(l10n.bookmarksTitle),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.pushNamed(AppRoutes.bookmarks),
                          ),
                          const Divider(height: 1, indent: 16, endIndent: 16),
                          ListTile(
                            leading: const _SettingIcon(
                              icon: Icons.bar_chart_rounded,
                              color: Color(0xFF5B8DEF),
                            ),
                            title: Text(l10n.statsTitle),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.pushNamed(AppRoutes.stats),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Card(
                    color: cs.surfaceContainerLow,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: ValueListenableBuilder<bool>(
                        valueListenable: AppUpdateService.hasUnseenUpdate,
                        builder: (context, hasUnseenUpdate, _) {
                          return ListTile(
                            leading: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                const _SettingIcon(
                                  icon: Icons.info_rounded,
                                  color: Color(0xFF4FA8FF),
                                ),
                                if (hasUnseenUpdate)
                                  Positioned(
                                    right: -1,
                                    top: -1,
                                    child: _NoticeRedDot(
                                      color: const Color(0xFF4FA8FF),
                                      borderColor: cs.surfaceContainerLow,
                                    ),
                                  ),
                              ],
                            ),
                            title: Text(l10n.aboutTitle),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.pushNamed(AppRoutes.about),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginCard(ColorScheme cs, TextTheme tt) {
    final l10n = AppLocalizations.of(context)!;

    return Card(
      color: cs.surfaceContainerLow,
      child: InkWell(
        borderRadius: AppRadius.lgR,
        onTap: _goLogin,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: cs.primaryContainer,
                child: Icon(
                  Icons.person,
                  size: 32,
                  color: cs.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.notLoggedInTitle, style: tt.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      l10n.loginPromptSubtitle,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserCard(ColorScheme cs, TextTheme tt) {
    final l10n = AppLocalizations.of(context)!;

    return Card(
      color: cs.surfaceContainerLow,
      child: InkWell(
        borderRadius: AppRadius.lgR,
        onTap: () {
          setState(() {
            _userActionsExpanded = !_userActionsExpanded;
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: cs.primaryContainer,
                    child:
                        _user.avatar != null && _user.avatar!.startsWith('http')
                        ? ClipOval(
                            child: CachedNetworkImage(
                              imageUrl: _user.avatar!,
                              width: 64,
                              height: 64,
                              fit: BoxFit.cover,
                            ),
                          )
                        : Icon(
                            Icons.person,
                            size: 32,
                            color: cs.onPrimaryContainer,
                          ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Text(
                      _user.nickname ?? _user.username ?? '',
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _userActionsExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.expand_more, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: _userActionsExpanded
                    ? Column(
                        children: [
                          const SizedBox(height: AppSpacing.md),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final buttonWidth =
                                  (constraints.maxWidth - 8) / 2;
                              return Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  SizedBox(
                                    width: buttonWidth,
                                    child: _buildUserActionButton(
                                      icon: Icons.refresh,
                                      label: l10n.refreshUserButton,
                                      onPressed: () => _refreshUserInfo(),
                                    ),
                                  ),
                                  SizedBox(
                                    width: buttonWidth,
                                    child: _buildUserActionButton(
                                      icon: Icons.switch_account,
                                      label: l10n.switchAccountButton,
                                      onPressed: () => _switchAccount(),
                                    ),
                                  ),
                                  SizedBox(
                                    width: buttonWidth,
                                    child: _buildUserActionButton(
                                      icon: Icons.copy_outlined,
                                      label: l10n.copyTokenButton,
                                      onPressed: () => _copyToken(),
                                    ),
                                  ),
                                  SizedBox(
                                    width: buttonWidth,
                                    child: _buildUserActionButton(
                                      icon: Icons.logout,
                                      label: l10n.logoutTitle,
                                      onPressed: () => _logout(),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 44,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 6),
              Text(label, maxLines: 1),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoticeRedDot extends StatelessWidget {
  const _NoticeRedDot({required this.color, required this.borderColor});

  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 1.2),
      ),
    );
  }
}

// ── 登录页 ──

class _RegisterPrefill {
  final String username;
  final String password;

  const _RegisterPrefill({required this.username, required this.password});
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _api = ApiClient();
  final _user = UserManager();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  bool _rememberMe = false;
  bool _useToken = false;
  bool _useCopyLogin = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (_user.savedUsername != null) {
      _usernameCtrl.text = _user.savedUsername!;
      _rememberMe = true;
    }
    if (_user.savedPassword != null) {
      _passwordCtrl.text = _user.savedPassword!;
    }
    _usernameCtrl.addListener(_onCredentialDraftChanged);
    _user.addListener(_onUserChanged);
    _useCopyLogin = _user.loginSource == 'copy';
  }

  @override
  void dispose() {
    _user.removeListener(_onUserChanged);
    _usernameCtrl.removeListener(_onCredentialDraftChanged);
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  void _onUserChanged() {
    if (mounted) setState(() {});
  }

  void _onCredentialDraftChanged() {
    if (mounted) setState(() {});
  }

  bool _isCopyCredential(SavedCredential credential) {
    final source = credential.loginSource;
    if (source != null && source.isNotEmpty) {
      return source == 'copy';
    }
    if (credential.username == _user.savedUsername) {
      return _user.loginSource == 'copy';
    }
    return false;
  }

  String _credentialTypeLabel(
    AppLocalizations l10n,
    SavedCredential credential,
  ) {
    return _isCopyCredential(credential)
        ? l10n.profileCopyCredentialLabel
        : l10n.profileHotCredentialLabel;
  }

  IconData _credentialTypeIcon(SavedCredential credential) {
    return _isCopyCredential(credential) ? Icons.language : Icons.phone_android;
  }

  bool _isCredentialSelected(SavedCredential credential) {
    return !_useToken &&
        _usernameCtrl.text.trim() == credential.username &&
        _useCopyLogin == _isCopyCredential(credential);
  }

  Widget _buildCredentialBadge({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color backgroundColor,
    required Color foregroundColor,
  }) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: AppRadius.fullR,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foregroundColor),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: tt.labelSmall?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSavedCredentialCard(
    BuildContext context,
    SavedCredential credential,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isCopy = _isCopyCredential(credential);
    final isSelected = _isCredentialSelected(credential);
    final nickname = credential.nickname?.trim();
    final typeBackgroundColor = isCopy
        ? cs.tertiaryContainer
        : cs.secondaryContainer;
    final typeForegroundColor = isCopy
        ? cs.onTertiaryContainer
        : cs.onSecondaryContainer;
    final initial = credential.username.isNotEmpty
        ? credential.username.substring(0, 1).toUpperCase()
        : '?';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: isSelected
            ? cs.primaryContainer.withValues(alpha: 0.45)
            : cs.surfaceContainerLow,
        borderRadius: AppRadius.lgR,
        border: Border.all(color: isSelected ? cs.primary : cs.outlineVariant),
        boxShadow: _profileCardShadow(cs),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadius.lgR,
          onTap: () => _applySavedCredential(credential),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: isSelected
                      ? cs.primary
                      : cs.surfaceContainerHighest,
                  child: Text(
                    initial,
                    style: tt.titleMedium?.copyWith(
                      color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        credential.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (nickname != null &&
                          nickname.isNotEmpty &&
                          nickname != credential.username) ...[
                        const SizedBox(height: 2),
                        Text(
                          nickname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildCredentialBadge(
                            context: context,
                            icon: _credentialTypeIcon(credential),
                            label: _credentialTypeLabel(l10n, credential),
                            backgroundColor: typeBackgroundColor,
                            foregroundColor: typeForegroundColor,
                          ),
                          if (isSelected)
                            _buildCredentialBadge(
                              context: context,
                              icon: Icons.check_circle,
                              label: l10n.profileCurrentSelectedCredential,
                              backgroundColor: cs.primary,
                              foregroundColor: cs.onPrimary,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: l10n.profileRemoveAccountTooltip,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _removeSavedCredential(credential),
                  icon: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _applySavedCredential(SavedCredential credential) {
    setState(() {
      _useToken = false;
      _useCopyLogin = _isCopyCredential(credential);
      _rememberMe = true;
      _error = null;
      _usernameCtrl.text = credential.username;
      _passwordCtrl.text = credential.password;
    });
  }

  Future<void> _removeSavedCredential(SavedCredential credential) async {
    await _user.removeSavedCredential(credential.username);
    if (!mounted) return;
    if (_usernameCtrl.text.trim() == credential.username) {
      setState(() {
        final next = _user.savedCredentials.isNotEmpty
            ? _user.savedCredentials.first
            : null;
        _usernameCtrl.text = next?.username ?? '';
        _passwordCtrl.text = next?.password ?? '';
        if (next != null) {
          _useCopyLogin = _isCopyCredential(next);
        }
        _rememberMe = next != null;
      });
    }
    showToast(
      context,
      AppLocalizations.of(
        context,
      )!.profileAccountRemovedToast(credential.username),
    );
  }

  Future<void> _goRegister() async {
    final result = await context.pushNamed<RegisterPrefill>(AppRoutes.register);
    if (result == null || !mounted) return;

    await UserManager().saveCredentials(result.username, result.password);
    if (!mounted) return;
    setState(() {
      _useToken = false;
      _rememberMe = true;
      _error = null;
      _usernameCtrl.text = result.username;
      _passwordCtrl.text = result.password;
    });
    showToast(
      context,
      AppLocalizations.of(context)!.profileRegisterSuccessLoginToast,
    );
  }

  Future<void> _login() async {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    final l10n = AppLocalizations.of(context)!;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = l10n.profileUsernamePasswordRequired);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = _useCopyLogin
          ? await _api.user.copyLogin(username, password)
          : await _api.user.login(username, password);
      await UserManager().setLoginSource(_useCopyLogin ? 'copy' : 'hotmanga');
      if (_rememberMe) {
        await UserManager().saveCredentials(username, password);
      } else {
        await UserManager().removeSavedCredential(username);
      }
      await UserManager().saveLogin(
        token: result['token'],
        userId: result['user_id'],
        username: result['username'],
        nickname: result['nickname'] ?? result['username'],
        avatar: result['avatar'] ?? '',
      );
      await UserManager().refreshUserInfo();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = isIpBlockedLoginError(e)
            ? l10n.profileLoginIpBlockedHint
            : '${l10n.profileLoginFailedProxyHint}\n$e';
        _loading = false;
      });
    }
  }

  Future<void> _loginWithToken() async {
    final token = _tokenCtrl.text.trim();
    final l10n = AppLocalizations.of(context)!;
    if (token.isEmpty) {
      setState(() => _error = l10n.profileTokenRequired);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 先临时保存 token 以便 API 请求携带 Authorization
      await UserManager().saveLogin(
        token: token,
        userId: '',
        username: '',
        nickname: '',
        avatar: '',
      );
      // 用 token 拉取用户信息验证有效性
      final info = await _api.user.getUserInfo();
      await UserManager().saveLogin(
        token: token,
        userId: info['user_id']?.toString() ?? '',
        username: info['username']?.toString() ?? '',
        nickname:
            info['nickname']?.toString() ?? info['username']?.toString() ?? '',
        avatar: info['avatar']?.toString() ?? '',
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      // 令牌无效，清除
      await UserManager().logout();
      if (!mounted) return;
      setState(() {
        _error = '${l10n.profileTokenInvalidOrExpired}\n$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth.clamp(0.0, 400.0);
    final hp = (screenWidth - contentWidth) / 2;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileLoginTitle)),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(hp + 24, 48, hp + 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Image.asset(_user.appLogoPath, width: 64, height: 64),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Kira',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(l10n.profileAccountPasswordLoginMode),
                  icon: const Icon(Icons.person_outline),
                ),
                ButtonSegment(
                  value: true,
                  label: Text(l10n.profileTokenLoginMode),
                  icon: const Icon(Icons.key),
                ),
              ],
              selected: {_useToken},
              onSelectionChanged: (v) => setState(() {
                _useToken = v.first;
                _error = null;
              }),
            ),
            const SizedBox(height: AppSpacing.xxl),
            if (!_useToken) ...[
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text(l10n.profileHotCredentialLabel),
                    icon: const Icon(Icons.phone_android, size: 18),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text(l10n.profileCopyCredentialLabel),
                    icon: const Icon(Icons.language, size: 18),
                  ),
                ],
                selected: {_useCopyLogin},
                onSelectionChanged: (v) => setState(() {
                  _useCopyLogin = v.first;
                  _error = null;
                }),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_user.savedCredentials.isNotEmpty) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.profileSavedAccountsTitle,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.profileSavedAccountsHint,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                Column(
                  children: [
                    for (var i = 0; i < _user.savedCredentials.length; i++) ...[
                      _buildSavedCredentialCard(
                        context,
                        _user.savedCredentials[i],
                      ),
                      if (i != _user.savedCredentials.length - 1)
                        const SizedBox(height: 10),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              TextField(
                controller: _usernameCtrl,
                decoration: InputDecoration(
                  labelText: l10n.profileUsernameLabel,
                  prefixIcon: const Icon(Icons.person_outline),
                  border: OutlineInputBorder(borderRadius: AppRadius.mdR),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _passwordCtrl,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: l10n.profilePasswordLabel,
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  border: OutlineInputBorder(borderRadius: AppRadius.mdR),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _login(),
              ),
            ] else ...[
              TextField(
                controller: _tokenCtrl,
                decoration: InputDecoration(
                  labelText: l10n.profileTokenLabel,
                  prefixIcon: const Icon(Icons.key),
                  hintText: l10n.profileTokenHint,
                  border: OutlineInputBorder(borderRadius: AppRadius.mdR),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _loginWithToken(),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                _error!,
                style: TextStyle(color: cs.error),
                textAlign: TextAlign.center,
              ),
            ],
            if (!_useToken) ...[
              const SizedBox(height: AppSpacing.sm),
              CheckboxListTile(
                value: _rememberMe,
                onChanged: (v) => setState(() => _rememberMe = v ?? false),
                title: Text(l10n.profileRememberAccountLabel),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _loading ? null : _goRegister,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: Text(l10n.profileRegisterHotMangaAccountButton),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            FilledButton(
              onPressed: _loading
                  ? null
                  : (_useToken ? _loginWithToken : _login),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.mdR),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      l10n.profileLoginButton,
                      style: const TextStyle(fontSize: 16),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  static final _hotMangaRegisterUri = Uri.parse(
    'https://m.manga2026.xyz/v2h5/register',
  );
  static Uri get _copyMangaRegisterUri => Uri.parse(
    'https://${UserManager().copyLoginHost}/web/login/loginByAccount',
  );
  List<String> _fallbackQuestions(AppLocalizations l10n) => [
    l10n.profileFallbackQuestionWife,
    l10n.profileFallbackQuestionFriend,
    l10n.profileFallbackQuestionBestFriendCount,
    l10n.profileFallbackQuestionParentName,
  ];

  final _api = ApiClient();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _answerCtrl = TextEditingController();

  List<String> _questions = [];
  String? _selectedQuestion;
  bool _loadingQuestions = true;
  bool _submitting = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _answerCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadQuestions() async {
    setState(() {
      _loadingQuestions = true;
      _error = null;
    });

    try {
      final questions = await _api.user.getSecurityQuestions();
      if (!mounted) return;
      final fallbackQuestions = _fallbackQuestions(
        AppLocalizations.of(context)!,
      );
      final availableQuestions = questions.isNotEmpty
          ? questions
          : fallbackQuestions;
      setState(() {
        _questions = availableQuestions;
        _selectedQuestion = availableQuestions.first;
        _loadingQuestions = false;
      });
    } catch (e) {
      if (!mounted) return;
      final fallbackQuestions = _fallbackQuestions(
        AppLocalizations.of(context)!,
      );
      setState(() {
        _questions = fallbackQuestions;
        _selectedQuestion = fallbackQuestions.first;
        _loadingQuestions = false;
        _error = null;
      });
    }
  }

  Future<void> _register() async {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    final confirmPassword = _confirmPasswordCtrl.text;
    final answer = _answerCtrl.text.trim();
    final l10n = AppLocalizations.of(context)!;

    if (username.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty ||
        answer.isEmpty) {
      setState(() => _error = l10n.profileRegisterInfoRequired);
      return;
    }
    if (password != confirmPassword) {
      setState(() => _error = l10n.profilePasswordMismatch);
      return;
    }
    if (_selectedQuestion == null || _selectedQuestion!.isEmpty) {
      setState(() => _error = l10n.profileSecurityQuestionRequired);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await _api.user.register(
        username: username,
        password: password,
        question: _selectedQuestion!,
        answer: answer,
      );
      if (!mounted) return;
      Navigator.pop(
        context,
        _RegisterPrefill(username: username, password: password),
      );
    } catch (e) {
      String msg = l10n.profileRegisterFailed;
      if (e is DioException) {
        msg = e.message ?? msg;
        if (e.response?.data is Map) {
          final data = e.response?.data as Map;
          final results = data['results'];
          msg =
              data['message']?.toString() ??
              data['detail']?.toString() ??
              (results is Map ? results['detail']?.toString() : null) ??
              msg;
        }
      }
      if (!mounted) return;
      setState(() {
        _error = msg;
        _submitting = false;
      });
    }
  }

  Future<void> _openOfficialRegister(Uri uri) async {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      showToast(
        context,
        AppLocalizations.of(context)!.profileOpenOfficialRegisterFailed,
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth.clamp(0.0, 420.0);
    final hp = (screenWidth - contentWidth) / 2;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileRegisterHotMangaAccountButton)),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(hp + 24, 24, hp + 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _usernameCtrl,
              decoration: InputDecoration(
                labelText: l10n.profileUsernameLabel,
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(borderRadius: AppRadius.mdR),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _passwordCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: l10n.profilePasswordLabel,
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                border: OutlineInputBorder(borderRadius: AppRadius.mdR),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _confirmPasswordCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: l10n.profileConfirmPasswordLabel,
                prefixIcon: const Icon(Icons.lock_reset_outlined),
                border: OutlineInputBorder(borderRadius: AppRadius.mdR),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_loadingQuestions)
              const Center(child: ExpressiveLoadingIndicator())
            else ...[
              DropdownButtonFormField<String>(
                initialValue: _selectedQuestion,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.profileSecurityQuestionLabel,
                  prefixIcon: const Icon(Icons.help_outline),
                  border: OutlineInputBorder(borderRadius: AppRadius.mdR),
                ),
                items: _questions
                    .map(
                      (q) => DropdownMenuItem<String>(
                        value: q,
                        child: Text(q, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _selectedQuestion = value),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _answerCtrl,
                decoration: InputDecoration(
                  labelText: l10n.profileSecurityAnswerLabel,
                  prefixIcon: const Icon(Icons.shield_outlined),
                  border: OutlineInputBorder(borderRadius: AppRadius.mdR),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submitting ? null : _register(),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                _error!,
                style: TextStyle(color: cs.error),
                textAlign: TextAlign.center,
              ),
            ],
            if (!_loadingQuestions && _questions.isEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              TextButton.icon(
                onPressed: _loadQuestions,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.profileReloadSecurityQuestionsButton),
              ),
            ],
            const SizedBox(height: AppSpacing.xxl),
            FilledButton(
              onPressed: _submitting || _loadingQuestions ? null : _register,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.mdR),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      l10n.profileRegisterButton,
                      style: const TextStyle(fontSize: 16),
                    ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.profileOfficialRegisterPrompt,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () => _openOfficialRegister(_hotMangaRegisterUri),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(l10n.profileHotMangaLabel),
                ),
                TextButton.icon(
                  onPressed: () => _openOfficialRegister(_copyMangaRegisterUri),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(l10n.profileCopyMangaLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

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

class _SettingIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _SettingIcon({required this.icon, required this.color});

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
    final controller = TextEditingController(text: _user.updateMirrorPrefix);
    final formKey = GlobalKey<FormState>();
    final l10n = AppLocalizations.of(context)!;

    try {
      final result = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          final cs = Theme.of(dialogContext).colorScheme;
          final tt = Theme.of(dialogContext).textTheme;

          return AlertDialog(
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
          );
        },
      );

      if (result == null) return;
      await _user.setUpdateMirrorPrefix(result);
      if (!mounted) return;
      showToast(context, l10n.aboutMirrorPrefixSavedToast);
    } finally {
      controller.dispose();
    }
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
