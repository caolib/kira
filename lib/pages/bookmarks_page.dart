import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../models/user_manager.dart';
import '../repositories/comic_detail_repository.dart';
import '../routing/app_router.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/app_logger.dart';
import '../utils/bookmark_store.dart';
import '../utils/cover_brightness_filter.dart';
import '../utils/reading_history.dart';
import '../utils/screen_layout.dart';
import '../utils/time_format.dart';
import '../widgets/cover_image.dart';
import 'novel_bookmarks_page.dart';

/// 本地书签按漫画/轻小说分开管理，清空只影响当前类型。
class BookmarksPage extends StatefulWidget {
  const BookmarksPage({super.key});

  @override
  State<BookmarksPage> createState() => _BookmarksPageState();
}

class _BookmarksPageState extends State<BookmarksPage>
    with SingleTickerProviderStateMixin {
  final _comicKey = GlobalKey<_ComicBookmarksPageState>();
  final _novelKey = GlobalKey<NovelBookmarksPageState>();
  final _searchController = TextEditingController();
  late final TabController _tabs;
  int _tabIndex = 0;

  /// 搜索词由宿主页持有：切换 tab 后沿用同一关键词，两个分页各自过滤。
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)..addListener(_onTabChanged);
    _searchController.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onQueryChanged)
      ..dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    if (_searchController.text == _query) return;
    setState(() => _query = _searchController.text);
  }

  void _onTabChanged() {
    if (_tabIndex == _tabs.index) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    setState(() => _tabIndex = _tabs.index);
  }

  void _onItemsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // 通用页「轻小说」开关关闭时隐藏 tab 组件，只展示漫画书签。
    final showNovel = UserManager().showNovel;
    final canClear = _tabIndex == 0 || !showNovel
        ? _comicKey.currentState?.hasBookmarks == true
        : _novelKey.currentState?.hasBookmarks == true;
    final hp = ScreenLayout.horizontalPadding(MediaQuery.sizeOf(context).width);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.bookmarksTitle),
        actions: [
          if (canClear)
            IconButton(
              key: const ValueKey('bookmarks_clear_current_type'),
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.bookmarksClearTitle,
              onPressed: () {
                if (_tabIndex == 0 || !showNovel) {
                  unawaited(_comicKey.currentState?._clearAll());
                } else {
                  unawaited(_novelKey.currentState?.clearAll());
                }
              },
            ),
        ],
        bottom: showNovel
            ? TabBar(
                controller: _tabs,
                tabs: [
                  Tab(text: l10n.historyTabComic),
                  Tab(text: l10n.historyTabNovel),
                ],
              )
            : null,
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(hp, AppSpacing.md, hp, AppSpacing.xs),
            child: SearchBar(
              controller: _searchController,
              hintText: l10n.bookmarksSearchHint,
              leading: const Padding(
                padding: EdgeInsets.only(left: AppSpacing.sm),
                child: Icon(Icons.search),
              ),
              trailing: _query.isEmpty
                  ? null
                  : [
                      IconButton(
                        key: const ValueKey('bookmarks_search_clear'),
                        icon: const Icon(Icons.clear),
                        tooltip: l10n.searchClearTooltip,
                        onPressed: _searchController.clear,
                      ),
                    ],
            ),
          ),
          Expanded(
            child: showNovel
                ? TabBarView(
                    controller: _tabs,
                    children: [
                      _ComicBookmarksPage(
                        key: _comicKey,
                        query: _query,
                        onChanged: _onItemsChanged,
                      ),
                      NovelBookmarksPage(
                        key: _novelKey,
                        query: _query,
                        onChanged: _onItemsChanged,
                      ),
                    ],
                  )
                : _ComicBookmarksPage(
                    key: _comicKey,
                    query: _query,
                    onChanged: _onItemsChanged,
                  ),
          ),
        ],
      ),
    );
  }
}

