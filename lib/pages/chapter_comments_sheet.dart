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
import '../utils/chinese_converter.dart';
import '../utils/comment_text.dart';
import '../utils/network_error.dart';
import '../utils/time_format.dart';
import '../utils/toast.dart';
import '../widgets/confetti_celebration.dart';
import '../widgets/text_controller_scope.dart';
import 'chapter_comment_display.dart';
import 'chapter_comments/comment_paging.dart';
import 'chapter_comments/comment_scroll_behavior.dart';

part 'chapter_comments/comment_models.dart';
part 'chapter_comments/comment_settings_panel.dart';
part 'chapter_comments/comment_style.dart';
part 'chapter_comments/comment_widgets.dart';

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

  void _flushSummaryText(
    StringBuffer buffer,
    StringBuffer reasoningBuffer, {
    bool allowScroll = true,
    bool syncSummaryCache = false,
  }) {
    final summaryText = buffer.toString();
    final reasoningText = reasoningBuffer.toString();
    _aiSummary = summaryText;
    _aiSummaryReasoning = reasoningText;
    if (allowScroll && _summarizing) {
      _scrollReasoningToBottom();
    }
    if (syncSummaryCache) {
      ChapterSummaryCache.updateProgress(
        widget.chapterUuid,
        summaryText,
        reasoningContent: reasoningText,
      );
    }
  }

  void _scheduleSummaryTextFlush(
    StringBuffer buffer,
    StringBuffer reasoningBuffer,
  ) {
    _summaryHasPendingTextFlush = true;
    if (_summaryThrottleScheduled) return;
    _summaryThrottleScheduled = true;
    _summaryThrottleTimer = Timer(const Duration(milliseconds: 66), () {
      _summaryThrottleScheduled = false;
      _summaryThrottleTimer = null;
      if (!mounted || !_summaryHasPendingTextFlush) return;
      _summaryHasPendingTextFlush = false;
      _flushSummaryText(buffer, reasoningBuffer, syncSummaryCache: true);
    });
  }

  void _finalizeSummaryTextFlush(
    StringBuffer buffer,
    StringBuffer reasoningBuffer,
  ) {
    _summaryThrottleTimer?.cancel();
    _summaryThrottleTimer = null;
    _summaryThrottleScheduled = false;
    if (!_summaryHasPendingTextFlush &&
        _aiSummary == buffer.toString() &&
        _aiSummaryReasoning == reasoningBuffer.toString()) {
      return;
    }
    _summaryHasPendingTextFlush = false;
    _flushSummaryText(buffer, reasoningBuffer);
  }

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

  void _onSummaryProgressChanged() {
    if (!mounted) return;
    _applySummaryProgress();
  }

  List<_AiSummaryModelChoice> get _modelChoices {
    final result = <_AiSummaryModelChoice>[];
    for (final provider in _aiSettings.enabledProviders) {
      final seen = <String>{};
      for (final model in provider.models) {
        final trimmed = model.trim();
        if (trimmed.isEmpty || !seen.add(trimmed)) continue;
        result.add(
          _AiSummaryModelChoice(
            providerId: provider.id,
            providerName: provider.name,
            model: trimmed,
          ),
        );
      }
    }
    return result;
  }

  void _applySummaryProgress() {
    if (!_summaryProgress.hasState) {
      if (_usingSharedSummaryProgress) {
        _aiSummary = '';
        _aiSummaryReasoning = '';
        _summarizing = false;
        _summaryError = null;
        _spoilerIds = const {};
        _usingSharedSummaryProgress = false;
        // Panel presence changes are handled by the VN listener.
        // Spoiler id changes need setState so comment masks refresh.
        if (mounted) setState(() {});
      }
      return;
    }

    _usingSharedSummaryProgress = true;
    _summarizing = _summaryProgress.isGenerating;
    if (_summaryProgress.content.isNotEmpty) {
      _aiSummary = _summaryProgress.content;
      final newSpoilerIds = _parseSpoilerIds(_summaryProgress.content);
      if (newSpoilerIds != _spoilerIds) {
        _spoilerIds = newSpoilerIds;
        if (mounted) setState(() {}); // Refresh comment spoiler masks.
      }
    }
    _aiSummaryReasoning = _summaryProgress.reasoningContent;
    if (_summarizing) _scrollReasoningToBottom();
    if (_summaryProgress.error != null) {
      _summaryError = _summaryProgress.error;
    } else if (_summaryProgress.isGenerating ||
        _summaryProgress.content.isNotEmpty) {
      _summaryError = null;
    }
    // Default panel expansion is owned by _SummaryPanel based on aiSettings.
  }

  void _maybeAutoSummary() {
    if (!_aiSettings.hasConfig ||
        !_aiSettings.summaryEnabled ||
        !_aiSettings.autoSummary) {
      return;
    }
    if (_aiSettings.autoSummaryTiming != AiAutoSummaryTiming.onOpen) {
      return;
    }
    if (_aiSummary.isNotEmpty || _summarizing || _comments.isEmpty) return;
    if (_comments.length < _aiSettings.autoSummaryMin) return;
    _summarizeComments();
  }

  Future<void> _loadCachedSummary() async {
    final cached = await ChapterSummaryCache.get(widget.chapterUuid);
    if (!mounted || cached == null || cached.isEmpty) return;
    _aiSummary = cached;
    _aiSummaryReasoning = '';
    setState(() => _spoilerIds = _parseSpoilerIds(cached));
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

  Future<void> _loadComments({
    bool loadMore = false,
    bool force = false,
  }) async {
    if (!force &&
        !loadMore &&
        widget.initialComments != null &&
        _comments.isNotEmpty) {
      return;
    }
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
      final data = await _api.manga.getChapterComments(
        widget.chapterUuid,
        limit: _pageSize,
        offset: loadMore ? _comments.length : 0,
      );
      if (!mounted) return;

      final mergedComments = loadMore
          ? appendDedupedById(_comments, data.list, (c) => c.id)
          : data.list;

      setState(() {
        _comments = mergedComments;
        _total = data.total;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
      _rebuildGroupedEntries();
      _notifyCommentsUpdated();
      if (!loadMore) {
        _maybeAutoSummary();
      }
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

  /// Refreshes page 1 after posting while keeping page 2+ data.
  ///
  /// New comments land on page 1, pushing the old page-1 tail onto page 2.
  /// When the fetched page is full, insert the old tail before existing page 2+.
  Future<void> _refreshFirstPage() async {
    try {
      final data = await _api.manga.getChapterComments(
        widget.chapterUuid,
        limit: _pageSize,
      );
      if (!mounted) return;

      final firstPageComments = data.list;

      // Existing comments that belong to page 2+.
      final existingBeyondPage1 = _comments.length > _pageSize
          ? _comments.sublist(_pageSize)
          : <ChapterComment>[];

      List<ChapterComment> merged;
      if (firstPageComments.length >= _pageSize &&
          existingBeyondPage1.isNotEmpty) {
        // A full page means the old page-1 tail overflowed to page 2.
        final overflowComment = _comments[_pageSize - 1];

        // Avoid duplicating the overflow comment if it already exists.
        final allIds = <int>{
          ...firstPageComments.map((c) => c.id),
          ...existingBeyondPage1.map((c) => c.id),
        };
        final insertOverflow = !allIds.contains(overflowComment.id);

        // Remove comments duplicated by the new page 1.
        merged = appendDedupedById(
          [...firstPageComments, if (insertOverflow) overflowComment],
          existingBeyondPage1,
          (c) => c.id,
        );
      } else {
        // If page 1 is not full or page 2+ is absent, append deduped tail.
        merged = appendDedupedById(
          firstPageComments,
          existingBeyondPage1,
          (c) => c.id,
        );
      }

      setState(() {
        _comments = merged;
        _total = data.total;
        _error = null;
      });
      _rebuildGroupedEntries();
      _notifyCommentsUpdated();
      _maybeAutoSummary();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        tryLoadMoreWhenNearBottom();
      });
    } catch (e) {
      if (!mounted) return;
      // Keep existing data when page-1 refresh fails; only log the issue.
      unawaited(
        AppLogger().recordWarning(
          'Refresh first comment page failed: $e',
          stackTrace: StackTrace.current,
        ),
      );
    }
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

  Future<void> _loadAllComments() async {
    if (_loadingAll) return;
    setState(() => _loadingAll = true);

    try {
      while (mounted && _comments.length < _total) {
        final data = await _api.manga.getChapterComments(
          widget.chapterUuid,
          limit: _pageSize,
          offset: _comments.length,
        );
        if (!mounted) return;

        final newComments = data.list
            .where((item) => !_comments.any((e) => e.id == item.id))
            .toList();
        if (newComments.isEmpty) break;

        setState(() {
          _comments = [..._comments, ...newComments];
          _total = data.total;
        });
        _rebuildGroupedEntries();
        _notifyCommentsUpdated();

        if (_comments.length < _total) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    } finally {
      if (mounted) setState(() => _loadingAll = false);
    }
  }

  bool get _allCommentsLoaded => _total > 0 && _comments.length >= _total;

  Future<void> _summarizeComments() async {
    final l10n = AppLocalizations.of(context)!;
    if (_summarizing) return;
    if (_comments.isEmpty) {
      showToast(context, l10n.chapterCommentsNoSummaryComments, isError: true);
      return;
    }
    if (!_aiSettings.hasConfig || !_aiSettings.summaryEnabled) {
      showToast(
        context,
        l10n.chapterCommentsEnableAiSummaryFirst,
        isError: true,
      );
      return;
    }

    final cancelToken = CancelToken();
    _summaryCancelToken = cancelToken;
    setState(() {
      _summarizing = true;
      _summaryError = null;
      _aiSummary = '';
      _aiSummaryReasoning = '';
      _spoilerIds = const {};
    });
    if (_reasoningScrollController.hasClients) {
      _reasoningScrollController.jumpTo(0);
    }
    ChapterSummaryCache.startProgress(widget.chapterUuid);

    final snippets = _buildCommentSnippets(l10n);
    final comicLine = widget.comicName?.trim().isNotEmpty == true
        ? l10n.chapterCommentsPromptComicLine(widget.comicName!.trim())
        : '';
    final messages = <AiMessage>[
      AiMessage(role: 'system', content: _aiSettings.summaryPrompt),
      AiMessage(
        role: 'user',
        content: l10n.chapterCommentsPromptUser(
          comicLine,
          widget.chapterName,
          _lastSnippetEntries.length,
          snippets,
        ),
      ),
    ];

    final buffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    try {
      final provider = _aiSettings.activeProvider;
      final stream = _aiApi.streamChatChunks(
        apiKey: provider.apiKey!,
        baseUrl: provider.baseUrl,
        apiFormat: provider.apiFormat,
        model: provider.model,
        messages: messages,
        cancelToken: cancelToken,
      );
      await for (final chunk in stream) {
        if (!mounted) return;
        if (chunk.isReasoning) {
          reasoningBuffer.write(chunk.text);
        } else {
          buffer.write(chunk.text);
        }
        _scheduleSummaryTextFlush(buffer, reasoningBuffer);
      }
      _finalizeSummaryTextFlush(buffer, reasoningBuffer);
      if (mounted && buffer.isNotEmpty) {
        final full = buffer.toString();
        setState(() => _spoilerIds = _parseSpoilerIds(full));
        await ChapterSummaryCache.set(
          widget.chapterUuid,
          full,
          reasoningContent: reasoningBuffer.isEmpty
              ? null
              : reasoningBuffer.toString(),
        );
      } else {
        ChapterSummaryCache.clearProgress(widget.chapterUuid);
      }
    } catch (e) {
      if (!mounted) return;
      if (e is DioException && CancelToken.isCancel(e)) {
        final partial = buffer.toString();
        if (partial.isNotEmpty) {
          await ChapterSummaryCache.set(
            widget.chapterUuid,
            partial,
            reasoningContent: reasoningBuffer.isEmpty
                ? null
                : reasoningBuffer.toString(),
          );
        } else {
          ChapterSummaryCache.clearProgress(widget.chapterUuid);
        }
        return;
      }
      final message = _extractSummaryError(e);
      ChapterSummaryCache.failProgress(widget.chapterUuid, message);
      _summaryError = message;
    } finally {
      _summaryThrottleTimer?.cancel();
      _summaryThrottleTimer = null;
      _summaryThrottleScheduled = false;
      _summaryHasPendingTextFlush = false;
      if (mounted) {
        _summarizing = false;
      }
      _summaryCancelToken = null;
    }
  }

  String _buildCommentSnippets(AppLocalizations l10n) {
    const maxChars = 64 * 1024;
    final buffer = StringBuffer();
    final entries = _groupedEntries;
    _lastSnippetEntries = entries;
    var truncated = false;
    for (final entry in entries) {
      final text = entry.content.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isEmpty) continue;
      final id = entry.primaryComment.id;
      final line = entry.isMerged
          ? l10n.chapterCommentsMergedSnippet(id, entry.count, text)
          : l10n.chapterCommentsSingleSnippet(
              id,
              entry.primaryComment.userName,
              text,
            );
      if (buffer.length + line.length > maxChars) {
        truncated = true;
        break;
      }
      buffer.write(line);
    }
    if (truncated) {
      buffer.write(l10n.chapterCommentsSnippetsTruncated(entries.length));
    }
    return buffer.toString();
  }

  static final _codeBlockRegex = RegExp(
    r'```[^`\r\n]*\r?\n([\s\S]*?)\r?\n\s*```',
  );
  static final _arrayRegex = RegExp(r'\[\s*([\d,\s]*)\s*\]');
  static final _spoilerLegacyRegex = RegExp(r'<!--\s*SPOILERS\s*:([^>]*)-->');

  /// Parses spoiler ids from model output, keeping legacy HTML marker support.
  /// Prefers the last fenced code block, then the last array, then legacy comment.
  Set<int> _parseSpoilerIds(String text) {
    // 1) Last fenced code block.
    Match? lastBlock;
    for (final m in _codeBlockRegex.allMatches(text)) {
      lastBlock = m;
    }
    if (lastBlock != null) {
      final content = lastBlock.group(1) ?? '';
      final arr = _arrayRegex.firstMatch(content);
      if (arr != null) return _splitIds(arr.group(1) ?? '');
    }
    // 2) Without code blocks, use the last [id, id, ...] array.
    Match? lastArr;
    for (final m in _arrayRegex.allMatches(text)) {
      lastArr = m;
    }
    if (lastArr != null) return _splitIds(lastArr.group(1) ?? '');
    // 3) Fallback to the legacy HTML comment.
    final legacy = _spoilerLegacyRegex.firstMatch(text);
    if (legacy != null) return _splitIds(legacy.group(1) ?? '');
    return const {};
  }

  Set<int> _splitIds(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return const {};
    final result = <int>{};
    for (final part in s.split(',')) {
      final n = int.tryParse(part.trim());
      if (n != null && n > 0) result.add(n);
    }
    return result;
  }

  /// Strips machine-readable markers from display text; only removes the last block.
  String _stripSpoilersMarker(String text) {
    Match? lastBlock;
    for (final m in _codeBlockRegex.allMatches(text)) {
      lastBlock = m;
    }
    if (lastBlock != null) {
      text = text.substring(0, lastBlock.start) + text.substring(lastBlock.end);
    }
    return text.replaceAll(_spoilerLegacyRegex, '').trimRight();
  }

  String _extractSummaryError(Object e) {
    return NetworkError.message(e, l10n: AppLocalizations.of(context)!);
  }

  void _stopSummarize() {
    _summaryCancelToken?.cancel('user_stop');
  }

  void _scrollReasoningToBottom() {
    if (_reasoningScrollPending) return;
    _reasoningScrollPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reasoningScrollPending = false;
      if (!mounted) return;
      final c = _reasoningScrollController;
      if (!c.hasClients) return;
      final max = c.position.maxScrollExtent;
      if (max > 0) c.jumpTo(max);
    });
  }

  Future<void> _clearSummary() async {
    await ChapterSummaryCache.remove(widget.chapterUuid);
    if (!mounted) return;
    setState(() {
      _aiSummary = '';
      _aiSummaryReasoning = '';
      _summaryError = null;
      _spoilerIds = const {};
    });
  }

  String _extractCommentPostErrorMessage(Object error) {
    if (error is DioException) {
      final inner = error.error;
      final innerText = inner?.toString().trim();
      if (innerText != null && innerText.isNotEmpty) {
        return innerText;
      }
      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) {
        return message;
      }
    }
    return NetworkError.message(error, l10n: AppLocalizations.of(context)!);
  }

  String _formatCommentPostErrorLog(Object error) {
    if (error is DioException) {
      final buffer = StringBuffer();
      buffer.writeln('DioException');
      buffer.writeln('type: ${error.type}');
      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) {
        buffer.writeln('message: $message');
      }
      buffer.writeln(
        'request: ${error.requestOptions.method} ${error.requestOptions.uri}',
      );

      final requestData = error.requestOptions.data;
      if (requestData != null) {
        buffer.writeln('requestData: ${_formatLogValue(requestData)}');
      }

      final response = error.response;
      if (response != null) {
        buffer.writeln('statusCode: ${response.statusCode}');
        if (response.data != null) {
          buffer.writeln('responseData: ${_formatLogValue(response.data)}');
        }
      }

      buffer.writeln('toString: ${error.toString()}');
      return buffer.toString().trimRight();
    }

    return error.toString();
  }

  String _formatLogValue(Object? value) {
    if (value == null) return 'null';
    if (value is String) return value;
    try {
      return jsonEncode(value);
    } catch (_) {
      return value.toString();
    }
  }

  Widget _buildPostCommentErrorPanel(
    BuildContext context, {
    required String message,
    required String log,
    required VoidCallback onCopy,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.55),
        borderRadius: AppRadius.mdR,
        border: Border.all(color: cs.error.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, size: 18, color: cs.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.chapterCommentsDioException,
                  style: tt.labelLarge?.copyWith(
                    color: cs.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onCopy,
                style: TextButton.styleFrom(foregroundColor: cs.error),
                icon: const Icon(Icons.copy, size: 16),
                label: Text(l10n.chapterCommentsCopyLog),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message,
            style: tt.bodySmall?.copyWith(
              color: cs.onErrorContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 140),
            child: SingleChildScrollView(
              child: SelectableText(
                log,
                style: tt.bodySmall?.copyWith(
                  color: cs.onErrorContainer.withValues(alpha: 0.9),
                  fontFamily: 'monospace',
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showPostCommentDialog() async {
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
    String? errorLog;

    Future<void> submit(
      BuildContext dialogContext,
      StateSetter setLocal,
      TextEditingController controller,
    ) async {
      final content = controller.text.trim();
      final length = CommentText.lengthOf(content);
      if (length < CommentText.minLength || length > CommentText.maxLength) {
        setLocal(() {
          errorText = l10n.chapterCommentsLengthRange;
          errorLog = 'ValidationError: ${l10n.chapterCommentsLengthRange}';
        });
        return;
      }

      setLocal(() {
        submitting = true;
        errorText = null;
        errorLog = null;
      });

      try {
        await _api.manga.postChapterComment(widget.chapterUuid, content);
        if (!mounted) return;
        if (dialogContext.mounted) {
          Navigator.of(dialogContext).pop();
        }
        showToast(context, l10n.chapterCommentsPosted);
        await _refreshFirstPage();
      } catch (e) {
        if (!dialogContext.mounted) return;
        setLocal(() {
          submitting = false;
          errorText = _extractCommentPostErrorMessage(e);
          errorLog = _formatCommentPostErrorLog(e);
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
                  title: Text(l10n.chapterCommentsPostTitle),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
                            hintText: l10n.chapterCommentsPostHint,
                            helperText: l10n.chapterCommentsLengthHelper,
                            errorText: errorText,
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (_) => setLocal(() {
                            errorText = null;
                            errorLog = null;
                          }),
                        ),
                        if (errorText != null && errorLog != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          _buildPostCommentErrorPanel(
                            dialogContext,
                            message: errorText!,
                            log: errorLog!,
                            onCopy: () async {
                              await Clipboard.setData(
                                ClipboardData(text: errorLog!),
                              );
                              if (!mounted) return;
                              showToast(context, l10n.chapterCommentsLogCopied);
                            },
                          ),
                        ],
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
                          : Text(l10n.chapterCommentsPublish),
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

  /// 点击合并评论：弹窗展示所有发表该评论的用户，按时间从新到旧排列。
  Future<void> _showMergedCommentUsersDialog(
    ChapterCommentDisplayEntry entry,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final comments = [...entry.comments]
      ..sort((a, b) {
        final ta = _parseCommentTime(a.createAt);
        final tb = _parseCommentTime(b.createAt);
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1; // 无法解析的排到最后
        if (tb == null) return -1;
        return tb.compareTo(ta); // 从新到旧
      });

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        minHeight: MediaQuery.sizeOf(context).height / 3,
        maxHeight:
            MediaQuery.sizeOf(context).height *
            _mergedCommentSheetMaxHeightFactor,
      ),
      builder: (sheetContext) {
        final cs = Theme.of(sheetContext).colorScheme;
        final tt = Theme.of(sheetContext).textTheme;
        final earliest = comments.isEmpty
            ? null
            : TimeFormat.relativeOf(comments.last.createAt, l10n);
        final latest = comments.isEmpty
            ? null
            : TimeFormat.relativeOf(comments.first.createAt, l10n);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (earliest != null && latest != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    '$earliest ~ $latest',
                    textAlign: TextAlign.center,
                    style: _buildCommentTimeStyle(tt, cs),
                  ),
                ),
              Flexible(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  shrinkWrap: true,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return Wrap(
                            spacing: _commentRowSpacing,
                            runSpacing: _commentRowSpacing,
                            children: [
                              for (final c in comments)
                                _buildMergedUserCard(
                                  context,
                                  c,
                                  l10n,
                                  constraints.maxWidth,
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 解析评论时间字符串，失败返回 null（与 TimeFormat.relativeOf 一致地处理空格分隔）。
  static DateTime? _parseCommentTime(String dateStr) {
    if (dateStr.isEmpty) return null;
    return DateTime.tryParse(dateStr.replaceFirst(' ', 'T'));
  }

  /// 合并评论用户卡片：按内容宽度自适应，多个卡片同行排列放不下才换行。
  Widget _buildMergedUserCard(
    BuildContext context,
    ChapterComment comment,
    AppLocalizations l10n,
    double maxWidth,
  ) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final name = comment.userName.trim();
    final displayName = name.isEmpty ? l10n.commentSettingsAnonymousUser : name;
    final userStyle = _buildCommentUserStyle(
      tt,
      cs,
      compact: true,
    )?.copyWith(color: cs.onSurface);
    final timeStyle = _buildCommentTimeStyle(
      tt,
      cs,
    )?.copyWith(color: cs.onSurfaceVariant);
    const avatarGap = 6.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (details) => _showCommentActions(
        content: comment.comment,
        comment: comment,
        canBlock: true,
        position: details.globalPosition,
      ),
      onSecondaryTapDown: (details) => _showCommentActions(
        content: comment.comment,
        comment: comment,
        canBlock: true,
        position: details.globalPosition,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth * 0.8),
        child: IntrinsicWidth(
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            decoration: _buildCommentCardDecoration(
              cs,
              brightness: Theme.of(context).brightness,
              highlightAsHot: false,
              withShadow: false,
              backgroundColor: cs.surfaceContainerHigh,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_showUserAvatar) ...[
                  _CommentAvatar(imageUrl: comment.userAvatar, size: 20),
                  const SizedBox(width: avatarGap),
                ],
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: userStyle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      TimeFormat.relativeOf(comment.createAt, l10n),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: timeStyle,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showCommentActionMenu(
    ChapterCommentDisplayEntry entry,
    Offset position,
  ) => _showCommentActions(
    content: entry.content,
    comment: entry.primaryComment,
    // 合并评论对应多个用户，屏蔽需在用户卡片上单独操作。
    canBlock: !entry.isMerged,
    position: position,
  );

  /// 评论操作菜单（长按 / 右键弹出），单个用户才提供屏蔽入口。
  Future<void> _showCommentActions({
    required String content,
    required ChapterComment comment,
    required bool canBlock,
    required Offset position,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    content = content.trim();
    if (content.isEmpty) return;

    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'copy',
          height: 40,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.copy_outlined, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Text(l10n.copyButton),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'plus_one',
          height: 40,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_comment_outlined, size: 18),
              SizedBox(width: AppSpacing.sm),
              Text('+1'),
            ],
          ),
        ),
        if (canBlock)
          PopupMenuItem<String>(
            value: 'block',
            height: 40,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.block_outlined, size: 18),
                const SizedBox(width: AppSpacing.sm),
                Text(l10n.chapterCommentsBlockUser),
              ],
            ),
          ),
      ],
    );

    if (!mounted || action == null) return;
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: content));
      if (!mounted) return;
      showToast(context, l10n.chapterCommentsCopied);
    } else if (action == 'plus_one') {
      await _plusOneComment(content);
    } else if (action == 'block') {
      await _blockCommentUser(comment);
    }
  }

  Future<void> _blockCommentUser(ChapterComment comment) async {
    final l10n = AppLocalizations.of(context)!;
    final name = comment.userName.trim();
    if (_user.commentBlockNoRemind) {
      await _user.blockCommentUser(comment.userId, name);
      if (!mounted) return;
      setState(_rebuildGroupedEntries);
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
                    : l10n.chapterCommentsBlockNamedConfirm(name),
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
    setState(_rebuildGroupedEntries);
    showToast(context, l10n.chapterCommentsUserBlocked);
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
      await _api.manga.postChapterComment(widget.chapterUuid, content);
      if (!mounted) return;
      showToast(context, l10n.chapterCommentsPlusOneSent);
      await _refreshFirstPage();
    } catch (e) {
      if (!mounted) return;
      await _showPostCommentErrorDialog(e);
    }
  }

  Future<void> _showPostCommentErrorDialog(Object error) async {
    final l10n = AppLocalizations.of(context)!;
    final message = _extractCommentPostErrorMessage(error);
    final log = _formatCommentPostErrorLog(error);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.chapterCommentsPostFailed),
        content: SingleChildScrollView(
          child: _buildPostCommentErrorPanel(
            dialogContext,
            message: message,
            log: log,
            onCopy: () async {
              await Clipboard.setData(ClipboardData(text: log));
              if (!mounted) return;
              showToast(context, l10n.chapterCommentsLogCopied);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.closeButton),
          ),
        ],
      ),
    );
  }

  Future<void> _showCommentSettings() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * _sheetMaxHeightFactor,
      ),
      builder: (sheetContext) {
        final sheetSize = MediaQuery.sizeOf(sheetContext);
        return Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: sheetSize.width,
            height: sheetSize.height * _sheetMaxHeightFactor,
            child: ExcludeSemantics(
              child: CommentSettingsPanel(
                useCompactLayout: _useCompactLayout,
                showUserAvatar: _showUserAvatar,
                showUserName: _showUserName,
                showCommentTime: _showCommentTime,
                commentFontScale: _commentFontScale,
                commentPreload: _user.commentPreload,
                commentAutoLoadAll: _user.commentAutoLoadAll,
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
                onPreloadChanged: (enabled) {
                  _user.setCommentPreload(enabled);
                  if (!enabled &&
                      _aiSettings.autoSummaryTiming ==
                          AiAutoSummaryTiming.afterPreload) {
                    _aiSettings.setAutoSummaryTiming(
                      AiAutoSummaryTiming.onOpen,
                    );
                  }
                },
                onAutoLoadAllChanged: (enabled) {
                  _user.setCommentAutoLoadAll(enabled);
                },
              ),
            ),
          ),
        );
      },
    );
    if (!mounted) return;
    // 编辑屏蔽词/屏蔽用户后，重新过滤已加载的评论。
    setState(_rebuildGroupedEntries);
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

  /// 评论区计数文案：全部加载且无屏蔽时显示「N 条」；
  /// 有屏蔽时为「显示数/总数|屏蔽数」，屏蔽为 0 则不显示 |屏蔽数。
  String _buildCountLabel(AppLocalizations l10n) {
    if (_total <= 0) return '';
    if (_allCommentsLoaded && _blockedCount == 0) {
      return l10n.chapterCommentsTotalCount(_total);
    }
    final shown = _comments.length - _blockedCount;
    if (_blockedCount > 0) {
      return l10n.chapterCommentsCountWithBlocked(shown, _total, _blockedCount);
    }
    return '$shown/$_total';
  }

  Widget _buildBody(BuildContext context, ColorScheme cs, TextTheme tt) {
    final l10n = AppLocalizations.of(context)!;
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
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.chapterCommentsLoadFailed,
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
                onPressed: () => _loadComments(),
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
              l10n.chapterCommentsEmptySubtitle,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    final entries = _groupedEntries;
    final hasSummary = _hasSummaryPanel;
    final summaryOffset = hasSummary ? 1 : 0;

    if (!_useCompactLayout) {
      return NotificationListener<ScrollNotification>(
        onNotification: handleScrollNotification,
        child: ListView.separated(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(
            16,
            12,
            16,
            _commentListBottomPadding,
          ),
          itemCount: summaryOffset + entries.length + (_loadingMore ? 1 : 0),
          separatorBuilder: (_, index) => const SizedBox(height: 10),
          itemBuilder: (_, index) {
            if (hasSummary && index == 0) {
              return _buildSummaryPanel(cs, tt);
            }
            final dataIndex = index - summaryOffset;
            if (dataIndex == entries.length && _loadingMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: ExpressiveLoadingIndicator()),
              );
            }

            final entry = entries[dataIndex];
            return _CommentCard(
              entry: entry,
              relativeTime: TimeFormat.relativeOf(
                entry.createAt,
                AppLocalizations.of(context)!,
              ),
              showAvatar: _showUserAvatar,
              showUserName: _showUserName,
              showCommentTime: _showCommentTime,
              spoilerIds: _aiSettings.spoilerAnalysis ? _spoilerIds : const {},
              onLongPress: (entry, position) =>
                  _showCommentActionMenu(entry, position),
              onTapMerged: (entry) => _showMergedCommentUsersDialog(entry),
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
          onNotification: handleScrollNotification,
          child: ListView.separated(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(
              16,
              12,
              16,
              _commentListBottomPadding,
            ),
            itemCount: summaryOffset + rows.length + (_loadingMore ? 1 : 0),
            separatorBuilder: (_, index) =>
                const SizedBox(height: AppSpacing.sm),
            itemBuilder: (_, index) {
              if (hasSummary && index == 0) {
                return _buildSummaryPanel(cs, tt);
              }
              final dataIndex = index - summaryOffset;
              if (dataIndex == rows.length && _loadingMore) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: ExpressiveLoadingIndicator()),
                );
              }

              final row = rows[dataIndex];
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < row.items.length; i++) ...[
                      SizedBox(
                        width: row.items[i].width,
                        child: _CommentCard(
                          entry: row.items[i].entry,
                          relativeTime: TimeFormat.relativeOf(
                            row.items[i].entry.createAt,
                            AppLocalizations.of(context)!,
                          ),
                          compact: true,
                          showAvatar: _showUserAvatar,
                          showUserName: _showUserName,
                          showCommentTime: _showCommentTime,
                          spoilerIds: _aiSettings.spoilerAnalysis
                              ? _spoilerIds
                              : const {},
                          onLongPress: (entry, position) =>
                              _showCommentActionMenu(entry, position),
                          onTapMerged: (entry) =>
                              _showMergedCommentUsersDialog(entry),
                        ),
                      ),
                      if (i != row.items.length - 1)
                        const SizedBox(width: _commentRowSpacing),
                    ],
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  bool get _hasSummaryPanel =>
      _aiSettings.hasApiKey &&
      _aiSettings.summaryEnabled &&
      (_aiSummary.isNotEmpty ||
          _aiSummaryReasoning.isNotEmpty ||
          _summarizing ||
          _summaryError != null);

  Widget _buildModelNameButton(ColorScheme cs, TextTheme tt) {
    final l10n = AppLocalizations.of(context)!;
    final canSwitch = !_summarizing;
    final provider = _aiSettings.activeProvider;
    return Tooltip(
      message: canSwitch
          ? l10n.chapterCommentsSwitchModel
          : l10n.chapterCommentsCannotSwitchModelGenerating,
      child: InkWell(
        borderRadius: AppRadius.fullR,
        onTap: canSwitch ? _showModelPickerSheet : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  l10n.chapterCommentsModelSummary(provider.model),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.labelLarge?.copyWith(
                    color: canSwitch ? cs.primary : cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.keyboard_arrow_up,
                size: 14,
                color: canSwitch ? cs.primary : cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _summaryStatusColor(
    ColorScheme cs, {
    required bool hasContent,
    required bool hasReasoning,
  }) {
    final isError = _summaryError != null;
    final isComplete = !_summarizing && !isError && hasContent;
    if (_summarizing) return Colors.amber;
    if (isError) return cs.error;
    if (isComplete) return cs.primary;
    if (hasReasoning) return cs.tertiary;
    return cs.outlineVariant;
  }

  Widget _buildSummaryTitle(ColorScheme cs, TextTheme tt) {
    final l10n = AppLocalizations.of(context)!;
    final provider = _aiSettings.activeProvider;
    if (_modelChoices.isNotEmpty) {
      return _buildModelNameButton(cs, tt);
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 180),
      child: Text(
        l10n.chapterCommentsModelSummary(provider.model),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: tt.labelLarge?.copyWith(
          color: cs.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Future<void> _showModelPickerSheet() async {
    final l10n = AppLocalizations.of(context)!;
    final choices = _modelChoices;
    if (_summarizing || choices.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final cs = Theme.of(sheetContext).colorScheme;
        final tt = Theme.of(sheetContext).textTheme;
        final active = _aiSettings.activeProvider;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      l10n.chapterCommentsSwitchModel,
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
                Text(
                  l10n.chapterCommentsActiveModel(active.name, active.model),
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.md),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: choices.length,
                    itemBuilder: (context, index) {
                      final choice = choices[index];
                      final showHeader =
                          index == 0 ||
                          choices[index - 1].providerId != choice.providerId;
                      final selected =
                          active.id == choice.providerId &&
                          active.model == choice.model;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (showHeader) ...[
                            if (index > 0) const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                              child: Text(
                                choice.providerName,
                                style: tt.labelSmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                          ListTile(
                            dense: true,
                            selected: selected,
                            shape: RoundedRectangleBorder(
                              borderRadius: AppRadius.mdR,
                            ),
                            title: Text(
                              choice.model,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: selected
                                ? Icon(Icons.check, color: cs.primary)
                                : null,
                            onTap: () async {
                              await _aiSettings.setActiveModel(
                                providerId: choice.providerId,
                                model: choice.model,
                              );
                              if (sheetContext.mounted) {
                                Navigator.of(sheetContext).pop();
                              }
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummaryPanel(ColorScheme cs, TextTheme tt) {
    return _SummaryPanel(
      aiSummaryListenable: _aiSummaryVN,
      aiSummaryReasoningListenable: _aiSummaryReasoningVN,
      summarizingListenable: _summarizingVN,
      summaryErrorListenable: _summaryErrorVN,
      reasoningScrollController: _reasoningScrollController,
      aiSettings: _aiSettings,
      modelChoices: _modelChoices,
      buildSummaryTitle: () => _buildSummaryTitle(cs, tt),
      summaryStatusColor:
          ({required bool hasContent, required bool hasReasoning}) =>
              _summaryStatusColor(
                cs,
                hasContent: hasContent,
                hasReasoning: hasReasoning,
              ),
      stripSpoilersMarker: _stripSpoilersMarker,
      onShowModelPicker: _showModelPickerSheet,
      onStopSummarize: _stopSummarize,
      onSummarizeComments: _summarizeComments,
      onClearSummary: _clearSummary,
      onCopied: () => showToast(
        context,
        AppLocalizations.of(context)!.chapterCommentsCopied,
      ),
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
    const compactCardHorizontalPadding = 20.0;
    const compactTextWidthBuffer = 10.0;
    final preferredMaxWidth = maxWidth * 0.8;

    final estimatedWidths = entries.map((entry) {
      final compactBodyStyle = buildCommentBodyStyle(textTheme, compact: true);
      final bodyWidth = _measureTextWidth(
        entry.content,
        compactBodyStyle,
        textScaler,
        preferredMaxWidth,
      );

      final headerWidth = _estimateCompactHeaderWidth(
        context,
        entry,
        preferredMaxWidth,
      );

      var contentWidth = bodyWidth > headerWidth ? bodyWidth : headerWidth;
      final mergedInlineWidth = _estimateCompactMergedInlineWidth(
        context,
        entry,
        bodyWidth: bodyWidth,
        maxWidth: preferredMaxWidth,
      );
      if (mergedInlineWidth > contentWidth) {
        contentWidth = mergedInlineWidth;
      }

      final cardWidth =
          (contentWidth + compactCardHorizontalPadding + compactTextWidthBuffer)
              .clamp(minWidth, preferredMaxWidth);
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
        final extraWidth = remainder / currentItems.length;
        currentItems = [
          for (final item in currentItems)
            _CommentLayoutItem(
              entry: item.entry,
              width: item.width + extraWidth,
            ),
        ];
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
    final showCountTag = _shouldShowMergedCountTag(entry.count);

    if (entry.isMerged) {
      final countTagWidth = showCountTag
          ? _estimateMergedCountTagWidth(
              context,
              entry.count,
              maxWidth,
              compact: true,
            )
          : 0.0;

      if (!_showUserAvatar) {
        return countTagWidth;
      }

      final avatarCount = entry.avatarComments().length;
      final avatarWidth = _avatarStackWidth(
        avatarCount,
        avatarSize: 22,
        overlap: 8,
      );
      if (!showCountTag) {
        return avatarWidth;
      }

      return avatarWidth + 8 + countTagWidth;
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
        TimeFormat.relativeOf(entry.createAt, AppLocalizations.of(context)!),
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

  double _estimateCompactMergedInlineWidth(
    BuildContext context,
    ChapterCommentDisplayEntry entry, {
    required double bodyWidth,
    required double maxWidth,
  }) {
    if (!entry.isMerged ||
        _showUserAvatar ||
        !_shouldShowMergedCountTag(entry.count)) {
      return bodyWidth;
    }

    return bodyWidth +
        8 +
        _estimateMergedCountTagWidth(
          context,
          entry.count,
          maxWidth,
          compact: true,
        );
  }
}

class _SummaryPanel extends StatefulWidget {
  final ValueListenable<String> aiSummaryListenable;
  final ValueListenable<String> aiSummaryReasoningListenable;
  final ValueListenable<bool> summarizingListenable;
  final ValueListenable<String> summaryErrorListenable;
  final ScrollController reasoningScrollController;
  final AiSettings aiSettings;
  final List<_AiSummaryModelChoice> modelChoices;
  final Widget Function() buildSummaryTitle;
  final Color Function({required bool hasContent, required bool hasReasoning})
  summaryStatusColor;
  final String Function(String text) stripSpoilersMarker;
  final Future<void> Function() onShowModelPicker;
  final void Function() onStopSummarize;
  final Future<void> Function() onSummarizeComments;
  final Future<void> Function() onClearSummary;
  final VoidCallback onCopied;

  const _SummaryPanel({
    required this.aiSummaryListenable,
    required this.aiSummaryReasoningListenable,
    required this.summarizingListenable,
    required this.summaryErrorListenable,
    required this.reasoningScrollController,
    required this.aiSettings,
    required this.modelChoices,
    required this.buildSummaryTitle,
    required this.summaryStatusColor,
    required this.stripSpoilersMarker,
    required this.onShowModelPicker,
    required this.onStopSummarize,
    required this.onSummarizeComments,
    required this.onClearSummary,
    required this.onCopied,
  });

  @override
  State<_SummaryPanel> createState() => _SummaryPanelState();
}

class _SummaryPanelState extends State<_SummaryPanel> {
  static const double _streamingSummaryPlaceholderHeight = 44;
  static const double _streamingSummaryBoxHeight = 220;
  bool _summaryExpanded = false;
  bool _summaryExpansionTouched = false;
  bool _summaryReasoningExpanded = false;
  bool _summaryReasoningExpansionTouched = false;

  bool get _summarizing => widget.summarizingListenable.value;
  String get _aiSummary => widget.aiSummaryListenable.value;
  String get _aiSummaryReasoning => widget.aiSummaryReasoningListenable.value;
  String? get _summaryError {
    final value = widget.summaryErrorListenable.value;
    return value.isEmpty ? null : value;
  }

  @override
  void initState() {
    super.initState();
    _applySummaryDefaultExpansion();
    widget.summarizingListenable.addListener(_onSummarizingChanged);
  }

  @override
  void didUpdateWidget(covariant _SummaryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.summarizingListenable != widget.summarizingListenable) {
      oldWidget.summarizingListenable.removeListener(_onSummarizingChanged);
      widget.summarizingListenable.addListener(_onSummarizingChanged);
    }
    _applySummaryDefaultExpansion();
  }

  @override
  void dispose() {
    widget.summarizingListenable.removeListener(_onSummarizingChanged);
    super.dispose();
  }

  void _onSummarizingChanged() {
    if (!_summarizing && !_summaryExpansionTouched) {
      _applySummaryDefaultExpansion();
    }
    if (_summarizing) {
      _summaryReasoningExpanded = false;
      _summaryReasoningExpansionTouched = false;
    }
  }

  void _applySummaryDefaultExpansion() {
    if (!_summaryExpansionTouched) {
      _summaryExpanded = !widget.aiSettings.summaryCollapsed;
    }
  }

  void _toggleSummaryExpanded() {
    setState(() {
      _summaryExpansionTouched = true;
      _summaryExpanded = !_summaryExpanded;
    });
  }

  void _toggleSummaryReasoningExpanded() {
    setState(() {
      _summaryReasoningExpansionTouched = true;
      _summaryReasoningExpanded = !_summaryReasoningExpanded;
    });
  }

  Widget _buildSummaryReasoningBox(
    BuildContext context,
    ColorScheme cs,
    TextTheme tt, {
    required String reasoning,
    required bool expanded,
    required bool toggleable,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final textStyle = tt.bodySmall?.copyWith(
      color: cs.onSurfaceVariant.withValues(alpha: 0.78),
      fontSize: 12,
      height: 1.35,
    );
    return InkWell(
      borderRadius: AppRadius.mdR,
      onTap: toggleable ? _toggleSummaryReasoningExpanded : null,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(4, 2, 8, 0),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest.withValues(alpha: 0.75),
          borderRadius: AppRadius.mdR,
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.psychology_alt_outlined,
                  size: 14,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.78),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  l10n.chapterCommentsReasoning,
                  style: textStyle?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (toggleable) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.78),
                  ),
                ],
              ],
            ),
            if (expanded) ...[
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  controller: widget.reasoningScrollController,
                  child: Text(reasoning, style: textStyle),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStreamingReasoningPlaceholder(
    BuildContext context,
    ColorScheme cs,
    TextTheme tt,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(4, 2, 8, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest.withValues(alpha: 0.75),
        borderRadius: AppRadius.mdR,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.psychology_alt_outlined,
                size: 14,
                color: cs.onSurfaceVariant.withValues(alpha: 0.78),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                l10n.chapterCommentsReasoning,
                style: tt.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.78),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStreamingSummaryContent(
    BuildContext context,
    ColorScheme cs,
    TextTheme tt,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final summaryText = widget.stripSpoilersMarker(_aiSummary);
    final hasSummaryText = summaryText.trim().isNotEmpty;
    final boxHeight = hasSummaryText
        ? _streamingSummaryBoxHeight
        : _streamingSummaryPlaceholderHeight;
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: boxHeight, maxHeight: boxHeight),
      margin: const EdgeInsets.fromLTRB(4, 2, 8, 2),
      padding: const EdgeInsets.fromLTRB(0, 0, 4, 0),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest.withValues(alpha: 0.42),
        borderRadius: AppRadius.mdR,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Scrollbar(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
          child: !hasSummaryText
              ? Text(
                  l10n.chapterCommentsGenerating,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                )
              : MarkdownBody(
                  data: summaryText,
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                      .copyWith(
                        p: tt.bodyMedium?.copyWith(height: 1.5),
                        h1: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        h2: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        h3: tt.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                        strong: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: cs.primary,
                        ),
                        listBullet: tt.bodyMedium,
                      ),
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.aiSummaryListenable,
        widget.aiSummaryReasoningListenable,
        widget.summarizingListenable,
        widget.summaryErrorListenable,
      ]),
      builder: (context, _) {
        final l10n = AppLocalizations.of(context)!;
        final cs = Theme.of(context).colorScheme;
        final tt = Theme.of(context).textTheme;
        final hasContent = _aiSummary.isNotEmpty;
        final reasoning = _aiSummaryReasoning.trim();
        final hasReasoning = reasoning.isNotEmpty;
        final showStreamingSummaryBox = _summarizing;
        final reasoningExpanded =
            hasReasoning &&
            (_summaryReasoningExpansionTouched
                ? _summaryReasoningExpanded
                : false);
        final statusColor = widget.summaryStatusColor(
          hasContent: hasContent,
          hasReasoning: hasReasoning,
        );

        return Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: AppRadius.mdR,
            border: Border.all(
              color: statusColor.withValues(alpha: 0.72),
              width: 1.2,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                borderRadius: AppRadius.smR,
                onTap: _toggleSummaryExpanded,
                child: Row(
                  children: [
                    if (widget.modelChoices.isEmpty)
                      widget.buildSummaryTitle()
                    else
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {},
                        child: widget.buildSummaryTitle(),
                      ),
                    const Spacer(),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: _summaryExpanded
                          ? l10n.chapterCommentsCollapse
                          : l10n.chapterCommentsExpand,
                      onPressed: _toggleSummaryExpanded,
                      icon: Icon(
                        _summaryExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
              if (_summaryExpanded) ...[
                if (_summarizing || hasReasoning) ...[
                  hasReasoning
                      ? _buildSummaryReasoningBox(
                          context,
                          cs,
                          tt,
                          reasoning: reasoning,
                          expanded: reasoningExpanded,
                          toggleable: true,
                        )
                      : _buildStreamingReasoningPlaceholder(context, cs, tt),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (_summaryError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
                    child: Text(
                      l10n.chapterCommentsSummaryFailed(_summaryError!),
                      style: tt.bodySmall?.copyWith(color: cs.error),
                    ),
                  )
                else if (showStreamingSummaryBox)
                  _buildStreamingSummaryContent(context, cs, tt)
                else if (hasContent)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 2, 8, 2),
                    child: MarkdownBody(
                      data: widget.stripSpoilersMarker(_aiSummary),
                      styleSheet:
                          MarkdownStyleSheet.fromTheme(
                            Theme.of(context),
                          ).copyWith(
                            p: tt.bodyMedium?.copyWith(height: 1.5),
                            h1: tt.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            h2: tt.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            h3: tt.bodyLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            strong: tt.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: cs.primary,
                            ),
                            listBullet: tt.bodyMedium,
                          ),
                    ),
                  )
                else if (_summarizing)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
                    child: Text(
                      l10n.chapterCommentsGenerating,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: _summarizing
                          ? l10n.chapterCommentsStop
                          : l10n.chapterCommentsRegenerate,
                      onPressed: _summarizing
                          ? widget.onStopSummarize
                          : widget.onSummarizeComments,
                      icon: Icon(
                        _summarizing ? Icons.stop : Icons.refresh,
                        size: 18,
                      ),
                    ),
                    if (hasContent && !_summarizing) ...[
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: l10n.copyButton,
                        onPressed: () async {
                          final text = widget.stripSpoilersMarker(_aiSummary);
                          await Clipboard.setData(ClipboardData(text: text));
                          if (context.mounted) widget.onCopied();
                        },
                        icon: const Icon(Icons.copy, size: 18),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: l10n.chapterCommentsClearSummary,
                        onPressed: widget.onClearSummary,
                        icon: const Icon(Icons.delete_outline, size: 18),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
