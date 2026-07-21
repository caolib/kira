import 'package:flutter/material.dart';

/// Soft elevation shadows used across cards and floating chrome.
///
/// Prefer these over hard-coded [Colors.black] opacities so light/dark weight
/// stays consistent.
@immutable
class AppShadows {
  const AppShadows._();

  static List<BoxShadow> sm(ColorScheme cs) => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.06),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
    BoxShadow(
      color: cs.shadow.withValues(alpha: 0.03),
      blurRadius: 3,
      offset: const Offset(0, 1),
    ),
  ];

  static List<BoxShadow> md(ColorScheme cs) => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.08),
      blurRadius: 18,
      offset: const Offset(0, 6),
    ),
    BoxShadow(
      color: cs.shadow.withValues(alpha: 0.04),
      blurRadius: 6,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> lg(ColorScheme cs) => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.12),
      blurRadius: 28,
      offset: const Offset(0, 10),
    ),
    BoxShadow(
      color: cs.shadow.withValues(alpha: 0.06),
      blurRadius: 10,
      offset: const Offset(0, 4),
    ),
  ];

  /// Navigation bar / toast floating elevation tint.
  static Color floatingTint([double alpha = 0.15]) =>
      Colors.black.withValues(alpha: alpha);
}