class _ComicBookmarksPage extends StatefulWidget {
  const _ComicBookmarksPage({
    super.key,
    required this.onChanged,
    this.query = '',
  });

  final VoidCallback onChanged;

  /// 宿主页搜索框的关键词，空串表示不过滤。
  final String query;

  @override
  State<_ComicBookmarksPage> createState() => _ComicBookmarksPageState();
}

class _ComicBookmarksPageState extends State<_ComicBookmarksPage>
    with AutomaticKeepAliveClientMixin {
  final _store = BookmarkStore();
  bool _loading = true;

  bool get hasBookmarks => !_loading && _store.bookmarks.isNotEmpty;

  @override
  bool get wantKeepAlive => true;

  /// 根 ScaffoldMessenger：删除书签的撤销 SnackBar 显示在根上，
  /// 页面退出时需手动隐藏，否则会残留在上一个页面直到时长结束。
  /// 不用 late final：didChangeDependencies 会多次执行，重复赋值 late final 会抛异常。
  ScaffoldMessengerState? _messenger;

  /// 漫画详情本地缓存（仅用于补充旧书签缺失的封面），key 为 pathWord。
  final Map<String, ComicDetailData> _details = {};
  final Set<String> _fetchingDetails = {};

  /// 每部漫画的本地阅读记录（null 表示查过但没有），供组头「继续阅读」。
  final Map<String, ReadingRecord?> _history = {};
  final Set<String> _fetchingHistory = {};

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
    ReadingHistory.changes.addListener(_onHistoryChanged);
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
    ReadingHistory.changes.removeListener(_onHistoryChanged);
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (!mounted) return;
    setState(() {});
    widget.onChanged();
  }

  /// 阅读记录变化（包括在别处阅读）时丢弃缓存，下次 build 重新查询。
  void _onHistoryChanged() {
    if (!mounted || _history.isEmpty) return;
    setState(_history.clear);
  }

  /// 只读本地阅读记录，不发任何请求；查过就记住，含「确实没有记录」。
  Future<void> _loadHistory(String pathWord) {
    if (_history.containsKey(pathWord)) return Future.value();
    if (!_fetchingHistory.add(pathWord)) return Future.value();
    return ReadingHistory.latestForComic(pathWord)
        .then((record) {
          if (!mounted) return;
          setState(() => _history[pathWord] = record);
        })
        .catchError((Object error, StackTrace stack) {
          unawaited(
            AppLogger.instance.recordWarning(
              error,
              stackTrace: stack,
              source: 'bookmarks_page.reading_history',
            ),
          );
        })
        .whenComplete(() => _fetchingHistory.remove(pathWord));
  }

  /// 组头「继续阅读」：直接跳到该漫画的本地阅读位置。
  Future<void> _continueReading(String pathWord) async {
    final record = _history[pathWord];
    if (record == null) return;
    _messenger?.clearSnackBars();
    await context.pushNamed(
      AppRoutes.reader,
      pathParameters: {'pathWord': pathWord, 'chapterUuid': record.chapterUuid},
      extra: ReaderExtra(
        comicName: record.comicName.isEmpty ? null : record.comicName,
        group: record.group,
        chapterName: record.chapterName,
        chapterListPage: record.chapterListPage,
        initialPage: record.page,
        noCatalogBelow: true,
      ),
    );
    if (!mounted) return;
    // 返回时记录已更新：丢缓存重查，下次仍从最新位置继续。
    setState(() => _history.remove(pathWord));
  }

  Future<void> _load() async {
    await _store.ensureLoaded();
    if (!mounted) return;
    setState(() => _loading = false);
    widget.onChanged();
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
        .catchError((Object error, StackTrace stack) {
          unawaited(
            AppLogger.instance.recordWarning(
              error,
              stackTrace: stack,
              source: 'bookmarks_page.cached_detail',
            ),
          );
        })
        .whenComplete(() => _fetchingDetails.remove(pathWord));
  }

  /// 组元数据（书签删光后仍保留）；没有则返回 null。
  ComicBookmarkGroup? _groupMetaOf(String pathWord) {
    for (final group in _store.groups) {
      if (group.pathWord == pathWord) return group;
    }
    return null;
  }

  /// 书签自带封面（打书签时从详情缓存读取并持久化）；旧书签缺失时
  /// 依次回退到组元数据、详情本地缓存，均无则为空（显示占位图）。
  String _groupCoverOf(List<ComicBookmark> group, String pathWord) {
    for (final bookmark in group) {
      if (bookmark.cover.isNotEmpty) return bookmark.cover;
    }
    final meta = _groupMetaOf(pathWord);
    if (meta != null && meta.cover.isNotEmpty) return meta.cover;
    return _details[pathWord]?.comic.cover ?? '';
  }

  /// 组头书名：优先书签自带，其次组元数据，最后回退详情缓存 / pathWord。
  String _groupNameOf(String pathWord) {
    for (final bookmark in _store.bookmarks) {
      if (bookmark.pathWord == pathWord && bookmark.comicName.isNotEmpty) {
        return bookmark.comicName;
      }
    }
    final meta = _groupMetaOf(pathWord);
    if (meta != null && meta.comicName.isNotEmpty) return meta.comicName;
    return _details[pathWord]?.comic.name ?? pathWord;
  }

  /// 组排序时间：组内最新书签的时间；空组用组元数据的时间。
  DateTime _groupUpdatedAt(String pathWord) {
    // _store.bookmarks 本身按时间倒序，第一条命中即最新。
    for (final bookmark in _store.bookmarks) {
      if (bookmark.pathWord == pathWord) {
        return bookmark.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      }
    }
    return _groupMetaOf(pathWord)?.updatedAt ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// 按漫画分组；全局列表本身按时间倒序，分组后组与组内均保持倒序。
  /// 搜索是「组级」的：组内任一条命中，该漫画的全部书签都照常展示，
  /// 组头上的条数与整组删除因此仍与所见一致。
  List<MapEntry<String, List<ComicBookmark>>> _grouped() {
    final query = widget.query.trim().toLowerCase();
    final groups = <String, List<ComicBookmark>>{};
    for (final bookmark in _store.bookmarks) {
      groups.putIfAbsent(bookmark.pathWord, () => []).add(bookmark);
    }
    // 书签被删光的组仍在：用组元数据补成空组，只显示组头与继续阅读。
    for (final group in _store.groups) {
      groups.putIfAbsent(group.pathWord, () => const []);
    }
    final entries = groups.entries.toList()
      ..sort(
        (a, b) => _groupUpdatedAt(b.key).compareTo(_groupUpdatedAt(a.key)),
      );
    if (query.isEmpty) return entries;
    return entries
        .where(
          (entry) =>
              entry.value.any((b) => _matchesQuery(b, query)) ||
              _groupNameOf(entry.key).toLowerCase().contains(query),
        )
        .toList();
  }

  bool _matchesQuery(ComicBookmark bookmark, String query) {
    if (query.isEmpty) return true;
    return bookmark.comicName.toLowerCase().contains(query) ||
        bookmark.chapterName.toLowerCase().contains(query);
  }

  void _showUndoSnackBar(
    String message,
    List<ComicBookmark> removed, {
    List<ComicBookmarkGroup> removedGroups = const [],
  }) {
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
                  _store.restoreAll(removed, groups: removedGroups);
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

  Future<void> _clearGroup(String pathWord) async {
    final group = _groupMetaOf(pathWord);
    final removed = await _store.removeGroup(pathWord);
    if (!mounted || (removed.isEmpty && group == null)) return;
    final l10n = AppLocalizations.of(context)!;
    _showUndoSnackBar(
      removed.isEmpty
          ? l10n.bookmarkDeleted
          : l10n.bookmarksGroupDeleted(removed.length),
      removed,
      removedGroups: group != null ? [group] : const [],
    );
  }

  Future<void> _clearAll() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.bookmarksClearTitle),
        content: Text(l10n.bookmarksTabClearContent(l10n.historyTabComic)),
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
        noCatalogBelow: true,
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
    super.build(context);
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final groups = _grouped();
    final screenWidth = MediaQuery.of(context).size.width;
    final hp = ScreenLayout.horizontalPadding(screenWidth);
    // 宽屏（横屏 / 桌面窗口）每组书签卡片两列并排，窄屏保持单列。
    final twoColumn =
        ScreenLayout.contentWidth(screenWidth) >= ScreenLayout.wideBreakpoint;
    // 两列各自堆叠：组卡片高度随书签条数变化，按行配对会在矮的一侧留白。
    final (leftColumn, rightColumn) = twoColumn
        ? ScreenLayout.splitTwoColumns(
            groups.length,
            (index) => groups[index].value.length + 1,
          )
        : (const <int>[], const <int>[]);
    // 「搜不到」和「一条书签都没有」要分开：否则搜索无结果会被误读成书签丢了。
    final searching = widget.query.trim().isNotEmpty;

    Widget groupCard(int index) {
      final group = groups[index];
      if (!_history.containsKey(group.key)) {
        // build 期间不得同步触发 setState，延迟到帧结束后再查阅读记录。
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _loadHistory(group.key),
        );
      }
      return _BookmarkGroupCard(
        pathWord: group.key,
        comicName: _groupNameOf(group.key),
        bookmarks: group.value,
        coverUrl: _groupCoverOf(group.value, group.key),
        continueRecord: _history[group.key],
        onFetchCover: () => _loadCachedDetail(group.key),
        onOpenComic: () => _openComic(group.key),
        onOpenBookmark: _openBookmark,
        onContinue: () => _continueReading(group.key),
        onRemove: _remove,
        onClearGroup: () => _clearGroup(group.key),
      );
    }

    /// 一列内的组卡片，纵向堆叠，卡片间距与单列一致。
    Widget bookmarkColumn(List<int> indices) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final index in indices)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: groupCard(index),
          ),
      ],
    );

    Widget swipeHint() => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(
          l10n.bookmarksSwipeHint,
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ),
    );

    return _loading
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
                                    searching
                                        ? Icons.search_off
                                        : Icons.bookmark_border,
                                    size: 64,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: AppSpacing.lg),
                                  Text(
                                    searching
                                        ? l10n.bookmarksSearchEmpty
                                        : l10n.bookmarksEmptyTitle,
                                    textAlign: TextAlign.center,
                                    style: tt.titleMedium?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  if (!searching) ...[
                                    const SizedBox(height: AppSpacing.sm),
                                    Text(
                                      l10n.bookmarksEmptySubtitle,
                                      textAlign: TextAlign.center,
                                      style: tt.bodySmall?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : twoColumn
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(hp, 8, hp, 24),
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: bookmarkColumn(leftColumn)),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(child: bookmarkColumn(rightColumn)),
                        ],
                      ),
                      swipeHint(),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(hp, 8, hp, 24),
                    itemCount: groups.length + 1,
                    itemBuilder: (context, index) => index == groups.length
                        ? swipeHint()
                        : Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: groupCard(index),
                          ),
                  ),
          );
  }
}

