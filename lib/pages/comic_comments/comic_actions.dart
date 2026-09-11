part of '../comic_comments_sheet.dart';

extension _ComicActions on _ComicCommentsSheetState {
  /// 顶级评论操作菜单（支持合并评论）。
  Future<void> _showCommentActionMenuForEntry(
    ComicCommentDisplayEntry entry,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final content = entry.content.trim();
    if (content.isEmpty) return;
    final comment = entry.primaryComment;
    final canBlock = !entry.isMerged;

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
                    color: _comicCommentCardInsetColor(cs),
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
                if (canBlock)
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

  Future<void> _showCommentActionMenu(ComicComment comment) async {
    final l10n = AppLocalizations.of(context)!;
    final content = comment.comment.trim();
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
                    color: _comicCommentCardInsetColor(cs),
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

  Future<void> _blockCommentUser(ComicComment comment) async {
    final l10n = AppLocalizations.of(context)!;
    final name = comment.userName.trim();
    if (_user.commentBlockNoRemind) {
      await _user.blockCommentUser(comment.userId, name);
      if (!mounted) return;
      _applyBlockedFilter();
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
    _applyBlockedFilter();
    showToast(context, l10n.chapterCommentsUserBlocked);
  }

  Future<void> _showCommentSettings() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      builder: (sheetContext) {
        final sheetSize = MediaQuery.sizeOf(sheetContext);
        // 键盘弹出时面板顶边保持不动、底边抬到输入法上方，否则输入法
        // 会盖住面板底部的屏蔽词输入框。
        final keyboard = MediaQuery.viewInsetsOf(sheetContext).bottom;
        final sheetHeight = (sheetSize.height * 0.85 - keyboard)
            .clamp(0.0, sheetSize.height)
            .toDouble();
        return Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(bottom: keyboard),
            child: SizedBox(
              width: sheetSize.width,
              height: sheetHeight,
              child: ExcludeSemantics(
                child: CommentSettingsPanel(
                  isChapterComments: false,
                  useCompactLayout: _user.commentCompactLayout,
                  showUserAvatar: _user.commentShowAvatar,
                  showUserName: _user.commentShowUserName,
                  showCommentTime: _user.commentShowTime,
                  commentFontScale: _user.commentFontScale,
                  commentPreload: _user.commentPreload,
                  commentAutoLoadAll: _user.commentAutoLoadAll,
                  onLayoutChanged: (_) {},
                  onShowAvatarChanged: (v) {
                    if (!mounted) return;
                    _setState(() {});
                    _user.setCommentShowAvatar(v);
                  },
                  onShowUserNameChanged: (v) {
                    if (!mounted) return;
                    _setState(() {});
                    _user.setCommentShowUserName(v);
                  },
                  onShowCommentTimeChanged: (v) {
                    if (!mounted) return;
                    _setState(() {});
                    _user.setCommentShowTime(v);
                  },
                  onFontScaleChanged: (v) {
                    if (!mounted) return;
                    _setState(() {});
                    _user.setCommentFontScale(v);
                  },
                  onPreloadChanged: (v) => _user.setCommentPreload(v),
                  onAutoLoadAllChanged: (v) => _user.setCommentAutoLoadAll(v),
                ),
              ),
            ),
          ),
        );
      },
    );
    if (!mounted) return;
    // 编辑屏蔽词/屏蔽用户后，重新过滤已加载的评论。
    _applyBlockedFilter();
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
      await _api.manga.postComicComment(widget.comicId, content);
      if (!mounted) return;
      showToast(context, l10n.chapterCommentsPlusOneSent);
      unawaited(_loadComments());
    } catch (e) {
      if (!mounted) return;
      showToast(context, NetworkError.message(e, l10n: l10n), isError: true);
    }
  }

  Future<void> _showPostCommentDialog({ComicComment? replyTo}) async {
    final l10n = AppLocalizations.of(context)!;
    if (!_user.isLoggedIn) {
      showToast(
        context,
        l10n.chapterCommentsLoginRequiredToPost,
        isError: true,
      );
      return;
    }

    var submitting = false;
    String? errorText;

    final isReply = replyTo != null;
    final title = isReply
        ? l10n.comicCommentReplyTitle(replyTo.userName)
        : l10n.chapterCommentsPostTitle;
    final hintText = isReply
        ? l10n.comicCommentReplyHint(replyTo.userName)
        : l10n.comicCommentPostHint;

    Future<void> submit(
      BuildContext dialogContext,
      StateSetter setLocal,
      TextEditingController controller,
    ) async {
      final content = controller.text.trim();
      final length = CommentText.lengthOf(content);
      if (length < CommentText.minLength || length > CommentText.maxLength) {
        setLocal(() => errorText = l10n.chapterCommentsLengthRange);
        return;
      }

      setLocal(() {
        submitting = true;
        errorText = null;
      });

      try {
        await _api.manga.postComicComment(
          widget.comicId,
          content,
          replyId: isReply ? replyTo.id : null,
        );
        if (!mounted) return;
        if (dialogContext.mounted) {
          Navigator.of(dialogContext).pop();
        }
        showToast(
          context,
          isReply ? l10n.comicCommentReplyPosted : l10n.chapterCommentsPosted,
        );
        if (isReply) {
          final index = _comments.indexWhere((c) => c.id == replyTo.id);
          if (index >= 0) {
            _comments[index] = ComicComment(
              id: replyTo.id,
              createAt: replyTo.createAt,
              userId: replyTo.userId,
              userName: replyTo.userName,
              userAvatar: replyTo.userAvatar,
              comment: replyTo.comment,
              replyCount: replyTo.replyCount + 1,
              parentId: replyTo.parentId,
              parentUserId: replyTo.parentUserId,
              parentUserName: replyTo.parentUserName,
            );
          }
          final currentState = _replyStateOf(replyTo.id);
          _setState(() {
            _replyStates[replyTo.id] = currentState.copyWith(
              expanded: true,
              total: currentState.total > 0 ? currentState.total + 1 : 0,
            );
          });
          unawaited(
            _loadReplies(
              _comments.firstWhere(
                (c) => c.id == replyTo.id,
                orElse: () => replyTo,
              ),
            ),
          );
        } else {
          unawaited(_loadComments());
        }
      } catch (e) {
        if (!dialogContext.mounted) return;
        setLocal(() {
          submitting = false;
          errorText = NetworkError.message(e, l10n: l10n);
        });
      }
    }

    // 控制器交给 TextControllerScope 托管：弹窗退出动画期间子树仍会重建，
    // 提前 dispose 会命中 “used after being disposed” 断言。
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return TextControllerScope(
          builder: (dialogContext, controller) {
            return StatefulBuilder(
              builder: (dialogContext, setLocal) {
                final length = CommentText.lengthOf(controller.text);
                final canSubmit =
                    !submitting &&
                    length >= CommentText.minLength &&
                    length <= CommentText.maxLength;
                return AlertDialog(
                  title: Text(title),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (isReply) ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerLow,
                              borderRadius: AppRadius.mdR,
                            ),
                            child: Text(
                              replyTo.comment,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        TextField(
                          controller: controller,
                          autofocus: true,
                          enabled: !submitting,
                          minLines: 3,
                          maxLines: 6,
                          maxLength: CommentText.maxLength,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(200),
                          ],
                          textInputAction: TextInputAction.newline,
                          decoration: InputDecoration(
                            hintText: hintText,
                            helperText: l10n.chapterCommentsLengthHelper,
                            errorText: errorText,
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (_) => setLocal(() => errorText = null),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: submitting
                          ? null
                          : () => Navigator.of(dialogContext).pop(),
                      child: Text(l10n.cancelButton),
                    ),
                    FilledButton(
                      onPressed: canSubmit
                          ? () => submit(dialogContext, setLocal, controller)
                          : null,
                      child: submitting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              isReply
                                  ? l10n.comicCommentReplyButton
                                  : l10n.chapterCommentsPublish,
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}
