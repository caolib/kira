import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../l10n/app_localizations.dart';
import '../models/anime.dart';
import '../models/api_ordering.dart';
import '../models/comic.dart' hide Theme;
import '../models/user_manager.dart';
import '../providers/app_providers.dart';
import '../providers/repository_providers.dart';
import '../repositories/bookshelf_repository.dart';
import '../routing/app_router.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../utils/app_logger.dart';
import '../utils/cover_brightness_filter.dart';
import '../utils/reading_history.dart';
import '../utils/screen_layout.dart';
import '../utils/time_format.dart';
import '../utils/toast.dart';
import '../widgets/comic_card_skeleton.dart';
import '../widgets/comic_hero_tags.dart';
import '../widgets/load_more_footer.dart';
import 'home_page.dart';

part 'bookshelf/bookshelf_grids.dart';
part 'bookshelf/bookshelf_toolbar.dart';
part 'bookshelf/bookshelf_widgets.dart';

enum _BookshelfType { comic, anime }

class BookshelfPage extends ConsumerStatefulWidget {
  const BookshelfPage({super.key});

  @override
  ConsumerState<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends ConsumerState<BookshelfPage> {
  ApiClient get _api => ref.read(apiClientProvider);
  ComicBookshelfRepository get _comicRepo =>
      ref.read(comicBookshelfRepoProvider);
  AnimeBookshelfRepository get _animeRepo =>
      ref.read(animeBookshelfRepoProvider);
  UserManager get _user => ref.read(userManagerProvider);
  final _scrollController = ScrollController();
  Timer? _cacheTimeTimer;
  List<BookshelfItem> _items = [];
  List<AnimeBookshelfItem> _animeItems = [];
  bool _loading = true;
  int _offset = 0;
  int _total = 0;
  int _comicTotal = 0;
  int _animeTotal = 0;
  DateTime? _comicCacheTime;
  DateTime? _animeCacheTime;
  bool _loadingMore = false;
  bool _refreshing = false;
  bool _showingLoginPrompt = false;
  late bool _lastIsLoggedIn = _user.isLoggedIn;
  late String? _lastToken = _user.token;
  late bool _lastAnimeFeatureEnabled = _user.animeFeatureEnabled;
  _BookshelfType _type = _BookshelfType.comic;
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
    final animeFeatureEnabled = _user.animeFeatureEnabled;
    final loginChanged = isLoggedIn != _lastIsLoggedIn || token != _lastToken;
    final animeFeatureChanged = animeFeatureEnabled != _lastAnimeFeatureEnabled;
    final nextOrdering = _user.bookshelfOrdering;
    final orderingChanged = _ordering != nextOrdering;

    _lastIsLoggedIn = isLoggedIn;
    _lastToken = token;
    _lastAnimeFeatureEnabled = animeFeatureEnabled;

    if (!isLoggedIn) {
      if (loginChanged) {
        setState(() {
          _items = [];
          _animeItems = [];
          _total = 0;
          _comicTotal = 0;
          _animeTotal = 0;
          _offset = 0;
          _loading = false;
          _loadingMore = false;
          _refreshing = false;
          _ordering = nextOrdering;
        });
      } else if (orderingChanged || animeFeatureChanged) {
        setState(() {
          _ordering = nextOrdering;
        });
      }
      return;
    }

    var switchedFromDisabledAnime = false;
    if (animeFeatureChanged &&
        !animeFeatureEnabled &&
        _type == _BookshelfType.anime) {
      switchedFromDisabledAnime = true;
      setState(() {
        _type = _BookshelfType.comic;
        _total = _comicTotal;
        _offset = _items.length;
        _loading = _items.isEmpty;
        _loadingMore = false;
        _ordering = nextOrdering;
      });
    } else if (orderingChanged || animeFeatureChanged) {
      setState(() {
        _ordering = nextOrdering;
      });
    }

    if (loginChanged) {
      _load(silent: true, force: true);
    } else if (switchedFromDisabledAnime && _items.isEmpty) {
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
    final animeCached = await _animeRepo.loadFromCache();
    if (animeCached != null && animeCached.items.isNotEmpty) {
      setState(() {
        _animeItems = animeCached.items;
        _total = animeCached.total;
        _animeTotal = animeCached.total;
        _offset = animeCached.items.length;
        _animeCacheTime = animeCached.cacheTime;
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

  Future<void> _saveAnimeCache(
    List<AnimeBookshelfItem> items,
    int total,
    DateTime cacheTime,
  ) async {
    await _animeRepo.saveToCache(
      AnimeBookshelfData(items: items, total: total, cacheTime: cacheTime),
    );
  }

  Future<void> _load({bool silent = false, bool force = false}) async {
    if (!force && !_currentItemsEmpty) {
      final cacheTime = _type == _BookshelfType.comic
          ? _comicCacheTime
          : _animeCacheTime;
      if (cacheTime != null &&
          DateTime.now().difference(cacheTime) < const Duration(minutes: 30)) {
        return;
      }
    }
    if (_refreshing && !force) return;
    final requestType = _type;
    _refreshing = true;
    final isInitial = _currentItemsEmpty;
    if (isInitial) {
      setState(() => _loading = true);
    }
    _offset = 0;
    try {
      if (requestType == _BookshelfType.comic) {
        final data = await _api.manga.getBookshelf(ordering: _ordering);
        if (!mounted || requestType != _type) return;
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
      } else {
        final data = await _api.anime.getAnimeBookshelf(ordering: _ordering);
        if (!mounted || requestType != _type) return;
        final now = DateTime.now();
        setState(() {
          _animeItems = data.list;
          _total = data.total;
          _animeTotal = data.total;
          _offset = data.list.length;
          _animeCacheTime = now;
          _loading = false;
        });
        unawaited(_saveAnimeCache(data.list, data.total, now));
      }
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
      if (requestType == _type) {
        _refreshing = false;
        if (mounted) {
          setState(() {});
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(0);
          }
        }
      }
    }
  }

  Future<void> _refreshLoaded() async {
    if (_refreshing) return;
    final requestType = _type;
    _refreshing = true;
    setState(() {});
    try {
      if (requestType == _BookshelfType.comic) {
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
        if (!mounted || requestType != _type) return;
        setState(() {
          _items = data.list;
          _total = data.total;
          _offset = data.list.length;
        });
      } else {
        final currentCount = _animeItems.length;
        if (currentCount == 0) {
          _refreshing = false;
          if (mounted) setState(() {});
          return;
        }
        final data = await _api.anime.getAnimeBookshelf(
          limit: currentCount,
          ordering: _ordering,
        );
        if (!mounted || requestType != _type) return;
        setState(() {
          _animeItems = data.list;
          _total = data.total;
          _offset = data.list.length;
        });
      }
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
      if (requestType == _type) {
        _refreshing = false;
        if (mounted) setState(() {});
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _refreshing || _offset >= _total) return;
    final requestType = _type;
    setState(() => _loadingMore = true);
    try {
      if (requestType == _BookshelfType.comic) {
        final data = await _api.manga.getBookshelf(
          offset: _offset,
          ordering: _ordering,
        );
        if (!mounted || requestType != _type) return;
        setState(() {
          _items.addAll(data.list);
          _offset = _items.length;
        });
      } else {
        final data = await _api.anime.getAnimeBookshelf(
          offset: _offset,
          ordering: _ordering,
        );
        if (!mounted || requestType != _type) return;
        setState(() {
          _animeItems.addAll(data.list);
          _offset = _animeItems.length;
        });
      }
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
      if (mounted && requestType == _type) {
        setState(() => _loadingMore = false);
      } else if (requestType == _type) {
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

    final shouldLogin = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(l10n.loginExpiredTitle),
          content: Text(l10n.loginExpiredBookshelfContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.laterButton),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.goLoginButton),
            ),
          ],
        );
      },
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

  bool get _currentItemsEmpty =>
      _type == _BookshelfType.comic ? _items.isEmpty : _animeItems.isEmpty;

  String _typeLabel(AppLocalizations l10n) =>
      _type == _BookshelfType.comic ? l10n.comicLabel : l10n.animeLabel;
  bool get _animeFeatureEnabled => _user.animeFeatureEnabled;

  String get _cacheTimeLabel {
    final cacheTime = _type == _BookshelfType.comic
        ? _comicCacheTime
        : _animeCacheTime;
    if (cacheTime == null) return '';
    return AppLocalizations.of(context)!.refreshedAt(
      TimeFormat.relative(cacheTime, AppLocalizations.of(context)!),
    );
  }

  void _setType(_BookshelfType type) {
    if (type == _BookshelfType.anime && !_animeFeatureEnabled) return;
    if (type == _type) return;
    final cacheTime = type == _BookshelfType.comic
        ? _comicCacheTime
        : _animeCacheTime;
    final hasValidCache =
        cacheTime != null &&
        DateTime.now().difference(cacheTime) < const Duration(minutes: 30);
    final items = type == _BookshelfType.comic ? _items : _animeItems;
    final itemsEmpty = type == _BookshelfType.comic
        ? _items.isEmpty
        : _animeItems.isEmpty;
    setState(() {
      _type = type;
      _total = type == _BookshelfType.comic ? _comicTotal : _animeTotal;
      _offset = items.length;
      _loading = !hasValidCache && itemsEmpty;
      _loadingMore = false;
    });
    if (!hasValidCache || itemsEmpty) {
      _load(silent: true, force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final hp = ScreenLayout.horizontalPadding(screenWidth);
    final cardExtent = ScreenLayout.cardExtent(screenWidth);

    return Scaffold(
      // 右下角悬浮回到顶部按钮：方形 FilledButton，与搜索页工具条同款
      // （primaryContainer 底 + 零内边距固定 48px，保证正方形且图标居中）。
      floatingActionButton: _showBackToTop
          ? SizedBox.square(
              dimension: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                  foregroundColor: Theme.of(
                    context,
                  ).colorScheme.onPrimaryContainer,
                  elevation: 6,
                  shadowColor: AppShadows.floatingTint(0.22),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size.square(48),
                  maximumSize: const Size.square(48),
                  fixedSize: const Size.square(48),
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.smR),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: _scrollToTop,
                child: const Icon(Icons.arrow_upward_rounded),
              ),
            )
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
                scrolledUnderElevation: 0,
                backgroundColor: Theme.of(context).colorScheme.surface,
                surfaceTintColor: Colors.transparent,
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
                      childCount: _type == _BookshelfType.comic ? 12 : 30,
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
              else if (_type == _BookshelfType.comic &&
                  _showUpdateOnly &&
                  _items.every((e) => !e.hasUpdate))
                SliverFillRemaining(child: _buildNoUpdates(context))
              else if (_type == _BookshelfType.comic)
                _buildComicGrid(context, hp)
              else
                _buildAnimeGrid(context, hp),
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
