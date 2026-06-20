import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/comic_comment.dart';
import '../models/user_manager.dart';
import '../utils/time_format.dart';

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

class _ComicCommentsSheetState extends State<ComicCommentsSheet> {
  static const _pageSize = 10;
  static const _replyPageSize = 3;
  static const _loadMoreThreshold = 240.0;
  static const _listBottomPadding = 32.0;

  final _api = ApiClient();
  final _scrollController = ScrollController();

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

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
      final data = await _api.getComicComments(
        widget.comicId,
        limit: _pageSize,
        offset: loadMore ? _comments.length : 0,
      );
      if (!mounted) return;

      final mergedComments = loadMore
          ? [
              ..._comments,
              ...data.list.where(
                (item) => !_comments.any((existing) => existing.id == item.id),
              ),
            ]
          : data.list;

      setState(() {
        _comments = mergedComments;
        _total = data.total;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _tryLoadMoreWhenNearBottom();
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

  bool _handleScrollNotification(ScrollNotification notification) {
    _tryLoadMoreWhenNearBottom(metrics: notification.metrics);
    return false;
  }

  void _tryLoadMoreWhenNearBottom({ScrollMetrics? metrics}) {
    if (_loading || _loadingMore || _comments.length >= _total) return;
    final currentMetrics =
        metrics ??
        (_scrollController.hasClients ? _scrollController.position : null);
    if (currentMetrics == null) return;
    if (currentMetrics.extentAfter <= _loadMoreThreshold) {
      _loadComments(loadMore: true);
    }
  }

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
      final data = await _api.getComicComments(
        widget.comicId,
        replyId: comment.id.toString(),
        limit: _replyPageSize,
        offset: loadMore ? currentState.replies.length : 0,
      );
      if (!mounted) return;

      final mergedReplies = loadMore
          ? [
              ...currentState.replies,
              ...data.list.where(
                (item) => !currentState.replies.any(
                  (existing) => existing.id == item.id,
                ),
              ),
            ]
          : data.list;

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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final width = MediaQuery.sizeOf(context).width;
    final height = MediaQuery.sizeOf(context).height * 0.85;

    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                    borderRadius: BorderRadius.circular(999),
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
                              '漫画评论',
                              style: tt.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
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
                                  ? '$_total 条'
                                  : '${_comments.length}/$_total')
                            : '',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        tooltip: '关闭',
                        icon: const Icon(Icons.close),
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
      ),
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme cs, TextTheme tt) {
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
              const SizedBox(height: 12),
              Text(
                '评论加载失败',
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
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: _loadComments,
                child: const Text('重试'),
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
            const SizedBox(height: 12),
            Text(
              '还没有评论',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              '这部漫画暂时没人发言',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, _listBottomPadding),
        itemCount: _comments.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, index) {
          if (index == _comments.length && _loadingMore) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final comment = _comments[index];
          return _buildCommentCard(cs, tt, comment);
        },
      ),
    );
  }

  Widget _buildCommentCard(ColorScheme cs, TextTheme tt, ComicComment comment) {
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
    final bodyStyle = (tt.bodyLarge ?? tt.bodyMedium)?.copyWith(
      height: 1.55,
      fontWeight: FontWeight.w500,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (showAvatar) ...[
                _ComicCommentAvatar(imageUrl: comment.userAvatar, size: 28),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  comment.userName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: userStyle,
                ),
              ),
              if (showCommentTime) ...[
                const SizedBox(width: 8),
                Text(TimeFormat.relativeOf(comment.createAt), style: timeStyle),
              ],
            ],
          ),
          const SizedBox(height: 8),
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
    );
  }

  Widget _buildCommentActions(
    ColorScheme cs,
    TextTheme tt,
    ComicComment comment,
    _ComicReplyState replyState,
  ) {
    final actionStyle = tt.bodyMedium?.copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w500,
    );

    return InkWell(
      borderRadius: BorderRadius.circular(999),
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
              replyState.expanded ? '收起回复' : '展开 ${comment.replyCount} 条回复',
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
                  if (index.isOdd) return const SizedBox(height: 12);
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
                      '回复加载失败',
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _loadReplies(comment),
                    child: const Text('重试'),
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
                '暂无可显示的回复',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          for (var i = 0; i < replies.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == replies.length - 1 ? 0 : 12,
              ),
              child: _buildReplyItem(cs, tt, replies[i], comment),
            ),
          if (replyState.error != null && replies.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton.icon(
                onPressed: replyState.loadingMore
                    ? null
                    : () => _loadReplies(comment, loadMore: true),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重试加载更多回复'),
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
                label: Text('加载更多回复 (${replies.length}/$totalReplies)'),
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
    final bodyStyle = tt.bodyMedium?.copyWith(
      height: 1.45,
      fontWeight: FontWeight.w500,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showAvatar) ...[
          _ComicCommentAvatar(imageUrl: reply.userAvatar, size: 22),
          const SizedBox(width: 8),
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
                            reply.userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: userStyle,
                          ),
                        ),
                        if (showReplyTarget) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_right_alt_rounded,
                            size: 14,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.78),
                          ),
                          const SizedBox(width: 4),
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
                    const SizedBox(width: 8),
                    Text(
                      TimeFormat.relativeOf(reply.createAt),
                      style: timeStyle,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              _buildCommentText(
                reply,
                bodyStyle: bodyStyle,
                backgroundColor: cs.surfaceContainerLow,
              ),
            ],
          ),
        ),
      ],
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
            borderRadius: BorderRadius.circular(12),
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
                    const SizedBox(height: 8),
                    IgnorePointer(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: widget.backgroundColor,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('展开全文', style: hintStyle),
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
                    const SizedBox(height: 8),
                    IgnorePointer(
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('收起', style: hintStyle),
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
        borderRadius: BorderRadius.circular(16),
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
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 48,
                height: 12,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            height: 14,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: MediaQuery.sizeOf(context).width * 0.55,
            height: 14,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
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
        const SizedBox(width: 8),
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
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 40,
                    height: 10,
                    decoration: BoxDecoration(
                      color: placeholderColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                height: 12,
                decoration: BoxDecoration(
                  color: placeholderColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: MediaQuery.sizeOf(context).width * 0.36,
                height: 12,
                decoration: BoxDecoration(
                  color: placeholderColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
