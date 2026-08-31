import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';
import 'package:path_provider/path_provider.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
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

  /// 内嵌于下载中心时的尾部悬浮按钮（如下载设置），与"打开下载位置"
  /// 按钮同行排布、位于其右侧。
  final Widget? trailingAction;
  final String title;
  final String emptyTitle;
  final String emptySubtitle;
  final String downloadFolderName;

  /// 可选：返回实际下载根目录（如漫画侧用 DownloadManager.rootPath，
  /// 以支持自定义保存目录）；null 时回退到 `downloadFolderName` 拼接。
  final String? Function()? downloadFolderPath;

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
    this.trailingAction,
    required this.title,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.downloadFolderName,
    this.downloadFolderPath,
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

  /// 全选/取消全选切换：若当前已全选则清空选中（保持选中态），否则全选。
  void _toggleSelectAll(List<LocalContentEntry> items) {
    final allIds = items.map((item) => item.pathWord).toSet();
    final allSelected =
        allIds.isNotEmpty && allIds.every(_selectedPathWords.contains);
    setState(() {
      _selectionMode = true;
      _selectedPathWords
        ..clear()
        ..addAll(allSelected ? const <String>{} : allIds);
    });
  }

  Future<void> _openDownloadFolder() async {
    try {
      final customPath = widget.downloadFolderPath?.call();
      final folder = Directory(
        customPath ??
            '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}${widget.downloadFolderName}',
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
                const SizedBox(height: AppSpacing.md),
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
      final l10n = AppLocalizations.of(context)!;
      // 选中态：叠加底部操作条（全选/删除/取消），并隐藏右下角悬浮按钮。
      if (_selectionMode) {
        return Stack(
          children: [
            body,
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Material(
                elevation: 6,
                borderRadius: AppRadius.lgR,
                color: cs.surfaceContainerHigh,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Text(
                        l10n.selectedItems(_selectedPathWords.length),
                        style: tt.labelLarge,
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: items.isEmpty
                            ? null
                            : () => _toggleSelectAll(items),
                        icon: const Icon(Icons.select_all),
                        tooltip: l10n.selectAll,
                      ),
                      IconButton(
                        onPressed: _selectedPathWords.isEmpty
                            ? null
                            : _deleteSelected,
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
                  ),
                ),
              ),
            ),
          ],
        );
      }
      // 移动端没有"打开下载位置"按钮，尾部按钮单独悬浮于右下角。
      final trailing = widget.trailingAction;
      if (!_isDesktopPlatform) {
        if (trailing == null) return body;
        return Stack(
          children: [
            body,
            Positioned(right: 16, bottom: 16, child: trailing),
          ],
        );
      }
      return Stack(
        children: [
          body,
          Positioned(
            right: 16,
            bottom: 16,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.extended(
                  heroTag: '${widget.heroTagPrefix}_open_folder',
                  onPressed: _openDownloadFolder,
                  icon: const Icon(Icons.folder_open, size: 20),
                  label: Text(
                    l10n.openDownloadFolder,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: AppSpacing.md),
                  trailing,
                ],
              ],
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
              onPressed: items.isEmpty ? null : () => _toggleSelectAll(items),
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
        borderRadius: AppRadius.lgR,
        onTap: onTap,
        onLongPress: onLongPress,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: AppRadius.lgR,
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
                      borderRadius: AppRadius.lgR,
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
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
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
              const SizedBox(height: 2),
              Text(
                AppLocalizations.of(
                  context,
                )!.downloadedCountUnit(entry.downloadedCount, unitLabel),
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
