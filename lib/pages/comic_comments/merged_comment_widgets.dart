part of '../comic_comments_sheet.dart';

// ─── 合并评论样式常量 & 纯函数（与 chapter_comments/comment_style.dart 对齐） ───

const _mergedCardCornerRadius = 10.0;
const _hotMergedCommentColor = AppStatusColors.hotAccent;

/// 评论卡片底色（与 chapter_comments/comment_style.dart 同款）。评论区容器是
/// [ColorScheme.surfaceContainerLow]，卡片用 [ColorScheme.surfaceContainerHigh]
/// 高两档，亮暗都靠同一令牌拉开层次。
Color _comicCommentCardColor(ColorScheme cs) => cs.surfaceContainerHigh;

/// 卡片内部的次级色块（头像底衬、图片占位等）：再亮一档。
Color _comicCommentCardInsetColor(ColorScheme cs) => cs.surfaceContainerHighest;

bool _shouldShowMergedCountTag(int count) => count > 1;
bool _isHotMergedComment(int count) => count >= 10;
String _formatMergedCount(int count) => '$count';

double _hotMergedTagIconSize({required bool compact}) => compact ? 14.0 : 16.0;
double _mergedCountTagHeight({required bool compact}) => compact ? 24.0 : 28.0;
double _mergedCountTagMinWidth({required bool compact, required bool isHot}) {
  if (!isHot) return compact ? 24.0 : 28.0;
  return compact ? 34.0 : 40.0;
}

double _mergedCountTagHorizontalPadding({required bool compact}) =>
    compact ? 12.0 : 16.0;

class _MergedCountTagColors {
  final Color foreground;
  const _MergedCountTagColors({required this.foreground});
}

_MergedCountTagColors _mergedCountTagColors(
  ColorScheme colorScheme, {
  required bool isHot,
}) {
  if (!isHot) {
    return _MergedCountTagColors(foreground: colorScheme.onPrimary);
  }
  return const _MergedCountTagColors(foreground: _hotMergedCommentColor);
}

BoxDecoration _buildMergedCountTagDecoration(
  ColorScheme colorScheme, {
  required bool isHot,
}) {
  if (!isHot) {
    return BoxDecoration(
      color: colorScheme.primary,
      borderRadius: AppRadius.fullR,
    );
  }

  return BoxDecoration(
    color: Color.lerp(
      colorScheme.surfaceContainerLow,
      _hotMergedCommentColor,
      0.08,
    ),
    borderRadius: AppRadius.fullR,
    border: Border.all(color: _hotMergedCommentColor.withValues(alpha: 0.58)),
  );
}

BoxDecoration _buildMergedCommentCardDecoration(
  ColorScheme colorScheme, {
  required bool highlightAsHot,
  bool withShadow = true,
  Color? backgroundColor,
}) {
  final borderRadius = BorderRadius.circular(_mergedCardCornerRadius);
  final shadows = withShadow
      ? _buildMergedCommentCardShadows(highlightAsHot: highlightAsHot)
      : null;
  final surface = backgroundColor ?? _comicCommentCardColor(colorScheme);
  if (!highlightAsHot) {
    return BoxDecoration(
      color: surface,
      borderRadius: borderRadius,
      border: Border.all(
        color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        width: 0.8,
      ),
      boxShadow: shadows,
    );
  }

  return BoxDecoration(
    color: surface,
    borderRadius: borderRadius,
    border: Border.all(color: _hotMergedCommentColor.withValues(alpha: 0.56)),
    boxShadow: shadows,
  );
}

List<BoxShadow> _buildMergedCommentCardShadows({required bool highlightAsHot}) {
  final shadows = <BoxShadow>[
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.14),
      blurRadius: 14,
      spreadRadius: -1,
      offset: const Offset(0, 4),
    ),
  ];

  if (highlightAsHot) {
    shadows.add(
      BoxShadow(
        color: _hotMergedCommentColor.withValues(alpha: 0.16),
        blurRadius: 16,
        spreadRadius: -2,
        offset: const Offset(0, 4),
      ),
    );
  }

  return shadows;
}

