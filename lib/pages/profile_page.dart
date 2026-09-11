import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
import '../l10n/app_localizations.dart';
import '../models/user_manager.dart';
import '../routing/app_router.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/app_logger.dart';
import '../utils/app_update.dart';
import '../utils/remote_notice_service.dart';
import '../utils/screen_layout.dart';
import '../utils/toast.dart';
import '../widgets/setting_tile_group.dart';
part 'profile/profile_account.dart';
part 'profile/profile_cards.dart';

const _noticeCenterColor = Color(0xFFEB6F92);

enum _SwitchAccountSheetAction { addAccount }

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _user = UserManager();
  bool _userActionsExpanded = false;

  /// extension part 文件里的成员不是 State 子类成员，不能直接调用受保护的
  /// [setState]，统一经由这个转发方法。
  void _setState(VoidCallback fn) => setState(fn);

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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final hp = ScreenLayout.horizontalPadding(screenWidth);
    final isWide =
        ScreenLayout.contentWidth(screenWidth) >= ScreenLayout.wideBreakpoint;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.of(context).padding.top),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(hp, 16, hp, 16),
              child: _user.isLoggedIn
                  ? _buildUserCard(cs, tt)
                  : _buildLoginCard(cs, tt),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(hp, 0, hp, 16),
              // 宽屏双栏：左列为通用设置卡片，右列为下载/记录卡片 + 关于卡片；
              // 窄屏维持原来的单列纵向排布。
              child: isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildGeneralSettingsCard()),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            children: [
                              _buildDataSettingsCard(),
                              const SizedBox(height: AppSpacing.md),
                              _buildAboutCard(),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        _buildGeneralSettingsCard(),
                        const SizedBox(height: AppSpacing.md),
                        _buildDataSettingsCard(),
                        const SizedBox(height: AppSpacing.md),
                        _buildAboutCard(),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard(ColorScheme cs, TextTheme tt) {
    final l10n = AppLocalizations.of(context)!;

    return Card(
      color: cs.surfaceBright,
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

class _SettingIcon extends StatelessWidget {
  final IconData icon;

  const _SettingIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    // 与许可证页头部图标同款：裸图标 + 主题色，不带底衬色块。
    return Icon(
      icon,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      size: 24,
    );
  }
}
