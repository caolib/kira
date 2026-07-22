import 'package:flutter/material.dart';

import '../models/theme_settings.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';

/// Shared clipped surface and shadow for manga cover cards.
class ComicCardSurface extends StatelessWidget {
  final Widget child;

  const ComicCardSurface({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final shadowStrength = ThemeSettings().comicCardShadowStrength;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadius.lgR,
        boxShadow: AppShadows.comicCard(colorScheme, strength: shadowStrength),
      ),
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: shadowStrength * 2,
        margin: EdgeInsets.zero,
        shadowColor: colorScheme.shadow.withValues(
          alpha: 0.28 * shadowStrength,
        ),
        child: child,
      ),
    );
  }
}
