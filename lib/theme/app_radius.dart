import 'package:flutter/material.dart';

/// Unified corner-radius tokens.
///
/// Prefer these over hard-coded [BorderRadius.circular] values so the app's
/// rounded shapes converge on a small, intentional scale instead of the
/// dozen ad-hoc radii (2/3/4/6/8/10/12/14/16/18/20/999) scattered across
/// pages. Values are chosen to match the most common existing radii so
/// adopting them is visually neutral.
@immutable
class AppRadius {
  const AppRadius._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double full = 999;

  static BorderRadius get xsR => BorderRadius.circular(xs);
  static BorderRadius get smR => BorderRadius.circular(sm);
  static BorderRadius get mdR => BorderRadius.circular(md);
  static BorderRadius get lgR => BorderRadius.circular(lg);
  static BorderRadius get xlR => BorderRadius.circular(xl);
  static BorderRadius get fullR => BorderRadius.circular(full);
}
