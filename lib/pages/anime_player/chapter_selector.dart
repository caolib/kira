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
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: chapters.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 100,
        mainAxisExtent: 40,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemBuilder: (context, index) {
        final chapter = chapters[index];
        return _AnimeChapterCard(
          chapter: chapter,
          selected: chapter.uuid == currentChapterUuid,
          onTap: () => onSelected(chapter),
        );
      },
    );
  }
}

class _AnimeChapterCard extends StatelessWidget {
  final AnimeChapter chapter;
  final bool selected;
  final VoidCallback onTap;

  const _AnimeChapterCard({
    required this.chapter,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final brightness = Theme.of(context).brightness;
    final backgroundColor = selected
        ? cs.primaryContainer
        : cs.surfaceContainerLow;
    final foregroundColor = selected ? cs.onPrimaryContainer : cs.onSurface;

    // 与漫画详情章节卡同构：圆角 + 细边框 + 轻阴影
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
            color: cs.shadow.withValues(
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
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                chapter.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: tt.labelMedium?.copyWith(
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
