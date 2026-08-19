import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';

import '../api/api_client.dart';
import '../l10n/app_localizations.dart';
import '../models/comic_comment.dart';
import '../models/user_manager.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../utils/comment_text.dart';
import '../utils/network_error.dart';
import '../utils/time_format.dart';
import '../utils/toast.dart';
import '../widgets/text_controller_scope.dart';
import 'chapter_comments/comment_paging.dart';
import 'chapter_comments/comment_scroll_behavior.dart';
import 'chapter_comments_sheet.dart'
    show CommentSettingsPanel, buildCommentBodyStyle;

class ComicCommentsSheet extends StatefulWidget {
  final String comicId;
  final String comicName;

  const ComicCommentsSheet({
    super.key,
    required this.comicId,
    required this.comicName,
  });

  @override
  State<ComicCommentsSheet> createState() => _ComicCommentsSheetState();
}

class _ComicCommentsSheetState extends State<ComicCommentsSheet>
    with CommentScrollBehavior<ComicCommentsSheet> {
  static const _replyPageSize = 3;
  static const _listBottomPadding = 80.0;

  final _api = ApiClient();
  final _user = UserManager();

  List<ComicComment> _comments = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _total = 0;
  final Map<int, _ComicReplyState> _replyStates = {};

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  Future<void> _loadComments({bool loadMore = false}) async {
    if (loadMore) {
      if (_loading || _loadingMore || _comments.length >= _total) return;
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final data = await _api.manga.getComicComments(
        widget.comicId,
        offset: loadMore ? _comments.length : 0,
      );
      if (!mounted) return;

      final mergedComments =
          (loadMore
                  ? appendDedupedById(_comments, data.list, (c) => c.id)
                  : data.list)
              .where(
                (item) => !_user.isCommentUserBlocked(
                  item.userId,
                  item.userName.trim(),
                ),
              )
              .toList();

      setState(() {
        _comments = mergedComments;
        _total = data.total;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        tryLoadMoreWhenNearBottom();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = e.toString();
      });
    }
  }

  @override
  bool get canLoadMore =>
      !_loading && !_loadingMore && _comments.length < _total;

  @override
  void loadMoreComments() => _loadComments(loadMore: true);

  _ComicReplyState _replyStateOf(int commentId) =>
      _replyStates[commentId] ?? const _ComicReplyState();

  Future<void> _toggleReplies(ComicComment comment) async {
    final currentState = _replyStateOf(comment.id);
    if (currentState.expanded) {
      setState(() {
        _replyStates[comment.id] = currentState.copyWith(
          expanded: false,
          error: null,
        );
      });
      return;
    }

    setState(() {
      _replyStates[comment.id] = currentState.copyWith(
        expanded: true,
        error: null,
      );
    });

    if (currentState.replies.isEmpty && !currentState.loading) {
      await _loadReplies(comment);
    }
  }

  Future<void> _loadReplies(
    ComicComment comment, {
    bool loadMore = false,
  }) async {
    final currentState = _replyStateOf(comment.id);
    final knownTotal = currentState.total > 0
        ? currentState.total
        : comment.replyCount;

    if (loadMore) {
      if (currentState.loading || currentState.loadingMore) return;
      if (currentState.replies.length >= knownTotal) return;
    } else if (currentState.loading) {
      return;
    }

    setState(() {
      _replyStates[comment.id] = currentState.copyWith(
        expanded: true,
        loading: !loadMore,
        loadingMore: loadMore,
        error: null,
      );
    });

    try {
      final data = await _api.manga.getComicComments(
        widget.comicId,
        replyId: comment.id.toString(),
        limit: _replyPageSize,
        offset: loadMore ? currentState.replies.length : 0,
      );
      if (!mounted) return;

      final mergedReplies =
          (loadMore
                  ? [
                      ...currentState.replies,
                      ...data.list.where(
                        (item) => !currentState.replies.any(
                          (existing) => existing.id == item.id,
                        ),
                      ),
                    ]
                  : data.list)
              .where(
                (item) => !_user.isCommentUserBlocked(
                  item.userId,
                  item.userName.trim(),
                ),
              )
              .toList();

      // 回复按时间正序（从旧到新）
      mergedReplies.sort((a, b) => a.createAt.compareTo(b.createAt));

      final latestState = _replyStateOf(comment.id);

      setState(() {
        _replyStates[comment.id] = latestState.copyWith(
          loading: false,
          loadingMore: false,
          replies: mergedReplies,
          total: data.total,
          error: null,
        );
      });
    } catch (e) {
      if (!mounted) return;
      final latestState = _replyStateOf(comment.id);
      setState(() {
        _replyStates[comment.id] = latestState.copyWith(
          loading: false,
          loadingMore: false,
          error: e.toString(),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final width = MediaQuery.sizeOf(context).width;
    final height = MediaQuery.sizeOf(context).height * 0.85;

    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                        borderRadius: AppRadius.fullR,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.comicCommentTitle,
                                  style: tt.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  widget.comicName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: tt.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            _total > 0
                                ? (_comments.length >= _total
                                      ? l10n.chapterCommentsTotalCount(_total)
                                      : '${_comments.length}/$_total')
                                : '',
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          IconButton(
                            onPressed: _showCommentSettings,
                            tooltip: l10n.comicCommentSettingsTooltip,
                            icon: const Icon(Icons.tune),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: cs.outlineVariant),
                    Expanded(child: _buildBody(context, cs, tt)),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: ValueListenableBuilder<bool>(
                valueListenable: showFloatingButtons,
                builder: (context, showFloatingButtons, child) {
                  final buttonStyle = FilledButton.styleFrom(
                    backgroundColor: cs.primaryContainer,
                    foregroundColor: cs.onPrimaryContainer,
                    elevation: 6,
                    shadowColor: AppShadows.floatingTint(0.22),
                    minimumSize: const Size(0, 52),
                    maximumSize: const Size.fromHeight(52),
                    fixedSize: const Size.fromHeight(52),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.smR),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  );

                  return AnimatedSlide(
                    offset: showFloatingButtons
                        ? Offset.zero
                        : const Offset(0, 1.2),
                    curve: Curves.easeInOutCubic,
                    duration: const Duration(milliseconds: 260),
                    child: AnimatedOpacity(
                      opacity: showFloatingButtons ? 1.0 : 0.0,
                      curve: Curves.easeInOutCubic,
                      duration: const Duration(milliseconds: 260),
                      child: SafeArea(
                        top: false,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FilledButton.icon(
                              style: buttonStyle,
                              onPressed: _showPostCommentDialog,
                              icon: const Icon(Icons.comment_outlined),
                              label: Text(l10n.chapterCommentsComment),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            SizedBox.square(
                              dimension: 52,
                              child: FilledButton(
                                style: buttonStyle.copyWith(
                                  padding: const WidgetStatePropertyAll(
                                    EdgeInsets.zero,
                                  ),
                                  minimumSize: const WidgetStatePropertyAll(
                                    Size.square(52),
                                  ),
                                  maximumSize: const WidgetStatePropertyAll(
                                    Size.square(52),
                                  ),
                                ),
                                onPressed: () =>
                                    Navigator.of(context).maybePop(),
                                child: const Center(
                                  child: Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme cs, TextTheme tt) {
    final l10n = AppLocalizations.of(context)!;
    if (_loading && _comments.isEmpty) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, _listBottomPadding),
        itemCount: 6,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, _) => const _ComicCommentSkeleton(),
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
                l10n.comicCommentLoadFailed,
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
                onPressed: _loadComments,
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
              l10n.comicCommentEmptySubtitle,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: handleScrollNotification,
      child: ListView.separated(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, _listBottomPadding),
        itemCount: _comments.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, index) {
          if (index == _comments.length && _loadingMore) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: ExpressiveLoadingIndicator()),
            );
          }

          final comment = _comments[index];
          return _buildCommentCard(cs, tt, comment);
        },
      ),
    );
  }

  Widget _buildCommentCard(ColorScheme cs, TextTheme tt, ComicComment comment) {
    final brightness = Theme.of(context).brightness;
    final replyState = _replyStateOf(comment.id);
    final canExpandReplies = comment.replyCount > 0;
    final user = UserManager();
    final showAvatar = user.commentShowAvatar;
    final showCommentTime = user.commentShowTime;
    final userStyle = tt.labelMedium?.copyWith(
      color: cs.onSurfaceVariant.withValues(alpha: 0.78),
      fontWeight: FontWeight.w500,
    );
    final timeStyle = tt.labelSmall?.copyWith(
      color: cs.onSurfaceVariant.withValues(alpha: 0.72),
      fontWeight: FontWeight.w400,
    );
    final bodyStyle = buildCommentBodyStyle(
      tt,
      compact: false,
      fontScale: user.commentFontScale,
    );

    return GestureDetector(
      onTap: () => _showPostCommentDialog(replyTo: comment),
      onLongPress: () => _showCommentActionMenu(comment),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: AppRadius.lgR,
          border: Border.all(
            color: cs.outlineVariant.withValues(
              alpha: brightness == Brightness.dark ? 0.22 : 0.45,
            ),
            width: 0.6,
          ),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withValues(
                alpha: brightness == Brightness.dark ? 0.30 : 0.14,
              ),
              blurRadius: brightness == Brightness.dark ? 12 : 14,
              spreadRadius: brightness == Brightness.dark ? 0 : -1,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (showAvatar) ...[
                  _ComicCommentAvatar(imageUrl: comment.userAvatar, size: 28),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: Text(
                    comment.userName.trim().isEmpty
                        ? AppLocalizations.of(
                            context,
                          )!.commentSettingsAnonymousUser
                        : comment.userName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: userStyle,
                  ),
                ),
                if (showCommentTime) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    TimeFormat.relativeOf(
                      comment.createAt,
                      AppLocalizations.of(context)!,
                    ),
                    style: timeStyle,
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _buildCommentText(
              comment,
              bodyStyle: bodyStyle,
              backgroundColor: cs.surfaceContainerLow,
            ),
            if (canExpandReplies) ...[
              const SizedBox(height: 10),
              _buildCommentActions(cs, tt, comment, replyState),
            ],
            if (canExpandReplies && replyState.expanded)
              _buildReplySection(cs, tt, comment, replyState),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentActions(
    ColorScheme cs,
    TextTheme tt,
    ComicComment comment,
    _ComicReplyState replyState,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final actionStyle = tt.bodyMedium?.copyWith(
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
                  ? l10n.comicCommentCollapseReplies
                  : l10n.comicCommentExpandReplies(comment.replyCount),
              style: actionStyle,
            ),
          ],
        ),
      ),
    );
  }

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
        : (totalReplies < _replyPageSize ? totalReplies : _replyPageSize);

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
      fontScale: user.commentFontScale,
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
                    color: cs.surfaceContainerLow,
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

  void _applyBlockedFilter() {
    setState(() {
      _comments = _comments
          .where(
            (c) => !_user.isCommentUserBlocked(c.userId, c.userName.trim()),
          )
          .toList();
      // 已展开的回复也需过滤
      for (final id in _replyStates.keys.toList()) {
        final s = _replyStates[id]!;
        if (s.replies.isEmpty) continue;
        final filtered = s.replies
            .where(
              (r) => !_user.isCommentUserBlocked(r.userId, r.userName.trim()),
            )
            .toList();
        if (filtered.length != s.replies.length) {
          _replyStates[id] = s.copyWith(replies: filtered);
        }
      }
    });
  }

  void _showCommentSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      builder: (sheetContext) {
        final sheetSize = MediaQuery.sizeOf(sheetContext);
        return Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: sheetSize.width,
            height: sheetSize.height * 0.85,
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
                  setState(() {});
                  _user.setCommentShowAvatar(v);
                },
                onShowUserNameChanged: (v) {
                  if (!mounted) return;
                  setState(() {});
                  _user.setCommentShowUserName(v);
                },
                onShowCommentTimeChanged: (v) {
                  if (!mounted) return;
                  setState(() {});
                  _user.setCommentShowTime(v);
                },
                onFontScaleChanged: (v) {
                  if (!mounted) return;
                  setState(() {});
                  _user.setCommentFontScale(v);
                },
                onPreloadChanged: (v) => _user.setCommentPreload(v),
                onAutoLoadAllChanged: (v) => _user.setCommentAutoLoadAll(v),
              ),
            ),
          ),
        );
      },
    );
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
          setState(() {
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

  Widget _buildCommentText(
    ComicComment comment, {
    required TextStyle? bodyStyle,
    required Color backgroundColor,
  }) {
    return _ExpandableCommentText(
      key: ValueKey('comic-comment-text-${comment.id}'),
      text: comment.comment,
      style: bodyStyle,
      backgroundColor: backgroundColor,
    );
  }
}

class _ComicReplyState {
  static const _unset = Object();

  final bool expanded;
  final bool loading;
  final bool loadingMore;
  final List<ComicComment> replies;
  final int total;
  final String? error;

  const _ComicReplyState({
    this.expanded = false,
    this.loading = false,
    this.loadingMore = false,
    this.replies = const [],
    this.total = 0,
    this.error,
  });

  _ComicReplyState copyWith({
    bool? expanded,
    bool? loading,
    bool? loadingMore,
    List<ComicComment>? replies,
    int? total,
    Object? error = _unset,
  }) {
    return _ComicReplyState(
      expanded: expanded ?? this.expanded,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      replies: replies ?? this.replies,
      total: total ?? this.total,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }
}

class _ComicCommentAvatar extends StatelessWidget {
  final String imageUrl;
  final double size;

  const _ComicCommentAvatar({required this.imageUrl, required this.size});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: imageUrl.isEmpty
            ? ColoredBox(
                color: cs.surfaceContainerHighest,
                child: Icon(
                  Icons.person,
                  size: size * 0.5,
                  color: cs.onSurfaceVariant,
                ),
              )
            : CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (_, _) => ColoredBox(
                  color: cs.surfaceContainerHighest,
                  child: Icon(
                    Icons.person,
                    size: size * 0.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                errorWidget: (_, _, _) => ColoredBox(
                  color: cs.surfaceContainerHighest,
                  child: Icon(
                    Icons.person,
                    size: size * 0.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
      ),
    );
  }
}

class _ExpandableCommentText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Color backgroundColor;

  const _ExpandableCommentText({
    super.key,
    required this.text,
    required this.style,
    required this.backgroundColor,
  });

  @override
  State<_ExpandableCommentText> createState() => _ExpandableCommentTextState();
}

class _ExpandableCommentTextState extends State<_ExpandableCommentText> {
  static const _maxLines = 3;
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant _ExpandableCommentText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _expanded = false;
    }
  }

  bool _isTextOverflowing(BuildContext context, double maxWidth) {
    if (maxWidth <= 0 || !maxWidth.isFinite) return false;

    final textPainter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      textDirection: Directionality.of(context),
      maxLines: _maxLines,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: maxWidth);

    return textPainter.didExceedMaxLines;
  }

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final baseFontSize = widget.style?.fontSize ?? 14.0;
    final hintStyle = widget.style?.copyWith(
      color: cs.primary,
      fontWeight: FontWeight.w700,
      fontSize: baseFontSize > 13 ? baseFontSize - 1 : baseFontSize,
      height: 1.2,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isOverflowing = _isTextOverflowing(context, constraints.maxWidth);

        if (!isOverflowing) {
          return Text(widget.text, style: widget.style);
        }

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: AppRadius.mdR,
            onTap: _toggleExpanded,
            child: AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    children: [
                      Text(
                        widget.text,
                        maxLines: _expanded ? null : _maxLines,
                        style: widget.style,
                      ),
                      if (!_expanded)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            child: Container(
                              height: 56,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    widget.backgroundColor.withValues(alpha: 0),
                                    widget.backgroundColor.withValues(
                                      alpha: 0.96,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (!_expanded) ...[
                    const SizedBox(height: AppSpacing.sm),
                    IgnorePointer(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: widget.backgroundColor,
                            borderRadius: AppRadius.fullR,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                l10n.comicCommentExpandFullText,
                                style: hintStyle,
                              ),
                              const SizedBox(width: 2),
                              Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 16,
                                color: cs.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (_expanded) ...[
                    const SizedBox(height: AppSpacing.sm),
                    IgnorePointer(
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              l10n.chapterCommentsCollapse,
                              style: hintStyle,
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.keyboard_arrow_up_rounded,
                              size: 16,
                              color: cs.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ComicCommentSkeleton extends StatelessWidget {
  const _ComicCommentSkeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: AppRadius.lgR,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.2),
                    borderRadius: AppRadius.xsR,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Container(
                width: 48,
                height: 12,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.2),
                  borderRadius: AppRadius.xsR,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            height: 14,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.2),
              borderRadius: AppRadius.xsR,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: MediaQuery.sizeOf(context).width * 0.55,
            height: 14,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.2),
              borderRadius: AppRadius.xsR,
            ),
          ),
        ],
      ),
    );
  }
}

class _ComicReplySkeleton extends StatelessWidget {
  const _ComicReplySkeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final placeholderColor = cs.onSurfaceVariant.withValues(alpha: 0.2);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: placeholderColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 86,
                    height: 12,
                    decoration: BoxDecoration(
                      color: placeholderColor,
                      borderRadius: AppRadius.xsR,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 40,
                    height: 10,
                    decoration: BoxDecoration(
                      color: placeholderColor,
                      borderRadius: AppRadius.xsR,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: double.infinity,
                height: 12,
                decoration: BoxDecoration(
                  color: placeholderColor,
                  borderRadius: AppRadius.xsR,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: MediaQuery.sizeOf(context).width * 0.36,
                height: 12,
                decoration: BoxDecoration(
                  color: placeholderColor,
                  borderRadius: AppRadius.xsR,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
