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
import '../theme/app_status_colors.dart';
import '../utils/comment_text.dart';
import '../utils/network_error.dart';
import '../utils/time_format.dart';
import '../utils/toast.dart';
import '../widgets/app_sheet.dart';
import '../widgets/text_controller_scope.dart';
import 'chapter_comments/comment_paging.dart';
import 'chapter_comments/comment_scroll_behavior.dart';
import 'chapter_comments_sheet.dart'
    show CommentFontScaler, CommentSettingsPanel, buildCommentBodyStyle;
import 'comic_comment_display.dart';
part 'comic_comments/comic_actions.dart';
part 'comic_comments/comic_data.dart';
part 'comic_comments/comic_merged.dart';
part 'comic_comments/comic_reply_build.dart';
part 'comic_comments/comment_widgets.dart';
part 'comic_comments/merged_comment_widgets.dart';

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
  List<ComicCommentDisplayEntry> _groupedEntries = const [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _total = 0;
  int _blockedCount = 0;
  final Map<int, _ComicReplyState> _replyStates = {};

  /// extension part 文件里的成员不是 State 子类成员，不能直接调用受保护的
  /// [setState]，统一经由这个转发方法。
  void _setState(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  bool get canLoadMore =>
      !_loading && !_loadingMore && _comments.length < _total;

  @override
  void loadMoreComments() => _loadComments(loadMore: true);

  void _scrollToTop() {
    if (scrollController.hasClients) {
      scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  _ComicReplyState _replyStateOf(int commentId) =>
      _replyStates[commentId] ?? const _ComicReplyState();

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
                color: AppSheet.backgroundColor(cs),
                borderRadius: AppSheet.borderRadius,
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    const AppSheetHandle(),
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
                            _buildCountLabel(l10n),
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
                    Expanded(
                      child: CommentFontScaler(
                        scale: _user.commentFontScale,
                        child: _buildBody(context, cs, tt),
                      ),
                    ),
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
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            FilledButton.icon(
                              style: buttonStyle,
                              onPressed: _showPostCommentDialog,
                              icon: const Icon(Icons.comment_outlined),
                              label: Text(l10n.chapterCommentsComment),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
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
                                    onPressed: _scrollToTop,
                                    child: const Center(
                                      child: Icon(Icons.arrow_upward_rounded),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.sm),
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

  /// 评论区计数文案：全部加载且无屏蔽时显示「N 条」；
  /// 有屏蔽时为「显示数/总数|屏蔽数」，屏蔽为 0 则不显示 |屏蔽数。
  String _buildCountLabel(AppLocalizations l10n) {
    if (_total <= 0) return '';
    final allLoaded = _comments.length + _blockedCount >= _total;
    if (allLoaded && _blockedCount == 0) {
      return l10n.chapterCommentsTotalCount(_total);
    }
    if (_blockedCount > 0) {
      return l10n.chapterCommentsCountWithBlocked(
        _comments.length,
        _total,
        _blockedCount,
      );
    }
    return '${_comments.length}/$_total';
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
        itemCount: _groupedEntries.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, index) {
          if (index == _groupedEntries.length && _loadingMore) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: ExpressiveLoadingIndicator()),
            );
          }

          final entry = _groupedEntries[index];
          return _buildCommentCard(cs, tt, entry);
        },
      ),
    );
  }

  Widget _buildCommentCard(
    ColorScheme cs,
    TextTheme tt,
    ComicCommentDisplayEntry entry,
  ) {
    final brightness = Theme.of(context).brightness;
    final comment = entry.primaryComment;
    final replyState = _replyStateOf(comment.id);
    final canExpandReplies = comment.replyCount > 0;
    final user = UserManager();
    final showAvatar = user.commentShowAvatar;
    final showCommentTime = user.commentShowTime;
    final isHotMerged = entry.isMerged && _isHotMergedComment(entry.count);
    final bodyStyle = buildCommentBodyStyle(
      tt,
      compact: false,
    )?.copyWith(color: isHotMerged ? _hotMergedCommentColor : null);
    final userStyle = _buildMergedCommentUserStyle(tt, cs, compact: false);
    final timeStyle = tt.labelSmall?.copyWith(
      color: cs.onSurfaceVariant.withValues(alpha: 0.72),
      fontWeight: FontWeight.w400,
    );

    return GestureDetector(
      onTap: entry.isMerged
          ? () => _showMergedCommentUsersDialog(entry)
          : () => _showPostCommentDialog(replyTo: comment),
      onLongPress: () => _showCommentActionMenuForEntry(entry),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_mergedCardCornerRadius),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: _buildMergedCommentCardDecoration(
            cs,
            brightness: brightness,
            highlightAsHot: isHotMerged,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (entry.isMerged)
                _ComicMergedCommentContent(
                  entry: entry,
                  compact: false,
                  contentSpacing: 8.0,
                  bodyStyle: bodyStyle,
                  userStyle: userStyle,
                  showAvatar: showAvatar,
                  showUserName: user.commentShowUserName,
                  backgroundColor: cs.surfaceContainerLow,
                )
              else ...[
                Row(
                  children: [
                    if (showAvatar) ...[
                      _ComicCommentAvatar(
                        imageUrl: comment.userAvatar,
                        size: 28,
                      ),
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
              ],
              if (canExpandReplies) ...[
                const SizedBox(height: 10),
                _buildCommentActions(cs, tt, comment, replyState),
              ],
              if (canExpandReplies && replyState.expanded)
                _buildReplySection(cs, tt, comment, replyState),
            ],
          ),
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

  static const _mergedCommentSheetMaxHeightFactor = 0.5;
  static const _commentRowSpacing = 8.0;

  /// 解析评论时间字符串，失败返回 null。
  static DateTime? _parseCommentTime(String dateStr) {
    if (dateStr.isEmpty) return null;
    return DateTime.tryParse(dateStr.replaceFirst(' ', 'T'));
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
