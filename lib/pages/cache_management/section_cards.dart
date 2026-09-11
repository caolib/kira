part of '../cache_management_page.dart';

class _ImageCacheSectionCard extends StatelessWidget {
  const _ImageCacheSectionCard({
    required this.section,
    required this.selectionMode,
    required this.selected,
    required this.sizeLabel,
    required this.onToggleSelected,
    required this.onClear,
  });

  final _ImageCacheSection section;
  final bool selectionMode;
  final bool selected;
  final String sizeLabel;
  final VoidCallback onToggleSelected;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final subtitle = l10n.cacheFileCountSize(section.fileCount, sizeLabel);

    return Card(
      color: cs.surfaceContainerLow,
      child: selectionMode
          ? ListTile(
              enabled: !section.isEmpty,
              onTap: section.isEmpty ? null : onToggleSelected,
              leading: Checkbox(
                value: selected,
                onChanged: section.isEmpty ? null : (_) => onToggleSelected(),
              ),
              title: Text(section.label),
              subtitle: Text(subtitle, style: tt.bodySmall),
              trailing: Icon(section.icon),
            )
          : ListTile(
              leading: Icon(section.icon),
              title: Text(section.label),
              subtitle: Text(subtitle, style: tt.bodySmall),
              trailing: FilledButton.tonalIcon(
                onPressed: section.isEmpty ? null : onClear,
                icon: const Icon(Icons.cleaning_services_rounded),
                label: Text(l10n.cacheClearButton),
              ),
            ),
    );
  }
}

class _FontCacheSectionCard extends StatelessWidget {
  const _FontCacheSectionCard({
    required this.section,
    required this.selectionMode,
    required this.selected,
    required this.sizeLabel,
    required this.onToggleSelected,
    required this.onClear,
  });

  final _FontCacheSection section;
  final bool selectionMode;
  final bool selected;
  final String sizeLabel;
  final VoidCallback onToggleSelected;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final subtitle = l10n.cacheFileCountSize(section.fonts.length, sizeLabel);

    return Card(
      color: cs.surfaceContainerLow,
      child: selectionMode
          ? ListTile(
              enabled: !section.isEmpty,
              onTap: section.isEmpty ? null : onToggleSelected,
              leading: Checkbox(
                value: selected,
                onChanged: section.isEmpty ? null : (_) => onToggleSelected(),
              ),
              title: Text(section.label),
              subtitle: Text(subtitle, style: tt.bodySmall),
              trailing: const Icon(Icons.font_download_outlined),
            )
          : ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              leading: const Icon(Icons.font_download_outlined),
              title: Text(section.label),
              subtitle: Text(subtitle, style: tt.bodySmall),
              children: [
                const Divider(height: 1),
                for (final font in section.fonts)
                  ListTile(
                    leading: const Icon(Icons.text_fields),
                    title: Text(font.name),
                    trailing: Text(
                      _FontCacheSectionCard._formatFileSize(font.sizeBytes),
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: section.isEmpty ? null : onClear,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: Text(l10n.deleteButton),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  static String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  }
}
