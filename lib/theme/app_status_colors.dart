import 'package:flutter/material.dart';

/// Semantic status color tokens (success / warning / danger / neutral).
///
/// Material 3's [ColorScheme] has no success or warning role, so pages used to
/// hard-code [Colors.green] / [Colors.orange] for things like latency tiers —
/// values that ignore dark mode and drift from page to page. These tokens keep
/// the app's status vocabulary in one place and stay legible on both surfaces.
///
/// Use them only for state that genuinely carries a good/degraded/bad meaning;
/// for everything else prefer the plain [ColorScheme] roles.
@immutable
class AppStatusColors {
  const AppStatusColors._();

  static const Color _successLight = Color(0xFF2E7D32); // green 800
  static const Color _successDark = Color(0xFF81C784); // green 300
  static const Color _warningLight = Color(0xFFE65100); // orange 900
  static const Color _warningDark = Color(0xFFFFB74D); // orange 300

  static bool _isDark(ColorScheme cs) => cs.brightness == Brightness.dark;

  /// Healthy / connected / low latency.
  static Color success(ColorScheme cs) =>
      _isDark(cs) ? _successDark : _successLight;

  /// Degraded but usable — high latency, weak connection.
  static Color warning(ColorScheme cs) =>
      _isDark(cs) ? _warningDark : _warningLight;

  /// Failed / unreachable. Follows the scheme's error role.
  static Color danger(ColorScheme cs) => cs.error;

  /// Unknown / not measured yet.
  static Color neutral(ColorScheme cs) => cs.onSurfaceVariant;

  /// Tinted fill for pills and cards carrying a status color.
  static Color fill(Color base, {double alpha = 0.12}) =>
      base.withValues(alpha: alpha);
}
