import 'package:flutter/material.dart';

/// Unified icon-size tokens.
///
/// Icon sizes used to be scattered literals (12/14/16/18/20/22/24/32/40/48/64)
/// with 18 vs 20 for the same kind of affordance depending on the page. This
/// scale keeps one size per role; prefer these over raw numbers so icons of
/// the same role look identical app-wide.
@immutable
class AppIconSize {
  const AppIconSize._();

  /// Tiny inline markers (badge counts, flame-on-cover style glyphs).
  static const double xs = 12;

  /// Compact actions in dense rows.
  static const double sm = 16;

  /// Section-header icons and trailing chevrons.
  static const double md = 18;

  /// Standard secondary action icons (toolbar / list leading).
  static const double lg = 20;

  /// Primary actions — matches Material's default icon size.
  static const double xl = 24;

  /// Cover placeholder glyph inside image boxes.
  static const double placeholder = 32;

  /// Empty-state hero icon.
  static const double empty = 48;

  /// Large empty-state variant (full-page empties).
  static const double display = 64;
}
