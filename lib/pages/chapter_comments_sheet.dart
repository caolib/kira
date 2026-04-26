import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/chapter_comment.dart';
import '../models/user_manager.dart';
import 'chapter_comment_display.dart';

class ChapterCommentsSheet extends StatefulWidget {
  final String chapterUuid;
  final String chapterName;
  final List<ChapterComment>? initialComments;
  final int? initialTotal;
  final bool hasNextChapter;
  final VoidCallback? onNextChapter;
  final VoidCallback? onBackToCatalog;

  const ChapterCommentsSheet({
    super.key,
    required this.chapterUuid,
    required this.chapterName,
    this.initialComments,
    this.initialTotal,
    this.hasNextChapter = false,
    this.onNextChapter,
    this.onBackToCatalog,
  });

  @override
  State<ChapterCommentsSheet> createState() => _ChapterCommentsSheetState();
}

class _ChapterCommentsSheetState extends State<ChapterCommentsSheet> {
  static const _pageSize = 100;
  static const _commentRowSpacing = 8.0;
  static const _loadMoreThreshold = 240.0;
  static const _commentListBottomPadding = 124.0;

  final _api = ApiClient();
  final _user = UserManager();
  final _scrollController = ScrollController();

  List<ChapterComment> _comments = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _total = 0;
  bool _useCompactLayout = true;
  bool _showUserAvatar = true;
  bool _showUserName = true;
  bool _showCommentTime = true;
  double _commentFontScale = 1.0;

