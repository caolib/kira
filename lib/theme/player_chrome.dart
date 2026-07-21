import 'package:flutter/material.dart';

/// Immersive video-player chrome tokens.
///
/// The player, like the reader, keeps the canvas near-black so the video
/// frame is the only light source. These tokens replace the hard-coded
/// [Colors.black]/[Colors.white]/[Colors.black54]/[Colors.black87] values
/// that were scattered through the player controls. Every constant here is
/// the exact ARGB value of the Flutter color it replaces, so swapping them
/// in is visually neutral — it only removes magic colors and centralizes
/// the player's immersive palette.
@immutable
class PlayerChrome {
  const PlayerChrome._();

  /// Canvas / video-letterbox background (was [Colors.black]).
  static const Color surface = Color(0xFF000000);

  /// Primary icons and text on [surface] (was [Colors.white]).
  static const Color onSurface = Color(0xFFFFFFFF);

  /// Secondary icons, e.g. close button (was [Colors.white70]).
  static const Color onSurfaceMuted = Color(0xB3FFFFFF);

  /// Disabled icons / inactive slider track (was [Colors.white38]).
  static const Color onSurfaceFaint = Color(0x61FFFFFF);

  /// Inactive slider track (was [Colors.white38]; same value as
  /// [onSurfaceFaint] but named for its slider role).
  static const Color trackInactive = Color(0x61FFFFFF);

  /// Translucent scrim for hint bubbles & the play button background
  /// (was [Colors.black54]).
  static const Color scrim = Color(0x8A000000);

  /// Bottom of the top/bottom gradient overlays (was [Colors.black87]).
  static const Color gradientEnd = Color(0xDD000000);

  /// Playlist panel background (was `Color(0xE6121212)`).
  static const Color panelSurface = Color(0xE6121212);

  /// Playlist panel border (was `Colors.white.withValues(alpha: 0.12)`).
  static Color get borderStrong => onSurface.withValues(alpha: 0.12);

  /// Thin divider over artwork (was `Colors.white.withValues(alpha: 0.10)`).
  static Color get divider => onSurface.withValues(alpha: 0.10);

  /// Unselected chip fill (was `Colors.white.withValues(alpha: 0.08)`).
  static Color get fillFaint => onSurface.withValues(alpha: 0.08);

  /// Unselected chip border (was `Colors.white.withValues(alpha: 0.14)`).
  static Color get borderFaint => onSurface.withValues(alpha: 0.14);

  /// Playlist panel drop shadow (was `Colors.black.withValues(alpha: 0.45)`).
  static Color get panelShadow => surface.withValues(alpha: 0.45);

  // ── Radii specific to the player chrome ────────────────────────────

  /// Hint bubble radius (was `BorderRadius.circular(8)`).
  static const double radiusHint = 8;

  /// Playlist panel radius (was `BorderRadius.circular(14)`).
  static const double radiusPanel = 14;

  /// Chapter chip radius (was `BorderRadius.circular(10)`).
  static const double radiusChip = 10;

  static BorderRadius get hintR => BorderRadius.circular(radiusHint);
  static BorderRadius get panelR => BorderRadius.circular(radiusPanel);
  static BorderRadius get chipR => BorderRadius.circular(radiusChip);
}
