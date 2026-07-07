part of '../anime_player_page.dart';

class _ChapterSelector extends StatelessWidget {
  final List<AnimeChapter> chapters;
  final String currentChapterUuid;
  final ValueChanged<AnimeChapter> onSelected;

  const _ChapterSelector({
    required this.chapters,
    required this.currentChapterUuid,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _CollapsiblePlayerCard(
      icon: Icons.video_library_outlined,
      title: l10n.animePlayerChapterSelectorWithCount(chapters.length),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final chapter in chapters)
            _ChapterButton(
              chapter: chapter,
              selected: chapter.uuid == currentChapterUuid,
              onTap: () => onSelected(chapter),
            ),
        ],
      ),
    );
  }
}

class _ChapterButton extends StatelessWidget {
  final AnimeChapter chapter;
  final bool selected;
  final VoidCallback onTap;

  const _ChapterButton({
    required this.chapter,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 88, maxWidth: 180),
      child: Material(
        color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Text(
              chapter.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                height: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
