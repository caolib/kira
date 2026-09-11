part of '../reader_page.dart';

/// Sliding top bar with back button and chapter title.
class _ReaderTopBar extends StatelessWidget {
  final bool showToolbar;
  final String chapterName;
  final double slideOffset;
  final VoidCallback onBack;
  final bool isBookmarked;
  final VoidCallback? onToggleBookmark;
  final bool isRefreshing;
  final VoidCallback? onRefresh;

  const _ReaderTopBar({
    required this.showToolbar,
    required this.chapterName,
    required this.slideOffset,
    required this.onBack,
    this.isBookmarked = false,
    this.onToggleBookmark,
    this.isRefreshing = false,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !showToolbar,
        child: AnimatedSlide(
          duration: adaptiveDuration(
            context,
            const Duration(milliseconds: 200),
          ),
          offset: Offset(0, showToolbar ? 0 : -slideOffset),
          child: Container(
            color: ReaderChrome.surface,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back,
                        color: ReaderChrome.onSurface,
                      ),
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).backButtonTooltip,
                      onPressed: onBack,
                    ),
                    Expanded(
                      child: Text(
                        chapterName,
                        style: const TextStyle(
                          color: ReaderChrome.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (onRefresh != null)
                      IconButton(
                        icon: isRefreshing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: ReaderChrome.onSurface,
                                ),
                              )
                            : const Icon(
                                Icons.refresh,
                                color: ReaderChrome.onSurface,
                              ),
                        tooltip: AppLocalizations.of(context)!.readerRefresh,
                        onPressed: isRefreshing ? null : onRefresh,
                      ),
                    if (onToggleBookmark != null)
                      IconButton(
                        icon: Icon(
                          isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                          color: isBookmarked
                              ? Colors.amberAccent
                              : ReaderChrome.onSurface,
                        ),
                        tooltip: isBookmarked
                            ? AppLocalizations.of(context)!.bookmarkRemove
                            : AppLocalizations.of(context)!.bookmarkAdd,
                        onPressed: onToggleBookmark,
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
