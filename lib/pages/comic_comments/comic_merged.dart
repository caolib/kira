part of '../comic_comments_sheet.dart';

extension _ComicMerged on _ComicCommentsSheetState {
  /// 点击合并评论：展示成员，按时间从新到旧排列；选中后关闭列表再回复。
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

    final selected = await showModalBottomSheet<ComicComment>(
      context: context,
      backgroundColor: Colors.transparent,
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
        return AppSheet(
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
    if (!mounted || selected == null) return;
    await _showPostCommentDialog(replyTo: selected);
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
    final borderRadius = BorderRadius.circular(_mergedCardCornerRadius);
    const avatarGap = 6.0;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth * 0.8),
      child: IntrinsicWidth(
        child: Material(
          color: Colors.transparent,
          borderRadius: borderRadius,
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: _buildMergedCommentCardDecoration(
              cs,
              highlightAsHot: false,
              withShadow: false,
              backgroundColor: _comicCommentCardInsetColor(cs),
            ),
            child: InkWell(
              key: ValueKey('comic-merged-member-${comment.id}'),
              borderRadius: borderRadius,
              onTap: () => Navigator.of(context).pop(comment),
              onLongPress: () => _showCommentActionMenu(comment),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_user.commentShowAvatar) ...[
                        _ComicCommentAvatar(
                          imageUrl: comment.userAvatar,
                          size: 20,
                        ),
                        const SizedBox(width: avatarGap),
                      ],
                      Flexible(
                        child: Column(
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
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
