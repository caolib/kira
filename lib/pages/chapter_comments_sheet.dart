import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../api/ai_api.dart';
import '../api/api_client.dart';
import '../l10n/app_localizations.dart';
import '../models/chapter_comment.dart';
import '../models/user_manager.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_status_colors.dart';
import '../theme/app_typography.dart';
import '../utils/adaptive_motion.dart';
import '../utils/app_logger.dart';
import '../utils/chapter_comment_paging.dart';
import '../utils/chapter_summary_cache.dart';
import '../utils/comment_text.dart';
import '../utils/log_sanitizer.dart';
import '../utils/network_error.dart';
import '../utils/time_format.dart';
import '../utils/toast.dart';
import '../widgets/app_sheet.dart';
import '../widgets/confetti_celebration.dart';
import '../widgets/load_more_footer.dart';
import '../widgets/text_controller_scope.dart';
import 'chapter_comment_display.dart';
import 'chapter_comments/comment_paging.dart';
import 'chapter_comments/comment_scroll_behavior.dart';
import 'chapter_comments/comment_toolbar.dart';

part 'chapter_comments/ai_summary.dart';
part 'chapter_comments/comment_actions.dart';
part 'chapter_comments/comment_body.dart';
part 'chapter_comments/comment_compact_layout.dart';
part 'chapter_comments/comment_data.dart';
part 'chapter_comments/comment_models.dart';
part 'chapter_comments/comment_posting.dart';
part 'chapter_comments/comment_settings_panel.dart';
part 'chapter_comments/comment_style.dart';
part 'chapter_comments/comment_widgets.dart';
part 'chapter_comments/summary_panel.dart';

class ChapterCommentsSheet extends StatefulWidget {
  final String chapterUuid;
  final String? comicName;
  final String chapterName;
  final List<ChapterComment>? initialComments;
  final int? initialTotal;
  final void Function(List<ChapterComment> comments, int total)?
  onCommentsUpdated;
  final bool hasNextChapter;
  final VoidCallback? onNextChapter;
  final VoidCallback? onBackToCatalog;

  const ChapterCommentsSheet({
    super.key,
    required this.chapterUuid,
    this.comicName,
    required this.chapterName,
    this.initialComments,
    this.initialTotal,
    this.onCommentsUpdated,
    this.hasNextChapter = false,
    this.onNextChapter,
    this.onBackToCatalog,
  });

  @override
  State<ChapterCommentsSheet> createState() => _ChapterCommentsSheetState();
}

