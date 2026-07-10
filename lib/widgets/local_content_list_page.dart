import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/app_localizations.dart';
import '../utils/anime_download_manager.dart' show LocalAnimeEntry;
import '../utils/cover_brightness_filter.dart';
import '../utils/download_manager.dart' show LocalComicEntry;
import '../utils/toast.dart';

/// Abstraction over comic/anime local content entries for the list page.
abstract class LocalContentEntry {
  String get pathWord;
  String get name;
  String? get coverPath;
  int get downloadedCount;
  String get subtitle;
  IconData get fallbackIcon;
}

/// Adapter for [LocalComicEntry].
class ComicLocalContentEntry implements LocalContentEntry {
  final LocalComicEntry _entry;

  const ComicLocalContentEntry(this._entry);

  @override
  String get pathWord => _entry.info.comic.pathWord;

  @override
  String get name => _entry.info.comic.name;

  @override
  String? get coverPath => _entry.info.coverPath;

  @override
  int get downloadedCount => _entry.downloadedCount;

  @override
  String get subtitle => _entry.info.comic.authors.isNotEmpty
      ? _entry.info.comic.authors.map((item) => item.name).join(' / ')
      : _entry.info.comic.pathWord;

  @override
  IconData get fallbackIcon => Icons.broken_image_outlined;
}

/// Adapter for [LocalAnimeEntry].
class AnimeLocalContentEntry implements LocalContentEntry {
  final LocalAnimeEntry _entry;

  const AnimeLocalContentEntry(this._entry);

  @override
  String get pathWord => _entry.info.anime.pathWord;

  @override
  String get name => _entry.info.anime.name;

  @override
  String? get coverPath => _entry.info.coverPath;

  @override
  int get downloadedCount => _entry.downloadedCount;

  @override
  String get subtitle => _entry.info.anime.pathWord;

  @override
  IconData get fallbackIcon => Icons.movie_outlined;
}

class LocalContentListPage extends StatefulWidget {
  final bool embedded;
  final String title;
  final String emptyTitle;
  final String emptySubtitle;
  final String downloadFolderName;
  final String deleteDialogTitle;
  final String Function(int) deleteDialogContent;
  final String deleteToastPrefix;
  final String deleteToastSuffix;
  final String heroTagPrefix;
  final double gridAspectRatio;
  final String unitLabel;

  // Functional callbacks that abstract the domain type
  final ChangeNotifier downloadManager;
  final Future<void> Function() initDownloads;
  final List<LocalContentEntry> Function() getLocalItems;
  final Future<void> Function(Set<String> pathWords) deleteLocalItems;
  final void Function(BuildContext context, String pathWord) onOpenDetail;

  const LocalContentListPage({
    super.key,
    this.embedded = false,
    required this.title,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.downloadFolderName,
    required this.deleteDialogTitle,
    required this.deleteDialogContent,
    required this.deleteToastPrefix,
    required this.deleteToastSuffix,
    required this.heroTagPrefix,
    required this.gridAspectRatio,
    required this.unitLabel,
    required this.downloadManager,
    required this.initDownloads,
    required this.getLocalItems,
    required this.deleteLocalItems,
    required this.onOpenDetail,
  });

  @override
  State<LocalContentListPage> createState() => _LocalContentListPageState();
}

class _LocalContentListPageState extends State<LocalContentListPage> {
  final Set<String> _selectedPathWords = {};
  bool _selectionMode = false;
  bool _loading = true;

