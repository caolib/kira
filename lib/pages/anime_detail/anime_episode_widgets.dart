part of '../anime_detail_page.dart';

class _BoundAnimeChapterRow extends StatelessWidget {
  final AnimeChapter chapter;
  final bool selected;
  final bool selectionMode;
  final bool isDownloaded;
  final List<DandanplayBangumiEpisode> episodes;
  final int? selectedEpisodeId;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<int?> onEpisodeChanged;

  const _BoundAnimeChapterRow({
    required this.chapter,
    required this.selected,
    required this.selectionMode,
    required this.isDownloaded,
    required this.episodes,
    required this.selectedEpisodeId,
    required this.onTap,
    required this.onLongPress,
    required this.onEpisodeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final itemValues = <int?>[null, ...episodes.map((e) => e.episodeId)];
    final currentValue = itemValues.contains(selectedEpisodeId)
        ? selectedEpisodeId
        : null;

    return Material(
      color: selected
          ? cs.primaryContainer.withValues(alpha: 0.26)
          : cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? cs.primary : cs.outlineVariant,
          width: selected ? 1.4 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final dropdownWidth = (constraints.maxWidth * 0.46)
                  .clamp(180.0, 340.0)
                  .toDouble();
              return Row(
                children: [
                  Icon(
                    selectionMode
                        ? selected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked
                        : Icons.play_circle_outline_rounded,
                    color: selectionMode && selected
                        ? cs.primary
                        : cs.onSurfaceVariant,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            chapter.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (isDownloaded) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.download_done_rounded,
                            color: Colors.green.shade600,
                            size: 18,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: dropdownWidth,
                    child: DropdownButtonFormField<int?>(
                      initialValue: currentValue,
                      isExpanded: true,
                      menuMaxHeight: 360,
                      decoration: const InputDecoration(
                        labelText: '弹幕',
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(child: Text('未绑定')),
                        for (final episode in episodes)
                          DropdownMenuItem<int?>(
                            value: episode.episodeId,
                            child: Text(
                              _formatDandanplayEpisodeLabel(episode),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      selectedItemBuilder: (context) => [
                        const Text(
                          '未绑定',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        for (final episode in episodes)
                          Text(
                            _formatDandanplayEpisodeLabel(episode),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                      onChanged: episodes.isEmpty ? null : onEpisodeChanged,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AnimeChapterCard extends StatelessWidget {
  final AnimeChapter chapter;
  final bool selected;
  final bool selectionMode;
  final bool isDownloaded;
  final bool isDownloading;
  final bool isQueued;
  final AnimeChapterDownloadProgress? progress;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _AnimeChapterCard({
    required this.chapter,
    required this.selected,
    required this.selectionMode,
    required this.isDownloaded,
    required this.isDownloading,
    required this.isQueued,
    required this.progress,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final backgroundColor = selected
        ? cs.secondaryContainer
        : cs.surfaceContainerLow;
    final foregroundColor = selected ? cs.onSecondaryContainer : cs.onSurface;
    final subtitle = isDownloaded
        ? '已下载'
        : isDownloading && progress != null
        ? '下载 ${progress!.completed}/${progress!.total}'
        : isQueued
        ? '排队中'
        : null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? cs.primary : Colors.transparent,
          width: 1.4,
        ),
      ),
      child: Stack(
        children: [
          Material(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onTap,
              onLongPress: onLongPress,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        chapter.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: tt.bodySmall?.copyWith(
                          color: foregroundColor,
                          fontWeight: selected ? FontWeight.bold : null,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          style: tt.labelSmall?.copyWith(
                            color: selected
                                ? foregroundColor.withValues(alpha: 0.8)
                                : cs.onSurfaceVariant,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (selectionMode)
            Positioned(
              top: 4,
              right: 4,
              child: Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? cs.primary : cs.onSurfaceVariant,
                size: 16,
              ),
            )
          else if (isDownloaded)
            Positioned(
              top: 4,
              right: 4,
              child: Icon(
                Icons.download_done_rounded,
                color: Colors.green.shade600,
                size: 16,
              ),
            ),
          if (isDownloading && progress != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(10),
                ),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  value: progress!.ratio,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
