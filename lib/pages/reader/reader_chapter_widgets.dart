part of '../reader_page.dart';

/// Shared button style for chapter divider action buttons.
final _chapterActionButtonStyle = OutlinedButton.styleFrom(
  foregroundColor: Colors.white,
  side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
  backgroundColor: Colors.white.withValues(alpha: 0.08),
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
);

/// Shared primary button style for "next chapter" actions.
final _chapterPrimaryButtonStyle = FilledButton.styleFrom(
  foregroundColor: Colors.white,
  backgroundColor: Colors.white.withValues(alpha: 0.18),
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
);

/// Action buttons shown in chapter dividers: catalog and comments.
class _ChapterDividerActions extends StatelessWidget {
  final int commentCount;
  final VoidCallback onCatalog;
  final VoidCallback onComments;

  const _ChapterDividerActions({
    required this.commentCount,
    required this.onCatalog,
    required this.onComments,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: onCatalog,
          icon: const Icon(Icons.list),
          label: Text(l10n.chapterCommentsCatalog),
          style: _chapterActionButtonStyle,
        ),
        OutlinedButton.icon(
          onPressed: onComments,
          icon: const Icon(Icons.forum_outlined),
          label: Text(
            commentCount > 0 ? '$commentCount' : l10n.chapterCommentsComment,
          ),
          style: _chapterActionButtonStyle,
        ),
      ],
    );
  }
}

/// Divider shown between chained chapters in continuous scroll mode.
class _ChapterDivider extends StatelessWidget {
  final int commentCount;
  final bool isHorizontalScroll;
  final double tailExtent;
  final VoidCallback onCatalog;
  final VoidCallback onComments;

  const _ChapterDivider({
    required this.commentCount,
    required this.isHorizontalScroll,
    required this.tailExtent,
    required this.onCatalog,
    required this.onComments,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ChapterDividerActions(
            commentCount: commentCount,
            onCatalog: onCatalog,
            onComments: onComments,
          ),
        ],
      ),
    );
    if (isHorizontalScroll) {
      return SizedBox(width: tailExtent, child: content);
    }
    return ColoredBox(color: Colors.black, child: content);
  }
}

/// "Load more" tail shown at the end of continuous scroll when next chapter exists.
class _LoadMoreTail extends StatelessWidget {
  final bool isLoading;
  final bool isHorizontalScroll;
  final double tailExtent;
  final int commentCount;
  final VoidCallback onCatalog;
  final VoidCallback onComments;

  const _LoadMoreTail({
    required this.isLoading,
    required this.isHorizontalScroll,
    required this.tailExtent,
    required this.commentCount,
    required this.onCatalog,
    required this.onComments,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ChapterDividerActions(
              commentCount: commentCount,
              onCatalog: onCatalog,
              onComments: onComments,
            ),
            const SizedBox(height: 16),
            if (isLoading)
              const CircularProgressIndicator(strokeWidth: 2)
            else
              Icon(Icons.expand_more, color: cs.onSurfaceVariant, size: 32),
            const SizedBox(height: 8),
            Text(
              isLoading
                  ? l10n.readerLoadingNextChapter
                  : l10n.readerContinueScrollLoadNext,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
      ),
    );
    return ColoredBox(
      color: Colors.black,
      child: SizedBox(
        width: isHorizontalScroll ? tailExtent : null,
        height: isHorizontalScroll ? null : tailExtent * 0.6,
        child: Align(alignment: Alignment.topCenter, child: content),
      ),
    );
  }
}

/// "First chapter" header shown when there is no previous chapter.
class _FirstChapterHead extends StatelessWidget {
  final bool isHorizontalScroll;
  final double tailExtent;

  const _FirstChapterHead({
    required this.isHorizontalScroll,
    required this.tailExtent,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final message = Center(
      child: Text(
        l10n.readerAlreadyFirstChapter,
        style: const TextStyle(color: Colors.white54, fontSize: 14),
      ),
    );

    if (isHorizontalScroll) {
      return SizedBox(
        width: tailExtent,
        child: Padding(padding: const EdgeInsets.all(32), child: message),
      );
    }

    return Padding(padding: const EdgeInsets.all(32), child: message);
  }
}

/// End-of-chapter action row: catalog, comments, and optional next chapter.
class _ChapterEndActionsRow extends StatelessWidget {
  final bool hasNext;
  final int commentCount;
  final VoidCallback onCatalog;
  final VoidCallback onComments;
  final VoidCallback? onNextChapter;

  const _ChapterEndActionsRow({
    required this.hasNext,
    required this.commentCount,
    required this.onCatalog,
    required this.onComments,
    this.onNextChapter,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: onCatalog,
          icon: const Icon(Icons.list),
          label: Text(l10n.chapterCommentsCatalog),
          style: _chapterActionButtonStyle,
        ),
        OutlinedButton.icon(
          onPressed: onComments,
          icon: const Icon(Icons.forum_outlined),
          label: Text(
            commentCount > 0 ? '$commentCount' : l10n.chapterCommentsComment,
          ),
          style: _chapterActionButtonStyle,
        ),
        if (hasNext)
          FilledButton.icon(
            onPressed: onNextChapter,
            icon: const Icon(Icons.skip_next),
            label: Text(l10n.chapterCommentsNext),
            style: _chapterPrimaryButtonStyle,
          ),
      ],
    );
  }
}

/// End-of-chapter actions for page mode (with SafeArea and hint text).
class _PageModeEndActions extends StatelessWidget {
  final bool hasNext;
  final int commentCount;
  final VoidCallback onCatalog;
  final VoidCallback onComments;
  final VoidCallback? onNextChapter;

  const _PageModeEndActions({
    required this.hasNext,
    required this.commentCount,
    required this.onCatalog,
    required this.onComments,
    this.onNextChapter,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 12, 32, 16),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ChapterEndActionsRow(
                  hasNext: hasNext,
                  commentCount: commentCount,
                  onCatalog: onCatalog,
                  onComments: onComments,
                  onNextChapter: onNextChapter,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    hasNext
                        ? l10n.readerContinuePageNextChapter
                        : l10n.readerAlreadyLastChapter,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tail shown at the end of scroll mode when there is no next chapter.
class _NextChapterTail extends StatelessWidget {
  final bool hasNext;
  final bool isHorizontalScroll;
  final double tailExtent;
  final int commentCount;
  final VoidCallback onCatalog;
  final VoidCallback onComments;
  final VoidCallback? onNextChapter;

  const _NextChapterTail({
    required this.hasNext,
    required this.isHorizontalScroll,
    required this.tailExtent,
    required this.commentCount,
    required this.onCatalog,
    required this.onComments,
    this.onNextChapter,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(32, 72, 32, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            hasNext
                ? l10n.readerContinueScrollOrTapNextChapter
                : l10n.readerAlreadyLastChapter,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
              height: 1.6,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          _ChapterEndActionsRow(
            hasNext: hasNext,
            commentCount: commentCount,
            onCatalog: onCatalog,
            onComments: onComments,
            onNextChapter: onNextChapter,
          ),
        ],
      ),
    );

    return ColoredBox(
      color: Colors.black,
      child: SizedBox(
        width: isHorizontalScroll ? tailExtent : null,
        height: isHorizontalScroll ? null : tailExtent,
        child: Align(alignment: Alignment.topCenter, child: content),
      ),
    );
  }
}
