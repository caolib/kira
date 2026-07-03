import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../api/ai_api.dart';
import '../api/api_client.dart';
import '../models/chapter_comment.dart';
import '../models/user_manager.dart';
import '../utils/app_logger.dart';
import '../utils/chapter_summary_cache.dart';
import '../utils/network_error.dart';
import '../utils/time_format.dart';
import '../utils/toast.dart';
import 'chapter_comment_display.dart';

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

class _ChapterCommentsSheetState extends State<ChapterCommentsSheet> {
  static const _pageSize = 100;
  static const _commentRowSpacing = 8.0;
  static const _loadMoreThreshold = 240.0;
  static const _commentListBottomPadding = 124.0;
  static const _sheetMaxHeightFactor = 0.85;

  final _api = ApiClient();
  final _user = UserManager();
  final _aiSettings = AiSettings();
  final _aiApi = AiApi();
  final _scrollController = ScrollController();
  final _reasoningScrollController = ScrollController();

  List<ChapterComment> _comments = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _loadingAll = false;
  String? _error;
  int _total = 0;
  bool _useCompactLayout = true;
  bool _showUserAvatar = true;
  bool _showUserName = true;
  bool _showCommentTime = true;
  double _commentFontScale = 1.0;
  final ValueNotifier<bool> _showFloatingButtons = ValueNotifier(true);
  double _lastScrollOffset = 0;

  String _aiSummary = '';
  String _aiSummaryReasoning = '';
  bool _summarizing = false;
  bool _summaryExpanded = false;
  bool _summaryExpansionTouched = false;
  bool _summaryReasoningExpanded = false;
  bool _summaryReasoningExpansionTouched = false;
  String? _summaryError;
  CancelToken? _summaryCancelToken;
  Set<int> _spoilerIds = const {};
  List<ChapterCommentDisplayEntry> _lastSnippetEntries = const [];
  // ── AI 流式节流 ──
  Timer? _summaryThrottleTimer;
  bool _summaryHasPendingUpdate = false;
  // ── 评论分组缓存 ──
  List<ChapterCommentDisplayEntry> _groupedEntries = const [];
  bool _reasoningScrollPending = false;

