part of '../chapter_comments_sheet.dart';

extension _ChapterCommentCompactLayout on _ChapterCommentsSheetState {
  List<_CommentRow> _buildCommentRows(
    BuildContext context,
    double maxWidth,
    List<ChapterCommentDisplayEntry> entries,
  ) {
    if (entries.isEmpty || maxWidth <= 0) return const [];

    final textTheme = Theme.of(context).textTheme;
    final textScaler = MediaQuery.textScalerOf(context);
    const minWidth = 108.0;
    const compactCardHorizontalPadding = 20.0;
    const compactTextWidthBuffer = 10.0;
    final preferredMaxWidth = maxWidth * 0.8;

    final estimatedWidths = entries.map((entry) {
      final compactBodyStyle = buildCommentBodyStyle(textTheme, compact: true);
      final bodyWidth = _measureTextWidth(
        entry.content,
        compactBodyStyle,
        textScaler,
        preferredMaxWidth,
      );

      final headerWidth = _estimateCompactHeaderWidth(
        context,
        entry,
        preferredMaxWidth,
      );

      var contentWidth = bodyWidth > headerWidth ? bodyWidth : headerWidth;
      final mergedInlineWidth = _estimateCompactMergedInlineWidth(
        context,
        entry,
        bodyWidth: bodyWidth,
        maxWidth: preferredMaxWidth,
      );
      if (mergedInlineWidth > contentWidth) {
        contentWidth = mergedInlineWidth;
      }

      final cardWidth =
          (contentWidth + compactCardHorizontalPadding + compactTextWidthBuffer)
              .clamp(minWidth, preferredMaxWidth);
      return _CommentLayoutItem(entry: entry, width: cardWidth);
    }).toList();

    final rows = <_CommentRow>[];
    var currentItems = <_CommentLayoutItem>[];
    var occupiedWidth = 0.0;

    void pushRow() {
      if (currentItems.isEmpty) return;

      final spacingWidth =
          _ChapterCommentsSheetState._commentRowSpacing *
          (currentItems.length > 1 ? currentItems.length - 1 : 0);
      final cardsWidth = currentItems.fold<double>(
        0,
        (sum, item) => sum + item.width,
      );
      final remainder = maxWidth - spacingWidth - cardsWidth;
      if (remainder > 0) {
        final extraWidth = remainder / currentItems.length;
        currentItems = [
          for (final item in currentItems)
            _CommentLayoutItem(
              entry: item.entry,
              width: item.width + extraWidth,
            ),
        ];
      }
      rows.add(_CommentRow(items: List<_CommentLayoutItem>.from(currentItems)));
      currentItems = <_CommentLayoutItem>[];
      occupiedWidth = 0.0;
    }

    for (final item in estimatedWidths) {
      final spacing = currentItems.isEmpty
          ? 0.0
          : _ChapterCommentsSheetState._commentRowSpacing;
      final nextWidth = occupiedWidth + spacing + item.width;

      if (currentItems.isNotEmpty && nextWidth > maxWidth) {
        pushRow();
      }

      if (item.width >= maxWidth) {
        rows.add(
          _CommentRow(
            items: [_CommentLayoutItem(entry: item.entry, width: maxWidth)],
          ),
        );
        continue;
      }

      final rowSpacing = currentItems.isEmpty
          ? 0.0
          : _ChapterCommentsSheetState._commentRowSpacing;
      occupiedWidth += rowSpacing + item.width;
      currentItems.add(item);
    }

    pushRow();
    return rows;
  }

  double _estimateCompactHeaderWidth(
    BuildContext context,
    ChapterCommentDisplayEntry entry,
    double maxWidth,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final textScaler = MediaQuery.textScalerOf(context);
    final showCountTag = _shouldShowMergedCountTag(entry.count);

    if (entry.isMerged) {
      final countTagWidth = showCountTag
          ? _estimateMergedCountTagWidth(
              context,
              entry.count,
              maxWidth,
              compact: true,
            )
          : 0.0;

      if (!_showUserAvatar) {
        return countTagWidth;
      }

      final avatarCount = entry.avatarComments().length;
      final avatarWidth = _avatarStackWidth(
        avatarCount,
        avatarSize: 22,
        overlap: 8,
      );
      if (!showCountTag) {
        return avatarWidth;
      }

      return avatarWidth + 8 + countTagWidth;
    }

    var width = 0.0;
    var visibleSegments = 0;

    if (_showUserAvatar) {
      width += 20;
      visibleSegments++;
    }

    if (_showUserName) {
      width += _measureTextWidth(
        entry.primaryComment.userName,
        textTheme.labelSmall,
        textScaler,
        maxWidth,
      );
      visibleSegments++;
    }

    if (_showCommentTime) {
      width += _measureTextWidth(
        TimeFormat.relativeOf(entry.createAt, AppLocalizations.of(context)!),
        textTheme.labelSmall,
        textScaler,
        maxWidth,
      );
      visibleSegments++;
    }

    if (visibleSegments > 1) {
      width += (visibleSegments - 1) * 6;
    }

    return width;
  }

  double _estimateCompactMergedInlineWidth(
    BuildContext context,
    ChapterCommentDisplayEntry entry, {
    required double bodyWidth,
    required double maxWidth,
  }) {
    if (!entry.isMerged ||
        _showUserAvatar ||
        !_shouldShowMergedCountTag(entry.count)) {
      return bodyWidth;
    }

    return bodyWidth +
        8 +
        _estimateMergedCountTagWidth(
          context,
          entry.count,
          maxWidth,
          compact: true,
        );
  }
}