TextStyle? _buildMergedCommentUserStyle(
  TextTheme textTheme,
  ColorScheme colorScheme, {
  required bool compact,
}) {
  final metaColor = colorScheme.onSurfaceVariant.withValues(
    alpha: compact ? 0.72 : 0.78,
  );
  return (compact ? textTheme.labelSmall : textTheme.labelMedium)?.copyWith(
    color: metaColor,
    fontWeight: FontWeight.w500,
  );
}

double _avatarStackWidth(
  int count, {
  required double avatarSize,
  required double overlap,
}) {
  if (count <= 0) return avatarSize;
  return avatarSize + (count - 1) * (avatarSize - overlap);
}

double _avatarInset(double avatarSize) => avatarSize <= 22 ? 1.5 : 2;

// ─── 合并评论显示组件 ───

/// 合并评论的内容区：头像叠放 + 用户名轮播 + 人数标签 + 正文。
class _ComicMergedCommentContent extends StatelessWidget {
  final ComicCommentDisplayEntry entry;
  final bool compact;
  final double contentSpacing;
  final TextStyle? bodyStyle;
  final TextStyle? userStyle;
  final bool showAvatar;
  final bool showUserName;
  final Color backgroundColor;

  const _ComicMergedCommentContent({
    required this.entry,
    required this.compact,
    required this.contentSpacing,
    required this.bodyStyle,
    this.userStyle,
    this.showAvatar = true,
    this.showUserName = true,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final showCountTag = _shouldShowMergedCountTag(entry.count);
    final rotatingName = (showUserName && entry.isMerged)
        ? _ComicRotatingUserName(
            names: entry.userNames(),
            style: userStyle,
            compact: compact,
          )
        : null;

    if (!showAvatar) {
      if (!showCountTag) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (rotatingName != null) ...[
              rotatingName,
              SizedBox(height: compact ? 4 : 6),
            ],
            _ExpandableCommentText(
              text: entry.content,
              style: bodyStyle,
              backgroundColor: backgroundColor,
            ),
          ],
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (rotatingName != null)
                Expanded(child: rotatingName)
              else
                const Spacer(),
              SizedBox(width: compact ? 6 : AppSpacing.sm),
              _ComicMergedCommentCountTag(count: entry.count, compact: compact),
            ],
          ),
          SizedBox(height: compact ? 4 : 6),
          _ExpandableCommentText(
            text: entry.content,
            style: bodyStyle,
            backgroundColor: backgroundColor,
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ComicCommentAvatarStack(
              comments: entry.avatarComments(),
              avatarSize: compact ? 22.0 : 26.0,
              overlap: compact ? 8.0 : 10.0,
            ),
            if (rotatingName != null) ...[
              SizedBox(width: compact ? 6 : 8),
              Expanded(child: rotatingName),
            ],
            const Spacer(),
            if (showCountTag) ...[
              const SizedBox(width: AppSpacing.sm),
              _ComicMergedCommentCountTag(count: entry.count, compact: compact),
            ],
          ],
        ),
        SizedBox(height: contentSpacing + (compact ? 1 : 2)),
        _ExpandableCommentText(
          text: entry.content,
          style: bodyStyle,
          backgroundColor: backgroundColor,
        ),
      ],
    );
  }
}

/// 合并评论的用户名轮播：定时淡入淡出切换显示不同的发表者名称。
class _ComicRotatingUserName extends StatefulWidget {
  final List<String> names;
  final TextStyle? style;
  final bool compact;

  const _ComicRotatingUserName({
    required this.names,
    this.style,
    this.compact = false,
  });

  @override
  State<_ComicRotatingUserName> createState() => _ComicRotatingUserNameState();
}

