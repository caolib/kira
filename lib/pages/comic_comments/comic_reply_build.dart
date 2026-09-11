part of '../comic_comments_sheet.dart';

extension _ComicReplyBuild on _ComicCommentsSheetState {
  Widget _buildReplySection(
    ColorScheme cs,
    TextTheme tt,
    ComicComment comment,
    _ComicReplyState replyState,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final replies = replyState.replies;
    final totalReplies = replyState.total > 0
        ? replyState.total
        : comment.replyCount;
    final skeletonCount = totalReplies <= 0
        ? 1
        : (totalReplies < _ComicCommentsSheetState._replyPageSize
              ? totalReplies
              : _ComicCommentsSheetState._replyPageSize);

    return Container(
      margin: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (replyState.loading && replies.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: List.generate(skeletonCount * 2 - 1, (index) {
                  if (index.isOdd) return const SizedBox(height: AppSpacing.md);
                  return const _ComicReplySkeleton();
                }),
              ),
            ),
          if (replyState.error != null && replies.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.comicCommentReplyLoadFailed,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _loadReplies(comment),
                    child: Text(l10n.retryButton),
                  ),
                ],
              ),
            ),
          if (!replyState.loading &&
              replies.isEmpty &&
              replyState.error == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                l10n.comicCommentEmptyReplies,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          for (var i = 0; i < replies.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == replies.length - 1 ? 0 : 0),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: _buildReplyItem(cs, tt, replies[i], comment),
                  ),
                  if (i < replies.length - 1)
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Divider(
                        height: 24,
                        thickness: 0.5,
                        color: cs.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                ],
              ),
            ),
          if (replyState.error != null && replies.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton.icon(
                onPressed: replyState.loadingMore
                    ? null
                    : () => _loadReplies(comment, loadMore: true),
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(l10n.comicCommentRetryLoadMoreReplies),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  minimumSize: const Size(0, 0),
                ),
              ),
            ),
          if (replyState.error == null &&
              replies.isNotEmpty &&
              replies.length < totalReplies)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton.icon(
                onPressed: replyState.loadingMore
                    ? null
                    : () => _loadReplies(comment, loadMore: true),
                icon: replyState.loadingMore
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.primary,
                        ),
                      )
                    : const Icon(Icons.expand_more_rounded, size: 18),
                label: Text(
                  l10n.comicCommentLoadMoreReplies(
                    replies.length,
                    totalReplies,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: cs.primary,
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  minimumSize: const Size(0, 0),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReplyItem(
    ColorScheme cs,
    TextTheme tt,
    ComicComment reply,
    ComicComment parentComment,
  ) {
    final isReplyToOp = _isReplyToOp(reply, parentComment);
    final parentUserName = reply.parentUserName?.trim() ?? '';
    final showReplyTarget = !isReplyToOp && parentUserName.isNotEmpty;
    final user = UserManager();
    final showAvatar = user.commentShowAvatar;
    final showCommentTime = user.commentShowTime;
    final userStyle = tt.labelSmall?.copyWith(
      color: cs.onSurfaceVariant.withValues(alpha: 0.78),
      fontWeight: FontWeight.w500,
    );
    final replyTargetStyle = userStyle?.copyWith(
      color: cs.primary.withValues(alpha: 0.9),
      fontWeight: FontWeight.w600,
    );
    final timeStyle = tt.labelSmall?.copyWith(
      color: cs.onSurfaceVariant.withValues(alpha: 0.72),
      fontWeight: FontWeight.w400,
    );
    final bodyStyle = buildCommentBodyStyle(
      tt,
      compact: true,
    )?.copyWith(height: 1.45);

    return GestureDetector(
      onTap: () => _showPostCommentDialog(replyTo: reply),
      onLongPress: () => _showCommentActionMenu(reply),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showAvatar) ...[
            _ComicCommentAvatar(imageUrl: reply.userAvatar, size: 22),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              reply.userName.trim().isEmpty
                                  ? AppLocalizations.of(
                                      context,
                                    )!.commentSettingsAnonymousUser
                                  : reply.userName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: userStyle,
                            ),
                          ),
                          if (showReplyTarget) ...[
                            const SizedBox(width: AppSpacing.xs),
                            Icon(
                              Icons.arrow_right_alt_rounded,
                              size: 14,
                              color: cs.onSurfaceVariant.withValues(
                                alpha: 0.78,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Flexible(
                              child: Text(
                                parentUserName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: replyTargetStyle,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (showCommentTime) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        TimeFormat.relativeOf(
                          reply.createAt,
                          AppLocalizations.of(context)!,
                        ),
                        style: timeStyle,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                _buildCommentText(
                  reply,
                  bodyStyle: bodyStyle,
                  backgroundColor: cs.surfaceContainerLow,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _isReplyToOp(ComicComment reply, ComicComment parentComment) {
    final replyParentUserId = reply.parentUserId?.trim() ?? '';
    final opUserId = parentComment.userId.trim();
    if (replyParentUserId.isNotEmpty && opUserId.isNotEmpty) {
      return replyParentUserId == opUserId;
    }
    final replyParentUserName = reply.parentUserName?.trim() ?? '';
    final opUserName = parentComment.userName.trim();
    if (replyParentUserName.isNotEmpty && opUserName.isNotEmpty) {
      return replyParentUserName == opUserName;
    }
    return false;
  }
}
