import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';

import '../api/novel/novel_api.dart' show novelErrorMessage;
import '../l10n/app_localizations.dart';
import '../models/novel.dart';
import '../models/user_manager.dart';
import '../pages/chapter_comments_sheet.dart'
    show CommentFontScaler, CommentSettingsPanel, buildCommentBodyStyle;
import '../providers/app_providers.dart';
import '../providers/novel_providers.dart';
import '../providers/settings_providers.dart';
import '../routing/app_router.dart';
import '../theme/app_icon_sizes.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../utils/adaptive_motion.dart';
import '../utils/app_logger.dart';
import '../utils/comment_text.dart';
import '../utils/time_format.dart';
import '../utils/toast.dart';
import 'account_avatar.dart';
import 'comment_skeleton.dart';
import 'error_retry_view.dart';
import 'load_more_footer.dart';
import 'novel_paged_controller.dart';
import 'novel_widgets.dart';
import 'text_controller_scope.dart';

part 'novel_comments_sheet_parts/comment_actions.dart';
part 'novel_comments_sheet_parts/view.dart';

/// One inline-expandable reply section's state, mirroring the comic sheet.
@immutable
class _NovelReplyState {
  final bool expanded;
  final bool loading;
  final bool loadingMore;
  final Object? error;
  final List<NovelComment> replies;
  final int? total;

  const _NovelReplyState({
    this.expanded = false,
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.replies = const [],
    this.total,
  });

  _NovelReplyState copyWith({
    bool? expanded,
    bool? loading,
    bool? loadingMore,
    Object? error,
    List<NovelComment>? replies,
    int? total,
  }) => _NovelReplyState(
    expanded: expanded ?? this.expanded,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    error: error,
    replies: replies ?? this.replies,
    total: total ?? this.total,
  );
}

/// Book comments and replies use the same documented endpoint, always with
/// the book UUID (not path_word). No request is made until this sheet opens.
///
/// Layout and interactions follow the comic comment sheet: inline expandable
/// replies (no second sheet), floating 评论/回到顶部/关闭 buttons that hide on
/// scroll down, tap-to-reply on cards and replies.
class NovelCommentsSheet extends ConsumerStatefulWidget {
  const NovelCommentsSheet({
    super.key,
    required this.bookUuid,
    required this.bookName,
    this.replyId,
    this.allowPosting = true,
  });

  final String bookUuid;

  /// 标题栏副标题展示的书名，与漫画评论区一致。
  final String bookName;
  final String? replyId;
  final bool allowPosting;

  @override
  ConsumerState<NovelCommentsSheet> createState() => _NovelCommentsSheetState();
}

class _NovelCommentsSheetState extends ConsumerState<NovelCommentsSheet> {
  static const _replyPageSize = 3;
  final _floatingButtonsKey = GlobalKey();
  double _floatingButtonsHeight = 0;

  late final UserManager _user = ref.read(userManagerProvider);
  late final _settings = ref.read(commentSettingsProvider);
  final ScrollController _scroll = ScrollController();
  late final NovelPagedController<NovelComment> _comments;
  final Map<String, _NovelReplyState> _replyStates = {};
  final Map<String, int> _replyRequests = {};
  final ValueNotifier<bool> _showFloatingButtons = ValueNotifier(true);
  DialogRoute<void>? _postDialog;
  String? _token;
  int _accountGeneration = 0;
  bool _posting = false;
  double _lastScrollOffset = 0;

  @override
  void initState() {
    super.initState();
    _token = _user.copyToken;
    _comments = NovelPagedController<NovelComment>(
      loadPage: (offset) => ref
          .read(novelApiProvider)
          .getComments(
            bookUuid: widget.bookUuid,
            replyId: widget.replyId,
            offset: offset,
          ),
      keyOf: (comment) => comment.id,
    )..addListener(_rebuild);
    _user.addListener(_onAccountChanged);
    // 屏蔽词/黑名单/群广告开关变更后即时重过滤已加载的评论。
    _user.addListener(_rebuild);
    _settings.addListener(_rebuild);
    _scroll.addListener(_handleScrollDirection);
    unawaited(_comments.refresh());
  }

