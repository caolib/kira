import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_nav_bar/google_nav_bar.dart';

import '../l10n/app_localizations.dart';
import '../models/user_manager.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../utils/adaptive_motion.dart';
import '../utils/app_update.dart';
import '../utils/dialog_width.dart';
import '../utils/remote_notice_service.dart';
import '../utils/settings_rebuild_guard.dart';
import '../utils/toast.dart';

part 'main_shell_parts/main_shell_badges.dart';
part 'main_shell_parts/main_shell_branch_container.dart';

// Navigation key → branch index mapping.
// The branch order in StatefulShellRoute must match this.
const _navKeyToBranchIndex = {
  'comic': 0,
  'search': 1,
  'bookshelf': 2,
  'profile': 3,
};

List<String> _visibleNavKeys(UserManager user) {
  final keys = user.navOrder
      .where(_navKeyToBranchIndex.containsKey)
      .where((key) => user.isLoggedIn || key != 'bookshelf')
      .toList();
  return keys.isEmpty ? const [UserManager.defaultNavKey] : keys;
}

/// 底部导航分支容器的 GlobalKey：MainShell 通过它把拖动手势转发给容器做跟手滑动。
final _branchContainerKey = GlobalKey<_AnimatedBranchContainerState>();

/// Keeps every StatefulShellRoute branch alive while animating branch changes.
Widget buildMainShellNavigatorContainer(
  BuildContext context,
  StatefulNavigationShell navigationShell,
  List<Widget> children,
) {
  return _AnimatedBranchContainer(
    key: _branchContainerKey,
    currentIndex: navigationShell.currentIndex,
    children: children,
  );
}

/// Shell widget that wraps the bottom navigation bar around the
/// [StatefulNavigationShell] provided by GoRouter's [StatefulShellRoute].
class MainShell extends StatefulWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({super.key, required this.navigationShell});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with SettingsRebuildGuard<MainShell> {
  /// 首次返回后允许「再按一次退出」的窗口期。
  static const _backExitWindow = Duration(seconds: 2);

  final _user = UserManager();
  bool _didAutoCheckUpdate = false;
  bool _didCheckDisclaimer = false;
  bool _didCheckRemoteNotice = false;
  DateTime? _lastBackAttemptAt;

