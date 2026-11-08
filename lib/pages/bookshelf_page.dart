import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../l10n/app_localizations.dart';
import '../models/api_ordering.dart';
import '../models/comic.dart' hide Theme;
import '../models/user_manager.dart';
import '../providers/app_providers.dart';
import '../providers/repository_providers.dart';
import '../repositories/bookshelf_repository.dart';
import '../routing/app_router.dart';
import '../routing/branch_activation.dart';
import '../theme/app_spacing.dart';
import '../utils/app_logger.dart';
import '../utils/network_error.dart';
import '../utils/reading_history.dart';
import '../utils/screen_layout.dart';
import '../utils/time_format.dart';
import '../utils/toast.dart';
import '../widgets/back_to_top_button.dart';
import '../widgets/branch_bottom_slack.dart';
import '../widgets/comic_card_skeleton.dart';
import '../widgets/comic_hero_tags.dart';
import '../widgets/error_retry_view.dart';
import '../widgets/load_more_footer.dart';
import '../widgets/login_expired_dialog.dart';
import '../widgets/ordering_tile.dart';
import '../widgets/update_badge.dart';
import 'home_page.dart';
import 'novel_bookshelf_page.dart';

part 'bookshelf/bookshelf_grids.dart';
part 'bookshelf/bookshelf_toolbar.dart';

enum BookshelfTab { comic, novel }

class BookshelfPage extends StatefulWidget {
  final BookshelfTab initialTab;

  const BookshelfPage({super.key, this.initialTab = BookshelfTab.comic});

  @override
  State<BookshelfPage> createState() => _BookshelfRootState();
}

class _BookshelfRootState extends State<BookshelfPage> {
  @override
  Widget build(BuildContext context) {
    final user = UserManager();
    return ListenableBuilder(
      listenable: user,
      builder: (context, _) {
        // 通用页「轻小说」开关关闭时隐藏 tab 组件，只展示漫画书架。
        if (!user.showNovel) {
          return const Scaffold(body: _ComicBookshelfPage(active: true));
        }
        return _BookshelfDualTabs(initialTab: widget.initialTab);
      },
    );
  }
}

class _BookshelfDualTabs extends StatefulWidget {
  final BookshelfTab initialTab;

  const _BookshelfDualTabs({required this.initialTab});

  @override
  State<_BookshelfDualTabs> createState() => _BookshelfTabsState();
}

class _BookshelfTabsState extends State<_BookshelfDualTabs>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late int _selected;
  final _visited = [false, false];
  final _totals = [0, 0];

  @override
  void initState() {
    super.initState();
    _selected = widget.initialTab.index;
    _visited[_selected] = true;
    _tabs = TabController(length: 2, vsync: this, initialIndex: _selected);
  }

  @override
  void didUpdateWidget(covariant _BookshelfDualTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab) {
      _tabs.index = widget.initialTab.index;
      _select(_tabs.index);
    }
  }

  void _select(int index) {
    setState(() {
      _selected = index;
      _visited[index] = true;
    });
  }

  void _updateTotal(int index, int total) {
    if (!mounted || _totals[index] == total) return;
    setState(() => _totals[index] = total);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      // 顶部不放「书架」大标题，TabBar 直接顶到状态栏下方。
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 0,
        bottom: TabBar(
          controller: _tabs,
          onTap: _select,
          tabs: [
            Tab(
              text: _totals[0] > 0
                  ? '${l10n.comicTabLabel} (${_totals[0]})'
                  : l10n.comicTabLabel,
            ),
            Tab(
              text: _totals[1] > 0
                  ? '${l10n.novelTitle} (${_totals[1]})'
                  : l10n.novelTitle,
            ),
          ],
        ),
      ),
      // Only load a shelf after it is selected, then preserve its scroll state.
      body: IndexedStack(
        index: _selected,
        children: [
          _visited[0]
              ? TickerMode(
                  enabled: _selected == 0,
                  child: _ComicBookshelfPage(
                    active: _selected == 0,
                    onTotalChanged: (total) => _updateTotal(0, total),
                  ),
                )
              : const SizedBox.shrink(),
          _visited[1]
              ? TickerMode(
                  enabled: _selected == 1,
                  child: NovelBookshelfPage(
                    active: _selected == 1,
                    onTotalChanged: (total) => _updateTotal(1, total),
                  ),
                )
              : const SizedBox.shrink(),
        ],
      ),
    );
  }
}

