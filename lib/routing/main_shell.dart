import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_nav_bar/google_nav_bar.dart';

import '../l10n/app_localizations.dart';
import '../models/user_manager.dart';
import '../utils/app_update.dart';
import '../utils/remote_notice_service.dart';

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

/// Keeps every StatefulShellRoute branch alive while animating branch changes.
Widget buildMainShellNavigatorContainer(
  BuildContext context,
  StatefulNavigationShell navigationShell,
  List<Widget> children,
) {
  return _AnimatedBranchContainer(
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

class _MainShellState extends State<MainShell> {
  final _user = UserManager();
  bool _didAutoCheckUpdate = false;
  bool _didCheckDisclaimer = false;
  bool _didCheckRemoteNotice = false;
  double _horizontalDragDistance = 0;

  @override
  void initState() {
    super.initState();
    _user.addListener(_onUserChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runStartupFlow();
    });
  }

  @override
  void dispose() {
    _user.removeListener(_onUserChanged);
    super.dispose();
  }

  void _onUserChanged() {
    if (mounted) setState(() {});
  }

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
    final velocity = details.primaryVelocity ?? 0;
    if (_horizontalDragDistance.abs() < 48 && velocity.abs() < 400) return;

    final selectedIndex = _selectedIndex(orderedKeys);
    final direction = velocity.abs() >= 400
        ? velocity.sign
        : _horizontalDragDistance.sign;
    final nextIndex = selectedIndex + (direction < 0 ? 1 : -1);
    if (nextIndex >= 0 && nextIndex < orderedKeys.length) {
      _goToDestination(orderedKeys, nextIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final orderedKeys = _visibleNavKeys(_user);
    final selectedIndex = _selectedIndex(orderedKeys);
    final labelMode = _user.bottomNavLabelMode;

    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => _horizontalDragDistance = 0,
        onHorizontalDragUpdate: (details) {
          _horizontalDragDistance += details.primaryDelta ?? 0;
        },
        onHorizontalDragEnd: (details) {
          _onHorizontalDragEnd(details, orderedKeys);
          _horizontalDragDistance = 0;
        },
        onHorizontalDragCancel: () => _horizontalDragDistance = 0,
        child: widget.navigationShell,
      ),
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
    );
  }

  Widget _buildClassicNavBar({
    required List<String> orderedKeys,
    required int selectedIndex,
    required AppLocalizations l10n,
  }) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: (index) =>
          _goToDestination(orderedKeys, index, resetIfSelected: true),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: [
        for (final key in orderedKeys)
          _buildClassicDestination(key: key, label: _navLabel(l10n, key)),
      ],
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
    return Material(
      color: cs.surfaceContainer,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: GNav(
            selectedIndex: selectedIndex,
            onTabChange: (index) =>
                _goToDestination(orderedKeys, index, resetIfSelected: true),
            gap: showSelectedLabel ? 8 : 0,
            iconSize: 24,
            // Match Bettbox's capsule indicator timing/feel.
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            color: cs.onSurfaceVariant,
            activeColor: cs.onSecondaryContainer,
            tabBackgroundColor: cs.secondaryContainer,
            rippleColor: cs.onSurface.withValues(alpha: 0.12),
            hoverColor: cs.onSurface.withValues(alpha: 0.08),
            padding: EdgeInsets.symmetric(
              horizontal: showSelectedLabel ? 16 : 18,
              vertical: 12,
            ),
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            tabs: [
              for (final key in orderedKeys)
                _buildGButton(
                  key: key,
                  label: showSelectedLabel ? _navLabel(l10n, key) : '',
                ),
            ],
          ),
        ),
      ),
    );
  }

  GButton _buildGButton({required String key, required String label}) {
    final item = _navItemData[key]!;
    if (key != 'profile') {
      return GButton(icon: item.selectedIcon, text: label);
    }

    return GButton(
      icon: item.selectedIcon,
      text: label,
      leading: _NoticeBadgeIcon(child: Icon(item.selectedIcon, size: 24)),
    );
  }
}

/// Dual-page linked slide between shell branches (no intermediate-page sweep).
///
/// Hidden tabs stay mounted offstage so branch state is preserved.
class _AnimatedBranchContainer extends StatefulWidget {
  const _AnimatedBranchContainer({
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

  late final AnimationController _controller;
  late final Animation<double> _animation;

  int? _outgoingIndex;
  double _direction = 1;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && _outgoingIndex != null) {
          setState(() => _outgoingIndex = null);
        }
      });
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant _AnimatedBranchContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex == widget.currentIndex) return;

    final orderedKeys = _visibleNavKeys(UserManager());
    final oldPosition = _branchPosition(oldWidget.currentIndex, orderedKeys);
    final newPosition = _branchPosition(widget.currentIndex, orderedKeys);
    _outgoingIndex = oldWidget.currentIndex;
    _direction = newPosition >= oldPosition ? 1 : -1;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _branchPosition(int branchIndex, List<String> orderedKeys) {
    final navKey = _navKeyToBranchIndex.entries
        .where((entry) => entry.value == branchIndex)
        .map((entry) => entry.key)
        .firstOrNull;
    final visibleIndex = navKey == null ? -1 : orderedKeys.indexOf(navKey);
    return visibleIndex < 0 ? branchIndex.toDouble() : visibleIndex.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
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
    final isCurrent = index == widget.currentIndex;
    final isOutgoing = index == _outgoingIndex;
    final isActive = isCurrent || isOutgoing;

    // Linked PageView-style offsets, but only between the two endpoints:
    // - incoming starts at +direction and settles at 0
    // - outgoing starts at 0 and exits to -direction
    final double dx;
    if (isCurrent) {
      dx = (1 - _animation.value) * _direction;
    } else if (isOutgoing) {
      dx = -_animation.value * _direction;
    } else {
      dx = 0;
    }

    return Offstage(
      offstage: !isActive,
      child: TickerMode(
        enabled: isCurrent,
        child: IgnorePointer(
          ignoring: !isCurrent,
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
        return _BadgeIcon(showBadge: count > 0, child: child);
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
          width: 420,
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
                        const SizedBox(height: 8),
                      ],
                      const SizedBox(height: 4),
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
              const SizedBox(height: 16),
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
