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

  static const _disclaimerItems = [
    '本应用（以下简称"本软件"）系独立开发的非官方第三方客户端，与任何内容平台、出版商或权利人均无隶属、合作或代理关系。',
    '本软件不生产、上传、存储、编辑、修改、推荐或预先审查任何具体内容。所有内容均来源于第三方平台公开接口或可访问资源，其合法性、准确性、完整性及合规性由相应内容提供方独立负责。',
    '本软件所展示的内容可能包含成人向、暴力、恐怖或其他不适宜未成年人浏览的信息。您确认您已年满 18 周岁，且您所在地法律法规允许您访问此类内容。如您不符合前述条件，请立即停止使用并卸载本软件。',
    '您应自行判断所浏览内容是否适合，并确保您的使用行为完全符合您所在地现行有效的法律法规。因您使用本软件而产生的一切法律后果由您自行承担。',
    '如任何第三方内容涉嫌侵犯他人合法权益或违反法律法规，权利人可通过本软件提供的联系方式向开发者发送有效通知，开发者将在合理期限内核实并采取必要措施。',
    '本软件按"现状"提供，开发者不对其功能性、可用性、准确性或可靠性作出任何明示或默示的保证。在任何情况下，开发者均不对因使用或无法使用本软件而产生的任何直接、间接、附带、特殊或后果性损害承担责任。',
  ];

  static const _disclaimerConfirmText = '我已年满 18 周岁，并已仔细阅读、充分理解且同意上述全部条款';

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
    await _maybeCheckRemoteNotice();
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

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _DisclaimerDialog(
        items: _disclaimerItems,
        confirmLabel: _disclaimerConfirmText,
      ),
    );
    if (!mounted) return;

    if (accepted == true) {
      await _user.setDisclaimerAccepted(true);
    }
  }

  Future<void> _maybeAutoCheckUpdate() async {
    if (!mounted || _didAutoCheckUpdate || !_user.autoCheckUpdate) return;
    _didAutoCheckUpdate = true;
    await AppUpdateService.checkAndPrompt(context, auto: true);
  }

  Future<void> _maybeCheckRemoteNotice() async {
    if (!mounted || _didCheckRemoteNotice) return;
    _didCheckRemoteNotice = true;
    await RemoteNoticeService.syncSilently();
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
