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
import '../theme/app_spacing.dart';
import '../theme/app_status_colors.dart';
import '../theme/app_typography.dart';
import '../utils/app_logger.dart';
import '../utils/reading_history.dart';
import '../utils/screen_layout.dart';
import '../utils/time_format.dart';
import '../utils/toast.dart';
import '../widgets/back_to_top_button.dart';
import '../widgets/comic_card_skeleton.dart';
import '../widgets/comic_hero_tags.dart';
import '../widgets/load_more_footer.dart';
import '../widgets/login_expired_dialog.dart';
import 'home_page.dart';

part 'bookshelf/bookshelf_grids.dart';
part 'bookshelf/bookshelf_toolbar.dart';
part 'bookshelf/bookshelf_widgets.dart';

class BookshelfPage extends ConsumerStatefulWidget {
  const BookshelfPage({super.key});

  @override
  ConsumerState<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends ConsumerState<BookshelfPage> {
  ApiClient get _api => ref.read(apiClientProvider);
  ComicBookshelfRepository get _comicRepo =>
      ref.read(comicBookshelfRepoProvider);
  UserManager get _user => ref.read(userManagerProvider);
  final _scrollController = ScrollController();
  Timer? _cacheTimeTimer;
  List<BookshelfItem> _items = [];
  bool _loading = true;
  int _offset = 0;
  int _total = 0;
  int _comicTotal = 0;
  DateTime? _comicCacheTime;
  bool _loadingMore = false;
  bool _refreshing = false;
  bool _showingLoginPrompt = false;
  late bool _lastIsLoggedIn = _user.isLoggedIn;
  late String? _lastToken = _user.token;
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
    _user.addListener(_onUserChanged);
    _startCacheTimeTimer();
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
    _cacheTimeTimer?.cancel();
    _scrollController.dispose();
    _user.removeListener(_onUserChanged);
    super.dispose();
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
          _total = 0;
          _comicTotal = 0;
          _offset = 0;
          _loading = false;
          _loadingMore = false;
          _refreshing = false;
          _ordering = nextOrdering;
        });
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
      setState(() {
        _items = comicCached.items;
        _total = comicCached.total;
        _comicTotal = comicCached.total;
        _offset = comicCached.items.length;
        _comicCacheTime = comicCached.cacheTime;
        _loading = false;
      });
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
      setState(() => _loading = true);
    }
    _offset = 0;
    try {
      final data = await _api.manga.getBookshelf(ordering: _ordering);
      if (!mounted) return;
      final now = DateTime.now();
      setState(() {
        _items = data.list;
        _total = data.total;
        _comicTotal = data.total;
        _offset = data.list.length;
        _comicCacheTime = now;
        _loading = false;
      });
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
      if (isInitial && mounted) setState(() => _loading = false);
      if (_isUnauthorized(e)) {
        await _handleUnauthorized();
      } else if (!silent && mounted) {
        showToast(
          context,
          AppLocalizations.of(context)!.refreshFailed,
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
      if (!mounted) return;
      setState(() {
        _items = data.list;
        _total = data.total;
        _offset = data.list.length;
      });
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
    setState(() => _loadingMore = true);
    try {
      final data = await _api.manga.getBookshelf(
        offset: _offset,
        ordering: _ordering,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(data.list);
        _offset = _items.length;
      });
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

    // 自动登录开启时，拦截器已尝试自动登录但失败了，静默提示即可
    if (_user.autoLogin) {
      await _user.logout();
      if (mounted) {
        showToast(
          context,
          AppLocalizations.of(context)!.autoLoginFailed,
          isError: true,
        );
      }
      return;
    }

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
              else if (_currentItemsEmpty)
                SliverFillRemaining(child: _buildEmptyState(context))
              else if (_showUpdateOnly && _items.every((e) => !e.hasUpdate))
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
                    horizontalPadding: hp,
                  ),
                ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
            ],
          ),
        ),
      ),
    );
  }
}