  bool get _isDesktopPlatform =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    widget.downloadManager.addListener(_handleChanged);
    unawaited(_initialize());
  }

  @override
  void dispose() {
    widget.downloadManager.removeListener(_handleChanged);
    super.dispose();
  }

  void _handleChanged() {
    if (!mounted) return;
    final valid = widget.getLocalItems().map((item) => item.pathWord).toSet();
    _selectedPathWords.removeWhere((pathWord) => !valid.contains(pathWord));
    if (_selectedPathWords.isEmpty) {
      _selectionMode = false;
    }
    setState(() {});
  }

  Future<void> _initialize() async {
    await widget.initDownloads();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _openDownloadFolder() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final folder = Directory(
        '${docsDir.path}${Platform.pathSeparator}${widget.downloadFolderName}',
      );
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }
      final path = folder.path;
      if (Platform.isWindows) {
        await Process.run('explorer', [path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [path]);
      }
    } catch (e) {
      if (!mounted) return;
      showToast(
        context,
        AppLocalizations.of(context)!.openFolderFailed(e.toString()),
        isError: true,
      );
    }
  }

  Future<void> _deleteSelected() async {
    if (_selectedPathWords.isEmpty) return;
    final count = _selectedPathWords.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(widget.deleteDialogTitle),
          content: Text(widget.deleteDialogContent(count)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancelButton),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.deleteButton),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    await widget.deleteLocalItems(_selectedPathWords);
    if (!mounted) return;
    setState(() {
      _selectedPathWords.clear();
      _selectionMode = false;
    });
    showToast(
      context,
      '${widget.deleteToastPrefix}$count${widget.deleteToastSuffix}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final items = widget.getLocalItems();

    final body = _loading
        ? const Center(child: ExpressiveLoadingIndicator())
        : items.isEmpty
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.download_done_outlined,
                  size: 56,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                Text(widget.emptyTitle, style: tt.titleMedium),
                const SizedBox(height: 6),
                Text(
                  widget.emptySubtitle,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          )
        : GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 150,
              childAspectRatio: widget.gridAspectRatio,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
            ),
            itemCount: items.length,
            itemBuilder: (_, index) {
              final item = items[index];
              final pathWord = item.pathWord;
              final selected = _selectedPathWords.contains(pathWord);
              return _LocalContentCard(
                entry: item,
                unitLabel: widget.unitLabel,
                selected: selected,
                selectionMode: _selectionMode,
                onTap: () {
                  if (_selectionMode) {
                    setState(() {
                      if (selected) {
                        _selectedPathWords.remove(pathWord);
                      } else {
                        _selectedPathWords.add(pathWord);
                      }
                      if (_selectedPathWords.isEmpty) {
                        _selectionMode = false;
                      }
                    });
                    return;
                  }
                  widget.onOpenDetail(context, pathWord);
                },
                onLongPress: () => setState(() {
                  _selectionMode = true;
                  _selectedPathWords.add(pathWord);
                }),
              );
            },
          );

    if (widget.embedded) {
      if (!_isDesktopPlatform) return body;
      return Stack(
        children: [
          body,
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              heroTag: '${widget.heroTagPrefix}_open_folder',
              onPressed: _openDownloadFolder,
              icon: const Icon(Icons.folder_open, size: 20),
              label: Text(
                AppLocalizations.of(context)!.openDownloadFolder,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
        ],
      );
    }

    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectionMode
              ? l10n.selectedItems(_selectedPathWords.length)
              : widget.title,
        ),
        actions: [
          if (!_selectionMode && items.isNotEmpty)
            IconButton(
              onPressed: () => setState(() => _selectionMode = true),
              icon: const Icon(Icons.checklist),
              tooltip: l10n.batchManage,
            ),
          if (_selectionMode) ...[
            IconButton(
              onPressed: items.isEmpty
                  ? null
                  : () => setState(() {
                      _selectedPathWords
                        ..clear()
                        ..addAll(items.map((item) => item.pathWord));
                    }),
              icon: const Icon(Icons.select_all),
              tooltip: l10n.selectAll,
            ),
            IconButton(
              onPressed: _selectedPathWords.isEmpty ? null : _deleteSelected,
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.deleteButton,
            ),
            IconButton(
              onPressed: () => setState(() {
                _selectionMode = false;
                _selectedPathWords.clear();
              }),
              icon: const Icon(Icons.close),
              tooltip: l10n.cancelButton,
            ),
          ],
        ],
      ),
      body: body,
    );
  }
}

class _LocalContentCard extends StatelessWidget {
  final LocalContentEntry entry;
  final String unitLabel;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _LocalContentCard({
    required this.entry,
    required this.unitLabel,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final coverPath = entry.coverPath;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? cs.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox.expand(
                        child: coverPath != null && File(coverPath).existsSync()
                            ? CoverBrightnessFilter(
                                child: Image.file(
                                  File(coverPath),
                                  fit: BoxFit.cover,
                                ),
                              )
                            : ColoredBox(
                                color: cs.surfaceContainerHighest,
                                child: Icon(
                                  entry.fallbackIcon,
                                  color: cs.onSurfaceVariant,
                                  size: 32,
                                ),
                              ),
                      ),
                    ),
                    if (selectionMode)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: selected ? cs.primary : Colors.black45,
                            shape: BoxShape.circle,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              selected ? Icons.check : Icons.circle_outlined,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          AppLocalizations.of(context)!.downloadedCountUnit(
                            entry.downloadedCount,
                            unitLabel,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.bodySmall,
              ),
              const SizedBox(height: 2),
              Text(
                entry.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