  /// 在 _comments 变化后调用，重建分组缓存。
  void _rebuildGroupedEntries() {
    if (_comments.isEmpty) {
      _groupedEntries = const [];
      return;
    }
    final blocked = _user.commentBlockedUsers;
    if (blocked.isEmpty) {
      _groupedEntries = groupChapterComments(_comments);
      return;
    }
    final filtered = _comments.where(
      (c) => !_user.isCommentUserBlocked(c.userId, c.userName.trim()),
    ).toList();
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
    _scrollController.addListener(_handleScrollDirection);
    _aiSettings.addListener(_onAiChanged);
    _applySummaryDefaultExpansion();
    _summaryProgress = ChapterSummaryCache.progressOf(widget.chapterUuid);
    _summaryProgress.addListener(_onSummaryProgressChanged);
    _applySummaryProgress(rebuild: false);
    _aiSettings.load().then((_) {
      if (!mounted) return;
      setState(_applySummaryDefaultExpansion);
      _loadCachedSummary().then((_) => _maybeAutoSummary());
    });
    if (widget.initialComments != null) {
      _comments = List<ChapterComment>.from(widget.initialComments!);
      _total = widget.initialTotal ?? _comments.length;
      _loading = false;
      _rebuildGroupedEntries();
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
    _scrollController.dispose();
    _reasoningScrollController.dispose();
    _showFloatingButtons.dispose();
    super.dispose();
  }

  void _onAiChanged() {
    if (mounted) setState(_applySummaryDefaultExpansion);
  }

  void _applySummaryDefaultExpansion() {
    if (!_summaryExpansionTouched) {
      _summaryExpanded = !_aiSettings.summaryCollapsed;
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

  void _applySummaryProgress({bool rebuild = true}) {
    void apply() {
      if (!_summaryProgress.hasState) {
        if (_usingSharedSummaryProgress) {
          _aiSummary = '';
          _aiSummaryReasoning = '';
          _summarizing = false;
          _summaryError = null;
          _spoilerIds = const {};
          _usingSharedSummaryProgress = false;
        }
        return;
      }

      _usingSharedSummaryProgress = true;
      _summarizing = _summaryProgress.isGenerating;
      if (_summaryProgress.content.isNotEmpty) {
        _aiSummary = _summaryProgress.content;
        _spoilerIds = _parseSpoilerIds(_summaryProgress.content);
      }
      _aiSummaryReasoning = _summaryProgress.reasoningContent;
      if (_summarizing) _scrollReasoningToBottom();
      if (_summaryProgress.error != null) {
        _summaryError = _summaryProgress.error;
      } else if (_summaryProgress.isGenerating ||
          _summaryProgress.content.isNotEmpty) {
        _summaryError = null;
      }
      _applySummaryDefaultExpansion();
    }

    if (rebuild) {
      setState(apply);
    } else {
      apply();
    }
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
    setState(() {
      _aiSummary = cached;
      _aiSummaryReasoning = '';
      _spoilerIds = _parseSpoilerIds(cached);
    });
  }

  void _handleScrollDirection() {
    final offset = _scrollController.offset;
    if (offset > _lastScrollOffset + 2 && _showFloatingButtons.value) {
      _showFloatingButtons.value = false;
    } else if (offset < _lastScrollOffset - 2 && !_showFloatingButtons.value) {
      _showFloatingButtons.value = true;
    }
    _lastScrollOffset = offset;
  }

  void _notifyCommentsUpdated() {
    final callback = widget.onCommentsUpdated;
    if (callback == null) return;
    callback(
      List<ChapterComment>.from(_comments),
      _total < _comments.length ? _comments.length : _total,
    );
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
      _rebuildGroupedEntries();
      _notifyCommentsUpdated();
      if (!loadMore) {
        _maybeAutoSummary();
      }
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

  /// 发评论后只刷新第 1 页，保留第 2+ 页已有数据。
  ///
  /// 新评论会出现在第 1 页，导致原第 1 页末尾评论「溢出」到第 2 页。
  /// 若新第 1 页满 pageSize 条，说明有一条溢出，需要把原第 1 页的最后一条
  /// 插入第 2 页头部（如果已加载了第 2+ 页的话）。第 2+ 页其余数据不动。
  Future<void> _refreshFirstPage() async {
    try {
      final data = await _api.manga.getChapterComments(
        widget.chapterUuid,
        limit: _pageSize,
      );
      if (!mounted) return;

      final firstPageComments = data.list;

      // 计算已有评论中属于第 2+ 页的部分
      final existingBeyondPage1 = _comments.length > _pageSize
          ? _comments.sublist(_pageSize)
          : <ChapterComment>[];

      List<ChapterComment> merged;
      if (firstPageComments.length >= _pageSize &&
          existingBeyondPage1.isNotEmpty) {
        // 第 1 页满，说明有一条从第 1 页溢出到第 2 页。
        // 溢出的是旧第 1 页的最后一条（原 _comments[_pageSize - 1]）。
        final overflowComment = _comments[_pageSize - 1];

        // 避免重复：如果溢出评论的 id 已存在于新 fetched 数据或
        // 后续页中，不再插入。
        final allIds = <int>{
          ...firstPageComments.map((c) => c.id),
          ...existingBeyondPage1.map((c) => c.id),
        };
        final insertOverflow = !allIds.contains(overflowComment.id);

        // 去除后续页中与第 1 页重复的评论
        final dedupedBeyond = existingBeyondPage1
            .where((c) => !firstPageComments.any((f) => f.id == c.id))
            .toList();

        merged = [
          ...firstPageComments,
          if (insertOverflow) overflowComment,
          ...dedupedBeyond,
        ];
      } else {
        // 第 1 页未满（评论总数 < pageSize），或没有第 2+ 页数据
        // 直接拼接第 1 页 + 去重后的后续页
        final dedupedBeyond = existingBeyondPage1
            .where((c) => !firstPageComments.any((f) => f.id == c.id))
            .toList();
        merged = [...firstPageComments, ...dedupedBeyond];
      }

      setState(() {
        _comments = merged;
        _total = data.total;
        _error = null;
      });
      _notifyCommentsUpdated();
      _maybeAutoSummary();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _tryLoadMoreWhenNearBottom();
      });
    } catch (e) {
      if (!mounted) return;
      // 刷新第 1 页失败时不影响已有数据，仅记录错误
      unawaited(
        AppLogger().recordWarning(
          '刷新第1页评论失败: $e',
          stackTrace: StackTrace.current,
        ),
      );
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
    if (_summarizing) return;
    if (_comments.isEmpty) {
      showToast(context, '当前没有可总结的评论', isError: true);
      return;
    }
    if (!_aiSettings.hasConfig || !_aiSettings.summaryEnabled) {
      showToast(context, '请先在评论区设置中启用 AI 总结', isError: true);
      return;
    }

    final cancelToken = CancelToken();
    _summaryCancelToken = cancelToken;
    setState(() {
      _summarizing = true;
      _summaryError = null;
      _aiSummary = '';
      _aiSummaryReasoning = '';
      _summaryReasoningExpanded = false;
      _summaryReasoningExpansionTouched = false;
      _spoilerIds = const {};
      _applySummaryDefaultExpansion();
    });
    if (_reasoningScrollController.hasClients) {
      _reasoningScrollController.jumpTo(0);
    }
    ChapterSummaryCache.startProgress(widget.chapterUuid);

    final snippets = _buildCommentSnippets();
    final comicLine = widget.comicName?.trim().isNotEmpty == true
        ? '漫画：${widget.comicName!.trim()}\n'
        : '';
    final messages = <AiMessage>[
      AiMessage(role: 'system', content: _aiSettings.summaryPrompt),
      AiMessage(
        role: 'user',
        content:
            '$comicLine章节：${widget.chapterName}\n共 ${_lastSnippetEntries.length} 条不同评论（相同内容已合并）。每条行首数字为该评论的 id：\n\n$snippets',
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
        // 节流 setState：最多每 66ms 刷新一次（~15fps），
        // 避免每个 SSE chunk 都触发整棵 Widget 树 rebuild。
        _summaryHasPendingUpdate = true;
        _summaryThrottleTimer ??= Timer(const Duration(milliseconds: 66), () {
          _summaryThrottleTimer = null;
          if (!mounted || !_summaryHasPendingUpdate) return;
          _summaryHasPendingUpdate = false;
          final reasoningText = reasoningBuffer.toString();
          setState(() {
            _aiSummary = buffer.toString();
            _aiSummaryReasoning = reasoningText;
          });
          _scrollReasoningToBottom();
        });
        ChapterSummaryCache.updateProgress(
          widget.chapterUuid,
          buffer.toString(),
          reasoningContent: reasoningBuffer.toString(),
        );
      }
      // Flush 任何因节流而未刷新的最终文本
      _summaryThrottleTimer?.cancel();
      _summaryThrottleTimer = null;
      if (_summaryHasPendingUpdate && mounted) {
        _summaryHasPendingUpdate = false;
        final reasoningText = reasoningBuffer.toString();
        setState(() {
          _aiSummary = buffer.toString();
          _aiSummaryReasoning = reasoningText;
        });
        _scrollReasoningToBottom();
      }
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
      setState(() => _summaryError = message);
    } finally {
      if (mounted) {
        setState(() => _summarizing = false);
      }
      _summaryCancelToken = null;
    }
  }

  String _buildCommentSnippets() {
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
          ? '$id. [${entry.count}人] $text\n'
          : '$id. ${entry.primaryComment.userName}: $text\n';
      if (buffer.length + line.length > maxChars) {
        truncated = true;
        break;
      }
      buffer.write(line);
    }
    if (truncated) {
      buffer.write('…（已截断，共 ${entries.length} 条不同评论）');
    }
    return buffer.toString();
  }

  static final _codeBlockRegex = RegExp(
    r'```[^`\r\n]*\r?\n([\s\S]*?)\r?\n\s*```',
  );
  static final _arrayRegex = RegExp(r'\[\s*([\d,\s]*)\s*\]');
  static final _spoilerLegacyRegex = RegExp(r'<!--\s*SPOILERS\s*:([^>]*)-->');

  /// 解析模型输出的剧透 id，兼容旧版 HTML 注释标记。
  /// 策略：先找最后一个 fenced code block，从中提取 [id, id, ...]；
  /// 若无代码块则找文本中最后一个数组模式；最后兜底旧版注释。
  Set<int> _parseSpoilerIds(String text) {
    // 1) 最后一个 fenced code block
    Match? lastBlock;
    for (final m in _codeBlockRegex.allMatches(text)) {
      lastBlock = m;
    }
    if (lastBlock != null) {
      final content = lastBlock.group(1) ?? '';
      final arr = _arrayRegex.firstMatch(content);
      if (arr != null) return _splitIds(arr.group(1) ?? '');
    }
    // 2) 无代码块，找文本中最后一个 [id, id, ...]
    Match? lastArr;
    for (final m in _arrayRegex.allMatches(text)) {
      lastArr = m;
    }
    if (lastArr != null) return _splitIds(lastArr.group(1) ?? '');
    // 3) 兜底旧版 HTML 注释
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

  /// 从展示文本里剥离机读标记，避免暴露给用户。只剥离最后一个代码块。
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
    return NetworkError.message(e);
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
      _summaryExpansionTouched = false;
      _summaryExpanded = !_aiSettings.summaryCollapsed;
      _summaryReasoningExpanded = false;
      _summaryReasoningExpansionTouched = false;
      _summaryError = null;
      _spoilerIds = const {};
    });
  }

