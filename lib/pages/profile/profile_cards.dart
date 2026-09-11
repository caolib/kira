part of '../profile_page.dart';

extension _ProfileCards on _ProfilePageState {
  /// 第一块设置卡片：通用 / 外观 / 网络 / AI 配置 / 通知中心。
  Widget _buildGeneralSettingsCard() {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return SettingTileGroup(
      children: [
        ListTile(
          leading: const _SettingIcon(icon: Icons.tune_rounded),
          title: Text(l10n.generalTitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.pushNamed(AppRoutes.general),
        ),
        ListTile(
          leading: const _SettingIcon(icon: Icons.palette_rounded),
          title: Text(l10n.appearanceTitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.pushNamed(AppRoutes.appearance),
        ),
        ListTile(
          leading: const _SettingIcon(icon: Icons.dns_rounded),
          title: Text(l10n.networkTitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.pushNamed(AppRoutes.network),
        ),
        ListTile(
          leading: const _SettingIcon(icon: Icons.smart_toy_outlined),
          title: Text(l10n.aiConfigTitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.pushNamed(AppRoutes.aiConfig),
        ),
        ValueListenableBuilder<int>(
          valueListenable: RemoteNoticeService.unreadActiveCount,
          builder: (context, count, _) {
            return ListTile(
              leading: Stack(
                clipBehavior: Clip.none,
                children: [
                  const _SettingIcon(icon: Icons.notifications_active_outlined),
                  if (count > 0)
                    Positioned(
                      right: -1,
                      top: -1,
                      child: _NoticeRedDot(
                        color: _noticeCenterColor,
                        borderColor: cs.surfaceBright,
                      ),
                    ),
                ],
              ),
              title: Text(l10n.noticeCenterTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.pushNamed(AppRoutes.noticeCenter),
            );
          },
        ),
      ],
    );
  }

  /// 第二块设置卡片：下载中心 / 浏览历史 / 书签 / 阅读统计。
  Widget _buildDataSettingsCard() {
    final l10n = AppLocalizations.of(context)!;
    return SettingTileGroup(
      children: [
        ListTile(
          leading: const _SettingIcon(icon: Icons.download_done_rounded),
          title: Text(l10n.downloadCenterTitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.pushNamed(AppRoutes.downloadCenter),
        ),
        ListTile(
          leading: const _SettingIcon(icon: Icons.history_rounded),
          title: Text(l10n.browseHistoryTitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.pushNamed(AppRoutes.browseHistory),
        ),
        ListTile(
          leading: const _SettingIcon(icon: Icons.bookmark_outline_rounded),
          title: Text(l10n.bookmarksTitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.pushNamed(AppRoutes.bookmarks),
        ),
        ListTile(
          leading: const _SettingIcon(icon: Icons.bar_chart_rounded),
          title: Text(l10n.statsTitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.pushNamed(AppRoutes.stats),
        ),
      ],
    );
  }

  /// 第三块设置卡片：关于。
  Widget _buildAboutCard() {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return SettingTileGroup(
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: AppUpdateService.hasUnseenUpdate,
          builder: (context, hasUnseenUpdate, _) {
            return ListTile(
              leading: Stack(
                clipBehavior: Clip.none,
                children: [
                  const _SettingIcon(icon: Icons.info_rounded),
                  if (hasUnseenUpdate)
                    Positioned(
                      right: -1,
                      top: -1,
                      child: _NoticeRedDot(
                        color: _noticeCenterColor,
                        borderColor: cs.surfaceBright,
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
      ],
    );
  }

  Widget _buildLoginCard(ColorScheme cs, TextTheme tt) {
    final l10n = AppLocalizations.of(context)!;

    return Card(
      color: cs.surfaceBright,
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
}
