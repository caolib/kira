part of '../anime_detail_page.dart';

class _AnimeDetailHeader extends StatelessWidget {
  final _AnimeIntroViewData intro;
  final bool isCollected;

  const _AnimeDetailHeader({required this.intro, required this.isCollected});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: intro.cover,
          fit: BoxFit.cover,
          placeholder: (_, _) => Container(color: cs.surfaceContainerHighest),
          errorWidget: (_, _, _) => Container(
            color: cs.surfaceContainerHighest,
            child: Icon(Icons.broken_image, color: cs.onSurfaceVariant),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.10),
                Colors.black.withValues(alpha: 0.78),
              ],
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 18,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Card(
                clipBehavior: Clip.antiAlias,
                margin: EdgeInsets.zero,
                child: CoverBrightnessFilter(
                  child: CachedNetworkImage(
                    imageUrl: intro.cover,
                    width: 96,
                    height: 124,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      intro.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (intro.primaryStat != null)
                          _HeaderPill(
                            icon: intro.primaryStat!.icon,
                            text: intro.primaryStat!.text,
                          ),
                        if (intro.secondaryStat != null)
                          _HeaderPill(
                            icon: intro.secondaryStat!.icon,
                            text: intro.secondaryStat!.text,
                          ),
                        ...intro.headerMetadata.map(
                          (item) =>
                              _HeaderPill(icon: item.icon, text: item.text),
                        ),
                        if (isCollected)
                          _HeaderPill(
                            icon: Icons.bookmark,
                            text: l10n.animeDetailCollected,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FabLabel extends StatelessWidget {
  final String text;
  final double maxWidth;

  const _FabLabel({required this.text, required this.maxWidth});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
    );
  }
}

class _AnimeInfoPanel extends StatelessWidget {
  final _AnimeIntroViewData intro;
  final bool isCollected;
  final bool collectSubmitting;
  final bool briefExpanded;
  final String? refreshedAtText;
  final VoidCallback onToggleCollect;
  final VoidCallback onToggleBrief;

  const _AnimeInfoPanel({
    required this.intro,
    required this.isCollected,
    required this.collectSubmitting,
    required this.briefExpanded,
    required this.refreshedAtText,
    required this.onToggleCollect,
    required this.onToggleBrief,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final chips = <Widget>[...intro.chips.map((item) => _InfoChip(text: item))];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Wrap(spacing: 8, runSpacing: 8, children: chips)),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: collectSubmitting ? null : onToggleCollect,
              icon: Icon(isCollected ? Icons.bookmark : Icons.bookmark_border),
              label: Text(
                collectSubmitting
                    ? l10n.processingStatus
                    : (isCollected
                          ? l10n.animeDetailCollected
                          : l10n.collectButton),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (intro.metaLine != null && intro.metaLine!.isNotEmpty)
          Text(
            intro.metaLine!,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        if (intro.subMetaLine != null && intro.subMetaLine!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            intro.subMetaLine!,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
        if (refreshedAtText != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.update, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                l10n.refreshedAt(refreshedAtText!),
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ],
        if (intro.summary.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            l10n.animeDetailIntroTab,
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: onToggleBrief,
            child: Text(
              intro.summary,
              maxLines: briefExpanded ? null : 4,
              overflow: briefExpanded ? null : TextOverflow.ellipsis,
              style: tt.bodyMedium?.copyWith(height: 1.5),
            ),
          ),
        ],
        if (intro.extraInfoLines.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            l10n.animeDetailInfoTitle,
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          for (final line in intro.extraInfoLines.take(8)) ...[
            Text(
              line,
              style: tt.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 4),
          ],
        ],
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String text;

  const _InfoChip({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  final IconData icon;
  final String text;

  const _HeaderPill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