  int _commentTextLength(String text) => text.trim().runes.length;

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
    return NetworkError.message(error);
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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
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
                  'Dio 异常',
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
                label: const Text('复制日志'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            message,
            style: tt.bodySmall?.copyWith(
              color: cs.onErrorContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
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
    if (!_user.isLoggedIn) {
      showToast(context, '请先登录后再发表评论', isError: true);
      return;
    }

    final controller = TextEditingController();
    var submitting = false;
    String? errorText;
    String? errorLog;

    Future<void> submit(
      BuildContext dialogContext,
      StateSetter setLocal,
    ) async {
      final content = controller.text.trim();
      final length = _commentTextLength(content);
      if (length < 3 || length > 200) {
        setLocal(() {
          errorText = '评论字数需在 3-200 之间';
          errorLog = 'ValidationError: 评论字数需在 3-200 之间';
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
        showToast(context, '评论已发布');
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

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogContext, setLocal) {
              final length = _commentTextLength(controller.text);
              final canSubmit = !submitting && length >= 3 && length <= 200;
              return AlertDialog(
                title: const Text('发表评论'),
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
                        maxLength: 200,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(200),
                        ],
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: '吐槽一下',
                          helperText: '评论字数 3-200',
                          errorText: errorText,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) => setLocal(() {
                          errorText = null;
                          errorLog = null;
                        }),
                      ),
                      if (errorText != null && errorLog != null) ...[
                        const SizedBox(height: 12),
                        _buildPostCommentErrorPanel(
                          dialogContext,
                          message: errorText!,
                          log: errorLog!,
                          onCopy: () async {
                            await Clipboard.setData(
                              ClipboardData(text: errorLog!),
                            );
                            if (!mounted) return;
                            showToast(context, '日志已复制');
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
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: canSubmit
                        ? () => submit(dialogContext, setLocal)
                        : null,
                    child: submitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('发布'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      // ponytail: 延后一帧 dispose，避免弹窗退出动画期间
      // 还在读取 controller.text 导致 used-after-dispose
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.dispose();
      });
    }
  }

  Future<void> _showCommentActionMenu(ChapterCommentDisplayEntry entry) async {
    final content = entry.content.trim();
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
                      '评论操作',
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: '关闭',
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
                    borderRadius: BorderRadius.circular(12),
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
                  title: const Text('复制'),
                  onTap: () => Navigator.of(sheetContext).pop('copy'),
                ),
                ListTile(
                  leading: const Icon(Icons.add_comment_outlined),
                  title: const Text('+1'),
                  subtitle: const Text('发送一条相同评论'),
                  onTap: () => Navigator.of(sheetContext).pop('plus_one'),
                ),
                ListTile(
                  leading: const Icon(Icons.block_outlined),
                  title: const Text('屏蔽用户'),
                  subtitle: Text(
                    '隐藏 ${entry.primaryComment.userName} 的评论',
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
      showToast(context, '评论已复制');
    } else if (action == 'plus_one') {
      await _plusOneComment(content);
    } else if (action == 'block') {
      await _blockCommentUser(entry.primaryComment);
    }
  }

  Future<void> _blockCommentUser(ChapterComment comment) async {
    final name = comment.userName.trim();
    if (_user.commentBlockNoRemind) {
      await _user.blockCommentUser(comment.userId, name);
      if (!mounted) return;
      setState(_rebuildGroupedEntries);
      showToast(context, '已屏蔽该用户');
      return;
    }

    var noRemind = false;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('屏蔽用户'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isEmpty
                    ? '确定屏蔽该用户吗？屏蔽后将不再显示其评论。'
                    : '确定屏蔽「$name」吗？屏蔽后将不再显示其评论。\n可在评论区设置 → 黑名单中解除。',
              ),
              const SizedBox(height: 8),
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
                        onChanged: (v) =>
                            setLocal(() => noRemind = v ?? false),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '不再提醒',
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
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('屏蔽'),
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
    showToast(context, '已屏蔽该用户');
  }

  Future<void> _plusOneComment(String content) async {
    if (!_user.isLoggedIn) {
      showToast(context, '请先登录后再发表评论', isError: true);
      return;
    }

    final length = _commentTextLength(content);
    if (length < 3 || length > 200) {
      showToast(context, '评论字数需在 3-200 之间，无法 +1', isError: true);
      return;
    }

    try {
      await _api.manga.postChapterComment(widget.chapterUuid, content);
      if (!mounted) return;
      showToast(context, '+1 已发送');
      await _refreshFirstPage();
    } catch (e) {
      if (!mounted) return;
      await _showPostCommentErrorDialog(e);
    }
  }

  Future<void> _showPostCommentErrorDialog(Object error) async {
    final message = _extractCommentPostErrorMessage(error);
    final log = _formatCommentPostErrorLog(error);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('发表评论失败'),
        content: SingleChildScrollView(
          child: _buildPostCommentErrorPanel(
            dialogContext,
            message: message,
            log: log,
            onCopy: () async {
              await Clipboard.setData(ClipboardData(text: log));
              if (!mounted) return;
              showToast(context, '日志已复制');
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showCommentSettings() {
    showModalBottomSheet(
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
  }

  @override
  Widget build(BuildContext context) {
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
                                        tooltip: '加载全部评论',
                                        onPressed: _loadAllComments,
                                        icon: const Icon(Icons.refresh),
                                      ),
                              if (_aiSettings.hasApiKey &&
                                  _aiSettings.summaryEnabled) ...[
                                IconButton(
                                  tooltip: _aiSummary.isEmpty
                                      ? 'AI 总结评论'
                                      : '重新生成 AI 总结',
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
                                    ? '切换为列表布局'
                                    : '切换为紧凑布局',
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
                                tooltip: '评论区设置',
                                onPressed: _showCommentSettings,
                                icon: const Icon(Icons.tune),
                              ),
                              Text(
                                _total > 0
                                    ? (_allCommentsLoaded
                                          ? '$_total 条'
                                          : '${_comments.length}/$_total')
                                    : '',
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
                    valueListenable: _showFloatingButtons,
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
                                  shadowColor: Colors.black.withValues(
                                    alpha: 0.22,
                                  ),
                                  minimumSize: const Size(0, 52),
                                  maximumSize: const Size.fromHeight(52),
                                  fixedSize: const Size.fromHeight(52),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                );

                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    FilledButton.icon(
                                      style: buttonStyle,
                                      onPressed: _showPostCommentDialog,
                                      icon: const Icon(Icons.comment_outlined),
                                      label: const Text('评论'),
                                    ),
                                    const SizedBox(width: 8),
                                    FilledButton.icon(
                                      style: buttonStyle,
                                      onPressed: () {
                                        widget.onBackToCatalog?.call();
                                        Navigator.of(
                                          context,
                                        ).pop('back_to_catalog');
                                      },
                                      icon: const Icon(Icons.list_rounded),
                                      label: const Text('目录'),
                                    ),
                                    if (widget.hasNextChapter) ...[
                                      const SizedBox(width: 8),
                                      FilledButton.icon(
                                        style: buttonStyle,
                                        onPressed: widget.onNextChapter,
                                        icon: const Icon(
                                          Icons.skip_next_rounded,
                                        ),
                                        label: const Text('下一话'),
                                      ),
                                    ],
                                    const SizedBox(width: 8),
                                    SizedBox.square(
                                      dimension: 52,
                                      child: FilledButton(
                                        style: buttonStyle.copyWith(
                                          padding: const WidgetStatePropertyAll(
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

    final entries = _groupedEntries;
    final hasSummary = _hasSummaryPanel;
    final summaryOffset = hasSummary ? 1 : 0;

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
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final entry = entries[dataIndex];
            return _CommentCard(
              entry: entry,
              relativeTime: TimeFormat.relativeOf(entry.createAt),
              showAvatar: _showUserAvatar,
              showUserName: _showUserName,
              showCommentTime: _showCommentTime,
              fontScale: _commentFontScale,
              spoilerIds: _aiSettings.spoilerAnalysis ? _spoilerIds : const {},
              onLongPress: (entry) => _showCommentActionMenu(entry),
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
            itemCount: summaryOffset + rows.length + (_loadingMore ? 1 : 0),
            separatorBuilder: (_, index) => const SizedBox(height: 8),
            itemBuilder: (_, index) {
              if (hasSummary && index == 0) {
                return _buildSummaryPanel(cs, tt);
              }
              final dataIndex = index - summaryOffset;
              if (dataIndex == rows.length && _loadingMore) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
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
                          ),
                          compact: true,
                          showAvatar: _showUserAvatar,
                          showUserName: _showUserName,
                          showCommentTime: _showCommentTime,
                          fontScale: _commentFontScale,
                          spoilerIds: _aiSettings.spoilerAnalysis
                              ? _spoilerIds
                              : const {},
                          onLongPress: (entry) => _showCommentActionMenu(entry),
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
    final canSwitch = !_summarizing;
    final provider = _aiSettings.activeProvider;
    return Tooltip(
      message: canSwitch ? '切换模型' : '生成中无法切换模型',
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: canSwitch ? _showModelPickerSheet : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  '${provider.model} 总结',
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
    final provider = _aiSettings.activeProvider;
    if (_modelChoices.isNotEmpty) {
      return _buildModelNameButton(cs, tt);
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 180),
      child: Text(
        '${provider.model} 总结',
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
                      '切换模型',
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text(
                  '当前模型：${active.name} / ${active.model}',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
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
                              borderRadius: BorderRadius.circular(12),
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
    final hasContent = _aiSummary.isNotEmpty;
    final reasoning = _aiSummaryReasoning.trim();
    final hasReasoning = reasoning.isNotEmpty;
    final defaultReasoningExpanded = _summarizing && !hasContent;
    final reasoningExpanded =
        hasReasoning &&
        (_summaryReasoningExpansionTouched
            ? _summaryReasoningExpanded
            : defaultReasoningExpanded);
    final statusColor = _summaryStatusColor(
      cs,
      hasContent: hasContent,
      hasReasoning: hasReasoning,
    );
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
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
            borderRadius: BorderRadius.circular(8),
            onTap: _toggleSummaryExpanded,
            child: Row(
              children: [
                if (_modelChoices.isEmpty)
                  _buildSummaryTitle(cs, tt)
                else
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: _buildSummaryTitle(cs, tt),
                  ),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: _summaryExpanded ? '收起' : '展开',
                  onPressed: _toggleSummaryExpanded,
                  icon: Icon(
                    _summaryExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
          if (_summaryExpanded) ...[
            if (hasReasoning) ...[
              _buildSummaryReasoningBox(
                cs,
                tt,
                reasoning: reasoning,
                expanded: reasoningExpanded,
                toggleable: true,
              ),
              const SizedBox(height: 8),
            ],
            if (_summaryError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
                child: Text(
                  '生成失败：${_summaryError!}',
                  style: tt.bodySmall?.copyWith(color: cs.error),
                ),
              )
            else if (hasContent)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 8, 2),
                child: MarkdownBody(
                  data: _stripSpoilersMarker(_aiSummary),
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
              )
            else if (_summarizing)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
                child: Text(
                  '正在生成中…',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: _summarizing ? '停止' : '重新生成',
                  onPressed: _summarizing ? _stopSummarize : _summarizeComments,
                  icon: Icon(
                    _summarizing ? Icons.stop : Icons.refresh,
                    size: 18,
                  ),
                ),
                if (hasContent && !_summarizing) ...[
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '复制',
                    onPressed: () async {
                      final text = _stripSpoilersMarker(_aiSummary);
                      await Clipboard.setData(ClipboardData(text: text));
                      if (mounted) showToast(context, '已复制');
                    },
                    icon: const Icon(Icons.copy, size: 18),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '清除总结',
                    onPressed: _clearSummary,
                    icon: const Icon(Icons.delete_outline, size: 18),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryReasoningBox(
    ColorScheme cs,
    TextTheme tt, {
    required String reasoning,
    required bool expanded,
    required bool toggleable,
  }) {
    final textStyle = tt.bodySmall?.copyWith(
      color: cs.onSurfaceVariant.withValues(alpha: 0.78),
      fontSize: 12,
      height: 1.35,
    );
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: toggleable ? _toggleSummaryReasoningExpanded : null,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(4, 2, 8, 0),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(10),
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
                const SizedBox(width: 4),
                Text(
                  expanded ? '思考过程' : '思考过程（已折叠）',
                  style: textStyle?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (toggleable) ...[
                  const SizedBox(width: 4),
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
                  controller: _reasoningScrollController,
                  child: Text(reasoning, style: textStyle),
                ),
              ),
            ],
          ],
        ),
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
      final compactBodyStyle = _buildCommentBodyStyle(
        textTheme,
        compact: true,
        fontScale: _commentFontScale,
      );
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
        TimeFormat.relativeOf(entry.createAt),
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
