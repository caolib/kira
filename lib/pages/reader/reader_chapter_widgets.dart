part of '../reader_page.dart';

/// Shared button style for chapter divider action buttons.
final _chapterActionButtonStyle = ReaderChrome.outlinedActionStyle;

/// Shared primary button style for "next chapter" actions.
final _chapterPrimaryButtonStyle = ReaderChrome.filledActionStyle;

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

/// 连续阅读中「章间目录/评论条」与「加载下一话」共用同一紧凑高度，
/// 避免 loadMore 替换为 divider 时高度突变导致跳动。
const double _chapterBridgeStripHeight = 80;

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
    final content = Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: _ChapterDividerActions(
          commentCount: commentCount,
          onCatalog: onCatalog,
          onComments: onComments,
        ),
      ),
    );
    return ColoredBox(
      color: ReaderChrome.surface,
      child: SizedBox(
        width: isHorizontalScroll ? tailExtent : null,
        height: isHorizontalScroll ? null : _chapterBridgeStripHeight,
        child: content,
      ),
    );
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
    final content = Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ChapterDividerActions(
              commentCount: commentCount,
              onCatalog: onCatalog,
              onComments: onComments,
            ),
            const SizedBox(height: AppSpacing.xs),
            if (isLoading)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(Icons.expand_more, color: cs.onSurfaceVariant, size: 18),
            Text(
              isLoading
                  ? l10n.readerLoadingNextChapter
                  : l10n.readerContinueScrollLoadNext,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
    return ColoredBox(
      color: ReaderChrome.surface,
      child: SizedBox(
        width: isHorizontalScroll ? tailExtent : null,
        // 与 _ChapterDivider 同高，追加下一话时不产生高度差跳动。
        height: isHorizontalScroll ? null : _chapterBridgeStripHeight,
        child: content,
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
        style: const TextStyle(
          color: ReaderChrome.onSurfaceSubtle,
          fontSize: 14,
        ),
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
      color: ReaderChrome.surface,
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
                    style: const TextStyle(
                      color: ReaderChrome.onSurfaceSubtle,
                      fontSize: 12,
                    ),
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
              color: ReaderChrome.onSurfaceMuted,
              fontSize: 16,
              height: 1.6,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
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
      color: ReaderChrome.surface,
      child: SizedBox(
        width: isHorizontalScroll ? tailExtent : null,
        height: isHorizontalScroll ? null : tailExtent,
        child: Align(alignment: Alignment.topCenter, child: content),
      ),
    );
  }
}