class _ComicRotatingUserNameState extends State<_ComicRotatingUserName> {
  late final Timer _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    if (widget.names.length > 1) {
      _timer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
        if (!mounted) return;
        setState(() {
          _index = (_index + 1) % widget.names.length;
        });
      });
    }
  }

  @override
  void dispose() {
    if (widget.names.length > 1) {
      _timer.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final names = widget.names;
    if (names.isEmpty) return const SizedBox.shrink();

    final displayName = names[_index].trim().isEmpty
        ? l10n.commentSettingsAnonymousUser
        : names[_index];

    final textScaler = MediaQuery.textScalerOf(context);
    final painter = TextPainter(
      text: TextSpan(text: displayName, style: widget.style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    final lineHeight = painter.size.height;
    painter.dispose();

    return ClipRect(
      child: SizedBox(
        width: double.infinity,
        height: lineHeight,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 360),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeIn,
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.centerLeft,
            children: <Widget>[...previousChildren, ?currentChild],
          ),
          transitionBuilder: (child, animation) {
            final key = child.key as ValueKey<String>;
            final isNew = key.value == 'rotating-name-$_index';
            final offsetTween = isNew
                ? Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
                : Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero);
            return SlideTransition(
              position: offsetTween.animate(animation),
              child: child,
            );
          },
          child: Text(
            displayName,
            key: ValueKey('rotating-name-$_index'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: widget.style,
          ),
        ),
      ),
    );
  }
}

class _ComicMergedCommentCountTag extends StatelessWidget {
  final int count;
  final bool compact;

  const _ComicMergedCommentCountTag({
    required this.count,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isHot = _isHotMergedComment(count);
    final tagHeight = _mergedCountTagHeight(compact: compact);
    final minWidth = _mergedCountTagMinWidth(compact: compact, isHot: isHot);
    final horizontalPadding = _mergedCountTagHorizontalPadding(
      compact: compact,
    );
    final colors = _mergedCountTagColors(cs, isHot: isHot);
    final decoration = _buildMergedCountTagDecoration(cs, isHot: isHot);
    final label = _formatMergedCount(count);
    final iconSize = _hotMergedTagIconSize(compact: compact);

    return Container(
      constraints: BoxConstraints(minWidth: minWidth, minHeight: tagHeight),
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding / 2),
      decoration: decoration,
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isHot) ...[
              Icon(
                Icons.local_fire_department_rounded,
                size: iconSize,
                color: colors.foreground,
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            Text(
              label,
              textAlign: TextAlign.center,
              textHeightBehavior: const TextHeightBehavior(
                applyHeightToFirstAscent: false,
                applyHeightToLastDescent: false,
              ),
              strutStyle: const StrutStyle(height: 1, forceStrutHeight: true),
              style: tt.labelSmall?.copyWith(
                color: colors.foreground,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComicCommentAvatarStack extends StatelessWidget {
  final List<ComicComment> comments;
  final double avatarSize;
  final double overlap;

  const _ComicCommentAvatarStack({
    required this.comments,
    required this.avatarSize,
    required this.overlap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = comments.isEmpty
        ? const <ComicComment>[]
        : comments.take(5).toList(growable: false);

    if (items.isEmpty) {
      return _ComicCommentAvatar(imageUrl: '', size: avatarSize);
    }

    final width = _avatarStackWidth(
      items.length,
      avatarSize: avatarSize,
      overlap: overlap,
    );
    final inset = _avatarInset(avatarSize);

    return SizedBox(
      width: width,
      height: avatarSize,
      child: Stack(
        children: [
          for (var i = 0; i < items.length; i++)
            Positioned(
              left: i * (avatarSize - overlap),
              child: Container(
                width: avatarSize,
                height: avatarSize,
                padding: EdgeInsets.all(inset),
                decoration: BoxDecoration(
                  color: _comicCommentCardColor(cs),
                  shape: BoxShape.circle,
                ),
                child: _ComicCommentAvatar(
                  imageUrl: items[i].userAvatar,
                  size: avatarSize - inset * 2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
