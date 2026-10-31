import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_icon_sizes.dart';
import '../utils/adaptive_motion.dart';

/// 行与箭头只展开/收起，开关独立控制启停。
class CollapsibleSwitchTile extends StatelessWidget {
  const CollapsibleSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.expanded,
    required this.onChanged,
    required this.onToggleExpanded,
    this.subtitle,
    this.switchKey,
    this.expandKey,
    this.adaptive = false,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final bool expanded;
  final ValueChanged<bool> onChanged;
  final VoidCallback onToggleExpanded;
  final Key? switchKey;
  final Key? expandKey;
  final bool adaptive;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: Colors.transparent,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              expanded: expanded,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(title),
                subtitle: subtitle == null ? null : Text(subtitle!),
                onTap: onToggleExpanded,
                trailing: Semantics(
                  label: title,
                  child: adaptive
                      ? Switch.adaptive(
                          key: switchKey,
                          value: value,
                          onChanged: onChanged,
                        )
                      : Switch(
                          key: switchKey,
                          value: value,
                          onChanged: onChanged,
                        ),
                ),
              ),
            ),
          ),
          Semantics(
            expanded: expanded,
            child: IconButton(
              key: expandKey,
              tooltip: expanded
                  ? l10n.chapterCommentsCollapse
                  : l10n.chapterCommentsExpand,
              onPressed: onToggleExpanded,
              icon: AnimatedRotation(
                key: ValueKey(prefersReducedMotion(context)),
                turns: expanded ? 0.5 : 0,
                duration: adaptiveDuration(
                  context,
                  const Duration(milliseconds: 180),
                ),
                child: const Icon(Icons.expand_more, size: AppIconSize.xl),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
