part of '../anime_player_page.dart';

class _VideoLinkPanel extends StatelessWidget {
  final String? videoUrl;
  final String currentLine;
  final Map<String, AnimeChapterLine> lines;
  final VoidCallback onCopy;
  final VoidCallback onOpen;
  final ValueChanged<String> onLineSelected;

  const _VideoLinkPanel({
    required this.videoUrl,
    required this.currentLine,
    required this.lines,
    required this.onCopy,
    required this.onOpen,
    required this.onLineSelected,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final url = videoUrl;
    final hasUrl = url != null && url.isNotEmpty;
    final configurableLines = lines.entries.where((e) => e.value.config);

    return _CollapsiblePlayerCard(
      icon: Icons.link,
      title: l10n.videoLinkTitle,
      trailing: configurableLines.length > 1
          ? Chip(
              avatar: const Icon(Icons.alt_route, size: 18),
              label: Text(_currentLineLabel),
              visualDensity: VisualDensity.compact,
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.7),
              ),
            ),
            child: SelectableText(
              hasUrl ? url : l10n.videoLinkPending,
              style: tt.bodySmall?.copyWith(
                color: hasUrl ? cs.onSurface : cs.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonalIcon(
                onPressed: hasUrl ? onCopy : null,
                icon: const Icon(Icons.copy_all_outlined),
                label: Text(l10n.copyButton),
              ),
              FilledButton.tonalIcon(
                onPressed: hasUrl ? onOpen : null,
                icon: const Icon(Icons.open_in_browser),
                label: Text(l10n.openInBrowserButton),
              ),
              if (configurableLines.length > 1)
                PopupMenuButton<String>(
                  tooltip: l10n.switchLineTooltip,
                  initialValue: currentLine,
                  onSelected: onLineSelected,
                  itemBuilder: (context) => [
                    for (final entry in configurableLines)
                      PopupMenuItem(
                        value: entry.value.pathWord.isNotEmpty
                            ? entry.value.pathWord
                            : entry.key,
                        child: Row(
                          children: [
                            if (_isCurrent(entry))
                              const Icon(Icons.check, size: 18)
                            else
                              const SizedBox(width: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                entry.value.name.isNotEmpty
                                    ? entry.value.name
                                    : entry.key,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  child: Chip(
                    avatar: const Icon(Icons.alt_route, size: 18),
                    label: Text(_currentLineLabel),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  bool _isCurrent(MapEntry<String, AnimeChapterLine> entry) {
    return entry.key == currentLine || entry.value.pathWord == currentLine;
  }

  String get _currentLineLabel {
    for (final entry in lines.entries.where((e) => e.value.config)) {
      if (_isCurrent(entry)) {
        return entry.value.name.isNotEmpty ? entry.value.name : entry.key;
      }
    }
    return currentLine;
  }
}
