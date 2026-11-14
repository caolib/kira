part of '../novel_comments_sheet.dart';

extension _NovelMergedComments on _NovelCommentsSheetState {
  Widget _buildMergedCommentCard(
    BuildContext context,
    NovelCommentDisplayEntry entry,
  ) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hot = entry.count >= 10;
    return Material(
      key: ValueKey('novel-merged-comment-${entry.primaryComment.id}'),
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.lgR,
        side: BorderSide(
          color: hot
              ? AppStatusColors.hotAccent.withValues(alpha: 0.56)
              : cs.outlineVariant.withValues(alpha: 0.6),
          width: 0.8,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showMergedCommentUsers(entry),
        onLongPress: () =>
            _showCommentActionMenu(entry.primaryComment, entry: entry),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: MergedCommentContent(
            count: entry.count,
            names: entry.userNames(),
            avatars: [
              for (final comment in entry.avatarComments())
                AccountAvatar(avatar: comment.userAvatar, radius: 11),
            ],
            showAvatar: _settings.showAvatar,
            showUserName: _settings.showUserName,
            userStyle: tt.labelMedium?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.78),
              fontWeight: FontWeight.w500,
            ),
            body: ExpandableCommentText(
              key: ValueKey('novel-merged-text-${entry.primaryComment.id}'),
              text: entry.content,
              backgroundColor: cs.surfaceContainerHigh,
              style: buildCommentBodyStyle(
                tt,
                compact: false,
              )?.copyWith(color: hot ? AppStatusColors.hotAccent : null),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showMergedCommentUsers(NovelCommentDisplayEntry entry) async {
    final generation = _accountGeneration;
    final comments = [...entry.comments]
      ..sort((a, b) => b.createAt.compareTo(a.createAt));
    final selected = await showAppSheet<NovelComment>(
      context,
      maxHeightFactor: 0.5,
      child: Builder(
        builder: (sheetContext) {
          final cs = Theme.of(sheetContext).colorScheme;
          final tt = Theme.of(sheetContext).textTheme;
          return ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.sizeOf(sheetContext).height / 3 - 40,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_settings.showTime &&
                      comments.first.createAt.isNotEmpty &&
                      comments.last.createAt.isNotEmpty) ...[
                    Text(
                      '${TimeFormat.relativeOf(comments.last.createAt, AppLocalizations.of(sheetContext)!)} ~ '
                      '${TimeFormat.relativeOf(comments.first.createAt, AppLocalizations.of(sheetContext)!)}',
                      textAlign: TextAlign.center,
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  LayoutBuilder(
                    builder: (context, constraints) => Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final comment in comments)
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth * 0.8,
                              minHeight: 48,
                            ),
                            child: Material(
                              color: cs.surfaceContainerHighest,
                              borderRadius: AppRadius.mdR,
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                key: ValueKey(
                                  'novel-merged-member-${comment.id}',
                                ),
                                onTap: () =>
                                    Navigator.of(sheetContext).pop(comment),
                                onLongPress: () =>
                                    _showCommentActionMenu(comment),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.sm,
                                    vertical: AppSpacing.sm,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_settings.showAvatar) ...[
                                        AccountAvatar(
                                          avatar: comment.userAvatar,
                                          radius: 10,
                                        ),
                                        const SizedBox(width: AppSpacing.sm),
                                      ],
                                      Flexible(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _displayName(comment),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: tt.labelMedium,
                                            ),
                                            if (_settings.showTime &&
                                                comment.createAt.isNotEmpty)
                                              Text(
                                                TimeFormat.relativeOf(
                                                  comment.createAt,
                                                  AppLocalizations.of(
                                                    sheetContext,
                                                  )!,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: tt.labelSmall?.copyWith(
                                                  color: cs.onSurfaceVariant,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (!mounted || generation != _accountGeneration || selected == null) {
      return;
    }
    await _showPostDialog(replyTo: selected);
  }
}