  @override
  void initState() {
    super.initState();
    _user.addListener(handleSettingsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runStartupFlow();
    });
  }

  @override
  void dispose() {
    _user.removeListener(handleSettingsChanged);
    super.dispose();
  }

  /// 含 build 间接依赖：_visibleNavKeys 会读 navOrder / isLoggedIn。
  /// navOrder 是 List，Record 对它是引用相等，
  /// 必须展平后再参与比较。
  @override
  Object watchedSettings() => (
    _user.autoCheckUpdate,
    _user.bottomNavLabelMode,
    _user.disclaimerAccepted,
    _user.lastNavKey,
    _user.remoteNoticeEnabled,
    _user.isLoggedIn,
    _user.navOrder.join('\u0000'),
    _user.theme.navSwipeEnabled,
    _user.theme.backExitConfirm,
  );

  Future<void> _runStartupFlow() async {
    await _ensureDisclaimerAccepted();
    if (!mounted) return;
    _restoreLastBranch();
    _maybeCheckRemoteNotice();
    if (!mounted) return;
    await _maybeAutoCheckUpdate();
  }

  void _restoreLastBranch() {
    final lastKey = _user.lastNavKey;
    final branchIndex = _navKeyToBranchIndex[lastKey];
    if (branchIndex != null &&
        branchIndex != widget.navigationShell.currentIndex) {
      widget.navigationShell.goBranch(branchIndex);
    }
  }

  Future<void> _ensureDisclaimerAccepted() async {
    if (_didCheckDisclaimer || _user.disclaimerAccepted || !mounted) return;
    _didCheckDisclaimer = true;

    final l10n = AppLocalizations.of(context)!;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DisclaimerDialog(
        items: _disclaimerItems(l10n),
        confirmLabel: l10n.disclaimerConfirmAgeAndTerms,
      ),
    );
    if (!mounted) return;

    if (accepted == true) {
      await _user.setDisclaimerAccepted(true);
    }
  }

  List<String> _disclaimerItems(AppLocalizations l10n) => [
    l10n.appDisclaimerItem1,
    l10n.appDisclaimerItem2,
    l10n.appDisclaimerItem3,
    l10n.appDisclaimerItem4,
    l10n.appDisclaimerItem5,
    l10n.appDisclaimerItem6,
  ];

  Future<void> _maybeAutoCheckUpdate() async {
    if (!mounted || _didAutoCheckUpdate || !_user.autoCheckUpdate) return;
    _didAutoCheckUpdate = true;
    await AppUpdateService.checkAndPrompt(context, auto: true);
  }

  void _maybeCheckRemoteNotice() {
    if (!mounted || _didCheckRemoteNotice || !_user.remoteNoticeEnabled) return;
    _didCheckRemoteNotice = true;
    unawaited(RemoteNoticeService.syncSilently());
  }

  static const _navItemData = {
    'comic': _NavItem(
      icon: Icons.menu_book_outlined,
      selectedIcon: Icons.menu_book,
      labelKey: 'comic',
    ),
    'search': _NavItem(
      icon: Icons.search_outlined,
      selectedIcon: Icons.search,
      labelKey: 'search',
    ),
    'bookshelf': _NavItem(
      icon: Icons.bookmark_border,
      selectedIcon: Icons.bookmark,
      labelKey: 'bookshelf',
    ),
    'profile': _NavItem(
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
      labelKey: 'profile',
    ),
  };

  static String _navLabel(AppLocalizations l10n, String key) {
    switch (key) {
      case 'comic':
        return l10n.comicTabLabel;
      case 'search':
        return l10n.searchTabLabel;
      case 'bookshelf':
        return l10n.bookshelfTabLabel;
      case 'profile':
        return l10n.profileTabLabel;
      default:
        return key;
    }
  }

  int _selectedIndex(List<String> orderedKeys) {
    final currentBranch = widget.navigationShell.currentIndex;
    // Map current branch index back to nav key
    final currentKey = _navKeyToBranchIndex.entries
        .where((e) => e.value == currentBranch)
        .map((e) => e.key)
        .firstOrNull;
    if (currentKey != null && orderedKeys.contains(currentKey)) {
      return orderedKeys.indexOf(currentKey);
    }
    // Fallback: find the ordered key whose branch index matches
    for (var i = 0; i < orderedKeys.length; i++) {
      final branchIndex = _navKeyToBranchIndex[orderedKeys[i]];
      if (branchIndex == currentBranch) return i;
    }
    return 0;
  }

  void _goToDestination(
    List<String> orderedKeys,
    int index, {
    bool resetIfSelected = false,
  }) {
    final navKey = orderedKeys[index];
    final branchIndex = _navKeyToBranchIndex[navKey];
    if (branchIndex != null) {
      widget.navigationShell.goBranch(
        branchIndex,
        initialLocation:
            resetIfSelected &&
            branchIndex == widget.navigationShell.currentIndex,
      );
    }
    unawaited(_user.setLastNavKey(navKey));
  }

  void _onHorizontalDragEnd(DragEndDetails details, List<String> orderedKeys) {
    // 容器负责收尾动画并返回落点；这里把结果提交给路由（同步 lastNavKey）。
    final state = _branchContainerKey.currentState;
    final destIndex = state?.settleFromPointer(details);
    if (destIndex == null) return;
    _goToDestination(orderedKeys, destIndex);
  }

  /// 双击返回退出：第一次返回只提示，窗口期内再返回才真正退出。
  void _handleBackAttempt() {
    final now = DateTime.now();
    final lastAttempt = _lastBackAttemptAt;
    if (lastAttempt != null && now.difference(lastAttempt) <= _backExitWindow) {
      _lastBackAttemptAt = null;
      SystemNavigator.pop();
      return;
    }

    _lastBackAttemptAt = now;
    showToast(
      context,
      AppLocalizations.of(context)!.backAgainToExitToast,
      duration: _backExitWindow,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final orderedKeys = _visibleNavKeys(_user);
    final selectedIndex = _selectedIndex(orderedKeys);
    final labelMode = _user.bottomNavLabelMode;
    final size = MediaQuery.sizeOf(context);
    // 宽 > 高且 ≥600 的横屏/宽窗口用左侧 NavigationRail，释放纵向空间；
    // 竖屏维持底部导航（含 capsule 样式与标签模式设置）。
    final useSideNav = size.width > size.height && size.width >= 600;

    // canPop=false 只作用于 shell 路由本身：分支内已 push 的页面、根导航栈上
    // 的顶层页面各自先处理返回，走不到这里。
    return PopScope(
      canPop: !_user.theme.backExitConfirm,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBackAttempt();
      },
      child: Scaffold(
        body: useSideNav
            ? Row(
                children: [
                  _buildSideNavRail(
                    orderedKeys: orderedKeys,
                    selectedIndex: selectedIndex,
                    l10n: l10n,
                  ),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                  Expanded(child: _buildBranchArea(orderedKeys)),
                ],
              )
            : _buildBranchArea(orderedKeys),
        bottomNavigationBar: useSideNav
            ? null
            : labelMode == BottomNavLabelMode.always
            ? _buildClassicNavBar(
                orderedKeys: orderedKeys,
                selectedIndex: selectedIndex,
                l10n: l10n,
              )
            : _buildCapsuleNavBar(
                orderedKeys: orderedKeys,
                selectedIndex: selectedIndex,
                l10n: l10n,
                showSelectedLabel: labelMode == BottomNavLabelMode.selectedOnly,
              ),
      ),
    );
  }

  /// 分支内容区：navSwipeEnabled 时外挂横向拖动手势做分支跟手切换。
  Widget _buildBranchArea(List<String> orderedKeys) {
    return _user.theme.navSwipeEnabled
        ? GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (details) =>
                _branchContainerKey.currentState?.dragBegin(details),
            onHorizontalDragUpdate: (details) =>
                _branchContainerKey.currentState?.dragUpdate(details),
            onHorizontalDragEnd: (details) {
              _onHorizontalDragEnd(details, orderedKeys);
            },
            onHorizontalDragCancel: () =>
                _branchContainerKey.currentState?.dragCancel(),
            child: widget.navigationShell,
          )
        : widget.navigationShell;
  }

  Widget _buildSideNavRail({
    required List<String> orderedKeys,
    required int selectedIndex,
    required AppLocalizations l10n,
  }) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: NavigationRail(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) =>
            _goToDestination(orderedKeys, index, resetIfSelected: true),
        backgroundColor: cs.surfaceContainer,
        labelType: NavigationRailLabelType.all,
        groupAlignment: -1.0,
        destinations: [
          for (final key in orderedKeys)
            _buildRailDestination(key: key, label: _navLabel(l10n, key)),
        ],
      ),
    );
  }

  NavigationRailDestination _buildRailDestination({
    required String key,
    required String label,
  }) {
    final item = _navItemData[key]!;
    if (key != 'profile') {
      return NavigationRailDestination(
        icon: Icon(item.icon),
        selectedIcon: Icon(item.selectedIcon),
        label: Text(label),
      );
    }

    return NavigationRailDestination(
      icon: _NoticeBadgeIcon(child: Icon(item.icon)),
      selectedIcon: _NoticeBadgeIcon(child: Icon(item.selectedIcon)),
      label: Text(label),
    );
  }

  Widget _buildClassicNavBar({
    required List<String> orderedKeys,
    required int selectedIndex,
    required AppLocalizations l10n,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainer,
      elevation: 3,
      shadowColor: AppShadows.floatingTint(),
      child: SafeArea(
        top: false,
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: (index) =>
              _goToDestination(orderedKeys, index, resetIfSelected: true),
          backgroundColor: Colors.transparent,
          elevation: 0,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            for (final key in orderedKeys)
              _buildClassicDestination(key: key, label: _navLabel(l10n, key)),
          ],
        ),
      ),
    );
  }

  NavigationDestination _buildClassicDestination({
    required String key,
    required String label,
  }) {
    final item = _navItemData[key]!;
    if (key != 'profile') {
      return NavigationDestination(
        icon: Icon(item.icon),
        selectedIcon: Icon(item.selectedIcon),
        label: label,
      );
    }

    return NavigationDestination(
      icon: _NoticeBadgeIcon(child: Icon(item.icon)),
      selectedIcon: _NoticeBadgeIcon(child: Icon(item.selectedIcon)),
      label: label,
    );
  }

  Widget _buildCapsuleNavBar({
    required List<String> orderedKeys,
    required int selectedIndex,
    required AppLocalizations l10n,
    required bool showSelectedLabel,
  }) {
    final cs = Theme.of(context).colorScheme;
    // icon scales with text size; padding caps at 1.2 so large-text users
    // don't blow up capsule height past SafeArea.
    final textScale = MediaQuery.textScalerOf(
      context,
    ).scale(1).clamp(1.0, 1.35);
    final cappedScale = textScale > 1.2 ? 1.2 : textScale;
    final iconSize = 24.0 * textScale;
    final hPad = (showSelectedLabel ? 16.0 : 18.0) * cappedScale;
    final vPad = 12.0 * cappedScale;
    final gap = showSelectedLabel ? 8.0 * cappedScale : 0.0;
    final reducedMotion = prefersReducedMotion(context);
    return Material(
      color: cs.surfaceContainer,
      elevation: 3,
      shadowColor: AppShadows.floatingTint(),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 12 * textScale,
            vertical: 10 * textScale,
          ),
          child: GNav(
            selectedIndex: selectedIndex,
            onTabChange: (index) =>
                _goToDestination(orderedKeys, index, resetIfSelected: true),
            gap: gap,
            iconSize: iconSize,
            // Match Bettbox's capsule indicator timing/feel.
            duration: adaptiveDuration(
              context,
              const Duration(milliseconds: 250),
            ),
            // Linear when reduced motion to avoid residual easing drift.
            curve: reducedMotion ? Curves.linear : Curves.easeInOut,
            color: cs.onSurfaceVariant,
            activeColor: cs.onSecondaryContainer,
            tabBackgroundColor: cs.secondaryContainer,
            rippleColor: cs.onSurface.withValues(alpha: 0.12),
            hoverColor: cs.onSurface.withValues(alpha: 0.08),
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            tabs: [
              for (final key in orderedKeys)
                _buildGButton(
                  key: key,
                  label: showSelectedLabel ? _navLabel(l10n, key) : '',
                  iconSize: iconSize,
                ),
            ],
          ),
        ),
      ),
    );
  }

  GButton _buildGButton({
    required String key,
    required String label,
    required double iconSize,
  }) {
    final item = _navItemData[key]!;
    if (key != 'profile') {
      return GButton(icon: item.selectedIcon, text: label);
    }

    return GButton(
      icon: item.selectedIcon,
      text: label,
      leading: _NoticeBadgeIcon(child: Icon(item.selectedIcon, size: iconSize)),
    );
  }
}
