import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/comic.dart' hide Theme;
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/cover_brightness_filter.dart';
import '../utils/time_format.dart';
import '../widgets/comic_card_surface.dart';
import '../widgets/comic_hero_tags.dart';

/// Reusable comic card with cover image, title, popular count, and optional
/// update time. Used across home, search, bookshelf, category, etc.
class ComicCoverCard extends StatelessWidget {
  final Comic comic;
  final String? heroTagBase;
  final VoidCallback onTap;
  final double? width;
  final bool showPopular;
  final bool showUpdateTime;

  const ComicCoverCard({
    super.key,
    required this.comic,
    this.heroTagBase,
    required this.onTap,
    this.width,
    this.showPopular = true,
    this.showUpdateTime = true,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final metaStyle = tt.labelSmall?.copyWith(
      color: cs.onSurfaceVariant,
      fontSize: 12,
    );

    final semanticsParts = <String>[comic.name];
    if (showPopular) {
      semanticsParts.add(formatPopular(comic.popular, l10n));
    }
    if (showUpdateTime && comic.datetimeUpdated != null) {
      semanticsParts.add(TimeFormat.relativeOf(comic.datetimeUpdated!, l10n));
    }

    return Semantics(
      button: true,
      label: semanticsParts.join(', '),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.lgR,
          child: SizedBox(
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildHero(
                    ComicHeroTags.cover,
                    ComicCardSurface(
                      child: CoverBrightnessFilter(
                        child: CachedNetworkImage(
                          imageUrl: comic.cover,
                          fit: BoxFit.cover,
                          width: width ?? double.infinity,
                          height: double.infinity,
                          fadeInDuration: Duration.zero,
                          fadeOutDuration: Duration.zero,
                          placeholder: (_, _) => _imagePlaceholder(cs),
                          errorWidget: (_, _, _) => _imageError(cs),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  comic.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodySmall,
                ),
                const SizedBox(height: 2),
                if (showPopular || showUpdateTime)
                  Row(
                    children: [
                      if (showPopular) ...[
                        Icon(
                          Icons.local_fire_department,
                          size: 12,
                          color: cs.primary,
                        ),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            formatPopular(comic.popular, l10n),
                            overflow: TextOverflow.ellipsis,
                            style: metaStyle,
                          ),
                        ),
                      ],
                      if (showUpdateTime && comic.datetimeUpdated != null) ...[
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          TimeFormat.relativeOf(comic.datetimeUpdated!, l10n),
                          style: metaStyle,
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHero(String Function(String base) tagOf, Widget child) {
    final base = heroTagBase;
    if (base == null) return child;
    return Hero(
      tag: tagOf(base),
      createRectTween: ComicHeroTags.createRectTween,
      placeholderBuilder: (_, heroSize, _) =>
          SizedBox(width: heroSize.width, height: heroSize.height),
      child: child,
    );
  }

  static Widget _imagePlaceholder(ColorScheme cs) => Container(
    color: cs.surfaceContainerHighest,
    child: Center(
      child: Icon(Icons.image, color: cs.onSurfaceVariant, size: 32),
    ),
  );

  static Widget _imageError(ColorScheme cs) => Container(
    color: cs.surfaceContainerHighest,
    child: Center(
      child: Icon(Icons.broken_image, color: cs.onSurfaceVariant, size: 32),
    ),
  );

  static String formatPopular(int n, AppLocalizations l10n) {
    if (n >= 100000000) {
      return l10n.hundredMillionUnit((n / 100000000).toStringAsFixed(1));
    }
    if (n >= 10000) {
      return l10n.tenThousandUnit((n / 10000).toStringAsFixed(1));
    }
    return n.toString();
  }
}