  @override
  void initState() {
    super.initState();
    _useCompactLayout = _user.commentCompactLayout;
    _showUserAvatar = _user.commentShowAvatar;
    _showUserName = _user.commentShowUserName;
    _showCommentTime = _user.commentShowTime;
    _commentFontScale = _user.commentFontScale;
    if (widget.initialComments != null) {
      _comments = List<ChapterComment>.from(widget.initialComments!);
      _total = widget.initialTotal ?? _comments.length;
      _loading = false;
      return;
    }
    _loadComments();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadComments({bool loadMore = false}) async {
    if (widget.initialComments != null) return;
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
      final data = await _api.getChapterComments(
        widget.chapterUuid,
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

  String _formatRelativeTime(String raw) {
    if (raw.isEmpty) return '';

    final normalized = raw.replaceFirst(' ', 'T');
    final parsed = DateTime.tryParse(normalized);
    if (parsed == null) return raw;

    final now = DateTime.now();
    final localTime = parsed.isUtc ? parsed.toLocal() : parsed;
    final diff = now.difference(localTime);

    if (diff.isNegative) return '刚刚';
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 30) return '${diff.inDays}天前';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}个月前';
    return '${(diff.inDays / 365).floor()}年前';
  }

  void _showCommentSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _CommentSettingsPanel(
        useCompactLayout: _useCompactLayout,
        showUserAvatar: _showUserAvatar,
        showUserName: _showUserName,
        showCommentTime: _showCommentTime,
        commentFontScale: _commentFontScale,
        onLayoutChanged: (compact) {
          if (!mounted) return;
          setState(() => _useCompactLayout = compact);
          _user.setCommentCompactLayout(compact);
        },
        onShowAvatarChanged: (enabled) {
          if (!mounted) return;
          setState(() => _showUserAvatar = enabled);
          _user.setCommentShowAvatar(enabled);
        },
        onShowUserNameChanged: (enabled) {
          if (!mounted) return;
          setState(() => _showUserName = enabled);
          _user.setCommentShowUserName(enabled);
        },
        onShowCommentTimeChanged: (enabled) {
          if (!mounted) return;
          setState(() => _showCommentTime = enabled);
          _user.setCommentShowTime(enabled);
        },
        onFontScaleChanged: (scale) {
          if (!mounted) return;
          setState(() => _commentFontScale = scale);
          _user.setCommentFontScale(scale);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final sheetWidth = MediaQuery.of(context).size.width;

    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        width: sheetWidth,
        height: MediaQuery.of(context).size.height * 0.85,
        child: Stack(
          children: [
            Container(
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
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '章节评论',
                                  style: tt.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.chapterName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: tt.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: _useCompactLayout ? '切换为列表布局' : '切换为紧凑布局',
                            onPressed: () {
                              setState(
                                () => _useCompactLayout = !_useCompactLayout,
                              );
                              _user.setCommentCompactLayout(_useCompactLayout);
                            },
                            icon: Icon(
                              _useCompactLayout
                                  ? Icons.view_agenda_outlined
                                  : Icons.dashboard_outlined,
                            ),
                          ),
                          IconButton(
                            tooltip: '评论区设置',
                            onPressed: _showCommentSettings,
                            icon: const Icon(Icons.tune),
                          ),
                          Text(
                            _total > 0 ? '$_total 条' : '',
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
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
              child: SafeArea(
                top: false,
                child: Builder(
                  builder: (context) {
                    final buttonBackgroundColor = cs.primaryContainer;
                    final buttonForegroundColor = cs.onPrimaryContainer;
                    final buttonStyle = FilledButton.styleFrom(
                      backgroundColor: buttonBackgroundColor,
                      foregroundColor: buttonForegroundColor,
                      elevation: 0,
                      minimumSize: const Size(0, 52),
                      maximumSize: const Size.fromHeight(52),
                      fixedSize: const Size.fromHeight(52),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    );

                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilledButton.icon(
                          style: buttonStyle,
                          onPressed: widget.hasNextChapter
                              ? widget.onNextChapter
                              : () {
                                  widget.onBackToCatalog?.call();
                                  Navigator.of(context).pop('back_to_catalog');
                                },
                          icon: Icon(
                            widget.hasNextChapter
                                ? Icons.skip_next_rounded
                                : Icons.list_rounded,
                          ),
                          label: Text(widget.hasNextChapter ? '下一话' : '返回目录'),
                        ),
                        const SizedBox(width: 8),
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
                            onPressed: () => Navigator.of(context).maybePop(),
                            child: const Center(
                              child: Icon(Icons.keyboard_arrow_down_rounded),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme cs, TextTheme tt) {
    if (_loading && _comments.isEmpty) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          16,
          12,
          16,
          _commentListBottomPadding,
        ),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 8,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) =>
            _CommentSkeleton(compact: _useCompactLayout),
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
                onPressed: () => _loadComments(),
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
              '这个章节暂时没人发言',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    final entries = groupChapterComments(_comments);

    if (!_useCompactLayout) {
      return NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: ListView.separated(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(
            16,
            12,
            16,
            _commentListBottomPadding,
          ),
          itemCount: entries.length + (_loadingMore ? 1 : 0),
          separatorBuilder: (_, index) => const SizedBox(height: 10),
          itemBuilder: (_, index) {
            if (index == entries.length && _loadingMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final entry = entries[index];
            return _CommentCard(
              entry: entry,
              relativeTime: _formatRelativeTime(entry.createAt),
              compact: false,
              showAvatar: _showUserAvatar,
              showUserName: _showUserName,
              showCommentTime: _showCommentTime,
              fontScale: _commentFontScale,
            );
          },
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final rows = _buildCommentRows(
          context,
          constraints.maxWidth - 32,
          entries,
        );

        return NotificationListener<ScrollNotification>(
          onNotification: _handleScrollNotification,
          child: ListView.separated(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(
              16,
              12,
              16,
              _commentListBottomPadding,
            ),
            itemCount: rows.length + (_loadingMore ? 1 : 0),
            separatorBuilder: (_, index) => const SizedBox(height: 8),
            itemBuilder: (_, index) {
              if (index == rows.length && _loadingMore) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final row = rows[index];
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < row.items.length; i++) ...[
                    SizedBox(
                      width: row.items[i].width,
                      child: _CommentCard(
                        entry: row.items[i].entry,
                        relativeTime: _formatRelativeTime(
                          row.items[i].entry.createAt,
                        ),
                        compact: true,
                        showAvatar: _showUserAvatar,
                        showUserName: _showUserName,
                        showCommentTime: _showCommentTime,
                        fontScale: _commentFontScale,
                      ),
                    ),
                    if (i != row.items.length - 1)
                      const SizedBox(width: _commentRowSpacing),
                  ],
                ],
              );
            },
          ),
        );
      },
    );
  }

  List<_CommentRow> _buildCommentRows(
    BuildContext context,
    double maxWidth,
    List<ChapterCommentDisplayEntry> entries,
  ) {
    if (entries.isEmpty || maxWidth <= 0) return const [];

    final textTheme = Theme.of(context).textTheme;
    final textScaler = MediaQuery.textScalerOf(context);
    const minWidth = 108.0;
    final preferredMaxWidth = maxWidth * 0.8;

    final estimatedWidths = entries.map((entry) {
      final compactBodyStyle = _buildCommentBodyStyle(
        textTheme,
        compact: true,
        fontScale: _commentFontScale,
      );
      final bodyPainter = TextPainter(
        text: TextSpan(text: entry.content, style: compactBodyStyle),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: 1,
      )..layout(minWidth: 0, maxWidth: preferredMaxWidth);

      final headerWidth = _estimateCompactHeaderWidth(
        context,
        entry,
        preferredMaxWidth,
      );

      final contentWidth = bodyPainter.size.width > headerWidth
          ? bodyPainter.size.width
          : headerWidth;

      final cardWidth = (contentWidth + 24).clamp(minWidth, preferredMaxWidth);
      return _CommentLayoutItem(entry: entry, width: cardWidth);
    }).toList();

    final rows = <_CommentRow>[];
    var currentItems = <_CommentLayoutItem>[];
    var occupiedWidth = 0.0;

    void pushRow() {
      if (currentItems.isEmpty) return;

      final spacingWidth =
          _commentRowSpacing *
          (currentItems.length > 1 ? currentItems.length - 1 : 0);
      final cardsWidth = currentItems.fold<double>(
        0,
        (sum, item) => sum + item.width,
      );
      final remainder = maxWidth - spacingWidth - cardsWidth;
      if (remainder > 0) {
        final last = currentItems.removeLast();
        currentItems.add(
          _CommentLayoutItem(entry: last.entry, width: last.width + remainder),
        );
      }
      rows.add(_CommentRow(items: List<_CommentLayoutItem>.from(currentItems)));
      currentItems = <_CommentLayoutItem>[];
      occupiedWidth = 0.0;
    }

    for (final item in estimatedWidths) {
      final spacing = currentItems.isEmpty ? 0.0 : _commentRowSpacing;
      final nextWidth = occupiedWidth + spacing + item.width;

      if (currentItems.isNotEmpty && nextWidth > maxWidth) {
        pushRow();
      }

      if (item.width >= maxWidth) {
        rows.add(
          _CommentRow(
            items: [_CommentLayoutItem(entry: item.entry, width: maxWidth)],
          ),
        );
        continue;
      }

      final rowSpacing = currentItems.isEmpty ? 0.0 : _commentRowSpacing;
      occupiedWidth += rowSpacing + item.width;
      currentItems.add(item);
    }

    pushRow();
    return rows;
  }

  double _estimateCompactHeaderWidth(
    BuildContext context,
    ChapterCommentDisplayEntry entry,
    double maxWidth,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final textScaler = MediaQuery.textScalerOf(context);

    if (entry.isMerged) {
      if (!_showUserAvatar) {
        if (!_shouldShowMergedCountTag(entry.count)) return 0;
        final countTagWidth = _measureTextWidth(
          _formatMergedCount(entry.count),
          textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
          textScaler,
          maxWidth,
        );
        return countTagWidth + 34;
      }
      final avatarCount = entry.avatarComments().length;
      final avatarWidth = _avatarStackWidth(
        avatarCount,
        avatarSize: 22,
        overlap: 8,
      );
      if (!_shouldShowMergedCountTag(entry.count)) {
        return avatarWidth + 12;
      }

      final countTagWidth = _measureTextWidth(
        _formatMergedCount(entry.count),
        textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
        textScaler,
        maxWidth,
      );
      return avatarWidth + countTagWidth + 34;
    }

    var width = 0.0;
    var visibleSegments = 0;

    if (_showUserAvatar) {
      width += 20;
      visibleSegments++;
    }

    if (_showUserName) {
      width += _measureTextWidth(
        entry.primaryComment.userName,
        textTheme.labelSmall,
        textScaler,
        maxWidth,
      );
      visibleSegments++;
    }

    if (_showCommentTime) {
      width += _measureTextWidth(
        _formatRelativeTime(entry.createAt),
        textTheme.labelSmall,
        textScaler,
        maxWidth,
      );
      visibleSegments++;
    }

    if (visibleSegments > 1) {
      width += (visibleSegments - 1) * 6;
    }

    return width;
  }

  double _measureTextWidth(
    String text,
    TextStyle? style,
    TextScaler textScaler,
    double maxWidth,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout(minWidth: 0, maxWidth: maxWidth);
    return painter.size.width;
  }
}

class _CommentSkeleton extends StatefulWidget {
  final bool compact;
  const _CommentSkeleton({required this.compact});

  @override
  State<_CommentSkeleton> createState() => _CommentSkeletonState();
}

class _CommentSkeletonState extends State<_CommentSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final horizontalPadding = widget.compact ? 10.0 : 12.0;
    final topPadding = widget.compact ? 8.0 : 12.0;
    final bottomPadding = widget.compact ? 4.0 : 12.0;
    final avatarSize = widget.compact ? 20.0 : 28.0;

    return FadeTransition(
      opacity: Tween<double>(
        begin: 0.3,
        end: 0.7,
      ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeInOut)),
      child: Container(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          topPadding,
          horizontalPadding,
          bottomPadding,
        ),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: avatarSize,
                  height: avatarSize,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 100,
                  height: 14,
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
              height: widget.compact ? 14 : 16,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: MediaQuery.sizeOf(context).width * 0.6,
              height: widget.compact ? 14 : 16,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _CommentCard extends StatelessWidget {
  final ChapterCommentDisplayEntry entry;
  final String relativeTime;
  final bool compact;
  final bool showAvatar;
  final bool showUserName;
  final bool showCommentTime;
  final double fontScale;

  const _CommentCard({
    required this.entry,
    required this.relativeTime,
    this.compact = false,
    this.showAvatar = true,
    this.showUserName = true,
    this.showCommentTime = true,
    this.fontScale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final horizontalPadding = compact ? 10.0 : 12.0;
    final topPadding = compact ? 8.0 : 12.0;
    final bottomPadding = compact ? 4.0 : 12.0;
    final avatarSize = compact ? 20.0 : 28.0;
    final contentSpacing = compact ? 9.0 : 8.0;
    final userStyle = _buildCommentUserStyle(tt, cs, compact: compact);
    final timeStyle = _buildCommentTimeStyle(tt, cs);
    final bodyStyle = _buildCommentBodyStyle(
      tt,
      compact: compact,
      fontScale: fontScale,
    );
    final showMetaRow = showAvatar || showUserName || showCommentTime;

    return Container(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        topPadding,
        horizontalPadding,
        bottomPadding,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: entry.isMerged
          ? _MergedCommentContent(
              entry: entry,
              compact: compact,
              contentSpacing: contentSpacing,
              bodyStyle: bodyStyle,
              showAvatar: showAvatar,
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showMetaRow) ...[
                  Row(
                    children: [
                      if (showAvatar) ...[
                        _CommentAvatar(
                          imageUrl: entry.primaryComment.userAvatar,
                          size: avatarSize,
                        ),
                        SizedBox(width: compact ? 6 : 8),
                      ],
                      if (showUserName)
                        Expanded(
                          child: Text(
                            entry.primaryComment.userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: userStyle,
                          ),
                        ),
                      if (showUserName && showCommentTime)
                        SizedBox(width: compact ? 6 : 8),
                      if (showCommentTime) Text(relativeTime, style: timeStyle),
                    ],
                  ),
                  SizedBox(height: contentSpacing),
                ],
                SelectableText(
                  entry.content,
                  minLines: compact ? 1 : null,
                  style: bodyStyle,
                ),
              ],
            ),
    );
  }
}

class _CommentRow {
  final List<_CommentLayoutItem> items;

  const _CommentRow({required this.items});
}

class _CommentLayoutItem {
  final ChapterCommentDisplayEntry entry;
  final double width;

  const _CommentLayoutItem({required this.entry, required this.width});
}

class _MergedCommentContent extends StatelessWidget {
  final ChapterCommentDisplayEntry entry;
  final bool compact;
  final double contentSpacing;
  final TextStyle? bodyStyle;
  final bool showAvatar;

  const _MergedCommentContent({
    required this.entry,
    required this.compact,
    required this.contentSpacing,
    required this.bodyStyle,
    this.showAvatar = true,
  });

  @override
  Widget build(BuildContext context) {
    final showCountTag = _shouldShowMergedCountTag(entry.count);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (showAvatar)
              _CommentAvatarStack(
                comments: entry.avatarComments(),
                avatarSize: compact ? 22.0 : 26.0,
                overlap: compact ? 8.0 : 10.0,
              ),
            const Spacer(),
            if (showCountTag) ...[
              if (showAvatar) const SizedBox(width: 8),
              _MergedCommentCountTag(count: entry.count, compact: compact),
            ],
          ],
        ),
        SizedBox(height: contentSpacing + (compact ? 1 : 2)),
        SelectableText(
          entry.content,
          minLines: compact ? 1 : null,
          style: bodyStyle,
        ),
      ],
    );
  }
}

