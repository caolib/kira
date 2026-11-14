part of '../novel_comments_sheet.dart';

extension _NovelCommentsViewPart on _NovelCommentsSheetState {
  Widget _buildList(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return RefreshIndicator(
      onRefresh: _comments.refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onListScrollNotification,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (_comments.loading && _comments.items.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                sliver: SliverList.separated(
                  itemCount: 6,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, _) => const CommentSkeleton(),
                ),
              )
            else if (_comments.error != null && _comments.items.isEmpty)
              SliverErrorRetryView(
                message: _errorMessage(
                  _comments.error,
                  l10n.novelCommentsFailed,
                ),
                onRetry: _comments.refresh,
              )
            else if (_comments.items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: NovelEmptyView(
                  message: l10n.novelNoComments,
                  icon: Icons.chat_bubble_outline,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                sliver: Builder(
                  builder: (context) {
                    // 屏蔽过滤在构建时套用，配置变化经 _rebuild 自动刷新。
                    final entries = groupNovelComments(
                      _visibleComments,
                      replyCountOf: (comment) =>
                          _replyCount(comment, _replyStateOf(comment.id)),
                      mergeEnabled: widget.replyId == null,
                    );
                    return SliverList.separated(
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return entry.isMerged
                            ? _buildMergedCommentCard(context, entry)
                            : _buildCommentCard(context, entry.primaryComment);
                      },
                    );
                  },
                ),
              ),
            if (_comments.items.isNotEmpty && _comments.hasMore)
              SliverToBoxAdapter(
                child: _comments.error != null
                    ? LoadMoreFooter(
                        loading: false,
                        onPressed: _comments.loadMore,
                        label: l10n.novelLoadMoreFailed,
                        detail: _errorMessage(_comments.error, ''),
                      )
                    : _comments.loading
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: ExpressiveLoadingIndicator()),
                      )
                    : const SizedBox(height: 32),
              ),
            SliverToBoxAdapter(child: SizedBox(height: _listBottomPadding)),
          ],
        ),
      ),
    );
  }

  /// 向下滚动隐藏，向上滚动或抵达底部时恢复。
  Widget _buildFloatingButtons(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final squareStyle = FilledButton.styleFrom(
      backgroundColor: cs.secondaryContainer,
      foregroundColor: cs.onSecondaryContainer,
      elevation: 6,
      shadowColor: AppShadows.floatingTint(0.22),
      minimumSize: const Size.square(52),
      maximumSize: const Size.square(52),
      fixedSize: const Size.square(52),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.smR),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Positioned(
      right: AppSpacing.lg,
      bottom: AppSpacing.lg,
      child: ValueListenableBuilder<bool>(
        valueListenable: _showFloatingButtons,
        builder: (context, visible, child) {
          final duration = adaptiveDuration(
            context,
            const Duration(milliseconds: 220),
          );
          return ExcludeFocus(
            excluding: !visible,
            child: IgnorePointer(
              ignoring: !visible,
              child: ExcludeSemantics(
                excluding: !visible,
                child: AnimatedSlide(
                  offset: visible ? Offset.zero : const Offset(0, 1.2),
                  curve: Curves.easeInOutCubic,
                  duration: duration,
                  child: AnimatedOpacity(
                    key: const ValueKey(
                      'novel-comment-floating-buttons-opacity',
                    ),
                    opacity: visible ? 1 : 0,
                    duration: duration,
                    child: child!,
                  ),
                ),
              ),
            ),
          );
        },
        child: SafeArea(
          top: false,
          child: Row(
            key: _floatingButtonsKey,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FilledButton.icon(
                key: const ValueKey('novel-comment-post-action'),
                style: squareStyle.copyWith(
                  backgroundColor: WidgetStatePropertyAll(cs.primary),
                  foregroundColor: WidgetStatePropertyAll(cs.onPrimary),
                  fixedSize: const WidgetStatePropertyAll(Size.fromHeight(52)),
                  minimumSize: const WidgetStatePropertyAll(Size(0, 52)),
                  maximumSize: const WidgetStatePropertyAll(
                    Size.fromHeight(52),
                  ),
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 14),
                  ),
                ),
                onPressed: _posting || !widget.allowPosting
                    ? null
                    : () => _showPostDialog(),
                icon: const Icon(Icons.comment_outlined, size: AppIconSize.lg),
                label: Text(l10n.chapterCommentsComment),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 52,
                    child: Tooltip(
                      message: l10n.backToTop,
                      child: FilledButton(
                        key: const ValueKey('novel-comment-scroll-top-action'),
                        style: squareStyle,
                        onPressed: _scrollToTop,
                        child: const Icon(Icons.arrow_upward_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox.square(
                    dimension: 52,
                    child: Tooltip(
                      message: l10n.closeButton,
                      child: FilledButton(
                        key: const ValueKey('novel-comment-close-action'),
                        style: squareStyle,
                        onPressed: () => Navigator.of(context).maybePop(),
                        child: const Icon(Icons.keyboard_arrow_down_rounded),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCommentCard(BuildContext context, NovelComment comment) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final showTime = _settings.showTime && comment.createAt.isNotEmpty;
    final showHeader =
        _settings.showAvatar || _settings.showUserName || showTime;
    final replyState = _replyStateOf(comment.id);
    final canExpandReplies =
        _replyCount(comment, replyState) > 0 || replyState.expanded;
    final displayName = comment.userName.trim().isEmpty
        ? l10n.commentSettingsAnonymousUser
        : comment.userName;

    return Container(
      key: ValueKey('novel-comment-${comment.id}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: AppRadius.lgR,
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.6),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 只让主评论内容响应“回复楼主”；回复子树不再被父级
          // GestureDetector 包住，避免点击楼中楼时错误地使用楼主 id。
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showPostDialog(replyTo: comment),
            onLongPress: () => _showCommentActionMenu(comment),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showHeader) ...[
                  Row(
                    children: [
                      if (_settings.showAvatar) ...[
                        AccountAvatar(avatar: comment.userAvatar, radius: 14),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                      Expanded(
                        child: _settings.showUserName
                            ? Text(
                                displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tt.labelMedium?.copyWith(
                                  color: cs.onSurfaceVariant.withValues(
                                    alpha: 0.78,
                                  ),
                                  fontWeight: FontWeight.w500,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      if (showTime) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            TimeFormat.relativeOf(comment.createAt, l10n),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant.withValues(
                                alpha: 0.72,
                              ),
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                ExpandableCommentText(
                  key: ValueKey('novel-comment-text-${comment.id}'),
                  text: comment.comment,
                  style: buildCommentBodyStyle(tt, compact: false),
                  backgroundColor: cs.surfaceContainerHigh,
                ),
              ],
            ),
          ),
          if (canExpandReplies) ...[
            const SizedBox(height: 10),
            _buildExpandControl(context, comment, replyState),
          ],
          if (canExpandReplies && replyState.expanded)
            _buildReplySection(context, comment, replyState),
        ],
      ),
    );
  }

  /// 展开/收起控制，样式与漫画评论区一致。
  Widget _buildExpandControl(
    BuildContext context,
    NovelComment comment,
    _NovelReplyState replyState,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final actionStyle = theme.textTheme.bodyMedium?.copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w500,
    );
    return InkWell(
      borderRadius: AppRadius.fullR,
      onTap: () => _toggleReplies(comment),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              replyState.expanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 2),
            Text(
              replyState.expanded
                  ? l10n.novelCommentCollapseReplies
                  : l10n.novelCommentExpandReplies(
                      _replyCount(comment, replyState),
                    ),
              style: actionStyle,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplySection(
    BuildContext context,
    NovelComment comment,
    _NovelReplyState replyState,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final replies = replyState.replies;
    final totalReplies = _replyCount(comment, replyState);
    final skeletonCount = totalReplies.clamp(
      1,
      _NovelCommentsSheetState._replyPageSize,
    );
    return Container(
      margin: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (replyState.loading && replies.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Column(
                children: [
                  for (var index = 0; index < skeletonCount; index++) ...[
                    if (index > 0) const SizedBox(height: AppSpacing.md),
                    const CommentReplySkeleton(),
                  ],
                ],
              ),
            ),
          if (replyState.error != null && replies.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _errorMessage(
                        replyState.error,
                        l10n.novelCommentReplyLoadFailed,
                      ),
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
                l10n.novelCommentEmptyReplies,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          for (var i = 0; i < replies.length; i++)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Column(
                children: [
                  _buildReplyItem(context, replies[i], comment),
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
                label: Text(l10n.novelCommentRetryLoadMoreReplies),
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
                  l10n.novelCommentLoadMoreReplies(
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
    BuildContext context,
    NovelComment reply,
    NovelComment parentComment,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    // 楼中楼回复目标：与漫画侧一致，回复楼主（OP）时不显示「→ 楼主」。
    final isReplyToOp = _isReplyToOp(reply, parentComment);
    final parentUserName = reply.parentUserName?.trim() ?? '';
    final showReplyTarget = !isReplyToOp && parentUserName.isNotEmpty;
    final showTime = _settings.showTime && reply.createAt.isNotEmpty;
    final displayName = reply.userName.trim().isEmpty
        ? l10n.commentSettingsAnonymousUser
        : reply.userName;
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
      behavior: HitTestBehavior.opaque,
      onTap: () => _showPostDialog(replyTo: reply),
      onLongPress: () => _showCommentActionMenu(reply),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_settings.showAvatar) ...[
            AccountAvatar(avatar: reply.userAvatar, radius: 11),
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
                              displayName,
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
                    if (showTime) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        TimeFormat.relativeOf(reply.createAt, l10n),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: timeStyle,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                ExpandableCommentText(
                  key: ValueKey('novel-comment-text-${reply.id}'),
                  text: reply.comment,
                  style: bodyStyle,
                  backgroundColor: cs.surfaceContainerHigh,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _isReplyToOp(NovelComment reply, NovelComment parentComment) {
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
