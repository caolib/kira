import 'package:flutter/material.dart';

/// Unified spacing tokens.
///
/// Prefer these over hard-coded `SizedBox(height/width: N)` values so the
/// app's rhythm converges on a small 4-pt scale. Only the common values
/// (4/8/12/16/20/24) are tokenized; ad-hoc values (2/6/10/14/18/...) stay
/// literal where their specific size carries meaning.
@immutable
class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
}