  void _rebuild() {
    if (!mounted) return;
    setState(() {});
    // 首屏未填满、展开回复或分页完成后，列表可能已经接近底部；
    // 与漫画评论区一致，自动继续加载，不让用户点击「加载更多」。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tryLoadMoreWhenNearBottom();
    });
  }

  void _tryLoadMoreWhenNearBottom() {
    if (!_comments.hasMore ||
        _comments.loading ||
        _comments.error != null ||
        _comments.items.isEmpty ||
        !_scroll.hasClients) {
      return;
    }
    if (_scroll.position.extentAfter <= 240) {
      unawaited(_comments.loadMore());
    }
  }

  bool _onListScrollNotification(ScrollNotification notification) {
    if (notification.depth == 0) _tryLoadMoreWhenNearBottom();
    return false;
  }

  void _onAccountChanged() {
    if (!mounted || _token == _user.copyToken) return;
    _token = _user.copyToken;
    ++_accountGeneration;
    _posting = false;
    final dialog = _postDialog;
    _postDialog = null;
    if (dialog != null && dialog.isActive) {
      dialog.navigator?.removeRoute(dialog);
    }
    _replyStates.clear();
    _replyRequests.clear();
    _comments.clear();
    unawaited(_comments.loadMore());
  }

  @override
  void dispose() {
    _user.removeListener(_onAccountChanged);
    _user.removeListener(_rebuild);
    _settings.removeListener(_rebuild);
    _scroll.removeListener(_handleScrollDirection);
    _scroll.dispose();
    _showFloatingButtons.dispose();
    _comments.dispose();
    super.dispose();
  }

  // ── Scrolling: floating buttons show/hide like the comic sheet ──────────

  static const _directionDeadZone = 2.0;

  void _handleScrollDirection() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final offset = position.pixels;
    // 抵达底部时始终恢复显示，否则滑到底后按钮无法再出现。
    if (offset >= position.maxScrollExtent && !_showFloatingButtons.value) {
      _showFloatingButtons.value = true;
    } else if (offset > _lastScrollOffset + _directionDeadZone &&
        _showFloatingButtons.value) {
      _showFloatingButtons.value = false;
    } else if (offset < _lastScrollOffset - _directionDeadZone &&
        !_showFloatingButtons.value) {
      _showFloatingButtons.value = true;
    }
    _lastScrollOffset = offset;
  }

  void _scrollToTop() {
    if (!_scroll.hasClients) return;
    if (prefersReducedMotion(context)) {
      _scroll.jumpTo(0);
    } else {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  double get _listBottomPadding => _floatingButtonsHeight + AppSpacing.lg * 2;

  void _measureFloatingButtons() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final height = _floatingButtonsKey.currentContext?.size?.height;
      if (height == null || height == _floatingButtonsHeight) return;
      setState(() => _floatingButtonsHeight = height);
    });
  }

  // ── Posting ────────────────────────────────────────────────────────────

  Future<void> _login() async {
    await context.pushNamed(
      AppRoutes.login,
      queryParameters: {'copyOnly': 'true'},
    );
    if (mounted && _user.isCopyLoggedIn) await _comments.refresh();
  }

  Future<bool> _post(String content, {String? replyId}) async {
    if (_posting || !CommentText.isValid(content) || !widget.allowPosting) {
      return false;
    }
    if (!_user.isCopyLoggedIn) {
      await _login();
      return false;
    }
    final generation = _accountGeneration;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _posting = true);
    try {
      await ref
          .read(novelApiProvider)
          .postComment(
            bookUuid: widget.bookUuid,
            content: content,
            replyId: replyId,
          );
      if (!mounted || generation != _accountGeneration) return false;
      showToast(context, l10n.novelCommentPosted);
      if (replyId != null) {
        // 回复可能指向楼中楼，不一定是顶层评论；刷新它所属的根评论，
        // 让新回复仍出现在同一 inline 回复区。
        final rootId = _rootCommentIdForReply(replyId);
        final target = _comments.items
            .where((comment) => comment.id == rootId)
            .firstOrNull;
        if (target != null) {
          final current = _replyStateOf(rootId);
          setState(() {
            _replyStates[rootId] = current.copyWith(
              expanded: true,
              total: _replyCount(target, current) + 1,
            );
          });
          unawaited(_loadReplies(target, forceRefresh: true));
        } else {
          unawaited(_comments.refresh());
        }
      } else {
        unawaited(_comments.refresh());
      }
      return true;
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'novel_comments.post',
        ),
      );
      if (mounted && generation == _accountGeneration) {
        showToast(
          context,
          novelErrorMessage(e, fallback: l10n.novelCommentFailed),
          isError: true,
        );
      }
      return false;
    } finally {
      if (mounted && generation == _accountGeneration) {
        setState(() => _posting = false);
      }
    }
  }

  String _rootCommentIdForReply(String replyId) {
    for (final entry in _replyStates.entries) {
      if (entry.value.replies.any((reply) => reply.id == replyId)) {
        return entry.key;
      }
    }
    // A top-level comment's own id is already the root id.
    return replyId;
  }

  /// 发表对话框：回复某条评论（点击卡片触发）或发表新评论（悬浮按钮触发）。
  /// 控制器由对话框自持，文本长度与漫画侧一致（1–200）。
  Future<void> _showPostDialog({NovelComment? replyTo}) async {
    final l10n = AppLocalizations.of(context)!;
    if (!_user.isCopyLoggedIn) {
      return _login();
    }
    if (!widget.allowPosting) {
      showToast(context, l10n.novelCommentsClosed, isError: true);
      return;
    }

    final generation = _accountGeneration;
    final isReply = replyTo != null;
    final title = isReply
        ? l10n.novelCommentReplyTitle(_displayName(replyTo))
        : l10n.novelPostComment;
    final hintText = isReply
        ? l10n.novelCommentReplyHint(_displayName(replyTo))
        : l10n.novelWriteComment;

    var submitting = false;
    String? errorText;

    Future<void> submit(
      BuildContext dialogContext,
      StateSetter setLocal,
      TextEditingController controller,
    ) async {
      if (!mounted || generation != _accountGeneration) return;
      final content = controller.text.trim();
      if (!CommentText.isValid(content)) {
        setLocal(() => errorText = l10n.chapterCommentsLengthRange);
        return;
      }
      setLocal(() {
        submitting = true;
        errorText = null;
      });
      final posted = await _post(content, replyId: isReply ? replyTo.id : null);
      if (!mounted || generation != _accountGeneration) return;
      if (posted && dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
      } else if (dialogContext.mounted) {
        setLocal(() => submitting = false);
      }
    }

    final dialog = DialogRoute<void>(
      context: context,
      builder: (dialogContext) => TextControllerScope(
        builder: (dialogContext, controller) => StatefulBuilder(
          builder: (dialogContext, setLocal) {
            final canSubmit =
                !submitting && CommentText.isValid(controller.text);
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
                            dialogContext,
                          ).colorScheme.surfaceContainerLow,
                          borderRadius: AppRadius.mdR,
                        ),
                        child: Text(
                          replyTo.comment,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(dialogContext).textTheme.bodySmall,
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
                        LengthLimitingTextInputFormatter(CommentText.maxLength),
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
                  key: const ValueKey('novel-comment-submit'),
                  onPressed: canSubmit
                      ? () => submit(dialogContext, setLocal, controller)
                      : null,
                  child: submitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(isReply ? l10n.novelReply : l10n.novelPostComment),
                ),
              ],
            );
          },
        ),
      ),
    );
    _postDialog = dialog;
    try {
      await Navigator.of(context, rootNavigator: true).push(dialog);
    } finally {
      if (identical(_postDialog, dialog)) _postDialog = null;
    }
  }

  _NovelReplyState _replyStateOf(String commentId) =>
      _replyStates[commentId] ?? const _NovelReplyState();

  int _replyCount(NovelComment comment, _NovelReplyState state) {
    final total = state.total ?? comment.count;
    return total < state.replies.length ? state.replies.length : total;
  }

  Future<void> _toggleReplies(NovelComment comment) async {
    final current = _replyStateOf(comment.id);
    if (current.expanded) {
      setState(() {
        _replyStates[comment.id] = current.copyWith(expanded: false);
      });
      return;
    }
    setState(() {
      _replyStates[comment.id] = current.copyWith(expanded: true);
    });
    if (current.replies.isEmpty && !current.loading) {
      await _loadReplies(comment);
    }
  }

  Future<void> _loadReplies(
    NovelComment comment, {
    bool loadMore = false,
    bool forceRefresh = false,
  }) async {
    final current = _replyStateOf(comment.id);
    if (loadMore) {
      if (current.loading || current.loadingMore) return;
      if (current.replies.length >= _replyCount(comment, current)) return;
    } else if (current.loading && !forceRefresh) {
      return;
    }
    final generation = _accountGeneration;
    final request = (_replyRequests[comment.id] ?? 0) + 1;
    _replyRequests[comment.id] = request;
    bool isCurrent() =>
        mounted &&
        generation == _accountGeneration &&
        request == _replyRequests[comment.id];
    setState(() {
      _replyStates[comment.id] = current.copyWith(
        expanded: true,
        loading: !loadMore,
        loadingMore: loadMore,
      );
    });
    try {
      final page = await ref
          .read(novelApiProvider)
          .getComments(
            bookUuid: widget.bookUuid,
            replyId: comment.id,
            limit: _replyPageSize,
            offset: loadMore ? current.replies.length : 0,
          );
      if (!isCurrent()) return;
      // 与漫画评论区一致：回复合并后先按屏蔽配置过滤，再按时间正序排列。
      // 未配置任何屏蔽时跳过判定，行为与数据都与原逻辑一致。
      final merged = loadMore
          ? [
              ...current.replies,
              ...page.list.where(
                (item) =>
                    !current.replies.any((existing) => existing.id == item.id),
              ),
            ]
          : [...page.list];
      final visibleReplies = _hasBlockFilters
          ? merged.where(_isCommentVisible).toList()
          : merged;
      // 回复按时间正序（从旧到新）。
      visibleReplies.sort((a, b) => a.createAt.compareTo(b.createAt));
      final latest = _replyStateOf(comment.id);
      setState(() {
        _replyStates[comment.id] = latest.copyWith(
          loading: false,
          loadingMore: false,
          replies: visibleReplies,
          total: page.total,
        );
      });
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'novel_comments.replies',
        ),
      );
      if (!isCurrent()) return;
      final latest = _replyStateOf(comment.id);
      setState(() {
        _replyStates[comment.id] = latest.copyWith(
          loading: false,
          loadingMore: false,
          error: e,
        );
      });
    }
  }

  // ── Settings ───────────────────────────────────────────────────────────

  Future<void> _showSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      builder: (sheetContext) {
        final sheetSize = MediaQuery.sizeOf(sheetContext);
        // 键盘弹出时面板顶边保持不动、底边抬到输入法上方，否则输入法
        // 会盖住面板底部的屏蔽词输入框（与漫画评论区同款处理）。
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
              child: CommentSettingsPanel(
                isChapterComments: false,
                useCompactLayout: false,
                showUserAvatar: _settings.showAvatar,
                showUserName: _settings.showUserName,
                showCommentTime: _settings.showTime,
                commentFontScale: _settings.fontScale,
                commentPreload: false,
                commentInitialPages: 2,
                onLayoutChanged: (_) {},
                onShowAvatarChanged: _settings.setShowAvatar,
                onShowUserNameChanged: _settings.setShowUserName,
                onShowCommentTimeChanged: _settings.setShowTime,
                onFontScaleChanged: _settings.setFontScale,
                onPreloadChanged: (_) {},
                onInitialPagesChanged: (_) {},
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final countLabel = _buildCountLabel(l10n);
    _measureFloatingButtons();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.replyId == null
                                ? l10n.chapterCommentsComment
                                : l10n.novelReplyTitle,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: l10n.comicCommentSettingsTooltip,
                          onPressed: _showSettings,
                          icon: const Icon(Icons.tune),
                        ),
                      ],
                    ),
                    if (widget.bookName.isNotEmpty ||
                        countLabel.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        key: const ValueKey('novel-comments-subtitle'),
                        children: [
                          if (widget.bookName.isNotEmpty)
                            Expanded(
                              child: Text(
                                widget.bookName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            )
                          else
                            const Spacer(),
                          if (widget.bookName.isNotEmpty &&
                              countLabel.isNotEmpty)
                            const SizedBox(width: AppSpacing.sm),
                          if (countLabel.isNotEmpty)
                            Text(
                              countLabel,
                              key: const ValueKey('novel-comments-count'),
                              maxLines: 1,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Divider(height: 1, color: cs.outlineVariant),
              Expanded(
                child: CommentFontScaler(
                  scale: _settings.fontScale,
                  child: _buildList(context),
                ),
              ),
            ],
          ),
          _buildFloatingButtons(context),
        ],
      ),
    );
  }
}