/// 单部漫画的书签组卡片：封面 + 漫画名 header，下方列出全部书签。
/// 左滑 header 删除该漫画的全部书签，左滑书签条目仅删除单条。
class _BookmarkGroupCard extends StatelessWidget {
  final String pathWord;

  /// 组头书名；书签删光后由组元数据提供，因此由父级算好传入。
  final String comicName;
  final List<ComicBookmark> bookmarks;
  final String coverUrl;

  /// 该漫画的本地阅读记录；为空表示没有可继续的进度，此时不显示按钮。
  final ReadingRecord? continueRecord;
  final VoidCallback onFetchCover;
  final VoidCallback onOpenComic;
  final ValueChanged<ComicBookmark> onOpenBookmark;
  final VoidCallback onContinue;
  final Future<void> Function(ComicBookmark) onRemove;
  final Future<void> Function() onClearGroup;

  const _BookmarkGroupCard({
    required this.pathWord,
    required this.comicName,
    required this.bookmarks,
    required this.coverUrl,
    required this.continueRecord,
    required this.onFetchCover,
    required this.onOpenComic,
    required this.onOpenBookmark,
    required this.onContinue,
    required this.onRemove,
    required this.onClearGroup,
  });

  /// 与详情页 FAB 一致：章节名 + 当前页/总页数；只有一页时只显示章节名。
  static String _continueLabel(ReadingRecord record) {
    final chapter = record.chapterName.trim();
    if (record.totalPage <= 1) return chapter;
    return chapter.isEmpty
        ? '${record.page}/${record.totalPage}'
        : '$chapter · ${record.page}/${record.totalPage}';
  }

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

