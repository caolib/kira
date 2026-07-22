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
