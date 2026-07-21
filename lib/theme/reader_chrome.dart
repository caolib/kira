import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Immersive reader chrome tokens.
///
/// The reader intentionally stays on a near-black canvas so page art is the
/// only light source. These tokens keep chrome, icons, and loaders consistent
/// without scattering hard-coded [Colors.black]/[Colors.white].
@immutable
class ReaderChrome {
  const ReaderChrome._();

  /// Canvas / toolbar / chapter bridge background.
  static const Color surface = Color(0xFF000000);

  /// Primary text and icons on [surface].
  static const Color onSurface = Color(0xFFFFFFFF);

  /// Secondary text (≈ white70).
  static const Color onSurfaceMuted = Color(0xB3FFFFFF);

  /// Hint / disabled text (≈ white54).
  static const Color onSurfaceSubtle = Color(0x8AFFFFFF);

  /// Disabled icons (≈ white38).
  static const Color onSurfaceFaint = Color(0x61FFFFFF);

  /// Inactive slider track / tick (≈ white24).
  static const Color trackInactive = Color(0x3DFFFFFF);

  /// Semi-transparent control chip over artwork.
  static const Color controlScrim = Color(0x6B000000);

  /// Pull-to-refresh indicator disc.
  static const Color indicatorScrim = Color(0xB8000000);

  /// Outlined chapter-action fill.
  static Color get actionFill => onSurface.withValues(alpha: 0.08);

  /// Outlined chapter-action border.
  static Color get actionBorder => onSurface.withValues(alpha: 0.28);

  /// Primary chapter-action fill.
  static Color get actionPrimaryFill => onSurface.withValues(alpha: 0.18);

  /// Dim overlay for night-mode reading.
  static Color dimOverlay(double alpha) =>
      surface.withValues(alpha: alpha.clamp(0.0, 1.0));

  static const SystemUiOverlayStyle systemUiToolbar = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: surface,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  static const SystemUiOverlayStyle systemUiImmersive = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  static ButtonStyle get outlinedActionStyle => OutlinedButton.styleFrom(
    foregroundColor: onSurface,
    side: BorderSide(color: actionBorder),
    backgroundColor: actionFill,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  );

  static ButtonStyle get filledActionStyle => FilledButton.styleFrom(
    foregroundColor: onSurface,
    backgroundColor: actionPrimaryFill,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  );
}
