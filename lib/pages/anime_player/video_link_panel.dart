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
    final url = videoUrl;
    final hasUrl = url != null && url.isNotEmpty;
    final configurableLines = lines.entries.where((e) => e.value.config);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.tonalIcon(
          onPressed: hasUrl ? onCopy : null,
          icon: const Icon(Icons.copy_all_outlined),
          label: Text(l10n.copyVideoLinkButton),
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
