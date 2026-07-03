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
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !showToolbar,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 200),
          offset: Offset(0, showToolbar ? 0 : slideOffset),
          child: Container(
            color: Colors.black,
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
                            color: Colors.white70,
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
                              inactiveTrackColor: Colors.white24,
                              activeTickMarkColor: colorScheme.primary,
                              inactiveTickMarkColor: Colors.white24,
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
                            color: Colors.white70,
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
                            color: hasPrev ? Colors.white : Colors.white38,
                          ),
                          onPressed: onPrevChapter,
                          tooltip: '上一章',
                        ),
                        IconButton(
                          icon: const Icon(Icons.list, color: Colors.white),
                          onPressed: onCatalog,
                          tooltip: '目录',
                        ),
                        if (showAutoScrollButton)
                          IconButton(
                            tooltip: autoScrollEnabled
                                ? (autoScrollActive ? '暂停自动滚动' : '自动滚动即将恢复')
                                : '开启自动滚动',
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
                                  : Colors.white,
                            ),
                            onPressed: onToggleAutoScroll,
                          ),
                        IconButton(
                          icon: Badge(
                            isLabelVisible: commentCount > 0,
                            backgroundColor: Colors.white,
                            textColor: Colors.black,
                            label: Text(
                              '$commentCount',
                              style: const TextStyle(fontSize: 10),
                            ),
                            child: const Icon(
                              Icons.forum_outlined,
                              color: Colors.white,
                            ),
                          ),
                          onPressed: onComments,
                          tooltip: '章节评论',
                        ),
                        IconButton(
                          icon: const Icon(Icons.settings, color: Colors.white),
                          onPressed: onSettings,
                          tooltip: '阅读设置',
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.skip_next,
                            color: hasNext ? Colors.white : Colors.white38,
                          ),
                          onPressed: onNextChapter,
                          tooltip: '下一话',
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
