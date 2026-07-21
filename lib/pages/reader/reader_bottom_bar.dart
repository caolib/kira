part of '../reader_page.dart';

/// Sliding bottom bar with page slider, chapter navigation, and action buttons.
class _ReaderBottomBar extends StatelessWidget {
  final bool showToolbar;
  final int currentPage;
  final int totalPage;
  final bool hasPrev;
  final bool hasNext;
  final int commentCount;
  final bool isPageMode;
  final bool autoScrollEnabled;
  final bool autoScrollActive;
  final bool showAutoScrollButton;
  final double slideOffset;
  final ColorScheme colorScheme;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final VoidCallback? onPrevChapter;
  final VoidCallback onCatalog;
  final VoidCallback? onToggleAutoScroll;
  final VoidCallback onComments;
  final VoidCallback onSettings;
  final VoidCallback? onNextChapter;

  const _ReaderBottomBar({
    required this.showToolbar,
    required this.currentPage,
    required this.totalPage,
    required this.hasPrev,
    required this.hasNext,
    required this.commentCount,
    required this.isPageMode,
    required this.autoScrollEnabled,
    required this.autoScrollActive,
    required this.showAutoScrollButton,
    required this.slideOffset,
    required this.colorScheme,
    required this.onPageChanged,
    required this.onDragStart,
    required this.onDragEnd,
    this.onPrevChapter,
    required this.onCatalog,
    this.onToggleAutoScroll,
    required this.onComments,
    required this.onSettings,
    this.onNextChapter,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !showToolbar,
        child: AnimatedSlide(
          duration: adaptiveDuration(context, const Duration(milliseconds: 200)),
          offset: Offset(0, showToolbar ? 0 : slideOffset),
          child: Container(
            color: ReaderChrome.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Page progress slider with tick marks
                    Row(
                      children: [
                        Text(
                          '$currentPage',
                          style: const TextStyle(
                            color: ReaderChrome.onSurfaceMuted,
                            fontSize: 12,
                          ),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 7,
                              ),
                              tickMarkShape: const RoundSliderTickMarkShape(
                                tickMarkRadius: 2.5,
                              ),
                              activeTrackColor: colorScheme.primary,
                              inactiveTrackColor: ReaderChrome.trackInactive,
                              activeTickMarkColor: colorScheme.primary,
                              inactiveTickMarkColor: ReaderChrome.trackInactive,
                              thumbColor: colorScheme.primary,
                              overlayColor: colorScheme.primary.withValues(
                                alpha: 0.2,
                              ),
                            ),
                            child: Slider(
                              value: currentPage.toDouble(),
                              min: 1,
                              max: totalPage.toDouble(),
                              divisions: totalPage > 1 ? totalPage - 1 : null,
                              onChangeStart: (_) => onDragStart(),
                              onChangeEnd: (_) => onDragEnd(),
                              onChanged: (v) => onPageChanged(v.round()),
                            ),
                          ),
                        ),
                        Text(
                          '$totalPage',
                          style: const TextStyle(
                            color: ReaderChrome.onSurfaceMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    // Action button row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.skip_previous,
                            color: hasPrev
                                ? ReaderChrome.onSurface
                                : ReaderChrome.onSurfaceFaint,
                          ),
                          onPressed: onPrevChapter,
                          tooltip: l10n.readerPreviousChapter,
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.list,
                            color: ReaderChrome.onSurface,
                          ),
                          onPressed: onCatalog,
                          tooltip: l10n.chapterCommentsCatalog,
                        ),
                        if (showAutoScrollButton)
                          IconButton(
                            tooltip: autoScrollEnabled
                                ? (autoScrollActive
                                      ? l10n.readerPauseAutoScroll
                                      : l10n.readerAutoScrollWillResume)
                                : l10n.readerEnableAutoScroll,
                            icon: Icon(
                              autoScrollEnabled
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_outline,
                              color: autoScrollEnabled
                                  ? (autoScrollActive
                                        ? colorScheme.primary
                                        : colorScheme.primary.withValues(
                                            alpha: 0.4,
                                          ))
                                  : ReaderChrome.onSurface,
                            ),
                            onPressed: onToggleAutoScroll,
                          ),
                        IconButton(
                          icon: Badge(
                            isLabelVisible: commentCount > 0,
                            backgroundColor: ReaderChrome.onSurface,
                            textColor: ReaderChrome.surface,
                            label: Text(
                              '$commentCount',
                              style: const TextStyle(fontSize: 12),
                            ),
                            child: const Icon(
                              Icons.forum_outlined,
                              color: ReaderChrome.onSurface,
                            ),
                          ),
                          onPressed: onComments,
                          tooltip: l10n.chapterCommentsTitle,
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.settings,
                            color: ReaderChrome.onSurface,
                          ),
                          onPressed: onSettings,
                          tooltip: l10n.readerSettingsTitle,
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.skip_next,
                            color: hasNext
                                ? ReaderChrome.onSurface
                                : ReaderChrome.onSurfaceFaint,
                          ),
                          onPressed: onNextChapter,
                          tooltip: l10n.chapterCommentsNext,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
