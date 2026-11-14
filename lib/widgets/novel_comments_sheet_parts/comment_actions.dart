part of '../novel_comments_sheet.dart';

extension _NovelCommentsActionsPart on _NovelCommentsSheetState {
  String _displayName(NovelComment comment) {
    final name = comment.userName.trim();
    return name.isEmpty
        ? AppLocalizations.of(context)!.commentSettingsAnonymousUser
        : name;
  }

  /// Surface the upstream text (code 210 keeps the whole body) instead of
  /// hiding it behind a generic label.
  String _errorMessage(Object? error, String fallback) =>
      novelErrorMessage(error, fallback: fallback);

  // ── 屏蔽过滤（与漫画评论区共用 UserManager 的屏蔽配置） ────────────────

  bool get _hasBlockFilters =>
      _user.commentBlockedUsers.isNotEmpty ||
      _user.commentBlockwords.isNotEmpty ||
      _user.commentBlockGroupSpam;

  bool _isCommentVisible(NovelComment comment) =>
      !_user.isCommentUserBlocked(comment.userId, comment.userName.trim()) &&
      !_user.isCommentBlockedByWord(comment.comment) &&
      !_user.isCommentGroupSpam(comment.comment);

  /// 主列表按屏蔽配置过滤后的可见评论；无任何屏蔽时直接复用原始列表。
  List<NovelComment> get _visibleComments => !_hasBlockFilters
      ? _comments.items
      : _comments.items.where(_isCommentVisible).toList(growable: false);

  /// 已加载评论中被屏蔽隐藏的条数，用于标题栏「显示数/总数|屏蔽数」。
  int get _blockedCount =>
      !_hasBlockFilters ? 0 : _comments.items.length - _visibleComments.length;

  /// 评论区计数文案，与漫画评论区一致：全部加载且无屏蔽时显示「N 条」；
  /// 有屏蔽时为「显示数/总数|屏蔽数」，屏蔽为 0 则不显示 |屏蔽数。
  String _buildCountLabel(AppLocalizations l10n) {
    final total = _comments.total;
    if (total <= 0) return '';
    final visibleCount = _visibleComments.length;
    final blocked = _blockedCount;
    final allLoaded = _comments.items.length >= total;
    if (allLoaded && blocked == 0) {
      return l10n.chapterCommentsTotalCount(total);
    }
    if (blocked > 0) {
      return l10n.chapterCommentsCountWithBlocked(visibleCount, total, blocked);
    }
    return '$visibleCount/$total';
  }

  // ── 评论长按操作菜单：复制 / +1 / 屏蔽用户（与漫画评论区一致） ──────────

  Future<void> _showCommentActionMenu(
    NovelComment comment, {
    NovelCommentDisplayEntry? entry,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final content = (entry?.content ?? comment.comment).trim();
    if (content.isEmpty) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      builder: (sheetContext) {
        final cs = Theme.of(sheetContext).colorScheme;
        final tt = Theme.of(sheetContext).textTheme;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      l10n.chapterCommentsActionTitle,
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: l10n.closeButton,
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: AppRadius.mdR,
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Text(
                    content,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodyMedium,
                  ),
                ),
                const SizedBox(height: 10),
                ListTile(
                  leading: const Icon(Icons.copy_outlined),
                  title: Text(l10n.copyButton),
                  onTap: () => Navigator.of(sheetContext).pop('copy'),
                ),
                ListTile(
                  leading: const Icon(Icons.add_comment_outlined),
                  title: const Text('+1'),
                  subtitle: Text(l10n.chapterCommentsPlusOneSubtitle),
                  onTap: () => Navigator.of(sheetContext).pop('plus_one'),
                ),
                if (entry?.isMerged != true)
                  ListTile(
                    leading: const Icon(Icons.block_outlined),
                    title: Text(l10n.chapterCommentsBlockUser),
                    subtitle: Text(
                      l10n.chapterCommentsHideUserComments(comment.userName),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.of(sheetContext).pop('block'),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || action == null) return;
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: content));
      if (!mounted) return;
      showToast(context, l10n.comicCommentCopied);
    } else if (action == 'plus_one') {
      await _plusOneComment(content);
    } else if (action == 'block') {
      await _blockCommentUser(comment);
    }
  }

  Future<void> _plusOneComment(String content) async {
    final l10n = AppLocalizations.of(context)!;
    if (!_user.isCopyLoggedIn) {
      await _login();
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
      await ref
          .read(novelApiProvider)
          .postComment(bookUuid: widget.bookUuid, content: content);
      if (!mounted) return;
      showToast(context, l10n.chapterCommentsPlusOneSent);
      unawaited(_comments.refresh());
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'novel_comments.plus_one',
        ),
      );
      if (mounted) {
        showToast(
          context,
          _errorMessage(e, l10n.novelCommentFailed),
          isError: true,
        );
      }
    }
  }

  Future<void> _blockCommentUser(NovelComment comment) async {
    final l10n = AppLocalizations.of(context)!;
    final name = comment.userName.trim();
    if (_user.commentBlockNoRemind) {
      await _user.blockCommentUser(comment.userId, name);
      if (!mounted) return;
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
                    : l10n.comicCommentBlockNamedConfirm(name),
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
    // UserManager 的变更通知会触发 _rebuild，按新黑名单重过滤。
    showToast(context, l10n.chapterCommentsUserBlocked);
  }

  // ── Inline replies (comic-sheet behavior) ──────────────────────────────
}
