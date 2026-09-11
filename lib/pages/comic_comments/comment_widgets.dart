part of '../comic_comments_sheet.dart';

class _ComicReplyState {
  static const _unset = Object();

  final bool expanded;
  final bool loading;
  final bool loadingMore;
  final List<ComicComment> replies;
  final int total;
  final String? error;

  const _ComicReplyState({
    this.expanded = false,
    this.loading = false,
    this.loadingMore = false,
    this.replies = const [],
    this.total = 0,
    this.error,
  });

  _ComicReplyState copyWith({
    bool? expanded,
    bool? loading,
    bool? loadingMore,
    List<ComicComment>? replies,
    int? total,
    Object? error = _unset,
  }) {
    return _ComicReplyState(
      expanded: expanded ?? this.expanded,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      replies: replies ?? this.replies,
      total: total ?? this.total,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }
}

class _ComicCommentAvatar extends StatelessWidget {
  final String imageUrl;
  final double size;

  const _ComicCommentAvatar({required this.imageUrl, required this.size});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: imageUrl.isEmpty
            ? ColoredBox(
                color: _comicCommentCardInsetColor(cs),
                child: Icon(
                  Icons.person,
                  size: size * 0.5,
                  color: cs.onSurfaceVariant,
                ),
              )
            : CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (_, _) => ColoredBox(
                  color: _comicCommentCardInsetColor(cs),
                  child: Icon(
                    Icons.person,
                    size: size * 0.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                errorWidget: (_, _, _) => ColoredBox(
                  color: _comicCommentCardInsetColor(cs),
                  child: Icon(
                    Icons.person,
                    size: size * 0.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
      ),
    );
  }
}

class _ExpandableCommentText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Color backgroundColor;

  const _ExpandableCommentText({
    super.key,
    required this.text,
    required this.style,
    required this.backgroundColor,
  });

  @override
  State<_ExpandableCommentText> createState() => _ExpandableCommentTextState();
}

class _ExpandableCommentTextState extends State<_ExpandableCommentText> {
  static const _maxLines = 3;
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant _ExpandableCommentText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _expanded = false;
    }
  }

  bool _isTextOverflowing(BuildContext context, double maxWidth) {
    if (maxWidth <= 0 || !maxWidth.isFinite) return false;

    final textPainter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      textDirection: Directionality.of(context),
      maxLines: _maxLines,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: maxWidth);

    return textPainter.didExceedMaxLines;
  }

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final baseFontSize = widget.style?.fontSize ?? 14.0;
    final hintStyle = widget.style?.copyWith(
      color: cs.primary,
      fontWeight: FontWeight.w700,
      fontSize: baseFontSize > 13 ? baseFontSize - 1 : baseFontSize,
      height: 1.2,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isOverflowing = _isTextOverflowing(context, constraints.maxWidth);

        if (!isOverflowing) {
          return Text(widget.text, style: widget.style);
        }

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: AppRadius.mdR,
            onTap: _toggleExpanded,
            child: AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    children: [
                      Text(
                        widget.text,
                        maxLines: _expanded ? null : _maxLines,
                        style: widget.style,
                      ),
                      if (!_expanded)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            child: Container(
                              height: 56,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    widget.backgroundColor.withValues(alpha: 0),
                                    widget.backgroundColor.withValues(
                                      alpha: 0.96,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (!_expanded) ...[
                    const SizedBox(height: AppSpacing.sm),
                    IgnorePointer(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: widget.backgroundColor,
                            borderRadius: AppRadius.fullR,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                l10n.comicCommentExpandFullText,
                                style: hintStyle,
                              ),
                              const SizedBox(width: 2),
                              Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 16,
                                color: cs.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (_expanded) ...[
                    const SizedBox(height: AppSpacing.sm),
                    IgnorePointer(
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              l10n.chapterCommentsCollapse,
                              style: hintStyle,
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.keyboard_arrow_up_rounded,
                              size: 16,
                              color: cs.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ComicCommentSkeleton extends StatelessWidget {
  const _ComicCommentSkeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _comicCommentCardColor(cs),
        borderRadius: AppRadius.lgR,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.2),
                    borderRadius: AppRadius.xsR,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Container(
                width: 48,
                height: 12,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.2),
                  borderRadius: AppRadius.xsR,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            height: 14,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.2),
              borderRadius: AppRadius.xsR,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: MediaQuery.sizeOf(context).width * 0.55,
            height: 14,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.2),
              borderRadius: AppRadius.xsR,
            ),
          ),
        ],
      ),
    );
  }
}

class _ComicReplySkeleton extends StatelessWidget {
  const _ComicReplySkeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final placeholderColor = _comicCommentCardInsetColor(
      cs,
    ).withValues(alpha: 0.2);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: placeholderColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 86,
                    height: 12,
                    decoration: BoxDecoration(
                      color: placeholderColor,
                      borderRadius: AppRadius.xsR,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 40,
                    height: 10,
                    decoration: BoxDecoration(
                      color: placeholderColor,
                      borderRadius: AppRadius.xsR,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: double.infinity,
                height: 12,
                decoration: BoxDecoration(
                  color: placeholderColor,
                  borderRadius: AppRadius.xsR,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: MediaQuery.sizeOf(context).width * 0.36,
                height: 12,
                decoration: BoxDecoration(
                  color: placeholderColor,
                  borderRadius: AppRadius.xsR,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