class _ChapterCommentsSheetState extends State<ChapterCommentsSheet>
    with CommentScrollBehavior<ChapterCommentsSheet> {
  /// 服务端实际页宽，见 [chapterCommentPageSize]。
  static const _pageSize = chapterCommentPageSize;
  bool _confettiShown = false;
  static const _commentRowSpacing = 8.0;
  final _commentToolbarKey = GlobalKey();
  double _commentToolbarHeight = 0;
  static const _sheetMaxHeightFactor = 0.85;
  static const _mergedCommentSheetMaxHeightFactor = 0.5;

  final _api = ApiClient();
  final _user = UserManager();
  final _aiSettings = AiSettings();
  final _aiApi = AiApi();
  final _reasoningScrollController = ScrollController();

  List<ChapterComment> _comments = [];
  bool _loading = true;
  bool _loadingMore = false;
  late final int _initialPages;

  /// 首屏补页进行中：期间把手动翻页交给它，避免同一 offset 并发请求。
  bool _prefetchingInitialPages = false;

  /// 递增即作废正在跑的补页循环（首屏重试、刷新首屏时）。
  int _prefetchGeneration = 0;
  String? _error;
  int _total = 0;
  int _blockedCount = 0;
  bool _useCompactLayout = true;
  bool _showUserAvatar = true;
  bool _showUserName = true;
  bool _showCommentTime = true;
  double _commentFontScale = 1.0;

  // Stream AI content through ValueNotifiers so chunks only rebuild the summary
  // panel, keeping the comment list still while generation is running.
  // Empty string represents null for _summaryError through the getter/setter.
  final ValueNotifier<String> _aiSummaryVN = ValueNotifier('');
  final ValueNotifier<String> _aiSummaryReasoningVN = ValueNotifier('');
  final ValueNotifier<bool> _summarizingVN = ValueNotifier(false);
  final ValueNotifier<String> _summaryErrorVN = ValueNotifier('');

  String get _aiSummary => _aiSummaryVN.value;
  set _aiSummary(String v) => _aiSummaryVN.value = v;
  String get _aiSummaryReasoning => _aiSummaryReasoningVN.value;
  set _aiSummaryReasoning(String v) => _aiSummaryReasoningVN.value = v;
  bool get _summarizing => _summarizingVN.value;
  set _summarizing(bool v) => _summarizingVN.value = v;
  String? get _summaryError =>
      _summaryErrorVN.value.isEmpty ? null : _summaryErrorVN.value;
  set _summaryError(String? v) => _summaryErrorVN.value = v ?? '';

  CancelToken? _summaryCancelToken;
  bool _summaryInitialized = false;
  bool _autoSummaryAttempted = false;
  Set<int> _spoilerIds = const {};
  List<ChapterCommentDisplayEntry> _lastSnippetEntries = const [];
  // Throttle AI stream writes to ValueNotifiers instead of calling setState.
  Timer? _summaryThrottleTimer;
  bool _summaryThrottleScheduled = false;
  bool _summaryHasPendingTextFlush = false;
  // Cached grouped comments.
  List<ChapterCommentDisplayEntry> _groupedEntries = const [];
  bool _reasoningScrollPending = false;
  // Cache _hasSummaryPanel and rebuild ListView only when panel presence changes.
  bool _hasSummaryPanelCached = false;

  /// extension part 文件里的成员不是 State 子类成员，不能直接调用受保护的
  /// [setState]，统一经由这个转发方法。
  void _setState(VoidCallback fn) => setState(fn);

  /// Rebuilds the grouped comment cache after _comments changes.
  void _rebuildGroupedEntries() {
    if (_comments.isEmpty) {
      _groupedEntries = const [];
      _blockedCount = 0;
      return;
    }
    final blockwords = _user.commentBlockwords;
    final hasBlockwords = blockwords.isNotEmpty || _user.commentBlockGroupSpam;
    final blocked = _user.commentBlockedUsers;
    if (blocked.isEmpty && !hasBlockwords) {
      _groupedEntries = groupChapterComments(_comments);
      _blockedCount = 0;
      return;
    }
    final filtered = _comments
        .where(
          (c) =>
              !_user.isCommentUserBlocked(c.userId, c.userName.trim()) &&
              !_user.isCommentBlockedByWord(c.comment) &&
              !_user.isCommentGroupSpam(c.comment),
        )
        .toList();
    _blockedCount = _comments.length - filtered.length;
    _groupedEntries = groupChapterComments(filtered);
  }

  late final ChapterSummaryProgress _summaryProgress;
  bool _usingSharedSummaryProgress = false;

  @override
  void initState() {
    super.initState();
    _useCompactLayout = _user.commentCompactLayout;
    _showUserAvatar = _user.commentShowAvatar;
    _showUserName = _user.commentShowUserName;
    _showCommentTime = _user.commentShowTime;
    _commentFontScale = _user.commentFontScale;
    _initialPages = _user.commentInitialPages;
    _aiSettings.addListener(_onAiChanged);
    // Listen to stream ValueNotifiers only for structural panel presence changes.
    // Incremental stream writes keep _hasSummaryPanel unchanged and avoid setState.
    _aiSummaryVN.addListener(_onSummaryPresenceVnChanged);
    _aiSummaryReasoningVN.addListener(_onSummaryPresenceVnChanged);
    _summarizingVN.addListener(_onSummaryPresenceVnChanged);
    _summaryErrorVN.addListener(_onSummaryPresenceVnChanged);
    _hasSummaryPanelCached = _hasSummaryPanel;
    _summaryProgress = ChapterSummaryCache.progressOf(widget.chapterUuid);
    _summaryProgress.addListener(_onSummaryProgressChanged);
    _applySummaryProgress();
    _aiSettings.load().then((_) async {
      if (!mounted) return;
      setState(() {}); // AI config loaded; refresh toolbar visibility.
      await _loadCachedSummary();
      if (!mounted) return;
      _summaryInitialized = true;
      _maybeAutoSummary();
    });
    if (widget.initialComments != null) {
      _comments = List<ChapterComment>.from(widget.initialComments!);
      _total = widget.initialTotal ?? _comments.length;
      _loading = false;
      _rebuildGroupedEntries();
      // 初始评论已达撒花条件时立即触发。
      _maybeShowConfetti();
      // 缓存/下载的评论可能只有第一页，按本次打开时的设定页数补齐。
      if (_comments.length < _total) {
        unawaited(_prefetchInitialPages());
      }
      return;
    }
    _loadComments();
  }

  @override
  void dispose() {
    _summaryCancelToken?.cancel();
    _summaryThrottleTimer?.cancel();
    _summaryProgress.removeListener(_onSummaryProgressChanged);
    _aiSettings.removeListener(_onAiChanged);
    _aiSummaryVN.removeListener(_onSummaryPresenceVnChanged);
    _aiSummaryReasoningVN.removeListener(_onSummaryPresenceVnChanged);
    _summarizingVN.removeListener(_onSummaryPresenceVnChanged);
    _summaryErrorVN.removeListener(_onSummaryPresenceVnChanged);
    _reasoningScrollController.dispose();
    _aiSummaryVN.dispose();
    _aiSummaryReasoningVN.dispose();
    _summarizingVN.dispose();
    _summaryErrorVN.dispose();
    super.dispose();
  }

  void _onAiChanged() {
    if (!mounted) return;
    // AiSettings changes, such as spoilerAnalysis, affect comment masks.
    // This is user-driven and rare, so one full tree refresh is fine.
    setState(() {});
  }

  /// Rebuilds the ListView structure only when the summary panel appears/disappears.
  /// Streaming updates keep _hasSummaryPanel true, so the comment list stays still.
  void _onSummaryPresenceVnChanged() {
    if (!mounted) return;
    final now = _hasSummaryPanel;
    if (now != _hasSummaryPanelCached) {
      _hasSummaryPanelCached = now;
      setState(() {});
    }
  }

  void _notifyCommentsUpdated() {
    final callback = widget.onCommentsUpdated;
    if (callback == null) return;
    callback(
      List<ChapterComment>.from(_comments),
      _total < _comments.length ? _comments.length : _total,
    );
    _maybeShowConfetti();
  }

  /// 当评论含「完结撒花/散花」超过 10 条时触发全屏撒花动画。
  ///
  /// 使用 flutter_confetti 包的礼炮式实现，从屏幕左右下角向上发射。
  void _maybeShowConfetti() {
    if (_confettiShown) return;
    final comments = _comments;
    if (comments.length < 10) return;

    final texts = comments.map((c) => c.comment).toList();
    if (!hasCompletionCelebration(texts)) return;

    _confettiShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showConfettiCelebration(context);
    });
  }

  @override
  bool get canLoadMore =>
      !_loading &&
      !_loadingMore &&
      // 上一页失败后不再由滚动自动重试：失败原因已显示在列表底部，
      // 交给用户显式点击，避免近底滚动反复打同一个失败请求。
      _error == null &&
      // 首屏补页期间自行按 offset 追加，避免近底翻页并发请求。
      !_prefetchingInitialPages &&
      _comments.length < _total;

  @override
  void loadMoreComments() => _loadComments(loadMore: true);

  void _scrollToTop() {
    if (!scrollController.hasClients) return;
    if (prefersReducedMotion(context)) {
      scrollController.jumpTo(0);
    } else {
      scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  double get _commentListBottomPadding =>
      _commentToolbarHeight + AppSpacing.lg * 2;

  void _measureCommentToolbar() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final height = _commentToolbarKey.currentContext?.size?.height;
      if (height == null || height == _commentToolbarHeight) return;
      setState(() => _commentToolbarHeight = height);
    });
  }

  static final _codeBlockRegex = RegExp(
    r'```[^`\r\n]*\r?\n([\s\S]*?)\r?\n\s*```',
  );
  static final _arrayRegex = RegExp(r'\[\s*([\d,\s]*)\s*\]');
  static final _spoilerLegacyRegex = RegExp(r'<!--\s*SPOILERS\s*:([^>]*)-->');

  /// 解析评论时间字符串，失败返回 null（与 TimeFormat.relativeOf 一致地处理空格分隔）。
  static DateTime? _parseCommentTime(String dateStr) {
    if (dateStr.isEmpty) return null;
    return DateTime.tryParse(dateStr.replaceFirst(' ', 'T'));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final sheetWidth = MediaQuery.of(context).size.width;
    final countLabel = _buildCountLabel(l10n);
    _measureCommentToolbar();

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      behavior: HitTestBehavior.translucent,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: GestureDetector(
          onTap: () {},
          child: SizedBox(
            width: sheetWidth,
            height: MediaQuery.of(context).size.height * _sheetMaxHeightFactor,
            child: Stack(
              children: [
                Material(
                  color: AppSheet.backgroundColor(cs),
                  borderRadius: AppSheet.borderRadius,
                  clipBehavior: Clip.antiAlias,
                  child: SafeArea(
                    top: false,
                    child: Column(
                      children: [
                        const AppSheetHandle(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      l10n.chapterCommentsTitle,
                                      style: tt.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  if (_aiSettings.hasApiKey &&
                                      _aiSettings.summaryEnabled)
                                    IconButton(
                                      tooltip: _aiSummary.isEmpty
                                          ? l10n.chapterCommentsAiSummaryTooltip
                                          : l10n.chapterCommentsRegenerateAiSummaryTooltip,
                                      onPressed: _summarizing
                                          ? null
                                          : _summarizeComments,
                                      icon: Icon(
                                        Icons.smart_toy_outlined,
                                        color: _summarizing
                                            ? cs.onSurfaceVariant
                                            : cs.primary,
                                      ),
                                    ),
                                  IconButton(
                                    tooltip: l10n.commentSettingsTitle,
                                    onPressed: _showCommentSettings,
                                    icon: const Icon(Icons.tune),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Row(
                                key: const ValueKey(
                                  'chapter-comments-subtitle',
                                ),
                                children: [
                                  Expanded(
                                    child: Text(
                                      widget.chapterName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: tt.bodySmall?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  if (countLabel.isNotEmpty) ...[
                                    const SizedBox(width: AppSpacing.sm),
                                    Text(
                                      countLabel,
                                      key: const ValueKey(
                                        'chapter-comments-count',
                                      ),
                                      maxLines: 1,
                                      style: tt.bodySmall?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        Divider(height: 1, color: cs.outlineVariant),
                        Expanded(
                          child: ExcludeSemantics(
                            child: CommentFontScaler(
                              scale: _commentFontScale,
                              child: _buildBody(context, cs, tt),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: AppSpacing.lg,
                  bottom: AppSpacing.lg,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: showFloatingButtons,
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
                              offset: visible
                                  ? Offset.zero
                                  : const Offset(0, 1.2),
                              curve: Curves.easeInOutCubic,
                              duration: duration,
                              child: AnimatedOpacity(
                                opacity: visible ? 1 : 0,
                                duration: duration,
                                child: SafeArea(top: false, child: child!),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: sheetWidth - AppSpacing.lg * 2,
                      ),
                      child: ChapterCommentToolbar(
                        key: _commentToolbarKey,
                        onComment: _showPostCommentDialog,
                        onCatalog: () {
                          widget.onBackToCatalog?.call();
                          Navigator.of(context).pop('back_to_catalog');
                        },
                        hasNextChapter: widget.hasNextChapter,
                        onNextChapter: widget.onNextChapter,
                        onScrollToTop: _scrollToTop,
                        onClose: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                  ),
                ),
              ],
            ), // Stack
          ), // SizedBox
        ), // GestureDetector (inner)
      ), // Align
    ); // GestureDetector (outer)
  }
}
