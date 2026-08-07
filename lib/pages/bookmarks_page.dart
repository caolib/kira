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
  /// 不用 late final：didChangeDependencies 会多次执行，重复赋值 late final 会抛异常。
  ScaffoldMessengerState? _messenger;

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
    _messenger?.clearSnackBars();
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

  Future<void> _refresh() async {
    _details.clear();
    await _store.reload();
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
    // 与消息正文同色,避免默认 primary 蓝色按钮在通知条上过于扎眼。
    final btnStyle = TextButton.styleFrom(
      foregroundColor: Theme.of(context).colorScheme.onInverseSurface,
    );
    // SnackBar 原生只支持单个 action,这里用 content 内嵌 Row 放「撤销」「关闭」
    // 两个按钮,让用户既能撤销删除,也能手动关掉通知。
    _messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Row(
            children: [
              Expanded(child: Text(message)),
              TextButton(
                style: btnStyle,
                onPressed: () {
                  _store.restoreAll(removed);
                  _messenger?.hideCurrentSnackBar();
                },
                child: Text(l10n.bookmarkUndo),
              ),
              TextButton(
                style: btnStyle,
                onPressed: () => _messenger?.hideCurrentSnackBar(),
                child: Text(l10n.closeButton),
              ),
            ],
          ),
          behavior: SnackBarBehavior.fixed,
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

  Future<void> _openBookmark(ComicBookmark bookmark) async {
    // 打开阅读器前清掉撤销 SnackBar：阅读器为全屏覆盖式页面,
    // 通知赖在根 messenger 上既无法手动关闭也干扰阅读体验。
    _messenger?.clearSnackBars();
    await context.pushNamed(
      AppRoutes.reader,
      pathParameters: {
        'pathWord': bookmark.pathWord,
        'chapterUuid': bookmark.chapterUuid,
      },
      extra: ReaderExtra(
        comicName: bookmark.comicName,
        group: bookmark.group.isNotEmpty ? bookmark.group : null,
        chapterName: bookmark.chapterName,
        initialPage: bookmark.page,
      ),
    );
    if (!mounted) return;

    // Store 的通知可能发生在阅读器覆盖本页期间；路由返回时再重建一次，
    // 确保刚添加或取消的书签立即反映到列表中。
    setState(() {});
  }

  Future<void> _openComic(String pathWord) async {
    // 与 _openBookmark 一致：跳转详情前清掉可能残留的撤销 SnackBar。
    _messenger?.clearSnackBars();
    await context.pushNamed(
      AppRoutes.comicDetail,
      pathParameters: {'pathWord': pathWord},
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
          : RefreshIndicator(
              onRefresh: _refresh,
              child: groups.isEmpty
                  ? LayoutBuilder(
                      builder: (context, constraints) => ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: constraints.maxHeight,
                            child: Center(
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
                                      style: tt.bodySmall?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
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
                          child: _BookmarkGroupCard(
                            pathWord: group.key,
                            bookmarks: group.value,
                            coverUrl: _groupCoverOf(group.value),
                            onFetchCover: () => _loadCachedDetail(group.key),
                            onOpenComic: () => _openComic(group.key),
                            onOpenBookmark: _openBookmark,
                            onRemove: _remove,
                            onClearGroup: _clearGroup,
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

/// 单部漫画的书签组卡片：封面 + 漫画名 header，下方列出全部书签。
/// 左滑 header 删除该漫画的全部书签，左滑书签条目仅删除单条。
class _BookmarkGroupCard extends StatelessWidget {
  final String pathWord;
  final List<ComicBookmark> bookmarks;
  final String coverUrl;
  final VoidCallback onFetchCover;
  final VoidCallback onOpenComic;
  final ValueChanged<ComicBookmark> onOpenBookmark;
  final ValueChanged<ComicBookmark> onRemove;
  final ValueChanged<List<ComicBookmark>> onClearGroup;

  const _BookmarkGroupCard({
    required this.pathWord,
    required this.bookmarks,
    required this.coverUrl,
    required this.onFetchCover,
    required this.onOpenComic,
    required this.onOpenBookmark,
    required this.onRemove,
    required this.onClearGroup,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;

    // build 期间不得同步触发 setState（会命中 dirty-element 断言），
    // 延迟到帧结束后再拉取缓存封面。
    if (coverUrl.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onFetchCover());
    }

    final comicName = bookmarks
        .map((b) => b.comicName)
        .firstWhere((name) => name.isNotEmpty, orElse: () => pathWord);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Dismissible(
            key: ValueKey('bookmark_group_$pathWord'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              color: cs.errorContainer,
              child: Icon(Icons.delete_outline, color: cs.onErrorContainer),
            ),
            onDismissed: (_) => onClearGroup(bookmarks),
            child: InkWell(
              key: ValueKey('bookmark_comic_$pathWord'),
              onTap: onOpenComic,
              child: Padding(
                padding: const EdgeInsets.all(10),
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
                  ],
                ),
              ),
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
                onTap: () => onOpenBookmark(bookmark),
              ),
            ),
          ),
        ],
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
      key: ValueKey('bookmark_open_${bookmark.id}'),
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
