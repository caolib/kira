import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../repositories/comic_detail_repository.dart';
import '../routing/app_router.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/bookmark_store.dart';
import '../utils/cover_brightness_filter.dart';
import '../utils/time_format.dart';

/// 书签列表页：展示用户在阅读器中手动标记的书签，点击直达对应章节页码。
///
/// 与浏览记录不同：纯本地数据、无需登录；按漫画分组合并显示，
/// 支持删除单个书签、单部漫画的全部书签、以及一键清空。
class BookmarksPage extends StatefulWidget {
  const BookmarksPage({super.key});

  @override
  State<BookmarksPage> createState() => _BookmarksPageState();
}

class _BookmarksPageState extends State<BookmarksPage> {
  final _store = BookmarkStore();
  bool _loading = true;

  /// 根 ScaffoldMessenger：删除书签的撤销 SnackBar 显示在根上，
  /// 页面退出时需手动隐藏，否则会残留在上一个页面直到时长结束。
  late final ScaffoldMessengerState _messenger;

  /// 漫画详情本地缓存（仅用于补充旧书签缺失的封面），key 为 pathWord。
  final Map<String, ComicDetailData> _details = {};
  final Set<String> _fetchingDetails = {};

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.of(context);
  }

  @override
  void dispose() {
    _messenger.hideCurrentSnackBar();
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    await _store.ensureLoaded();
    if (mounted) setState(() => _loading = false);
  }

  /// 仅从漫画详情本地缓存补充封面，绝不发网络请求：
  /// 缓存缺失或损坏时保持占位图标。
  Future<void> _loadCachedDetail(String pathWord) {
    if (_details.containsKey(pathWord)) return Future.value();
    if (!_fetchingDetails.add(pathWord)) return Future.value();
    return ComicDetailRepository(pathWord)
        .loadFromCache()
        .then((data) {
          if (!mounted || data == null) return;
          setState(() => _details[pathWord] = data);
        })
        .catchError((_) {
          // 无可用缓存时保持占位图标。
        })
        .whenComplete(() => _fetchingDetails.remove(pathWord));
  }

  /// 书签自带封面（打书签时从详情缓存读取并持久化）；旧书签缺失时
  /// 回退到详情本地缓存，均无则为空（显示占位图）。
  String _coverOf(ComicBookmark bookmark) {
    if (bookmark.cover.isNotEmpty) return bookmark.cover;
    return _details[bookmark.pathWord]?.comic.cover ?? '';
  }

  String _groupCoverOf(List<ComicBookmark> group) {
    for (final bookmark in group) {
      if (bookmark.cover.isNotEmpty) return bookmark.cover;
    }
    return _details[group.first.pathWord]?.comic.cover ?? '';
  }

  /// 按漫画分组；全局列表本身按时间倒序，分组后组与组内均保持倒序。
  List<MapEntry<String, List<ComicBookmark>>> _grouped() {
    final groups = <String, List<ComicBookmark>>{};
    for (final bookmark in _store.bookmarks) {
      groups.putIfAbsent(bookmark.pathWord, () => []).add(bookmark);
    }
    return groups.entries.toList();
  }

  void _showUndoSnackBar(String message, List<ComicBookmark> removed) {
    final l10n = AppLocalizations.of(context)!;
    _messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: l10n.bookmarkUndo,
            onPressed: () => _store.restoreAll(removed),
          ),
        ),
      );
  }

  Future<void> _remove(ComicBookmark bookmark) async {
    final l10n = AppLocalizations.of(context)!;
    await _store.remove(bookmark.id);
    if (!mounted) return;
    _showUndoSnackBar(l10n.bookmarkDeleted, [bookmark]);
  }

  Future<void> _clearGroup(List<ComicBookmark> group) async {
    final removed = await _store.removeForComic(group.first.pathWord);
    if (!mounted || removed.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    _showUndoSnackBar(l10n.bookmarksGroupDeleted(removed.length), removed);
  }

  Future<void> _clearAll() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.bookmarksClearTitle),
        content: Text(l10n.bookmarksClearContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.cacheClearButton),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final removed = await _store.clear();
    if (!mounted || removed.isEmpty) return;
    _showUndoSnackBar(l10n.bookmarksGroupDeleted(removed.length), removed);
  }

  void _openBookmark(ComicBookmark bookmark) {
    context.pushNamed(
      AppRoutes.reader,
      pathParameters: {
        'pathWord': bookmark.pathWord,
        'chapterUuid': bookmark.chapterUuid,
      },
      extra: ReaderExtra(
        comicName: bookmark.comicName,
        chapterName: bookmark.chapterName,
        initialPage: bookmark.page,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final groups = _grouped();
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth.clamp(0.0, 900.0);
    final hp = (screenWidth - contentWidth) / 2 + 16;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.bookmarksTitle),
        actions: [
          if (groups.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.bookmarksClearTitle,
              onPressed: _clearAll,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : groups.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bookmark_border,
                      size: 64,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      l10n.bookmarksEmptyTitle,
                      style: tt.titleMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      l10n.bookmarksEmptySubtitle,
                      textAlign: TextAlign.center,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(hp, 8, hp, 24),
              itemCount: groups.length + 1,
              itemBuilder: (context, index) {
                if (index == groups.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Text(
                        l10n.bookmarksSwipeHint,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                }
                final group = groups[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  // 只有一条书签的漫画用单条卡片，多条才合并为组卡片。
                  child: group.value.length == 1
                      ? _SingleBookmarkCard(
                          bookmark: group.value.single,
                          coverUrl: _coverOf(group.value.single),
                          onFetchCover: () => _loadCachedDetail(group.key),
                          onTap: () => _openBookmark(group.value.single),
                          onRemove: _remove,
                        )
                      : _BookmarkGroupCard(
                          pathWord: group.key,
                          bookmarks: group.value,
                          coverUrl: _groupCoverOf(group.value),
                          onFetchCover: () => _loadCachedDetail(group.key),
                          onOpen: _openBookmark,
                          onRemove: _remove,
                          onClearGroup: _clearGroup,
                        ),
                );
              },
            ),
    );
  }
}

/// 单部漫画的书签组卡片：封面 + 漫画名 header（带组删除按钮），
/// 下方列出该漫画的全部书签条目。
class _BookmarkGroupCard extends StatelessWidget {
  final String pathWord;
  final List<ComicBookmark> bookmarks;
  final String coverUrl;
  final VoidCallback onFetchCover;
  final ValueChanged<ComicBookmark> onOpen;
  final ValueChanged<ComicBookmark> onRemove;
  final ValueChanged<List<ComicBookmark>> onClearGroup;

  const _BookmarkGroupCard({
    required this.pathWord,
    required this.bookmarks,
    required this.coverUrl,
    required this.onFetchCover,
    required this.onOpen,
    required this.onRemove,
    required this.onClearGroup,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;

    if (coverUrl.isEmpty) {
      onFetchCover();
    }

    final comicName = bookmarks
        .map((b) => b.comicName)
        .firstWhere((name) => name.isNotEmpty, orElse: () => pathWord);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: AspectRatio(
                    aspectRatio: 0.72,
                    child: _BookmarkCover(coverUrl: coverUrl),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        comicName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.bookmarksCount(bookmarks.length),
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline, color: cs.onSurfaceVariant),
                  tooltip: l10n.bookmarksClearGroupTitle,
                  onPressed: () => onClearGroup(bookmarks),
                ),
              ],
            ),
          ),
          const Divider(height: 1, indent: 10, endIndent: 10),
          ...bookmarks.map(
            (bookmark) => Dismissible(
              key: ValueKey('bookmark_${bookmark.id}'),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                color: cs.errorContainer,
                child: Icon(Icons.delete_outline, color: cs.onErrorContainer),
              ),
              onDismissed: (_) => onRemove(bookmark),
              child: _BookmarkTile(
                bookmark: bookmark,
                onTap: () => onOpen(bookmark),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单条书签卡片：漫画只有一条书签时的布局（封面 + 漫画名 + 章节/页码）。
class _SingleBookmarkCard extends StatelessWidget {
  final ComicBookmark bookmark;
  final String coverUrl;
  final VoidCallback onFetchCover;
  final VoidCallback onTap;
  final ValueChanged<ComicBookmark> onRemove;

  const _SingleBookmarkCard({
    required this.bookmark,
    required this.coverUrl,
    required this.onFetchCover,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;

    if (coverUrl.isEmpty) {
      onFetchCover();
    }

    return Dismissible(
      key: ValueKey('bookmark_${bookmark.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: AppRadius.mdR,
        ),
        child: Icon(Icons.delete_outline, color: cs.onErrorContainer),
      ),
      onDismissed: (_) => onRemove(bookmark),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: AspectRatio(
                    aspectRatio: 0.72,
                    child: _BookmarkCover(coverUrl: coverUrl),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bookmark.comicName.isNotEmpty
                            ? bookmark.comicName
                            : bookmark.pathWord,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.bookmark, size: 14, color: cs.primary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              bookmark.chapterName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.bodySmall,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          l10n.bookmarkPage(bookmark.page),
                          if (bookmark.updatedAt != null)
                            TimeFormat.relative(bookmark.updatedAt!, l10n),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 书签封面：带圆角与亮度滤镜，加载失败退化为占位图标。
class _BookmarkCover extends StatelessWidget {
  final String coverUrl;

  const _BookmarkCover({required this.coverUrl});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: AppRadius.smR,
      child: CoverBrightnessFilter(
        child: coverUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: coverUrl,
                fit: BoxFit.cover,
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                placeholder: (_, _) => _placeholder(cs),
                errorWidget: (_, _, _) => _placeholder(cs, error: true),
              )
            : _placeholder(cs),
      ),
    );
  }

  Widget _placeholder(ColorScheme cs, {bool error = false}) {
    return Container(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Icon(
          error ? Icons.broken_image : Icons.image,
          color: cs.onSurfaceVariant,
          size: 22,
        ),
      ),
    );
  }
}

/// 单个书签条目：章节名 + 页码/时间，点击直达阅读位置。
class _BookmarkTile extends StatelessWidget {
  final ComicBookmark bookmark;
  final VoidCallback onTap;

  const _BookmarkTile({required this.bookmark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.bookmark, size: 16, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bookmark.chapterName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      l10n.bookmarkPage(bookmark.page),
                      if (bookmark.updatedAt != null)
                        TimeFormat.relative(bookmark.updatedAt!, l10n),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
