import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';

import '../api/novel/novel_api.dart' show novelErrorMessage;
import '../l10n/app_localizations.dart';
import '../models/novel_reading_progress.dart';
import '../providers/novel_providers.dart';
import '../routing/app_router.dart';
import '../theme/app_icon_sizes.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/app_logger.dart';
import '../utils/novel_bookmark_store.dart';
import '../utils/novel_chapter_display.dart';
import '../utils/novel_reading_store.dart';
import '../utils/screen_layout.dart';
import '../utils/time_format.dart';
import '../utils/toast.dart';
import '../widgets/error_retry_view.dart';
import '../widgets/novel_widgets.dart';

/// 统一书签页的轻小说分页，不查询网络目录，也不改写最后阅读进度。
class NovelBookmarksPage extends ConsumerStatefulWidget {
  const NovelBookmarksPage({
    super.key,
    required this.onChanged,
    this.query = '',
  });

  final VoidCallback onChanged;

  /// 宿主页搜索框的关键词，空串表示不过滤。
  final String query;

  @override
  ConsumerState<NovelBookmarksPage> createState() => NovelBookmarksPageState();
}

class NovelBookmarksPageState extends ConsumerState<NovelBookmarksPage>
    with AutomaticKeepAliveClientMixin {
  late final NovelBookmarkStore _store;
  ScaffoldMessengerState? _messenger;
  bool _loading = true;
  bool _failed = false;
  Object? _loadError;
  bool _updating = false;

  bool get hasBookmarks =>
      !_loading && !_updating && _store.bookmarks.isNotEmpty;

  /// 每部轻小说的本地阅读进度（null 表示查过但没有），供组头「继续阅读」。
  final Map<String, NovelReadingProgress?> _history = {};
  final Set<String> _fetchingHistory = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _store = ref.read(novelBookmarkStoreProvider)..addListener(_onStoreChanged);
    NovelReadingStore.changes.addListener(_onHistoryChanged);
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.of(context);
  }

  @override
  void dispose() {
    _messenger?.clearSnackBars();
    NovelReadingStore.changes.removeListener(_onHistoryChanged);
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (!mounted) return;
    setState(() {});
    widget.onChanged();
  }

  /// 阅读进度变化（包括在别处阅读）时丢弃缓存，下次 build 重新查询。
  void _onHistoryChanged() {
    if (!mounted || _history.isEmpty) return;
    setState(_history.clear);
  }

  /// 只读本地阅读进度，不发任何请求；查过就记住，含「确实没有记录」。
  Future<void> _loadHistory(String pathWord) async {
    if (_history.containsKey(pathWord)) return;
    if (!_fetchingHistory.add(pathWord)) return;
    try {
      final progress = await ref
          .read(novelReadingStoreProvider)
          .readProgress(pathWord);
      if (!mounted) return;
      setState(() => _history[pathWord] = progress);
    } catch (error, stack) {
      _logFailure(error, stack);
    } finally {
      _fetchingHistory.remove(pathWord);
    }
  }

  /// 组头「继续阅读」：直接跳到该轻小说的本地阅读位置。
  Future<void> _continueReading(String pathWord) async {
    final progress = _history[pathWord];
    if (progress == null) return;
    _messenger?.clearSnackBars();
    await context.pushNamed(
      AppRoutes.novelReader,
      pathParameters: {
        'pathWord': progress.pathWord,
        'volumeId': progress.volumeId,
      },
      extra: NovelReaderExtra(
        name: progress.name,
        cover: progress.cover,
        entryIndex: progress.entryIndex,
        initialParagraphIndex: progress.paragraphIndex,
        initialParagraphAlignment: progress.paragraphAlignment,
        noDetailBelow: true,
      ),
    );
    if (!mounted) return;
    // 返回时进度已更新：丢缓存重查，下次仍从最新位置继续。
    setState(() => _history.remove(pathWord));
  }

  Future<void> _load({bool refresh = false}) async {
    try {
      if (refresh) {
        await _store.reload();
      } else {
        await _store.ensureLoaded();
      }
      if (mounted) setState(() => _failed = false);
    } catch (error, stack) {
      _logFailure(error, stack);
      if (mounted) {
        setState(() {
          _failed = true;
          _loadError = error;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        widget.onChanged();
      }
    }
  }

  void _logFailure(Object error, StackTrace stack) {
    unawaited(
      AppLogger.instance.recordWarning(
        'Novel bookmark page operation failed (${error.runtimeType})',
        stackTrace: stack,
        source: 'novel_bookmarks_page',
      ),
    );
  }

  Future<void> _update(
    Future<List<NovelBookmark>> Function() action, {
    bool undo = false,
    List<NovelBookmarkGroup> removedGroups = const [],
  }) async {
    if (_updating) return;
    setState(() => _updating = true);
    widget.onChanged();
    try {
      final removed = await action();
      if (mounted &&
          !undo &&
          (removed.isNotEmpty || removedGroups.isNotEmpty)) {
        _showUndo(removed, removedGroups: removedGroups);
      }
    } catch (error, stack) {
      _logFailure(error, stack);
      if (mounted) {
        showToast(
          context,
          AppLocalizations.of(
            context,
          )!.bookmarksUpdateFailedDetail(novelErrorMessage(error)),
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _updating = false);
        widget.onChanged();
      }
    }
  }

  Future<void> _remove(NovelBookmark bookmark) => _update(() async {
    final removed = await _store.remove(bookmark.id);
    return removed == null ? const [] : [removed];
  });

  Future<void> _clearGroup(String pathWord) {
    final group = _groupMetaOf(pathWord);
    return _update(
      () => _store.removeGroup(pathWord),
      removedGroups: group != null ? [group] : const [],
    );
  }

  Future<void> clearAll() async {
    if (!hasBookmarks) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.bookmarksClearTitle),
        content: Text(l10n.bookmarksTabClearContent(l10n.historyTabNovel)),
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
    if (confirmed == true && mounted) await _update(_store.clear);
  }

  void _showUndo(
    List<NovelBookmark> removed, {
    List<NovelBookmarkGroup> removedGroups = const [],
  }) {
    final l10n = AppLocalizations.of(context)!;
    final style = TextButton.styleFrom(
      foregroundColor: Theme.of(context).colorScheme.onInverseSurface,
    );
    _messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.fixed,
          duration: const Duration(seconds: 5),
          content: Row(
            children: [
              Expanded(
                child: Text(
                  removed.length <= 1
                      ? l10n.bookmarkDeleted
                      : l10n.bookmarksGroupDeleted(removed.length),
                ),
              ),
              TextButton(
                style: style,
                onPressed: () {
                  _messenger?.hideCurrentSnackBar();
                  unawaited(
                    _update(() async {
                      await _store.restoreAll(removed, groups: removedGroups);
                      return const [];
                    }, undo: true),
                  );
                },
                child: Text(l10n.bookmarkUndo),
              ),
              TextButton(
                style: style,
                onPressed: () => _messenger?.hideCurrentSnackBar(),
                child: Text(l10n.closeButton),
              ),
            ],
          ),
        ),
      );
  }

  Future<void> _open(NovelBookmark bookmark) async {
    _messenger?.clearSnackBars();
    await context.pushNamed(
      AppRoutes.novelReader,
      pathParameters: {
        'pathWord': bookmark.pathWord,
        'volumeId': bookmark.volumeId,
      },
      extra: NovelReaderExtra(
        name: bookmark.name,
        cover: bookmark.cover,
        entryIndex: bookmark.entryIndex,
        initialParagraphIndex: bookmark.paragraphIndex,
        initialParagraphAlignment: bookmark.paragraphAlignment,
        noDetailBelow: true,
        // 书签进入时短暂高亮目标段落。
        highlightParagraph: true,
      ),
    );
    if (mounted) setState(() {});
  }

  /// 组元数据（书签删光后仍保留）；没有则返回 null。
  NovelBookmarkGroup? _groupMetaOf(String pathWord) {
    for (final group in _store.groups) {
      if (group.pathWord == pathWord) return group;
    }
    return null;
  }

  /// 组头书名：优先书签自带，其次组元数据，最后回退 pathWord。
  String _groupNameOf(String pathWord) {
    for (final bookmark in _store.bookmarks) {
      if (bookmark.pathWord == pathWord && bookmark.name.isNotEmpty) {
        return bookmark.name;
      }
    }
    final meta = _groupMetaOf(pathWord);
    if (meta != null && meta.name.isNotEmpty) return meta.name;
    return pathWord;
  }

  /// 组头封面：优先书签自带，其次组元数据。
  String _groupCoverOf(String pathWord) {
    for (final bookmark in _store.bookmarks) {
      if (bookmark.pathWord == pathWord && bookmark.cover.isNotEmpty) {
        return bookmark.cover;
      }
    }
    return _groupMetaOf(pathWord)?.cover ?? '';
  }

  /// 组排序时间：组内最新书签的时间；空组用组元数据的时间。
  DateTime _groupUpdatedAt(String pathWord) {
    // _store.bookmarks 本身按时间倒序，第一条命中即最新。
    for (final bookmark in _store.bookmarks) {
      if (bookmark.pathWord == pathWord) return bookmark.updatedAt;
    }
    return _groupMetaOf(pathWord)?.updatedAt ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// 组头点击进入详情；书签删光的组也能进。
  Future<void> _openDetails(String pathWord) async {
    _messenger?.clearSnackBars();
    await context.pushNamed(
      AppRoutes.novelDetail,
      pathParameters: {'pathWord': pathWord},
    );
    if (mounted) setState(() {});
  }

  /// 书名、卷名与章节名都参与匹配（卷内章节名通常不带卷名前缀）。
  bool _matchesQuery(NovelBookmark bookmark, String query) {
    if (query.isEmpty) return true;
    return bookmark.name.toLowerCase().contains(query) ||
        bookmark.volumeName.toLowerCase().contains(query) ||
        bookmark.chapterName.toLowerCase().contains(query);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final query = widget.query.trim().toLowerCase();
    final groups = <String, List<NovelBookmark>>{};
    for (final bookmark in _store.bookmarks) {
      groups.putIfAbsent(bookmark.pathWord, () => []).add(bookmark);
    }
    // 书签被删光的组仍在：用组元数据补成空组，只显示组头与继续阅读。
    for (final group in _store.groups) {
      groups.putIfAbsent(group.pathWord, () => const []);
    }
    final all = groups.entries.toList()
      ..sort(
        (a, b) => _groupUpdatedAt(b.key).compareTo(_groupUpdatedAt(a.key)),
      );
    // 搜索是「组级」的：组内任一条命中，该轻小说的全部书签都照常展示。
    final entries = query.isEmpty
        ? all
        : all
              .where(
                (entry) =>
                    entry.value.any((b) => _matchesQuery(b, query)) ||
                    _groupNameOf(entry.key).toLowerCase().contains(query),
              )
              .toList();
    final searching = query.isNotEmpty;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final hp = ScreenLayout.horizontalPadding(screenWidth);
    // 宽屏（横屏 / 桌面窗口）每组书签卡片两列并排，窄屏保持单列。
    final twoColumn =
        ScreenLayout.contentWidth(screenWidth) >= ScreenLayout.wideBreakpoint;
    // 两列各自堆叠：组卡片高度随书签条数变化，按行配对会在矮的一侧留白。
    final (leftColumn, rightColumn) = twoColumn
        ? ScreenLayout.splitTwoColumns(
            entries.length,
            (index) => entries[index].value.length + 1,
          )
        : (const <int>[], const <int>[]);

    Widget groupCard(int index) {
      final pathWord = entries[index].key;
      if (!_history.containsKey(pathWord)) {
        // build 期间不得同步触发 setState，延迟到帧结束后再查阅读进度。
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _loadHistory(pathWord),
        );
      }
      return _NovelBookmarkGroupCard(
        pathWord: pathWord,
        name: _groupNameOf(pathWord),
        cover: _groupCoverOf(pathWord),
        bookmarks: entries[index].value,
        continueProgress: _history[pathWord],
        updating: _updating,
        onOpen: _open,
        onDetails: () => unawaited(_openDetails(pathWord)),
        onContinue: () => _continueReading(pathWord),
        onRemove: _remove,
        onClear: () => _clearGroup(pathWord),
      );
    }

    /// 一列内的组卡片，纵向堆叠，卡片间距与单列一致。
    Widget bookmarkColumn(List<int> indices) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final index in indices)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: groupCard(index),
          ),
      ],
    );

    if (_loading) return const Center(child: ExpressiveLoadingIndicator());
    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: CustomScrollView(
        key: const PageStorageKey('novel_bookmarks_list'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (_failed)
            SliverErrorRetryView(
              message: _loadError == null
                  ? l10n.bookmarksLoadFailed
                  : '${l10n.bookmarksLoadFailed}：'
                        '${novelErrorMessage(_loadError)}',
              onRetry: () => _load(refresh: true),
            )
          else if (entries.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        searching ? Icons.search_off : Icons.bookmark_border,
                        size: AppIconSize.display,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        searching
                            ? l10n.bookmarksSearchEmpty
                            : l10n.bookmarksEmptyTitle,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (!searching) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          l10n.novelBookmarksEmptySubtitle,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            )
          else ...[
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                hp,
                AppSpacing.sm,
                hp,
                AppSpacing.md,
              ),
              sliver: twoColumn
                  ? SliverToBoxAdapter(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: bookmarkColumn(leftColumn)),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(child: bookmarkColumn(rightColumn)),
                        ],
                      ),
                    )
                  : SliverList.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: groupCard(index),
                      ),
                    ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                child: Text(
                  l10n.bookmarksSwipeHint,
                  textAlign: TextAlign.center,
                  style: AppTypography.meta(
                    theme.textTheme,
                  )?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NovelBookmarkGroupCard extends StatelessWidget {
  const _NovelBookmarkGroupCard({
    required this.pathWord,
    required this.name,
    required this.cover,
    required this.bookmarks,
    required this.continueProgress,
    required this.updating,
    required this.onOpen,
    required this.onDetails,
    required this.onContinue,
    required this.onRemove,
    required this.onClear,
  });

  final String pathWord;

  /// 组头书名与封面；书签删光后由组元数据提供，因此由父级算好传入。
  final String name;
  final String cover;
  final List<NovelBookmark> bookmarks;

  /// 该轻小说的本地阅读进度；为空表示没有可继续的进度，此时不显示按钮。
  final NovelReadingProgress? continueProgress;
  final bool updating;
  final Future<void> Function(NovelBookmark) onOpen;
  final VoidCallback onDetails;
  final VoidCallback onContinue;
  final Future<void> Function(NovelBookmark) onRemove;
  final Future<void> Function() onClear;

  /// 与本地小说页 FAB 一致：卷名 + 卷内百分比。
  static String _continueLabel(NovelReadingProgress progress) => [
    progress.volumeName,
    '${_percentLabel(progress.progress)}%',
  ].where((part) => part.isNotEmpty).join(' · ');

  /// 卷名 + 去重后的章节名，两者都空时返回空串。
  static String _chapterLabel(NovelBookmark bookmark) => [
    bookmark.volumeName,
    stripVolumePrefix(bookmark.chapterName, bookmark.volumeName),
  ].where((part) => part.isNotEmpty).join(' · ');

  /// 百分比保留两位小数；未到结尾不得四舍五入成 100%。
  static String _percentLabel(double progress) {
    if (progress >= 1) return '100.00';
    final percent = progress * 100;
    return (percent > 99.99 ? 99.99 : percent).toStringAsFixed(2);
  }

  Widget _dismissible({
    required String id,
    required Widget child,
    required Future<void> Function() remove,
    required ColorScheme cs,
  }) => Dismissible(
    key: ValueKey(id),
    direction: updating ? DismissDirection.none : DismissDirection.endToStart,
    background: Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: AppSpacing.xl),
      color: cs.errorContainer,
      child: Icon(Icons.delete_outline, color: cs.onErrorContainer),
    ),
    // 等待落盘后由 store 通知移除条目；失败时保留，不留下已滑走的假删除。
    confirmDismiss: (_) async {
      await remove();
      return false;
    },
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // 书签删光的组只保留组头（封面 + 书名 + 继续阅读），没有可删的条目。
    final empty = bookmarks.isEmpty;
    return Card(
      margin: EdgeInsets.zero,
      color: cs.surfaceBright,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _dismissible(
            id: 'novel_bookmark_group_$pathWord',
            cs: cs,
            remove: onClear,
            child: InkWell(
              key: ValueKey('novel_bookmark_details_$pathWord'),
              onTap: onDetails,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      child: AspectRatio(
                        aspectRatio: 0.72,
                        child: CardTheme(
                          data: CardTheme.of(context).copyWith(elevation: 0),
                          child: NovelCover(url: cover),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            l10n.bookmarksCount(bookmarks.length),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 组头「继续阅读」：胶囊按钮，章节 + 卷内百分比取自本地进度。
                    if (continueProgress != null) ...[
                      const SizedBox(width: AppSpacing.sm),
                      FilledButton.tonalIcon(
                        key: ValueKey('novel_bookmark_continue_$pathWord'),
                        onPressed: onContinue,
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(
                            _continueLabel(continueProgress!),
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
                          textStyle: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (!empty) ...[
            const Divider(
              height: 1,
              indent: AppSpacing.md,
              endIndent: AppSpacing.md,
            ),
            for (final bookmark in bookmarks)
              _dismissible(
                id: 'novel_bookmark_${bookmark.id}',
                cs: cs,
                remove: () => onRemove(bookmark),
                child: ListTile(
                  key: ValueKey('novel_bookmark_open_${bookmark.id}'),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  horizontalTitleGap: AppSpacing.sm,
                  minLeadingWidth: AppIconSize.sm,
                  leading: Icon(
                    Icons.bookmark,
                    size: AppIconSize.sm,
                    color: cs.primary,
                  ),
                  // 章节名过长时先截断，百分比/时间右对齐、始终完整可见。
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _chapterLabel(bookmark),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        '${_percentLabel(bookmark.progress)}%'
                        ' · ${TimeFormat.relative(bookmark.updatedAt, l10n)}',
                        maxLines: 1,
                        style: AppTypography.meta(
                          theme.textTheme,
                        )?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                  onTap: () => onOpen(bookmark),
                  // 与漫画书签条目一致：尾部只放导航箭头，删除走左滑。
                  trailing: Icon(
                    Icons.chevron_right,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
