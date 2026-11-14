import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_icon_sizes.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_status_colors.dart';
import '../utils/adaptive_motion.dart';

/// 漫画与小说共用合并卡片内容，正文仍由各域提供原有组件。
class MergedCommentContent extends StatelessWidget {
  const MergedCommentContent({
    super.key,
    required this.count,
    required this.names,
    required this.avatars,
    required this.body,
    this.userStyle,
    this.compact = false,
    this.contentSpacing = 8,
    this.showAvatar = true,
    this.showUserName = true,
  });

  final int count;
  final List<String> names;
  final List<Widget> avatars;
  final Widget body;
  final TextStyle? userStyle;
  final bool compact;
  final double contentSpacing;
  final bool showAvatar;
  final bool showUserName;

  @override
  Widget build(BuildContext context) {
    final avatarSize = compact ? 22.0 : 26.0;
    final overlap = compact ? 8.0 : 10.0;
    final avatarItems = avatars.take(5).toList(growable: false);
    final hasAvatars = showAvatar && avatarItems.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasAvatars) ...[
              SizedBox(
                width:
                    avatarSize +
                    (avatarItems.length - 1) * (avatarSize - overlap),
                height: avatarSize,
                child: Stack(
                  children: [
                    for (var i = 0; i < avatarItems.length; i++)
                      Positioned(
                        left: i * (avatarSize - overlap),
                        child: Container(
                          width: avatarSize,
                          height: avatarSize,
                          padding: EdgeInsets.all(compact ? 1.5 : 2),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHigh,
                            shape: BoxShape.circle,
                          ),
                          child: avatarItems[i],
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(width: compact ? 6 : AppSpacing.sm),
            ],
            if (showUserName)
              Expanded(
                child: _RotatingCommentUserName(names: names, style: userStyle),
              )
            else
              const Spacer(),
            if (count > 1) ...[
              const SizedBox(width: AppSpacing.sm),
              _MergedCommentCountTag(count: count, compact: compact),
            ],
          ],
        ),
        SizedBox(
          height: hasAvatars
              ? contentSpacing + (compact ? 1 : 2)
              : (compact ? 4 : 6),
        ),
        body,
      ],
    );
  }
}

class _RotatingCommentUserName extends StatefulWidget {
  const _RotatingCommentUserName({required this.names, this.style});

  final List<String> names;
  final TextStyle? style;

  @override
  State<_RotatingCommentUserName> createState() =>
      _RotatingCommentUserNameState();
}

class _RotatingCommentUserNameState extends State<_RotatingCommentUserName> {
  Timer? _timer;
  int _index = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTimer();
  }

  @override
  void didUpdateWidget(_RotatingCommentUserName oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_index >= widget.names.length) _index = 0;
    _syncTimer();
  }

  void _syncTimer() {
    final rotate =
        widget.names.length > 1 &&
        !prefersReducedMotion(context) &&
        TickerMode.valuesOf(context).enabled;
    if (!rotate) {
      _timer?.cancel();
      _timer = null;
      _index = 0;
    } else {
      _timer ??= Timer.periodic(const Duration(milliseconds: 2500), (_) {
        if (!mounted) return;
        setState(() => _index = (_index + 1) % widget.names.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.names.isEmpty) return const SizedBox.shrink();
    final name = widget.names[_index].trim();
    return AnimatedSwitcher(
      duration: adaptiveDuration(context, const Duration(milliseconds: 250)),
      layoutBuilder: (child, previous) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previous, ?child],
      ),
      child: Text(
        name.isEmpty
            ? AppLocalizations.of(context)!.commentSettingsAnonymousUser
            : name,
        key: ValueKey('rotating-name-$_index'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: widget.style,
      ),
    );
  }
}

class _MergedCommentCountTag extends StatelessWidget {
  const _MergedCommentCountTag({required this.count, required this.compact});

  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hot = count >= 10;
    const hotColor = AppStatusColors.hotAccent;
    final foreground = hot ? hotColor : cs.onPrimary;
    return Container(
      constraints: BoxConstraints(
        minWidth: hot ? (compact ? 34 : 40) : (compact ? 24 : 28),
        minHeight: compact ? 24 : 28,
      ),
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : AppSpacing.sm),
      decoration: BoxDecoration(
        color: hot
            ? Color.lerp(cs.surfaceContainerLow, hotColor, 0.08)
            : cs.primary,
        borderRadius: AppRadius.fullR,
        border: hot
            ? Border.all(color: hotColor.withValues(alpha: 0.58))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (hot) ...[
            Icon(
              Icons.local_fire_department_rounded,
              size: compact ? 14 : AppIconSize.sm,
              color: foreground,
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            '$count',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
