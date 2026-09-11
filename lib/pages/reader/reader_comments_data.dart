part of '../reader_page.dart';

extension _ReaderCommentsData on _ReaderPageState {
  int get _commentCount {
    if (_detail == null) return 0;
    return _commentCountFor(_detail!);
  }

  bool _hasCommentCacheFor(String chapterUuid) =>
      _commentCache.containsKey(chapterUuid);

  List<ChapterComment>? _cachedCommentsFor(String chapterUuid) =>
      _commentCache[chapterUuid];

  int _cachedCommentTotalFor(String chapterUuid) =>
      _commentTotalCache[chapterUuid] ?? 0;

  /// 获取指定章节的评论数：下载章用本地计数；在线章用命中的缓存，否则 0。
  int _commentCountFor(ChapterDetail chapter) {
    if (chapter.isDownloaded) return chapter.commentTotal;
    return _cachedCommentTotalFor(chapter.uuid);
  }

  void _updateCommentCache(
    String chapterUuid,
    List<ChapterComment> comments,
    int total, {
    bool rebuild = false,
    bool replaceFirstPage = false,
  }) {
    var nextComments = List<ChapterComment>.from(comments);
    var nextTotal = total < nextComments.length ? nextComments.length : total;

    final existing = _commentCache[chapterUuid];
    if (!replaceFirstPage &&
        existing != null &&
        existing.length > nextComments.length) {
      nextComments = List<ChapterComment>.from(existing);
    }
    final existingTotal = _commentTotalCache[chapterUuid];
    if (existingTotal != null && existingTotal > nextTotal) {
      nextTotal = existingTotal;
    }

    void apply() {
      _commentCache[chapterUuid] = nextComments;
      _commentTotalCache[chapterUuid] = nextTotal;
    }

    if (rebuild && mounted) {
      _setState(apply);
      return;
    }
    apply();
  }

  void _clearCommentCache() {
    _commentCache.clear();
    _commentTotalCache.clear();
  }

  Future<void> _preloadComments({ChapterDetail? chapter}) async {
    if (!_user.commentPreload) return;
    final detail = chapter ?? _detail;
    if (detail == null || detail.isDownloaded) return;
    final uuid = detail.uuid;
    if (_hasCommentCacheFor(uuid)) return;

    final chapterUuid = uuid;
    final chapterName = detail.name;

    try {
      final data = await _api.manga.getChapterComments(chapterUuid, limit: 100);
      if (!mounted) return;
      _updateCommentCache(chapterUuid, data.list, data.total, rebuild: true);
      await _maybeAutoSummaryAfterPreload(
        chapterUuid: chapterUuid,
        chapterName: chapterName,
        comments: data.list,
      );
    } catch (_) {
      // Preload failures do not affect reading.
    }
  }