class _ComicBookshelfPage extends ConsumerStatefulWidget {
  const _ComicBookshelfPage({required this.active, this.onTotalChanged});

  /// 共享 Tab 是否处于前台：重新激活时按缓存年龄决定是否静默刷新。
  final bool active;
  final ValueChanged<int>? onTotalChanged;

  @override
  ConsumerState<_ComicBookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends ConsumerState<_ComicBookshelfPage>
    with WidgetsBindingObserver, BranchDeferredInit {
  static const _cacheTtl = Duration(minutes: 30);
  ApiClient get _api => ref.read(apiClientProvider);
  ComicBookshelfRepository get _comicRepo =>
      ref.read(comicBookshelfRepoProvider);
  late final UserManager _user = ref.read(userManagerProvider);
  final _scrollController = ScrollController();
  Timer? _cacheTimeTimer;
  List<BookshelfItem> _items = [];
  Map<String, Set<String>> _readChapters = {};
  int _historyGeneration = 0;
  bool _loading = true;

  /// 首屏加载失败的原因。失败时若只把列表留空，用户看到的是「书架是空的」，
  /// 真实错误（DNS/超时/401/业务码）就被完全掩盖了。
  String? _loadError;
  int _offset = 0;
  int _total = 0;
  DateTime? _comicCacheTime;
  bool _loadingMore = false;
  String? _loadMoreError;
  bool _refreshing = false;
  bool _showingLoginPrompt = false;
  late bool _lastIsLoggedIn;
  late String? _lastToken;
  late String _ordering = _user.bookshelfOrdering;
  bool _showUpdateOnly = false;
  bool _showBackToTop = false;

  static const _showUpdateOnlyKey = 'local_bookshelf_show_update_only';
  static const _legacyShowUpdateOnlyKey = 'bookshelf_show_update_only';

  /// extension part 文件里的成员不是 State 子类成员，不能直接调用受保护的
  /// [setState]，统一经由这个转发方法。
  void _setState(VoidCallback fn) => setState(fn);

  void _startCacheTimeTimer() {
    _cacheTimeTimer?.cancel();
    _cacheTimeTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void initState() {
    super.initState();
    _lastIsLoggedIn = _user.isLoggedIn;
    _lastToken = _user.token;
    WidgetsBinding.instance.addObserver(this);
    _user.addListener(_onUserChanged);
    ReadingHistory.changes.addListener(_onReadingHistoryChanged);
    _startCacheTimeTimer();
    deferInitialLoadToBranchActivation();
  }

  @override
  void onBranchFirstActivated() {
    _loadShowUpdateOnly();
    if (_user.isLoggedIn) {
      _tryLoadCache().then((_) {
        if (mounted && _currentItemsEmpty) _load(silent: true);
      });
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cacheTimeTimer?.cancel();
    _scrollController.dispose();
    _user.removeListener(_onUserChanged);
    ReadingHistory.changes.removeListener(_onReadingHistoryChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _ensureFresh();
  }

  @override
  void didUpdateWidget(covariant _ComicBookshelfPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) _ensureFresh();
    if (oldWidget.onTotalChanged != widget.onTotalChanged) {
      _notifyTotalChanged();
    }
  }

  void _notifyTotalChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onTotalChanged?.call(_total);
    });
  }

  bool _hasUpdate(BookshelfItem item) =>
      item.hasUpdate &&
      !(_readChapters[item.comic.pathWord]?.contains(
            item.comic.lastChapterId,
          ) ??
          false);

