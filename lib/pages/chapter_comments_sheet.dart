import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';

import '../api/ai_api.dart';
import '../api/api_client.dart';
import '../l10n/app_localizations.dart';
import '../models/chapter_comment.dart';
import '../models/user_manager.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/app_logger.dart';
import '../utils/chapter_summary_cache.dart';
import '../utils/comment_text.dart';
import '../utils/network_error.dart';
import '../utils/time_format.dart';
import '../utils/toast.dart';
import '../widgets/confetti_celebration.dart';
import '../widgets/text_controller_scope.dart';
import 'chapter_comment_display.dart';
import 'chapter_comments/comment_paging.dart';
import 'chapter_comments/comment_scroll_behavior.dart';

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
  static const _pageSize = 100;
  bool _confettiShown = false;
  static const _commentRowSpacing = 8.0;
  static const _commentListBottomPadding = 124.0;
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
  bool _loadingAll = false;
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
    _aiSettings.load().then((_) {
      if (!mounted) return;
      setState(() {}); // AI config loaded; refresh toolbar visibility.
      _loadCachedSummary().then((_) => _maybeAutoSummary());
    });
    if (widget.initialComments != null) {
      _comments = List<ChapterComment>.from(widget.initialComments!);
      _total = widget.initialTotal ?? _comments.length;
      _loading = false;
      _rebuildGroupedEntries();
      // 初始评论已达撒花条件时立即触发（此前仅 _loadAllComments 路径会检查，
      // 导致已加载完成的评论区永远不触发）。
      _maybeShowConfetti();
      if (_user.commentAutoLoadAll && _comments.length < _total) {
        _loadAllComments();
      }
      return;
    }
    _loadComments().then((_) {
      if (_user.commentAutoLoadAll && _comments.length < _total) {
        _loadAllComments();
      }
    });
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
                            borderRadius: AppRadius.fullR,
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
                                      l10n.chapterCommentsTitle,
                                      style: tt.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
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
                              if (!_allCommentsLoaded)
                                _loadingAll
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: Padding(
                                          padding: EdgeInsets.all(2),
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      )
                                    : IconButton(
                                        tooltip:
                                            l10n.chapterCommentsLoadAllTooltip,
                                        onPressed: _loadAllComments,
                                        icon: const Icon(Icons.refresh),
                                      ),
                              if (_aiSettings.hasApiKey &&
                                  _aiSettings.summaryEnabled) ...[
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
                              ],
                              IconButton(
                                tooltip: _useCompactLayout
                                    ? l10n.chapterCommentsSwitchToListLayout
                                    : l10n.chapterCommentsSwitchToCompactLayout,
                                onPressed: () {
                                  setState(
                                    () =>
                                        _useCompactLayout = !_useCompactLayout,
                                  );
                                  _user.setCommentCompactLayout(
                                    _useCompactLayout,
                                  );
                                },
                                icon: Icon(
                                  _useCompactLayout
                                      ? Icons.view_agenda_outlined
                                      : Icons.dashboard_outlined,
                                ),
                              ),
                              IconButton(
                                tooltip: l10n.commentSettingsTitle,
                                onPressed: _showCommentSettings,
                                icon: const Icon(Icons.tune),
                              ),
                              Text(
                                _buildCountLabel(l10n),
                                style: tt.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
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
                  right: 16,
                  bottom: 16,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: showFloatingButtons,
                    builder: (context, showFloatingButtons, child) {
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
                            child: Builder(
                              builder: (context) {
                                final buttonBackgroundColor =
                                    cs.primaryContainer;
                                final buttonForegroundColor =
                                    cs.onPrimaryContainer;
                                final buttonStyle = FilledButton.styleFrom(
                                  backgroundColor: buttonBackgroundColor,
                                  foregroundColor: buttonForegroundColor,
                                  elevation: 6,
                                  shadowColor: AppShadows.floatingTint(0.22),
                                  minimumSize: const Size(0, 52),
                                  maximumSize: const Size.fromHeight(52),
                                  fixedSize: const Size.fromHeight(52),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: AppRadius.smR,
                                  ),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                );

                                return Row(
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
                                    FilledButton.icon(
                                      style: buttonStyle,
                                      onPressed: () {
                                        widget.onBackToCatalog?.call();
                                        Navigator.of(
                                          context,
                                        ).pop('back_to_catalog');
                                      },
                                      icon: const Icon(Icons.list_rounded),
                                      label: Text(l10n.chapterCommentsCatalog),
                                    ),
                                    if (widget.hasNextChapter) ...[
                                      const SizedBox(width: AppSpacing.sm),
                                      FilledButton.icon(
                                        style: buttonStyle,
                                        onPressed: widget.onNextChapter,
                                        icon: const Icon(
                                          Icons.skip_next_rounded,
                                        ),
                                        label: Text(l10n.chapterCommentsNext),
                                      ),
                                    ],
                                    const SizedBox(width: AppSpacing.sm),
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox.square(
                                          dimension: 52,
                                          child: FilledButton(
                                            style: buttonStyle.copyWith(
                                              padding:
                                                  const WidgetStatePropertyAll(
                                                    EdgeInsets.zero,
                                                  ),
                                              minimumSize:
                                                  const WidgetStatePropertyAll(
                                                    Size.square(52),
                                                  ),
                                              maximumSize:
                                                  const WidgetStatePropertyAll(
                                                    Size.square(52),
                                                  ),
                                            ),
                                            onPressed: _scrollToTop,
                                            child: const Center(
                                              child: Icon(
                                                Icons.arrow_upward_rounded,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: AppSpacing.sm),
                                        SizedBox.square(
                                          dimension: 52,
                                          child: FilledButton(
                                            style: buttonStyle.copyWith(
                                              padding:
                                                  const WidgetStatePropertyAll(
                                                    EdgeInsets.zero,
                                                  ),
                                              minimumSize:
                                                  const WidgetStatePropertyAll(
                                                    Size.square(52),
                                                  ),
                                              maximumSize:
                                                  const WidgetStatePropertyAll(
                                                    Size.square(52),
                                                  ),
                                            ),
                                            onPressed: () => Navigator.of(
                                              context,
                                            ).maybePop(),
                                            child: const Center(
                                              child: Icon(
                                                Icons
                                                    .keyboard_arrow_down_rounded,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
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
