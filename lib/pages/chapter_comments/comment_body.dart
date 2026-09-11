part of '../chapter_comments_sheet.dart';

extension _ChapterCommentBody on _ChapterCommentsSheetState {
  /// 评论区计数文案：全部加载且无屏蔽时显示「N 条」；
  /// 有屏蔽时为「显示数/总数|屏蔽数」，屏蔽为 0 则不显示 |屏蔽数。
  String _buildCountLabel(AppLocalizations l10n) {
    if (_total <= 0) return '';
    if (_allCommentsLoaded && _blockedCount == 0) {
      return l10n.chapterCommentsTotalCount(_total);
    }
    final shown = _comments.length - _blockedCount;
    if (_blockedCount > 0) {
      return l10n.chapterCommentsCountWithBlocked(shown, _total, _blockedCount);
    }
    return '$shown/$_total';
  }

  Widget _buildBody(BuildContext context, ColorScheme cs, TextTheme tt) {
    final l10n = AppLocalizations.of(context)!;
    if (_loading && _comments.isEmpty) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          16,
          12,
          16,
          _ChapterCommentsSheetState._commentListBottomPadding,
        ),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 8,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) =>
            _CommentSkeleton(compact: _useCompactLayout),
      );
    }

    if (_error != null && _comments.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 40, color: cs.onSurfaceVariant),
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.chapterCommentsLoadFailed,
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                _error!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton.tonal(
                onPressed: () => _loadComments(),
                child: Text(l10n.retryButton),
              ),
            ],
          ),
        ),
      );
    }

    if (_comments.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 40, color: cs.onSurfaceVariant),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.chapterCommentsEmptyTitle,
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.chapterCommentsEmptySubtitle,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    final entries = _groupedEntries;
    final hasSummary = _hasSummaryPanel;
    final summaryOffset = hasSummary ? 1 : 0;

    if (!_useCompactLayout) {
      return NotificationListener<ScrollNotification>(
        onNotification: handleScrollNotification,
        child: ListView.separated(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(
            16,
            12,
            16,
            _ChapterCommentsSheetState._commentListBottomPadding,
          ),
          itemCount: summaryOffset + entries.length + (_loadingMore ? 1 : 0),
          separatorBuilder: (_, index) => const SizedBox(height: 10),
          itemBuilder: (_, index) {
            if (hasSummary && index == 0) {
              return _buildSummaryPanel(cs, tt);
            }
            final dataIndex = index - summaryOffset;
            if (dataIndex == entries.length && _loadingMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: ExpressiveLoadingIndicator()),
              );
            }

            final entry = entries[dataIndex];
            return _CommentCard(
              entry: entry,
              relativeTime: TimeFormat.relativeOf(
                entry.createAt,
                AppLocalizations.of(context)!,
              ),
              showAvatar: _showUserAvatar,
              showUserName: _showUserName,
              showCommentTime: _showCommentTime,
              spoilerIds: _aiSettings.spoilerAnalysis ? _spoilerIds : const {},
              onLongPress: (entry, position) =>
                  _showCommentActionMenu(entry, position),
              onTapMerged: (entry) => _showMergedCommentUsersDialog(entry),
            );
          },
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final rows = _buildCommentRows(
          context,
          constraints.maxWidth - 32,
          entries,
        );

        return NotificationListener<ScrollNotification>(
          onNotification: handleScrollNotification,
          child: ListView.separated(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(
              16,
              12,
              16,
              _ChapterCommentsSheetState._commentListBottomPadding,
            ),
            itemCount: summaryOffset + rows.length + (_loadingMore ? 1 : 0),
            separatorBuilder: (_, index) =>
                const SizedBox(height: AppSpacing.sm),
            itemBuilder: (_, index) {
              if (hasSummary && index == 0) {
                return _buildSummaryPanel(cs, tt);
              }
              final dataIndex = index - summaryOffset;
              if (dataIndex == rows.length && _loadingMore) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: ExpressiveLoadingIndicator()),
                );
              }

              final row = rows[dataIndex];
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < row.items.length; i++) ...[
                      SizedBox(
                        width: row.items[i].width,
                        child: _CommentCard(
                          entry: row.items[i].entry,
                          relativeTime: TimeFormat.relativeOf(
                            row.items[i].entry.createAt,
                            AppLocalizations.of(context)!,
                          ),
                          compact: true,
                          showAvatar: _showUserAvatar,
                          showUserName: _showUserName,
                          showCommentTime: _showCommentTime,
                          spoilerIds: _aiSettings.spoilerAnalysis
                              ? _spoilerIds
                              : const {},
                          onLongPress: (entry, position) =>
                              _showCommentActionMenu(entry, position),
                          onTapMerged: (entry) =>
                              _showMergedCommentUsersDialog(entry),
                        ),
                      ),
                      if (i != row.items.length - 1)
                        const SizedBox(
                          width: _ChapterCommentsSheetState._commentRowSpacing,
                        ),
                    ],
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
