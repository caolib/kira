part of '../comic_comments_sheet.dart';

const _mergedCardCornerRadius = 10.0;
const _hotMergedCommentColor = AppStatusColors.hotAccent;

Color _comicCommentCardColor(ColorScheme cs) => cs.surfaceContainerHigh;
Color _comicCommentCardInsetColor(ColorScheme cs) => cs.surfaceContainerHighest;
bool _isHotMergedComment(int count) => count >= 10;

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

/// 漫画正文保留展开组件，合并头像/用户名/人数使用共享展示。
class _ComicMergedCommentContent extends StatelessWidget {
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

  final ComicCommentDisplayEntry entry;
  final bool compact;
  final double contentSpacing;
  final TextStyle? bodyStyle;
  final TextStyle? userStyle;
  final bool showAvatar;
  final bool showUserName;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) => MergedCommentContent(
    count: entry.count,
    names: entry.userNames(),
    avatars: [
      for (final comment in entry.avatarComments())
        _ComicCommentAvatar(
          imageUrl: comment.userAvatar,
          size: compact ? 19 : 22,
        ),
    ],
    compact: compact,
    contentSpacing: contentSpacing,
    userStyle: userStyle,
    showAvatar: showAvatar,
    showUserName: showUserName,
    body: ExpandableCommentText(
      text: entry.content,
      style: bodyStyle,
      backgroundColor: backgroundColor,
    ),
  );
}