  Future<void> _maybeAutoSummaryAfterPreload({
    required String chapterUuid,
    required String chapterName,
    required List<ChapterComment> comments,
  }) async {
    await _aiSettings.load();
    // ponytail: 检查章节是否仍在链中（连续阅读追加后 _currentUuid 可能尚未更新）。
    // 允许后台 AI 总结运行，不要求 _currentUuid == chapterUuid。
    if (!mounted || !_chain.any((c) => c.uuid == chapterUuid)) return;
    if (!_user.commentPreload ||
        !_aiSettings.hasConfig ||
        !_aiSettings.summaryEnabled ||
        !_aiSettings.autoSummary ||
        _aiSettings.autoSummaryTiming != AiAutoSummaryTiming.afterPreload) {
      return;
    }
    if (comments.isEmpty || comments.length < _aiSettings.autoSummaryMin) {
      return;
    }

    final cached = await ChapterSummaryCache.get(chapterUuid);
    if (!mounted || !_chain.any((c) => c.uuid == chapterUuid)) return;
    if (cached != null && cached.isNotEmpty) return;
    if (ChapterSummaryCache.isGenerating(chapterUuid)) return;

    final input = _buildPreloadedSummaryInput(comments);
    if (input.snippets.trim().isEmpty) return;

    final comicLine = widget.comicName?.trim().isNotEmpty == true
        ? '漫画：${widget.comicName!.trim()}\n'
        : '';
    final messages = <AiMessage>[
      AiMessage(role: 'system', content: _aiSettings.summaryPrompt),
      AiMessage(
        role: 'user',
        content:
            '$comicLine章节：$chapterName\n共 ${input.count} 条不同评论（相同内容已合并）。每条行首数字为该评论的 id：\n\n${input.snippets}',
      ),
    ];

    final buffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    ChapterSummaryCache.startProgress(chapterUuid);
    final l10n = AppLocalizations.of(context)!;
    try {
      final provider = _aiSettings.activeProvider;
      final stream = _aiApi.streamChatChunks(
        apiKey: provider.apiKey!,
        baseUrl: provider.baseUrl,
        apiFormat: provider.apiFormat,
        model: provider.model,
        messages: messages,
      );
      await for (final chunk in stream) {
        if (!mounted || !_chain.any((c) => c.uuid == chapterUuid)) {
          ChapterSummaryCache.clearProgress(chapterUuid);
          return;
        }
        if (chunk.isReasoning) {
          reasoningBuffer.write(chunk.text);
        } else {
          buffer.write(chunk.text);
        }
        ChapterSummaryCache.updateProgress(
          chapterUuid,
          buffer.toString(),
          reasoningContent: reasoningBuffer.toString(),
        );
      }
      final full = buffer.toString();
      if (full.isNotEmpty) {
        await ChapterSummaryCache.set(
          chapterUuid,
          full,
          reasoningContent: reasoningBuffer.isEmpty
              ? null
              : reasoningBuffer.toString(),
        );
      } else {
        ChapterSummaryCache.clearProgress(chapterUuid);
      }
    } catch (e) {
      ChapterSummaryCache.failProgress(
        chapterUuid,
        l10n.readerAutoSummaryFailed(NetworkError.message(e, l10n: l10n)),
      );
      // Background auto-summary failures do not interrupt reading.
    }
  }

  ({String snippets, int count}) _buildPreloadedSummaryInput(
    List<ChapterComment> comments,
  ) {
    const maxChars = 64 * 1024;
    final buffer = StringBuffer();
    final entries = groupChapterComments(comments);
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
      buffer.write(
        AppLocalizations.of(
          context,
        )!.chapterCommentsSnippetsTruncated(entries.length),
      );
    }
    return (snippets: buffer.toString(), count: entries.length);
  }

  Future<void> _showChapterComments({ChapterDetail? chapter}) async {
    final detail = chapter ?? _detail;
    if (detail == null) return;

    // 打开评论面板期间暂停自动滚动，与设置面板保持一致
    _pauseAutoScrollForOverlay();
    final useCachedComments = _hasCommentCacheFor(detail.uuid);
    final initialComments = detail.isDownloaded
        ? detail.comments
        : (useCachedComments ? _cachedCommentsFor(detail.uuid) : null);
    final initialTotal = detail.isDownloaded
        ? detail.commentTotal
        : (useCachedComments ? _cachedCommentTotalFor(detail.uuid) : null);

    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width),
      backgroundColor: Colors.transparent,
      builder: (_) => ChapterCommentsSheet(
        chapterUuid: detail.uuid,
        comicName: widget.comicName ?? widget.pathWord,
        chapterName: detail.name,
        initialComments: initialComments,
        initialTotal: initialTotal,
        onCommentsUpdated: detail.isDownloaded
            ? null
            : (comments, total) {
                if (!mounted || _currentUuid != detail.uuid) return;
                _updateCommentCache(
                  detail.uuid,
                  comments,
                  total,
                  rebuild: true,
                  replaceFirstPage: true,
                );
              },
        hasNextChapter: detail.next != null,
        onNextChapter: detail.next == null
            ? null
            : () {
                Navigator.of(context).maybePop();
                _goChapter(detail.next);
              },
      ),
    );

    if (action == 'back_to_catalog') {
      // 返回目录会退出阅读页，无需恢复自动滚动
      if (mounted) unawaited(Navigator.of(context).maybePop());
      return;
    }
    if (mounted) _resumeAutoScrollAfterOverlay();
  }
}
