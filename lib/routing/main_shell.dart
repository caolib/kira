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

// Navigation key → branch index mapping.
// The branch order in StatefulShellRoute must match this.
const _navKeyToBranchIndex = {
  'comic': 0,
  'anime': 1,
  'search': 2,
  'bookshelf': 3,
  'profile': 4,
};

List<String> _visibleNavKeys(UserManager user) {
  final keys = user.navOrder
      .where(_navKeyToBranchIndex.containsKey)
      .where((key) => user.isLoggedIn || key != 'bookshelf')
      .where((key) => user.animeFeatureEnabled || key != 'anime')
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

  /// 含 build 间接依赖：_visibleNavKeys 会读 navOrder / isLoggedIn /
  /// animeFeatureEnabled。navOrder 是 List，Record 对它是引用相等，
  /// 必须展平后再参与比较。
  @override
  Object watchedSettings() => (
    _user.autoCheckUpdate,
    _user.bottomNavLabelMode,
    _user.disclaimerAccepted,
    _user.lastNavKey,
    _user.remoteNoticeEnabled,
    _user.isLoggedIn,
    _user.animeFeatureEnabled,
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
    'anime': _NavItem(
      icon: Icons.movie_outlined,
      selectedIcon: Icons.movie,
      labelKey: 'anime',
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
      case 'anime':
        return l10n.animeTabLabel;
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

    // canPop=false 只作用于 shell 路由本身：分支内已 push 的页面、根导航栈上
    // 的顶层页面各自先处理返回，走不到这里。
    return PopScope(
      canPop: !_user.theme.backExitConfirm,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBackAttempt();
      },
      child: Scaffold(
        body: _user.theme.navSwipeEnabled
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
            : widget.navigationShell,
        bottomNavigationBar: labelMode == BottomNavLabelMode.always
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

/// Dual-page linked slide between shell branches (no intermediate-page sweep).
///
/// Hidden tabs stay mounted offstage so branch state is preserved.
///
/// 视觉模型：单一连续滚动位置 [_AnimatedBranchContainerState._scrollPos]（单位：页宽），
/// 页 i 的平移量 = 可见序(i) − _S。三种来源写入 _scrollPos —— 跟手拖动、松手收尾补间、
/// 标准切换补间。仅参与滚动的相邻两页保持可见，其余照旧 offstage 保活。
class _AnimatedBranchContainer extends StatefulWidget {
  const _AnimatedBranchContainer({
    super.key,
    required this.currentIndex,
    required this.children,
  });

  final int currentIndex;
  final List<Widget> children;

  @override
  State<_AnimatedBranchContainer> createState() =>
      _AnimatedBranchContainerState();
}

class _AnimatedBranchContainerState extends State<_AnimatedBranchContainer>
    with SingleTickerProviderStateMixin {
  static const _duration = kTabScrollDuration;

  /// 与旧行为一致的甩动翻页速度阈值（px/s）。
  static const _flingVelocity = 400.0;

  late final AnimationController _controller;
  Animation<double>? _tween;

  late List<String> _orderedKeys;
  bool _reduceMotion = false;

  /// 连续滚动位置（可见页单位），静止时恒为整数页位。
  double _scrollPos = 0;

  /// 手势交互期间接收指针的真实分支。滑动未确认前保持旧值，避免指针中途
  /// 落到尚未到达的新页上。
  int _logicalBranch = 0;

  /// 跟手拖动中。
  bool _dragging = false;

  /// 本次手势累计位移（px，右滑为正）。
  double _dragAccumPx = 0;

  /// 拖动开始时相对逻辑页位的既有偏移（上次收尾被打断时的残余），保证连续。
  double _dragBaseProgress = 0;

  /// 松手收尾后等待父级 goBranch 确认的目标分支；确认前 UI 视觉已到位，
  /// didUpdateWidget 收到同分支变化时只认领逻辑页，不重放动画。
  int? _pendingBranch;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration);
    _controller.addListener(() {
      final tween = _tween;
      if (tween == null) return;
      setState(() => _scrollPos = tween.value);
    });
    _controller.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      _tween = null;
      setState(() {});
    });
    _logicalBranch = widget.currentIndex;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _orderedKeys = _visibleNavKeys(UserManager());
    _reduceMotion = prefersReducedMotion(context);
    _controller.duration = _reduceMotion ? Duration.zero : _duration;
    if (!_dragging && _pendingBranch == null) {
      _scrollPos = _visiblePos(widget.currentIndex);
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedBranchContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _orderedKeys = _visibleNavKeys(UserManager());

    if (oldWidget.currentIndex == widget.currentIndex) return;

    final newPos = _visiblePos(widget.currentIndex);

    // 松手收尾的目标被父级确认：视觉已经在路上，只认领逻辑分支。
    if (_pendingBranch == widget.currentIndex && !_dragging) {
      setState(() {
        _logicalBranch = widget.currentIndex;
        _pendingBranch = null;
      });
      return;
    }

    if (_dragging) _abortDrag();
    _pendingBranch = null;

    setState(() {
      _logicalBranch = widget.currentIndex;
      if (_reduceMotion) {
        _tween = null;
        _controller.stop();
        _scrollPos = newPos;
      } else {
        _startTween(_scrollPos, newPos, _duration);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _uiBranch => (_dragging || _pendingBranch != null)
      ? _logicalBranch
      : widget.currentIndex;

  double _visiblePos(int branchIndex) {
    final navKey = _navKeyToBranchIndex.entries
        .where((entry) => entry.value == branchIndex)
        .map((entry) => entry.key)
        .firstOrNull;
    final visibleIndex = navKey == null ? -1 : _orderedKeys.indexOf(navKey);
    return visibleIndex < 0 ? branchIndex.toDouble() : visibleIndex.toDouble();
  }

  void _startTween(double from, double to, Duration duration) {
    _tween = Tween<double>(
      begin: from,
      end: to,
    ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(_controller);
    _controller.duration = duration;
    _controller.forward(from: 0);
  }

  // ---- 跟手拖动（由 MainShell 转发手势回调） ----

  void dragBegin(DragStartDetails details) {
    if (_dragging) return;
    // 打断进行中的收尾/切换补间，从当前位置无缝接管。
    _controller.stop();
    _tween = null;
    _pendingBranch = null;
    _dragging = true;
    _dragAccumPx = 0;
    _dragBaseProgress = _scrollPos - _visiblePos(_uiBranch);
  }

  void dragUpdate(DragUpdateDetails details) {
    if (!_dragging) return;
    final width = context.size?.width ?? 0;
    if (width <= 0) return;
    _dragAccumPx += details.primaryDelta ?? 0;
    var progress = _dragBaseProgress - _dragAccumPx / width;

    // 边界钳制：progress<0 是往上一页方向——首页没有上一页，钳住；
    // 末页没有下一页同理（PageView 行为）。
    final cur = _visiblePos(_uiBranch);
    if (cur <= 0 && progress < 0) progress = 0;
    if (cur >= _orderedKeys.length - 1 && progress > 0) progress = 0;
    progress = progress.clamp(-1.0, 1.0);

    setState(() => _scrollPos = cur + progress);
  }

  /// 当前拖动进度（负值表示朝下一页方向）。
  double get _dragProgress {
    final width = context.size?.width ?? 0;
    if (width <= 0 || !_dragging) return 0;
    return (_scrollPos - _visiblePos(_uiBranch)).clamp(-1.0, 1.0);
  }

  /// 松手收尾：按位移过半或甩动方向决定落到相邻页还是弹回，
  /// 返回应提交的可见序（无切换时返回 null）。调用方随后 goBranch 确认。
  int? settleFromPointer(DragEndDetails details) {
    if (!_dragging) return null;
    final cur = _visiblePos(_uiBranch);
    final velocity = details.primaryVelocity ?? 0;

    var target = 0;
    // 拖动进度 p = _S − cur：向左滑为正（朝下一页）。位移过半或沿该方向的
    // 甩动速度足够快即翻页；两者冲突时以甩动为准（PageView 行为）。
    final progress = _dragProgress;
    if (velocity.abs() >= _flingVelocity) {
      target = velocity.sign < 0 ? 1 : -1;
    } else if (progress >= 0.5) {
      target = 1;
    } else if (progress <= -0.5) {
      target = -1;
    }

    // 目标页越界则原地弹回。
    final destIndex = (cur.round() + target).clamp(0, _orderedKeys.length - 1);
    target = destIndex - cur.round();

    _dragging = false;
    _dragAccumPx = 0;
    _dragBaseProgress = 0;

    final dest = cur + target.toDouble();
    if ((dest - _scrollPos).abs() < 0.0005) {
      _scrollPos = dest;
      setState(() {});
      return target == 0 ? null : destIndex;
    }
    if (target != 0) _pendingBranch = _branchAtVisiblePos(destIndex);
    setState(() {});
    if (_reduceMotion) {
      _tween = null;
      _controller.stop();
      _scrollPos = dest;
      setState(() {});
    } else {
      // 快速轻甩时距离短，收尾节奏随剩余距离缩短，避免「一甩等半秒」。
      final remaining = (dest - _scrollPos).abs();
      _startTween(
        _scrollPos,
        dest,
        Duration(milliseconds: (120 + 180 * remaining).round()),
      );
    }
    return target == 0 ? null : destIndex;
  }

  int _branchAtVisiblePos(int visibleIndex) {
    for (final entry in _navKeyToBranchIndex.entries) {
      if (_orderedKeys.indexOf(entry.key) == visibleIndex) return entry.value;
    }
    return visibleIndex;
  }

  void dragCancel() {
    if (!_dragging) return;
    _dragging = false;
    _dragAccumPx = 0;
    _dragBaseProgress = 0;
    final dest = _visiblePos(_uiBranch);
    if ((dest - _scrollPos).abs() < 0.0005) {
      _scrollPos = dest;
      setState(() {});
      return;
    }
    if (_reduceMotion) {
      _tween = null;
      _controller.stop();
      _scrollPos = dest;
      setState(() {});
    } else {
      _startTween(
        _scrollPos,
        dest,
        Duration(milliseconds: (120 + 180 * (dest - _scrollPos).abs()).round()),
      );
    }
  }

  /// 不播放收尾动画地终止拖动状态（例如父级在拖动中切换了分支）。
  void _abortDrag() {
    _dragging = false;
    _dragAccumPx = 0;
    _dragBaseProgress = 0;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            for (var index = 0; index < widget.children.length; index++)
              _buildBranch(index),
          ],
        );
      },
    );
  }

  Widget _buildBranch(int index) {
    final pos = _scrollPos;
    final v = _visiblePos(index);
    // 只有两端参与滚动（floor/ceil 各占其一）；区间判定容忍浮点误差。
    final participates = v >= pos.floorToDouble() && v <= pos.ceilToDouble();
    final isLogical = index == _uiBranch;

    if (!participates) {
      return Offstage(
        child: TickerMode(
          enabled: false,
          child: IgnorePointer(child: widget.children[index]),
        ),
      );
    }

    final dx = v - pos;
    return Offstage(
      offstage: dx.abs() >= 1,
      child: TickerMode(
        enabled: isLogical,
        child: IgnorePointer(
          ignoring: !isLogical,
          child: FractionalTranslation(
            translation: Offset(dx, 0),
            child: widget.children[index],
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String labelKey;
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.labelKey,
  });
}

class _BadgeIcon extends StatelessWidget {
  const _BadgeIcon({required this.showBadge, required this.child});

  final bool showBadge;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!showBadge) return child;
    final cs = Theme.of(context).colorScheme;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -2,
          top: -2,
          child: ExcludeSemantics(
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: cs.primary,
                shape: BoxShape.circle,
                border: Border.all(color: cs.surface, width: 1.2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NoticeBadgeIcon extends StatelessWidget {
  const _NoticeBadgeIcon({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: RemoteNoticeService.unreadActiveCount,
      builder: (_, count, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: AppUpdateService.hasUnseenUpdate,
          builder: (_, hasUnseenUpdate, _) {
            final showBadge = count > 0 || hasUnseenUpdate;
            return _BadgeIcon(showBadge: showBadge, child: child);
          },
        );
      },
    );
  }
}

class _DisclaimerDialog extends StatefulWidget {
  final List<String> items;
  final String confirmLabel;

  const _DisclaimerDialog({required this.items, required this.confirmLabel});

  @override
  State<_DisclaimerDialog> createState() => _DisclaimerDialogState();
}

class _DisclaimerDialogState extends State<_DisclaimerDialog> {
  bool _accepted = false;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(l10n.disclaimerTitle),
        content: SizedBox(
          width: dialogContentWidth(context, 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final item in widget.items) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('• ', style: tt.bodyMedium),
                            Expanded(child: Text(item, style: tt.bodyMedium)),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        l10n.disclaimerAgreeNote,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              CheckboxListTile(
                value: _accepted,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(widget.confirmLabel),
                onChanged: (value) {
                  setState(() => _accepted = value ?? false);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => SystemNavigator.pop(),
            child: Text(l10n.disagreeAndExit),
          ),
          FilledButton(
            onPressed: _accepted ? () => Navigator.of(context).pop(true) : null,
            child: Text(l10n.confirmButton),
          ),
        ],
      ),
    );
  }
}
