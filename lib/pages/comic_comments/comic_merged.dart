part of '../comic_comments_sheet.dart';

extension _ComicMerged on _ComicCommentsSheetState {
  /// 点击合并评论：弹窗展示所有发表该评论的用户，按时间从新到旧排列。
  Future<void> _showMergedCommentUsersDialog(
    ComicCommentDisplayEntry entry,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final comments = [...entry.comments]
      ..sort((a, b) {
        final ta = _ComicCommentsSheetState._parseCommentTime(a.createAt);
        final tb = _ComicCommentsSheetState._parseCommentTime(b.createAt);
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        minHeight: MediaQuery.sizeOf(context).height / 3,
        maxHeight:
            MediaQuery.sizeOf(context).height *
            _ComicCommentsSheetState._mergedCommentSheetMaxHeightFactor,
      ),
      builder: (sheetContext) {
        final cs = Theme.of(sheetContext).colorScheme;
        final tt = Theme.of(sheetContext).textTheme;
        final earliest = comments.isEmpty
            ? null
            : TimeFormat.relativeOf(comments.last.createAt, l10n);
        final latest = comments.isEmpty
            ? null
            : TimeFormat.relativeOf(comments.first.createAt, l10n);
        final timeStyle = tt.labelSmall?.copyWith(
          color: cs.onSurfaceVariant.withValues(alpha: 0.72),
        );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (earliest != null && latest != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    '$earliest ~ $latest',
                    textAlign: TextAlign.center,
                    style: timeStyle,
                  ),
                ),
              Flexible(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  shrinkWrap: true,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return Wrap(
                            spacing:
                                _ComicCommentsSheetState._commentRowSpacing,
                            runSpacing:
                                _ComicCommentsSheetState._commentRowSpacing,
                            children: [
                              for (final c in comments)
                                _buildMergedUserCard(
                                  context,
                                  c,
                                  l10n,
                                  constraints.maxWidth,
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 合并评论用户卡片：按内容宽度自适应，多个卡片同行排列放不下才换行。
  Widget _buildMergedUserCard(
    BuildContext context,
    ComicComment comment,
    AppLocalizations l10n,
    double maxWidth,
  ) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final name = comment.userName.trim();
    final displayName = name.isEmpty ? l10n.commentSettingsAnonymousUser : name;
    final userStyle = _buildMergedCommentUserStyle(
      tt,
      cs,
      compact: true,
    )?.copyWith(color: cs.onSurface);
    final timeStyle = tt.labelSmall?.copyWith(color: cs.onSurfaceVariant);
    const avatarGap = 6.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _showCommentActionMenu(comment),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth * 0.8),
        child: IntrinsicWidth(
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            decoration: _buildMergedCommentCardDecoration(
              cs,
              brightness: Theme.of(context).brightness,
              highlightAsHot: false,
              withShadow: false,
              backgroundColor: cs.surfaceContainerHigh,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_user.commentShowAvatar) ...[
                  _ComicCommentAvatar(imageUrl: comment.userAvatar, size: 20),
                  const SizedBox(width: avatarGap),
                ],
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: userStyle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      TimeFormat.relativeOf(comment.createAt, l10n),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: timeStyle,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
