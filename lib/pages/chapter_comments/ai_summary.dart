part of '../chapter_comments_sheet.dart';

extension _ChapterAiSummary on _ChapterCommentsSheetState {
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
        if (mounted) _setState(() {});
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
        if (mounted) _setState(() {}); // Refresh comment spoiler masks.
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
    _setState(() => _spoilerIds = _parseSpoilerIds(cached));
  }

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
    _setState(() {
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
        _setState(() => _spoilerIds = _parseSpoilerIds(full));
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

  /// Parses spoiler ids from model output, keeping legacy HTML marker support.
  /// Prefers the last fenced code block, then the last array, then legacy comment.
  Set<int> _parseSpoilerIds(String text) {
    // 1) Last fenced code block.
    Match? lastBlock;
    for (final m in _ChapterCommentsSheetState._codeBlockRegex.allMatches(
      text,
    )) {
      lastBlock = m;
    }
    if (lastBlock != null) {
      final content = lastBlock.group(1) ?? '';
      final arr = _ChapterCommentsSheetState._arrayRegex.firstMatch(content);
      if (arr != null) return _splitIds(arr.group(1) ?? '');
    }
    // 2) Without code blocks, use the last [id, id, ...] array.
    Match? lastArr;
    for (final m in _ChapterCommentsSheetState._arrayRegex.allMatches(text)) {
      lastArr = m;
    }
    if (lastArr != null) return _splitIds(lastArr.group(1) ?? '');
    // 3) Fallback to the legacy HTML comment.
    final legacy = _ChapterCommentsSheetState._spoilerLegacyRegex.firstMatch(
      text,
    );
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
    for (final m in _ChapterCommentsSheetState._codeBlockRegex.allMatches(
      text,
    )) {
      lastBlock = m;
    }
    if (lastBlock != null) {
      text = text.substring(0, lastBlock.start) + text.substring(lastBlock.end);
    }
    return text
        .replaceAll(_ChapterCommentsSheetState._spoilerLegacyRegex, '')
        .trimRight();
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
    _setState(() {
      _aiSummary = '';
      _aiSummaryReasoning = '';
      _summaryError = null;
      _spoilerIds = const {};
    });
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
}
