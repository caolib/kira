part of '../chapter_comments_sheet.dart';

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
            color: _commentCardColor(cs),
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