    // 书签删光的组只保留组头（封面 + 书名 + 继续阅读），没有可删的条目。
    final empty = bookmarks.isEmpty;

    return Card(
      margin: EdgeInsets.zero,
      color: cs.surfaceBright,
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
            // 等待落盘后由 store 通知刷新；组头即使书签被删光也仍在，
            // 因此不能用 onDismissed（会命中「已 dismiss 的 Dismissible 仍在树上」断言）。
            confirmDismiss: (_) async {
              await onClearGroup();
              return false;
            },
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
                    // 组头「继续阅读」：胶囊按钮，章节 + 页码取自本地阅读记录。
                    if (continueRecord != null) ...[
                      const SizedBox(width: AppSpacing.sm),
                      FilledButton.tonalIcon(
                        key: ValueKey('bookmark_continue_$pathWord'),
                        onPressed: onContinue,
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(
                            _continueLabel(continueRecord!),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.surfaceContainerHighest,
                          foregroundColor: cs.onSurfaceVariant,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                          ),
                          // 高度对齐详情页 FAB（48），压扁会显得局促。
                          minimumSize: const Size(0, 48),
                          textStyle: tt.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (!empty) ...[
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
                confirmDismiss: (_) async {
                  await onRemove(bookmark);
                  return false;
                },
                child: _BookmarkTile(
                  bookmark: bookmark,
                  onTap: () => onOpenBookmark(bookmark),
                ),
              ),
            ),
          ],
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
            ? CoverImage(
                url: coverUrl,
                placeholder: _placeholder(cs),
                errorWidget: _placeholder(cs, error: true),
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

/// 单个书签条目：单行显示章节名 + 页码 + 时间，点击直达阅读位置。
class _BookmarkTile extends StatelessWidget {
  final ComicBookmark bookmark;
  final VoidCallback onTap;

  const _BookmarkTile({required this.bookmark, required this.onTap});

  /// 页码与相对时间，跟在章节名后以小字号显示。
  String _metaOf(AppLocalizations l10n) => [
    l10n.bookmarkPage(bookmark.page),
    if (bookmark.updatedAt != null)
      TimeFormat.relative(bookmark.updatedAt!, l10n),
  ].where((part) => part.isNotEmpty).join(' · ');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    final chapter = bookmark.chapterName.trim();
    final meta = _metaOf(l10n);

    return InkWell(
      key: ValueKey('bookmark_open_${bookmark.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.bookmark, size: 16, color: cs.primary),
            const SizedBox(width: 8),
            // 章节名过长时先截断，页码/时间右对齐、始终完整可见。
            Expanded(
              child: Text(
                chapter,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.bodyMedium,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              meta,
              maxLines: 1,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
