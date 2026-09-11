import 'package:flutter/material.dart';

class AppTypography {
  const AppTypography._();

  static TextScaler composeTextScaler(
    TextScaler platformTextScaler,
    double fontSizeFactor,
  ) {
    if (fontSizeFactor == 1) return platformTextScaler;
    return _AppTextScaler(platformTextScaler, fontSizeFactor);
  }

  /// Meta line under titles/inside cards: timestamps, counts, chapter names.
  ///
  /// Pages used to spell this as `labelSmall.copyWith(fontSize: 12)` in dozens
  /// of ad-hoc places; keep one source so the app's "small grey text" never
  /// drifts.
  static TextStyle? meta(TextTheme tt) => tt.labelSmall?.copyWith(fontSize: 12);

  /// Floating action button label — the two FAB sites used to disagree on
  /// weight and letter spacing.
  static TextStyle? fabLabel(TextTheme tt) =>
      tt.labelLarge?.copyWith(fontSize: 13, fontWeight: FontWeight.w600);
}

@immutable
class _AppTextScaler extends TextScaler {
  final TextScaler platformTextScaler;
  final double fontSizeFactor;

  const _AppTextScaler(this.platformTextScaler, this.fontSizeFactor)
    : assert(fontSizeFactor >= 0);

  @override
  double scale(double fontSize) =>
      platformTextScaler.scale(fontSize) * fontSizeFactor;

  @override
  double get textScaleFactor => scale(1);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _AppTextScaler &&
          other.platformTextScaler == platformTextScaler &&
          other.fontSizeFactor == fontSizeFactor;

  @override
  int get hashCode => Object.hash(platformTextScaler, fontSizeFactor);
}
