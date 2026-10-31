import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'collapsible_content.dart';
import 'section_header.dart';
import 'settings_section.dart';

/// 阅读设置中的细调分组；主开关由宿主放在分组外。
class ReaderSettingsFold extends StatefulWidget {
  const ReaderSettingsFold({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  State<ReaderSettingsFold> createState() => _ReaderSettingsFoldState();
}

class _ReaderSettingsFoldState extends State<ReaderSettingsFold> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            expanded: _expanded,
            child: Material(
              color: Colors.transparent,
              child: SectionHeader(
                title: widget.title,
                icon: widget.icon,
                onTap: () => setState(() => _expanded = !_expanded),
                trailing: Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                ),
              ),
            ),
          ),
          CollapsibleContent(
            expanded: _expanded,
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}
