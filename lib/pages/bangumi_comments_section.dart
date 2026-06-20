import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/dandanplay_api.dart';
import '../models/user_manager.dart';
import '../utils/time_format.dart';

typedef BangumiCommentsLoader =
    Future<DandanplayBangumiCommentsPage> Function(
      String bangumiId, {
      int page,
      bool forceRefresh,
    });

class BangumiCommentsSection extends StatefulWidget {
  final String bangumiId;
  final String animeTitle;
  final BangumiCommentsLoader? loader;

  const BangumiCommentsSection({
    super.key,
    required this.bangumiId,
    required this.animeTitle,
    this.loader,
  });

  @override
  State<BangumiCommentsSection> createState() => BangumiCommentsSectionState();
}

class BangumiCommentsSectionState extends State<BangumiCommentsSection> {
  static const _autoLoadMoreThreshold = 240.0;

  late final DandanplayApi _api;
  ScrollPosition? _ancestorScrollPosition;

  List<DandanplayBangumiComment> _comments = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _currentPage = -1;
  String? _error;

  BangumiCommentsLoader get _loader =>
      widget.loader ??
      (String bangumiId, {int page = 0, bool forceRefresh = false}) =>
          _api.getBangumiComments(
            bangumiId,
            page: page,
            forceRefresh: forceRefresh,
          );

  @override
  void initState() {
    super.initState();
    _api = DandanplayApi();
    _loadComments();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextPosition = Scrollable.maybeOf(context)?.position;
    if (identical(nextPosition, _ancestorScrollPosition)) return;
    _ancestorScrollPosition?.removeListener(_handleAncestorScroll);
    _ancestorScrollPosition = nextPosition;
    _ancestorScrollPosition?.addListener(_handleAncestorScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _tryLoadMoreWhenNearBottom(metrics: _ancestorScrollPosition);
      }
    });
  }

  @override
  void didUpdateWidget(covariant BangumiCommentsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bangumiId != widget.bangumiId) {
      _loadComments(forceRefresh: true);
    }
  }

  Future<void> reload({bool forceRefresh = true}) =>
      _loadComments(forceRefresh: forceRefresh);

  @override
  void dispose() {
    _ancestorScrollPosition?.removeListener(_handleAncestorScroll);
    super.dispose();
  }

  void _handleAncestorScroll() {
    _tryLoadMoreWhenNearBottom(metrics: _ancestorScrollPosition);
  }

  void _tryLoadMoreWhenNearBottom({ScrollMetrics? metrics}) {
    if (_loading || _loadingMore || !_hasMore || _error != null) return;
    final currentMetrics = metrics;
    if (currentMetrics == null) return;
    if (currentMetrics.extentAfter <= _autoLoadMoreThreshold) {
      _loadComments(loadMore: true);
    }
  }

  Future<void> _loadComments({
    bool loadMore = false,
    bool forceRefresh = false,
  }) async {
    if (loadMore) {
      if (_loading || _loadingMore || !_hasMore) return;
      setState(() {
        _loadingMore = true;
        _error = null;
      });
    } else {
      setState(() {
        _loading = true;
        _loadingMore = false;
        _error = null;
        if (forceRefresh) {
          _comments = [];
          _hasMore = false;
          _currentPage = -1;
        }
      });
    }

    final nextPage = loadMore ? _currentPage + 1 : 0;

    try {
      final data = await _loader(
        widget.bangumiId,
        page: nextPage,
        forceRefresh: forceRefresh && !loadMore,
      );
      if (!mounted) return;

      final merged = loadMore
          ? [
              ..._comments,
              ...data.comments.where(
                (item) => !_comments.any((existing) => existing.id == item.id),
              ),
            ]
          : data.comments;

      setState(() {
        _comments = merged;
        _hasMore = data.hasMore;
        _currentPage = nextPage;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _tryLoadMoreWhenNearBottom(metrics: _ancestorScrollPosition);
        }
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
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (_loading && _comments.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null && _comments.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: _BangumiCommentsMessage(
          icon: Icons.rate_review_outlined,
          title: '评论加载失败',
          description: '下拉或点按钮重试',
          action: FilledButton.tonal(
            onPressed: () => _loadComments(forceRefresh: true),
            child: const Text('重试'),
          ),
        ),
      );
    }

    if (_comments.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: _BangumiCommentsMessage(
          icon: Icons.forum_outlined,
          title: '还没有评论',
          description: '暂时没有可显示的 Bangumi 评论',
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        for (var i = 0; i < _comments.length; i++) ...[
          _BangumiCommentCard(
            comment: _comments[i],
            relativeTime: TimeFormat.relativeOf(_comments[i].updatedTime),
          ),
          if (i != _comments.length - 1) const SizedBox(height: 10),
        ],
        if (_error != null && _comments.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('更多评论加载失败', style: tt.bodySmall?.copyWith(color: cs.error)),
        ],
        if (_loadingMore) ...[
          const SizedBox(height: 16),
          const Center(child: CircularProgressIndicator()),
        ] else if (_hasMore || _error != null) ...[
          const SizedBox(height: 16),
          Center(
            child: FilledButton.tonalIcon(
              onPressed: () => _loadComments(loadMore: true),
              icon: Icon(_error != null ? Icons.refresh : Icons.expand_more),
              label: Text(_error != null ? '重试加载更多' : '加载更多'),
            ),
          ),
        ],
      ],
    );
  }
}