  Future<Map<String, Set<String>>> _readLocalChapters(
    Iterable<BookshelfItem> items,
  ) async {
    try {
      return await ReadingHistory.readChapterUuidsForComics(
        items.map((item) => item.comic.pathWord),
      );
    } catch (error, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          error,
          stackTrace: stack,
          source: 'bookshelf_page.local_read_chapters',
        ),
      );
      return {};
    }
  }

  void _onReadingHistoryChanged() {
    if (_items.isNotEmpty) unawaited(_reloadLocalChapters());
  }

  Future<void> _reloadLocalChapters() async {
    final generation = ++_historyGeneration;
    final chapters = await _readLocalChapters(_items);
    if (!mounted || generation != _historyGeneration) return;
    setState(() => _readChapters = chapters);
  }

  /// 缓存新鲜时只重读本地已读状态，过期（或缺失）时静默重拉。
  void _ensureFresh() {
    if (!_user.isLoggedIn || _refreshing || _loading) return;
    final cacheTime = _comicCacheTime;
    if (cacheTime != null && DateTime.now().difference(cacheTime) < _cacheTtl) {
      unawaited(_reloadLocalChapters());
      return;
    }
    unawaited(_load(silent: true));
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _onUserChanged() {
    if (!mounted) return;

    final isLoggedIn = _user.isLoggedIn;
    final token = _user.token;
    final loginChanged = isLoggedIn != _lastIsLoggedIn || token != _lastToken;
    final nextOrdering = _user.bookshelfOrdering;
    final orderingChanged = _ordering != nextOrdering;

    _lastIsLoggedIn = isLoggedIn;
    _lastToken = token;

    if (!isLoggedIn) {
      if (loginChanged) {
        setState(() {
          _items = [];
          _readChapters = {};
          ++_historyGeneration;
          _total = 0;
          _offset = 0;
          _loading = false;
          _loadingMore = false;
          _loadMoreError = null;
          _loadError = null;
          _refreshing = false;
          _ordering = nextOrdering;
        });
        _notifyTotalChanged();
      } else if (orderingChanged) {
        setState(() {
          _ordering = nextOrdering;
        });
      }
      return;
    }

    if (orderingChanged) {
      setState(() {
        _ordering = nextOrdering;
      });
    }

    if (loginChanged) {
      _load(silent: true, force: true);
    }
  }

  Future<void> _loadShowUpdateOnly() async {
    final prefs = await SharedPreferences.getInstance();
    var value = prefs.getBool(_showUpdateOnlyKey);
    final legacyValue = prefs.getBool(_legacyShowUpdateOnlyKey);

    if (value == null && legacyValue != null) {
      value = legacyValue;
      await prefs.setBool(_showUpdateOnlyKey, legacyValue);
    }
    if (legacyValue != null) {
      await prefs.remove(_legacyShowUpdateOnlyKey);
    }

    if (!mounted || value == null) return;
    setState(() => _showUpdateOnly = value!);
  }

  void _setShowUpdateOnly(bool value) {
    if (_showUpdateOnly == value) return;
    setState(() => _showUpdateOnly = value);
    unawaited(_saveShowUpdateOnly(value));
  }

  Future<void> _saveShowUpdateOnly(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showUpdateOnlyKey, value);
    await prefs.remove(_legacyShowUpdateOnlyKey);
  }

  Future<void> _tryLoadCache() async {
    final comicCached = await _comicRepo.loadFromCache();
    if (comicCached != null && comicCached.items.isNotEmpty) {
      final chapters = await _readLocalChapters(comicCached.items);
      if (!mounted) return;
      setState(() {
        _items = comicCached.items;
        _readChapters = chapters;
        ++_historyGeneration;
        _total = comicCached.total;
        _offset = comicCached.items.length;
        _comicCacheTime = comicCached.cacheTime;
        _loading = false;
      });
      _notifyTotalChanged();
    }
  }

  Future<void> _saveComicCache(
    List<BookshelfItem> items,
    int total,
    DateTime cacheTime,
  ) async {
    await _comicRepo.saveToCache(
      ComicBookshelfData(items: items, total: total, cacheTime: cacheTime),
    );
  }

  Future<void> _load({bool silent = false, bool force = false}) async {
    if (!force && !_currentItemsEmpty) {
      final cacheTime = _comicCacheTime;
      if (cacheTime != null &&
          DateTime.now().difference(cacheTime) < const Duration(minutes: 30)) {
        return;
      }
    }
    if (_refreshing && !force) return;
    _refreshing = true;
    final isInitial = _currentItemsEmpty;
    if (isInitial) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    } else {
      setState(() => _loadError = null);
    }
    _offset = 0;
    try {
      final data = await _api.manga.getBookshelf(ordering: _ordering);
      final chapters = await _readLocalChapters(data.list);
      if (!mounted) return;
      final now = DateTime.now();
      setState(() {
        _items = data.list;
        _readChapters = chapters;
        ++_historyGeneration;
        _total = data.total;
        _offset = data.list.length;
        _comicCacheTime = now;
        _loading = false;
        _loadError = null;
      });
      _notifyTotalChanged();
      unawaited(_saveComicCache(data.list, data.total, now));
      if (!silent && mounted) {
        showToast(context, AppLocalizations.of(context)!.refreshSuccess);
      }
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'bookshelf_page.load',
        ),
      );
      if (isInitial && mounted) {
        setState(() {
          _loading = false;
          _loadError = NetworkError.message(e);
        });
      }
      if (_isUnauthorized(e)) {
        await _handleUnauthorized();
      } else if (!silent && mounted) {
        final l10n = AppLocalizations.of(context)!;
        showToast(
          context,
          l10n.refreshFailedDetail(NetworkError.message(e, l10n: l10n)),
          isError: true,
        );
      }
    } finally {
      _refreshing = false;
      if (mounted) {
        setState(() {});
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      }
    }
  }

  Future<void> _refreshLoaded() async {
    if (_refreshing) return;
    _refreshing = true;
    setState(() {});
    try {
      final currentCount = _items.length;
      if (currentCount == 0) {
        _refreshing = false;
        if (mounted) setState(() {});
        return;
      }
      final data = await _api.manga.getBookshelf(
        limit: currentCount,
        ordering: _ordering,
      );
      final chapters = await _readLocalChapters(data.list);
      if (!mounted) return;
      setState(() {
        _items = data.list;
        _readChapters = chapters;
        ++_historyGeneration;
        _total = data.total;
        _offset = data.list.length;
      });
      _notifyTotalChanged();
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'bookshelf_page.refresh_loaded',
        ),
      );
      if (_isUnauthorized(e)) {
        await _handleUnauthorized();
      }
    } finally {
      _refreshing = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _refreshing || _offset >= _total) return;
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    try {
      final data = await _api.manga.getBookshelf(
        offset: _offset,
        ordering: _ordering,
      );
      final items = [..._items, ...data.list];
      final chapters = await _readLocalChapters(items);
      if (!mounted) return;
      setState(() {
        _items = items;
        _readChapters = chapters;
        ++_historyGeneration;
        _total = data.total;
        _offset = _items.length;
      });
      _notifyTotalChanged();
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'bookshelf_page.load_more',
        ),
      );
      if (_isUnauthorized(e)) {
        await _handleUnauthorized();
      } else if (mounted) {
        setState(() => _loadMoreError = NetworkError.message(e));
      }
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
      } else {
        _loadingMore = false;
      }
    }
  }

  bool _isUnauthorized(Object error) =>
      error is DioException && error.response?.statusCode == 401;

  Future<void> _handleUnauthorized() async {
    if (_showingLoginPrompt || !mounted) return;

    _showingLoginPrompt = true;

    await _user.logout();
    if (!mounted) {
      _showingLoginPrompt = false;
      return;
    }

    final shouldLogin = await showLoginExpiredDialog(
      context,
      content: AppLocalizations.of(context)!.loginExpiredBookshelfContent,
    );

    if (shouldLogin == true && mounted) {
      final loggedIn = await context.pushNamed<bool>(AppRoutes.login);
      if (loggedIn == true && mounted) {
        unawaited(_load(silent: true));
      }
    } else if (mounted) {
      showToast(
        context,
        AppLocalizations.of(context)!.loginToViewBookshelf,
        isError: true,
      );
    }

    _showingLoginPrompt = false;
  }

  static String _orderingLabel(AppLocalizations l10n, String ordering) {
    switch (ordering) {
      case ApiOrdering.datetimeUpdated:
        return l10n.sortByUpdate;
      case ApiOrdering.datetimeModifier:
        return l10n.sortByFavorite;
      case ApiOrdering.datetimeBrowse:
        return l10n.sortByRead;
      default:
        return l10n.sortLabel;
    }
  }

  bool get _currentItemsEmpty => _items.isEmpty;

  String get _cacheTimeLabel {
    final cacheTime = _comicCacheTime;
    if (cacheTime == null) return '';
    return AppLocalizations.of(context)!.refreshedAt(
      TimeFormat.relative(cacheTime, AppLocalizations.of(context)!),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final hp = ScreenLayout.horizontalPadding(screenWidth);
    final cardExtent = ScreenLayout.cardExtent(screenWidth);

    return Scaffold(
      // 右下角悬浮回到顶部按钮，与其他列表页共用 BackToTopButton。
      floatingActionButton: _showBackToTop
          ? BackToTopButton(onPressed: _scrollToTop)
          : null,
      body: RefreshIndicator(
        onRefresh: () => _load(force: true),
        edgeOffset: MediaQuery.of(context).padding.top,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.axis == Axis.vertical) {
              final shouldShow = n.metrics.pixels > 400;
              if (shouldShow != _showBackToTop) {
                setState(() => _showBackToTop = shouldShow);
              }
              if (!_loading &&
                  n.metrics.pixels > 0 &&
                  n.metrics.pixels > n.metrics.maxScrollExtent - 300) {
                _loadMore();
              }
            }
            return false;
          },
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar(
                floating: true,
                snap: true,
                automaticallyImplyLeading: false,
                toolbarHeight: 0,
                bottom: PreferredSize(
                  preferredSize: Size.fromHeight(
                    _toolbarContentHeight(context),
                  ),
                  child: _buildToolbar(context, hp),
                ),
              ),
              if (_loading)
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: hp),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate(
                      (_, _) => const ComicCardSkeleton(),
                      childCount: 12,
                    ),
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: cardExtent,
                      childAspectRatio: 0.55,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                    ),
                  ),
                )
              else if (_currentItemsEmpty && _loadError != null)
                SliverFillRemaining(
                  child: ErrorRetryView(
                    message: AppLocalizations.of(
                      context,
                    )!.refreshFailedDetail(_loadError!),
                    onRetry: () => _load(force: true),
                  ),
                )
              else if (_currentItemsEmpty)
                SliverFillRemaining(child: _buildEmptyState(context))
              else if (_showUpdateOnly && !_items.any(_hasUpdate))
                SliverFillRemaining(child: _buildNoUpdates(context))
              else
                _buildComicGrid(context, hp),
              if (!_loading && !_currentItemsEmpty && _offset < _total)
                SliverToBoxAdapter(
                  child: LoadMoreFooter(
                    loading: _loadingMore,
                    onPressed: _loadMore,
                    label: AppLocalizations.of(
                      context,
                    )!.loadMoreProgress(_offset, _total),
                    detail: _loadMoreError,
                    horizontalPadding: hp,
                  ),
                ),
              const SliverToBoxAdapter(
                child: BranchBottomSlack(extra: AppSpacing.xxl),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
