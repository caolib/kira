part of '../bookshelf_page.dart';

class _UpdateBadge extends StatelessWidget {
  const _UpdateBadge();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: const BoxDecoration(
          color: Color(0xFFBA1A1A),
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(12),
            bottomLeft: Radius.circular(10),
          ),
        ),
        child: Text(
          AppLocalizations.of(context)!.updateBadge,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _AnimeBookshelfCard extends StatelessWidget {
  final Anime anime;
  final VoidCallback onTap;

  const _AnimeBookshelfCard({required this.anime, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final meta = anime.count > 0
        ? AppLocalizations.of(context)!.totalEpisodes(anime.count)
        : (anime.company?.name ?? anime.years ?? '');

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              margin: EdgeInsets.zero,
              child: CoverBrightnessFilter(
                child: CachedNetworkImage(
                  imageUrl: anime.cover,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  placeholder: (_, _) => _ImagePlaceholder(
                    icon: Icons.movie_outlined,
                    color: cs.surfaceContainerHighest,
                    iconColor: cs.onSurfaceVariant,
                  ),
                  errorWidget: (_, _, _) => _ImagePlaceholder(
                    icon: Icons.broken_image,
                    color: cs.surfaceContainerHighest,
                    iconColor: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            anime.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tt.bodySmall,
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.local_fire_department, size: 12, color: cs.primary),
              const SizedBox(width: 2),
              Text(
                ComicCard.formatPopular(
                  anime.popular,
                  AppLocalizations.of(context)!,
                ),
                style: tt.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color iconColor;

  const _ImagePlaceholder({
    required this.icon,
    required this.color,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: color,
      child: Center(child: Icon(icon, color: iconColor, size: 32)),
    );
  }
}

class _OrderingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _OrderingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: selected ? cs.primary : null),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: selected ? Icon(Icons.check, color: cs.primary) : null,
      selected: selected,
      onTap: onTap,
    );
  }
}