class _BangumiCommentCard extends StatelessWidget {
  final DandanplayBangumiComment comment;
  final String relativeTime;

  const _BangumiCommentCard({
    required this.comment,
    required this.relativeTime,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final user = UserManager();
    final showAvatar = user.commentShowAvatar;
    final showCommentTime = user.commentShowTime;
    final userStyle = tt.labelMedium?.copyWith(
      fontWeight: FontWeight.w500,
      color: cs.onSurfaceVariant.withValues(alpha: 0.72),
    );
    final metaStyle = tt.labelSmall?.copyWith(
      color: cs.onSurfaceVariant.withValues(alpha: 0.58),
    );
    final bodyStyle = tt.bodyMedium?.copyWith(
      height: 1.5,
      fontWeight: FontWeight.w400,
    );

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showAvatar) ...[
                _BangumiCommentAvatar(imageUrl: comment.imageUrl),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            comment.userName.isEmpty
                                ? '匿名用户'
                                : comment.userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: userStyle,
                          ),
                        ),
                        if (comment.rating > 0) ...[
                          const SizedBox(width: 8),
                          _BangumiRatingBadge(rating: comment.rating),
                        ],
                      ],
                    ),
                    if (showCommentTime && relativeTime.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(relativeTime, style: metaStyle),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            comment.text.isEmpty ? '这条评论没有内容' : comment.text,
            style: bodyStyle,
          ),
        ],
      ),
    );
  }
}

class _BangumiCommentAvatar extends StatelessWidget {
  final String imageUrl;

  const _BangumiCommentAvatar({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final url = imageUrl.trim();
    if (url.isEmpty) {
      return CircleAvatar(
        radius: 20,
        backgroundColor: cs.surfaceContainerHighest,
        child: Icon(Icons.person_outline, color: cs.onSurfaceVariant),
      );
    }

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) => CircleAvatar(
          radius: 20,
          backgroundColor: cs.surfaceContainerHighest,
          child: Icon(Icons.person_outline, color: cs.onSurfaceVariant),
        ),
        placeholder: (_, _) => CircleAvatar(
          radius: 20,
          backgroundColor: cs.surfaceContainerHighest,
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
          ),
        ),
      ),
    );
  }
}

class _BangumiRatingBadge extends StatelessWidget {
  final int rating;

  const _BangumiRatingBadge({required this.rating});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final badgeBackground = isDark
        ? const Color(0xFF5C4A10)
        : const Color(0xFFFFF3CD);
    final badgeForeground = isDark
        ? const Color(0xFFF5D86A)
        : const Color(0xFFB7791F);
    const starColor = Color(0xFFFFB800);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: badgeBackground,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 14, color: starColor),
          const SizedBox(width: 4),
          Text(
            '$rating',
            style: tt.labelSmall?.copyWith(
              color: badgeForeground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _BangumiCommentsMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Widget? action;

  const _BangumiCommentsMessage({
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(title, style: tt.titleMedium),
          const SizedBox(height: 6),
          Text(
            description,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}