class _MergedCommentCountTag extends StatelessWidget {
  final int count;
  final bool compact;

  const _MergedCommentCountTag({required this.count, required this.compact});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      constraints: BoxConstraints(minWidth: compact ? 24 : 28),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _formatMergedCount(count),
        textAlign: TextAlign.center,
        style: tt.labelSmall?.copyWith(
          color: cs.onPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CommentAvatarStack extends StatelessWidget {
  final List<ChapterComment> comments;
  final double avatarSize;
  final double overlap;

  const _CommentAvatarStack({
    required this.comments,
    required this.avatarSize,
    required this.overlap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = comments.isEmpty
        ? const <ChapterComment>[]
        : comments.take(5).toList(growable: false);

    if (items.isEmpty) {
      return _CommentAvatar(imageUrl: '', size: avatarSize);
    }

    final width = _avatarStackWidth(
      items.length,
      avatarSize: avatarSize,
      overlap: overlap,
    );
    final inset = _avatarInset(avatarSize);

    return SizedBox(
      width: width,
      height: avatarSize,
      child: Stack(
        children: [
          for (var i = 0; i < items.length; i++)
            Positioned(
              left: i * (avatarSize - overlap),
              child: Container(
                width: avatarSize,
                height: avatarSize,
                padding: EdgeInsets.all(inset),
                decoration: BoxDecoration(
                  color: cs.surface,
                  shape: BoxShape.circle,
                ),
                child: _CommentAvatar(
                  imageUrl: items[i].userAvatar,
                  size: avatarSize - inset * 2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CommentAvatar extends StatelessWidget {
  final String imageUrl;
  final double size;

  const _CommentAvatar({required this.imageUrl, this.size = 40});

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

class _CommentSettingsPanel extends StatefulWidget {
  final bool useCompactLayout;
  final bool showUserAvatar;
  final bool showUserName;
  final bool showCommentTime;
  final double commentFontScale;
  final ValueChanged<bool> onLayoutChanged;
  final ValueChanged<bool> onShowAvatarChanged;
  final ValueChanged<bool> onShowUserNameChanged;
  final ValueChanged<bool> onShowCommentTimeChanged;
  final ValueChanged<double> onFontScaleChanged;

  const _CommentSettingsPanel({
    required this.useCompactLayout,
    required this.showUserAvatar,
    required this.showUserName,
    required this.showCommentTime,
    required this.commentFontScale,
    required this.onLayoutChanged,
    required this.onShowAvatarChanged,
    required this.onShowUserNameChanged,
    required this.onShowCommentTimeChanged,
    required this.onFontScaleChanged,
  });

  @override
  State<_CommentSettingsPanel> createState() => _CommentSettingsPanelState();
}

class _CommentSettingsPanelState extends State<_CommentSettingsPanel> {
  late bool _useCompactLayout;
  late bool _showUserAvatar;
  late bool _showUserName;
  late bool _showCommentTime;
  late double _commentFontScale;

  @override
  void initState() {
    super.initState();
    _useCompactLayout = widget.useCompactLayout;
    _showUserAvatar = widget.showUserAvatar;
    _showUserName = widget.showUserName;
    _showCommentTime = widget.showCommentTime;
    _commentFontScale = widget.commentFontScale;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final defaultFontSizePx = _defaultCommentFontSizePx(
      tt,
      compact: _useCompactLayout,
    );
    final minFontSizePx = _commentFontMinPx(defaultFontSizePx);
    final maxFontSizePx = _commentFontMaxPx(defaultFontSizePx);
    final currentFontSizePx = _commentFontScaleToPx(
      defaultFontSizePx,
      _commentFontScale,
    ).clamp(minFontSizePx, maxFontSizePx);

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '评论区设置',
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Text('布局', style: tt.bodyMedium),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.dashboard_outlined),
                      label: Text('紧凑布局'),
                    ),
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.view_agenda_outlined),
                      label: Text('列表布局'),
                    ),
                  ],
                  selected: {_useCompactLayout},
                  onSelectionChanged: (values) {
                    final value = values.first;
                    setState(() => _useCompactLayout = value);
                    widget.onLayoutChanged(value);
                  },
                ),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('显示头像'),
                subtitle: const Text('合并评论的头像不受影响'),
                value: _showUserAvatar,
                onChanged: (value) {
                  setState(() => _showUserAvatar = value);
                  widget.onShowAvatarChanged(value);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('显示用户名'),
                value: _showUserName,
                onChanged: (value) {
                  setState(() => _showUserName = value);
                  widget.onShowUserNameChanged(value);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('显示评论时间'),
                value: _showCommentTime,
                onChanged: (value) {
                  setState(() => _showCommentTime = value);
                  widget.onShowCommentTimeChanged(value);
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('评论内容字体大小', style: tt.bodyMedium),
                  const Spacer(),
                  Text(
                    '${currentFontSizePx.round()} px',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              Slider(
                value: currentFontSizePx,
                min: minFontSizePx,
                max: maxFontSizePx,
                divisions: ((maxFontSizePx - minFontSizePx) / 1).round(),
                label: '${currentFontSizePx.round()} px',
                onChanged: (value) {
                  final nextScale = _commentFontPxToScale(
                    defaultFontSizePx,
                    value,
                  );
                  setState(() => _commentFontScale = nextScale);
                  widget.onFontScaleChanged(nextScale);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatMergedCount(int count) => count > 99 ? 'x99+' : 'x$count';

bool _shouldShowMergedCountTag(int count) => count > 1;

TextStyle? _buildCommentUserStyle(
  TextTheme textTheme,
  ColorScheme colorScheme, {
  required bool compact,
}) {
  final metaColor = colorScheme.onSurfaceVariant.withValues(
    alpha: compact ? 0.72 : 0.78,
  );
  return (compact ? textTheme.labelSmall : textTheme.labelMedium)?.copyWith(
    color: metaColor,
    fontWeight: FontWeight.w500,
  );
}

TextStyle? _buildCommentTimeStyle(
  TextTheme textTheme,
  ColorScheme colorScheme,
) {
  return textTheme.labelSmall?.copyWith(
    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
    fontWeight: FontWeight.w400,
  );
}

TextStyle? _buildCommentBodyStyle(
  TextTheme textTheme, {
  required bool compact,
  required double fontScale,
}) {
  final baseStyle = compact
      ? textTheme.bodyMedium
      : (textTheme.bodyLarge ?? textTheme.bodyMedium);
  final defaultFontSize = _defaultCommentFontSizePx(
    textTheme,
    compact: compact,
  );

  return baseStyle?.copyWith(
        fontSize: defaultFontSize * fontScale,
        height: compact ? 1.35 : 1.55,
        fontWeight: FontWeight.w500,
      ) ??
      TextStyle(
        fontSize: defaultFontSize * fontScale,
        height: compact ? 1.35 : 1.55,
        fontWeight: FontWeight.w500,
      );
}

double _defaultCommentFontSizePx(TextTheme textTheme, {required bool compact}) {
  final baseStyle = compact
      ? textTheme.bodyMedium
      : (textTheme.bodyLarge ?? textTheme.bodyMedium);
  final fontSize = baseStyle?.fontSize;
  return fontSize != null && fontSize >= 16 ? fontSize : 16.0;
}

double _commentFontMinPx(double defaultFontSizePx) {
  final minPx = defaultFontSizePx - 5;
  return minPx < 10 ? 10 : minPx;
}

double _commentFontMaxPx(double defaultFontSizePx) => defaultFontSizePx + 14;

double _commentFontScaleToPx(double defaultFontSizePx, double scale) =>
    defaultFontSizePx * scale;

double _commentFontPxToScale(double defaultFontSizePx, double fontSizePx) =>
    fontSizePx / defaultFontSizePx;

double _avatarStackWidth(
  int count, {
  required double avatarSize,
  required double overlap,
}) {
  if (count <= 0) return avatarSize;
  return avatarSize + (count - 1) * (avatarSize - overlap);
}

double _avatarInset(double avatarSize) => avatarSize <= 22 ? 1.5 : 2;
