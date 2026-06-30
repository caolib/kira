import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/comic.dart' hide Theme;
import '../utils/comic_hero_tags.dart';
import '../utils/cover_brightness_filter.dart';
import '../utils/time_format.dart';

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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildHero(
                ComicHeroTags.cover,
                Card(
                  clipBehavior: Clip.antiAlias,
                  margin: EdgeInsets.zero,
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
                    Icon(Icons.local_fire_department, size: 12, color: cs.primary),
                    const SizedBox(width: 2),
                    Flexible(
                      child: Text(
                        formatPopular(comic.popular),
                        overflow: TextOverflow.ellipsis,
                        style: tt.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                  if (showUpdateTime && comic.datetimeUpdated != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      TimeFormat.relativeOf(comic.datetimeUpdated!),
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
          ],
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

  /// Format popular count to compact Chinese representation.
  static String formatPopular(int n) {
    if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}亿';
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    return n.toString();
  }
}
