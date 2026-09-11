part of '../chapter_comments_sheet.dart';

extension _ChapterCommentActions on _ChapterCommentsSheetState {
  /// 点击合并评论：弹窗展示所有发表该评论的用户，按时间从新到旧排列。
  Future<void> _showMergedCommentUsersDialog(
    ChapterCommentDisplayEntry entry,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final comments = [...entry.comments]
      ..sort((a, b) {
        final ta = _ChapterCommentsSheetState._parseCommentTime(a.createAt);
        final tb = _ChapterCommentsSheetState._parseCommentTime(b.createAt);
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1; // 无法解析的排到最后
        if (tb == null) return -1;
        return tb.compareTo(ta); // 从新到旧
      });

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        minHeight: MediaQuery.sizeOf(context).height / 3,
        maxHeight:
            MediaQuery.sizeOf(context).height *
            _ChapterCommentsSheetState._mergedCommentSheetMaxHeightFactor,
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
                    style: _buildCommentTimeStyle(tt, cs),
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
                                _ChapterCommentsSheetState._commentRowSpacing,
                            runSpacing:
                                _ChapterCommentsSheetState._commentRowSpacing,
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
    ChapterComment comment,
    AppLocalizations l10n,
    double maxWidth,
  ) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final name = comment.userName.trim();
    final displayName = name.isEmpty ? l10n.commentSettingsAnonymousUser : name;
    final userStyle = _buildCommentUserStyle(
      tt,
      cs,
      compact: true,
    )?.copyWith(color: cs.onSurface);
    final timeStyle = _buildCommentTimeStyle(
      tt,
      cs,
    )?.copyWith(color: cs.onSurfaceVariant);
    const avatarGap = 6.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (details) => _showCommentActions(
        content: comment.comment,
        comment: comment,
        canBlock: true,
        position: details.globalPosition,
      ),
      onSecondaryTapDown: (details) => _showCommentActions(
        content: comment.comment,
        comment: comment,
        canBlock: true,
        position: details.globalPosition,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth * 0.8),
        child: IntrinsicWidth(
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            decoration: _buildCommentCardDecoration(
              cs,
              brightness: Theme.of(context).brightness,
              highlightAsHot: false,
              withShadow: false,
              backgroundColor: cs.surfaceContainerHigh,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_showUserAvatar) ...[
                  _CommentAvatar(imageUrl: comment.userAvatar, size: 20),
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

  Future<void> _showCommentActionMenu(
    ChapterCommentDisplayEntry entry,
    Offset position,
  ) => _showCommentActions(
    content: entry.content,
    comment: entry.primaryComment,
    // 合并评论对应多个用户，屏蔽需在用户卡片上单独操作。
    canBlock: !entry.isMerged,
    position: position,
  );

  /// 评论操作菜单（长按 / 右键弹出），单个用户才提供屏蔽入口。
  Future<void> _showCommentActions({
    required String content,
    required ChapterComment comment,
    required bool canBlock,
    required Offset position,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    content = content.trim();
    if (content.isEmpty) return;

    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'copy',
          height: 40,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.copy_outlined, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Text(l10n.copyButton),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'plus_one',
          height: 40,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_comment_outlined, size: 18),
              SizedBox(width: AppSpacing.sm),
              Text('+1'),
            ],
          ),
        ),
        if (canBlock)
          PopupMenuItem<String>(
            value: 'block',
            height: 40,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.block_outlined, size: 18),
                const SizedBox(width: AppSpacing.sm),
                Text(l10n.chapterCommentsBlockUser),
              ],
            ),
          ),
      ],
    );

    if (!mounted || action == null) return;
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: content));
      if (!mounted) return;
      showToast(context, l10n.chapterCommentsCopied);
    } else if (action == 'plus_one') {
      await _plusOneComment(content);
    } else if (action == 'block') {
      await _blockCommentUser(comment);
    }
  }

  Future<void> _blockCommentUser(ChapterComment comment) async {
    final l10n = AppLocalizations.of(context)!;
    final name = comment.userName.trim();
    if (_user.commentBlockNoRemind) {
      await _user.blockCommentUser(comment.userId, name);
      if (!mounted) return;
      _setState(_rebuildGroupedEntries);
      showToast(context, l10n.chapterCommentsUserBlocked);
      return;
    }

    var noRemind = false;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(l10n.chapterCommentsBlockUser),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isEmpty
                    ? l10n.chapterCommentsBlockUnnamedConfirm
                    : l10n.chapterCommentsBlockNamedConfirm(name),
              ),
              const SizedBox(height: AppSpacing.sm),
              GestureDetector(
                onTap: () => setLocal(() => noRemind = !noRemind),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: Checkbox(
                        value: noRemind,
                        onChanged: (v) => setLocal(() => noRemind = v ?? false),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      l10n.chapterCommentsNoRemindAgain,
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancelButton),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.chapterCommentsBlock),
            ),
          ],
        ),
      ),
    );
    if (confirm != true || !mounted) return;
    if (noRemind) await _user.setCommentBlockNoRemind(true);
    await _user.blockCommentUser(comment.userId, name);
    if (!mounted) return;
    _setState(_rebuildGroupedEntries);
    showToast(context, l10n.chapterCommentsUserBlocked);
  }

  Future<void> _plusOneComment(String content) async {
    final l10n = AppLocalizations.of(context)!;
    if (!_user.isLoggedIn) {
      showToast(
        context,
        l10n.chapterCommentsLoginRequiredToPost,
        isError: true,
      );
      return;
    }

    final length = CommentText.lengthOf(content);
    if (length < CommentText.minLength || length > CommentText.maxLength) {
      showToast(
        context,
        l10n.chapterCommentsPlusOneLengthInvalid,
        isError: true,
      );
      return;
    }

    try {
      await _api.manga.postChapterComment(widget.chapterUuid, content);
      if (!mounted) return;
      showToast(context, l10n.chapterCommentsPlusOneSent);
      await _refreshFirstPage();
    } catch (e) {
      if (!mounted) return;
      await _showPostCommentErrorDialog(e);
    }
  }
}
