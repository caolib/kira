import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../models/user_manager.dart';
import '../utils/app_update.dart';
import '../utils/remote_notice_service.dart';

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
    if (!mounted || _didCheckRemoteNotice) return;
    _didCheckRemoteNotice = true;
    unawaited(RemoteNoticeService.syncSilently());
  }

  // Navigation key → branch index mapping.
  // The branch order in StatefulShellRoute must match this.
  static const _navKeyToBranchIndex = {
    'comic': 0,
    'anime': 1,
    'search': 2,
    'bookshelf': 3,
    'profile': 4,
  };

  static const _navItemData = {
    'comic': _NavItem(
      icon: Icon(Icons.menu_book_outlined),
      selectedIcon: Icon(Icons.menu_book),
      labelKey: 'comic',
    ),
    'anime': _NavItem(
      icon: Icon(Icons.movie_outlined),
      selectedIcon: Icon(Icons.movie),
      labelKey: 'anime',
    ),
    'search': _NavItem(
      icon: Icon(Icons.search_outlined),
      selectedIcon: Icon(Icons.search),
      labelKey: 'search',
    ),
    'bookshelf': _NavItem(
      icon: Icon(Icons.bookmark_border),
      selectedIcon: Icon(Icons.bookmark),
      labelKey: 'bookshelf',
    ),
    'profile': _NavItem(
      icon: Icon(Icons.person_outline),
      selectedIcon: Icon(Icons.person),
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

  List<String> _visibleNavKeys() {
    final keys = _user.navOrder
        .where(_navItemData.containsKey)
        .where((k) => _user.isLoggedIn || k != 'bookshelf')
        .where((k) => _user.animeFeatureEnabled || k != 'anime')
        .toList();
    return keys.isEmpty ? const [UserManager.defaultNavKey] : keys;
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final orderedKeys = _visibleNavKeys();
    final destinations = [
      for (final key in orderedKeys)
        _buildDestination(key: key, label: _navLabel(l10n, key)),
    ];
    final selectedIndex = _selectedIndex(orderedKeys);

    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (i) {
          final navKey = orderedKeys[i];
          final branchIndex = _navKeyToBranchIndex[navKey];
          if (branchIndex != null) {
            widget.navigationShell.goBranch(
              branchIndex,
              initialLocation:
                  branchIndex == widget.navigationShell.currentIndex,
            );
          }
          unawaited(_user.setLastNavKey(navKey));
        },
        height: _user.bottomNavShowLabels ? null : 64,
        labelBehavior: _user.bottomNavShowLabels
            ? NavigationDestinationLabelBehavior.alwaysShow
            : NavigationDestinationLabelBehavior.alwaysHide,
        destinations: destinations,
      ),
    );
  }

  NavigationDestination _buildDestination({
    required String key,
    required String label,
  }) {
    final item = _navItemData[key]!;
    if (key != 'profile') {
      return NavigationDestination(
        icon: item.icon,
        selectedIcon: item.selectedIcon,
        label: label,
      );
    }

    return NavigationDestination(
      icon: _NoticeBadgeIcon(child: item.icon),
      selectedIcon: _NoticeBadgeIcon(child: item.selectedIcon),
      label: label,
    );
  }
}

class _NavItem {
  final Icon icon;
  final Icon selectedIcon;
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
