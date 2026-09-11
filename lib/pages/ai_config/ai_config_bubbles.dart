part of '../ai_config_page.dart';

extension _AiConfigBubbles on _AiConfigPageState {
  Widget _buildEmpty(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 48,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              _settings.hasConfig
                  ? AppLocalizations.of(context)!.aiConfigReadyEmptyHint
                  : AppLocalizations.of(context)!.aiConfigSetupEmptyHint,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBubble(AiMessage msg, ColorScheme cs, int index) {
    final isUser = msg.role == 'user';
    final bg = isUser ? cs.primary : cs.surfaceContainerHighest;
    final fg = isUser ? cs.onPrimary : cs.onSurface;
    final reasoning = msg.reasoningContent?.trim();
    final hasReasoning = !isUser && reasoning != null && reasoning.isNotEmpty;
    final shouldCollapseReasoning = msg.content.trim().isNotEmpty;
    final reasoningExpanded =
        hasReasoning &&
        (!shouldCollapseReasoning || _expandedReasoningIndexes.contains(index));

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        child: GestureDetector(
          onLongPress: () async {
            if (msg.content.isEmpty) return;
            await Clipboard.setData(ClipboardData(text: msg.content));
            if (mounted) {
              showToast(
                context,
                AppLocalizations.of(context)!.chapterCommentsCopied,
              );
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: bg, borderRadius: AppRadius.lgR),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasReasoning)
                  _buildReasoningBox(
                    reasoning,
                    cs,
                    expanded: reasoningExpanded,
                    collapsed: shouldCollapseReasoning,
                    onTap: shouldCollapseReasoning
                        ? () => _setState(() {
                            if (_expandedReasoningIndexes.contains(index)) {
                              _expandedReasoningIndexes.remove(index);
                            } else {
                              _expandedReasoningIndexes.add(index);
                            }
                          })
                        : null,
                  ),
                if (hasReasoning && msg.content.isNotEmpty)
                  const SizedBox(height: AppSpacing.sm),
                if (msg.content.isEmpty)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                  )
                else if (isUser)
                  Text(msg.content, style: TextStyle(color: fg, fontSize: 15))
                else
                  MarkdownBody(
                    data: msg.content,
                    onTapLink: (text, href, title) async {
                      if (href == null) return;
                      final uri = Uri.tryParse(href);
                      if (uri == null) return;
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    styleSheet: _markdownStyle(cs, fg),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReasoningBox(
    String reasoning,
    ColorScheme cs, {
    required bool expanded,
    required bool collapsed,
    VoidCallback? onTap,
  }) {
    final textStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant.withValues(alpha: 0.78),
      fontSize: 12,
      height: 1.35,
    );
    return InkWell(
      borderRadius: AppRadius.mdR,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow.withValues(alpha: 0.72),
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
                  AppLocalizations.of(context)!.chapterCommentsReasoning,
                  style: textStyle?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (collapsed) ...[
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
              Text(reasoning, style: textStyle),
            ],
          ],
        ),
      ),
    );
  }

  MarkdownStyleSheet _markdownStyle(ColorScheme cs, Color fg) {
    final base = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: fg, fontSize: 15, height: 1.45);
    final codeBg = cs.surfaceContainerHigh;
    return MarkdownStyleSheet(
      p: base,
      h1: base?.copyWith(fontSize: 22, fontWeight: FontWeight.bold),
      h2: base?.copyWith(fontSize: 20, fontWeight: FontWeight.bold),
      h3: base?.copyWith(fontSize: 18, fontWeight: FontWeight.bold),
      h4: base?.copyWith(fontSize: 16, fontWeight: FontWeight.bold),
      strong: base?.copyWith(fontWeight: FontWeight.bold),
      em: base?.copyWith(fontStyle: FontStyle.italic),
      a: base?.copyWith(
        color: cs.primary,
        decoration: TextDecoration.underline,
      ),
      blockquote: base?.copyWith(color: cs.onSurfaceVariant),
      blockquoteDecoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(left: BorderSide(color: cs.primary, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      code: base?.copyWith(
        fontFamily: 'monospace',
        backgroundColor: codeBg,
        fontSize: 14,
      ),
      codeblockDecoration: BoxDecoration(
        color: codeBg,
        borderRadius: AppRadius.smR,
      ),
      codeblockPadding: const EdgeInsets.all(12),
      listBullet: base,
      tableBody: base,
      tableHead: base?.copyWith(fontWeight: FontWeight.bold),
      tableBorder: TableBorder.all(color: cs.outlineVariant),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
    );
  }
}
