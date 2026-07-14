part of '../chapter_comments_sheet.dart';

double _measureTextWidth(
  String text,
  TextStyle? style,
  TextScaler textScaler,
  double maxWidth,
) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
    maxLines: 1,
  )..layout(maxWidth: maxWidth);
  return painter.size.width;
}

double _estimateMergedCountTagWidth(
  BuildContext context,
  int count,
  double maxWidth, {
  required bool compact,
}) {
  final textTheme = Theme.of(context).textTheme;
  final textScaler = MediaQuery.textScalerOf(context);
  final isHot = _isHotMergedComment(count);
  final label = _formatMergedCount(count);
  final labelWidth = _measureTextWidth(
    label,
    textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
    textScaler,
    maxWidth,
  );
  final minWidth = _mergedCountTagMinWidth(compact: compact, isHot: isHot);
  final horizontalPadding = _mergedCountTagHorizontalPadding(compact: compact);
  final iconWidth = isHot ? _hotCommentTagIconSize(compact: compact) + 4 : 0.0;
  final intrinsicWidth = labelWidth + horizontalPadding + iconWidth;
  return intrinsicWidth < minWidth ? minWidth : intrinsicWidth;
}

String _formatMergedCount(int count) => '$count';

bool _shouldShowMergedCountTag(int count) => count > 1;

bool _isHotMergedComment(int count) => count >= 10;

const _commentCardCornerRadius = 10.0;

const _hotCommentAccentColor = Color(0xFFFF7A2F);

double _hotCommentTagIconSize({required bool compact}) => compact ? 14.0 : 16.0;

double _mergedCountTagHeight({required bool compact}) => compact ? 24.0 : 28.0;

double _mergedCountTagMinWidth({required bool compact, required bool isHot}) {
  if (!isHot) return compact ? 24.0 : 28.0;
  return compact ? 34.0 : 40.0;
}

double _mergedCountTagHorizontalPadding({required bool compact}) =>
    compact ? 12.0 : 16.0;

_MergedCountTagColors _mergedCountTagColors(
  ColorScheme colorScheme, {
  required bool isHot,
}) {
  if (!isHot) {
    return _MergedCountTagColors(foreground: colorScheme.onPrimary);
  }
  return const _MergedCountTagColors(foreground: _hotCommentAccentColor);
}

BoxDecoration _buildMergedCountTagDecoration(
  ColorScheme colorScheme, {
  required bool isHot,
}) {
  if (!isHot) {
    return BoxDecoration(
      color: colorScheme.primary,
      borderRadius: BorderRadius.circular(999),
    );
  }

  return BoxDecoration(
    color: Color.lerp(
      colorScheme.surfaceContainerLow,
      _hotCommentAccentColor,
      0.08,
    ),
    borderRadius: BorderRadius.circular(999),
    border: Border.all(color: _hotCommentAccentColor.withValues(alpha: 0.58)),
  );
}

BoxDecoration _buildCommentCardDecoration(
  ColorScheme colorScheme, {
  required Brightness brightness,
  required bool highlightAsHot,
}) {
  final borderRadius = BorderRadius.circular(_commentCardCornerRadius);
  final shadows = _buildCommentCardShadows(
    brightness,
    highlightAsHot: highlightAsHot,
  );
  if (!highlightAsHot) {
    return BoxDecoration(
      color: colorScheme.surfaceContainerLow,
      borderRadius: borderRadius,
      border: Border.all(
        color: colorScheme.outlineVariant.withValues(
          alpha: brightness == Brightness.dark ? 0.22 : 0.45,
        ),
        width: 0.6,
      ),
      boxShadow: shadows,
    );
  }

  final surface = colorScheme.surfaceContainerLow;
  return BoxDecoration(
    color: surface,
    borderRadius: borderRadius,
    border: Border.all(
      color: _hotCommentAccentColor.withValues(
        alpha: brightness == Brightness.dark ? 0.48 : 0.56,
      ),
    ),
    boxShadow: shadows,
  );
}

List<BoxShadow> _buildCommentCardShadows(
  Brightness brightness, {
  required bool highlightAsHot,
}) {
  final baseShadowAlpha = brightness == Brightness.dark ? 0.30 : 0.14;
  final shadows = <BoxShadow>[
    BoxShadow(
      color: Colors.black.withValues(alpha: baseShadowAlpha),
      blurRadius: brightness == Brightness.dark ? 12 : 14,
      spreadRadius: brightness == Brightness.dark ? 0 : -1,
      offset: const Offset(0, 4),
    ),
  ];

  if (highlightAsHot) {
    shadows.add(
      BoxShadow(
        color: _hotCommentAccentColor.withValues(
          alpha: brightness == Brightness.dark ? 0.20 : 0.16,
        ),
        blurRadius: 16,
        spreadRadius: -2,
        offset: const Offset(0, 4),
      ),
    );
  }

  return shadows;
}

TextStyle? _buildCommentUserStyle(
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

TextStyle? _buildCommentTimeStyle(
  TextTheme textTheme,
  ColorScheme colorScheme,
) {
  return textTheme.labelSmall?.copyWith(
    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
    fontWeight: FontWeight.w400,
  );
}

TextStyle? buildCommentBodyStyle(
  TextTheme textTheme, {
  required bool compact,
  required double fontScale,
}) {
  final baseStyle = compact
      ? textTheme.bodyMedium
      : (textTheme.bodyLarge ?? textTheme.bodyMedium);
  final defaultFontSize = _defaultCommentFontSizePx(
    textTheme,
    compact: compact,
  );

  return baseStyle?.copyWith(
        fontSize: defaultFontSize * fontScale,
        height: compact ? 1.35 : 1.55,
        fontWeight: FontWeight.w500,
      ) ??
      TextStyle(
        fontSize: defaultFontSize * fontScale,
        height: compact ? 1.35 : 1.55,
        fontWeight: FontWeight.w500,
      );
}

double _defaultCommentFontSizePx(TextTheme textTheme, {required bool compact}) {
  final baseStyle = compact
      ? textTheme.bodyMedium
      : (textTheme.bodyLarge ?? textTheme.bodyMedium);
  final fontSize = baseStyle?.fontSize;
  return fontSize != null && fontSize >= 16 ? fontSize : 16.0;
}

double _commentFontMinPx(double defaultFontSizePx) {
  final minPx = defaultFontSizePx - 5;
  return minPx < 10 ? 10 : minPx;
}

double _commentFontMaxPx(double defaultFontSizePx) => defaultFontSizePx + 14;

double _commentFontScaleToPx(double defaultFontSizePx, double scale) =>
    defaultFontSizePx * scale;

double _commentFontPxToScale(double defaultFontSizePx, double fontSizePx) =>
    fontSizePx / defaultFontSizePx;

double _avatarStackWidth(
  int count, {
  required double avatarSize,
  required double overlap,
}) {
  if (count <= 0) return avatarSize;
  return avatarSize + (count - 1) * (avatarSize - overlap);
}

double _avatarInset(double avatarSize) => avatarSize <= 22 ? 1.5 : 2;
