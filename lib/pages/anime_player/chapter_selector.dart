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
    return LayoutBuilder(
      builder: (context, constraints) {
        final cs = Theme.of(context).colorScheme;
        final brightness = Theme.of(context).brightness;
        const maxExtent = 120.0;
        final columns = (constraints.maxWidth / maxExtent).floor().clamp(1, constraints.maxWidth ~/ maxExtent);
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final chapter in chapters)
              SizedBox(
                width: (constraints.maxWidth - 6 * (columns - 1)) / columns,
                height: 52,
                child: _AnimeChapterCard(
                  chapter: chapter,
                  selected: chapter.uuid == currentChapterUuid,
                  brightness: brightness,
                  cs: cs,
                  onTap: () => onSelected(chapter),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AnimeChapterCard extends StatelessWidget {
  final AnimeChapter chapter;
  final bool selected;
  final Brightness brightness;
  final ColorScheme cs;
  final VoidCallback onTap;

  const _AnimeChapterCard({
    required this.chapter,
    required this.selected,
    required this.brightness,
    required this.cs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final backgroundColor = selected
        ? cs.primaryContainer
        : cs.surfaceContainerLow;
    final foregroundColor = selected
        ? cs.onPrimaryContainer
        : cs.onSurface;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected
              ? cs.primary
              : cs.outlineVariant.withValues(
                  alpha: brightness == Brightness.dark ? 0.22 : 0.45,
                ),
          width: selected ? 1.4 : 0.6,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: brightness == Brightness.dark ? 0.30 : 0.14,
            ),
            blurRadius: brightness == Brightness.dark ? 12 : 14,
            spreadRadius: brightness == Brightness.dark ? 0 : -1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                chapter.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: tt.bodySmall?.copyWith(
                  color: foregroundColor,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
