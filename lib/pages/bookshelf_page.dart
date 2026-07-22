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
import '../theme/app_spacing.dart';
import '../utils/cover_brightness_filter.dart';
import '../utils/reading_history.dart';
import '../utils/time_format.dart';
import '../utils/toast.dart';
import '../widgets/comic_card_skeleton.dart';
import '../widgets/comic_hero_tags.dart';
import 'home_page.dart';

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
    } catch (e) {
      debugPrint('BookshelfPage load error: $e');
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
    } catch (e) {
      debugPrint('BookshelfPage refreshLoaded error: $e');
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
    } catch (e) {
      debugPrint('BookshelfPage loadMore error: $e');
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

  void _setOrdering(BuildContext context, String ordering) {
    Navigator.pop(context);
    setState(() => _ordering = ordering);
    _user.setBookshelfOrdering(ordering);
    _load(silent: true, force: true);
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
    final contentWidth = screenWidth.clamp(0.0, 900.0);
    final hp = (screenWidth - contentWidth) / 2 + 16;

    return Scaffold(
      floatingActionButton: _showBackToTop
          ? FloatingActionButton.small(
              heroTag: 'bookshelf_back_to_top',
              onPressed: _scrollToTop,
              tooltip: AppLocalizations.of(context)!.backToTop,
              child: const Icon(Icons.arrow_upward_rounded),
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
                pinned: false,
                floating: true,
                snap: true,
                primary: true,
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
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 130,
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
              const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
            ],
          ),
        ),
      ),
    );
  }

  double _toolbarContentHeight(BuildContext context) {
    // top/bottom padding + chip 行；若开启动画功能再加类型切换行。
    // FilterChip/ActionChip 在 M3 下实际约 40–48，预留一点防溢出。
    const filterRow = 4.0 + 48.0 + 8.0;
    if (!_animeFeatureEnabled) return filterRow;
    return filterRow + 48.0 + AppSpacing.sm;
  }

  Widget _buildToolbar(BuildContext context, double hp) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 4, hp, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_animeFeatureEnabled) ...[
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<_BookshelfType>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: _BookshelfType.comic,
                    icon: const Icon(Icons.menu_book),
                    label: Text(
                      _comicTotal > 0
                          ? l10n.comicWithCount(_comicTotal)
                          : l10n.comicLabel,
                    ),
                  ),
                  ButtonSegment(
                    value: _BookshelfType.anime,
                    icon: const Icon(Icons.movie_outlined),
                    label: Text(
                      _animeTotal > 0
                          ? l10n.animeWithCount(_animeTotal)
                          : l10n.animeLabel,
                    ),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (v) => _setType(v.first),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Row(
            children: [
              if (_type == _BookshelfType.comic)
                FilterChip(
                  label: Text(l10n.hasUpdate),
                  selected: _showUpdateOnly,
                  onSelected: _setShowUpdateOnly,
                ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                _cacheTimeLabel,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const Spacer(),
              ActionChip(
                avatar: const Icon(Icons.sort, size: 18),
                label: Text(
                  _orderingLabel(AppLocalizations.of(context)!, _ordering),
                ),
                onPressed: () => _showOrderingSheet(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showOrderingSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tt = Theme.of(context).textTheme;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(l10n.sortMethod, style: tt.titleMedium),
            ),
            _OrderingTile(
              icon: Icons.update,
              title: l10n.sortByUpdateTime,
              subtitle: l10n.sortByUpdateTimeDesc(_typeLabel(l10n)),
              selected: _ordering == ApiOrdering.datetimeUpdated,
              onTap: () => _setOrdering(context, ApiOrdering.datetimeUpdated),
            ),
            _OrderingTile(
              icon: Icons.bookmark_added,
              title: l10n.sortByFavoriteTime,
              subtitle: l10n.sortByFavoriteTimeDesc,
              selected: _ordering == ApiOrdering.datetimeModifier,
              onTap: () => _setOrdering(context, ApiOrdering.datetimeModifier),
            ),
            _OrderingTile(
              icon: Icons.history,
              title: l10n.sortByBrowseTime,
              subtitle: l10n.sortByBrowseTimeDesc,
              selected: _ordering == ApiOrdering.datetimeBrowse,
              onTap: () => _setOrdering(context, ApiOrdering.datetimeBrowse),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bookmark_border, size: 64, color: cs.onSurfaceVariant),
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.bookshelfEmpty,
            style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.goFindSomething(_typeLabel(l10n)),
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.tonalIcon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: Text(l10n.refreshButton),
          ),
        ],
      ),
    );
  }

  Widget _buildNoUpdates(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 48,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            AppLocalizations.of(context)!.noComicUpdates,
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildComicGrid(BuildContext context, double hp) {
    final filtered = _showUpdateOnly
        ? _items.where((e) => e.hasUpdate).toList()
        : _items;
    final skeletonCount = _loadingMore ? 6 : 0;
    final totalCount = filtered.length + skeletonCount;
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: hp),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate((_, i) {
          if (i >= filtered.length) {
            return const ComicCardSkeleton();
          }
          final item = filtered[i];
          final heroTagBase = ComicHeroTags.base(
            scope: _showUpdateOnly ? 'bookshelf-updates' : 'bookshelf',
            pathWord: item.comic.pathWord,
            index: i,
          );
          return Stack(
            children: [
              ComicCard(
                comic: item.comic,
                heroTagBase: heroTagBase,
                onTap: () => _openComicDetail(item, heroTagBase),
              ),
              if (item.hasUpdate) const _UpdateBadge(),
            ],
          );
        }, childCount: totalCount),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 130,
          childAspectRatio: 0.55,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
      ),
    );
  }

  Future<void> _openComicDetail(BookshelfItem item, String heroTagBase) async {
    final pathWord = item.comic.pathWord;
    final before = await ReadingHistory.latestForComic(pathWord);
    if (!mounted) return;

    await context.pushNamed(
      AppRoutes.comicDetail,
      pathParameters: {'pathWord': pathWord},
      extra: ComicDetailExtra(
        initialComic: item.comic,
        heroTagBase: heroTagBase,
        lastBrowseId: item.lastBrowseId,
        lastBrowseName: item.lastBrowseName,
      ),
    );
    if (!mounted) return;

    await _refreshLoaded();
    if (!mounted) return;
    await _applyLocalBrowseToComicItem(pathWord, before);
  }

  Future<void> _applyLocalBrowseToComicItem(
    String pathWord,
    ReadingRecord? before,
  ) async {
    final record = await ReadingHistory.latestForComic(pathWord);
    if (!mounted || record == null || record.chapterUuid.isEmpty) return;

    final changedDuringNavigation = _readingRecordChanged(before, record);
    var changed = false;
    final nextItems = _items.map((item) {
      if (item.comic.pathWord != pathWord) return item;
      final alreadyCurrent =
          item.lastBrowseId == record.chapterUuid &&
          item.lastBrowseName == record.chapterName;
      if (alreadyCurrent) return item;

      final localRecordClearsUpdate =
          item.comic.lastChapterId != null &&
          item.comic.lastChapterId == record.chapterUuid;
      if (!changedDuringNavigation && !localRecordClearsUpdate) return item;

      changed = true;
      return BookshelfItem(
        comic: item.comic,
        lastBrowseId: record.chapterUuid,
        lastBrowseName: record.chapterName,
      );
    }).toList();

    if (!changed || !mounted) return;
    setState(() => _items = nextItems);
    unawaited(
      _saveComicCache(
        nextItems,
        _comicTotal > 0 ? _comicTotal : _total,
        _comicCacheTime ?? DateTime.now(),
      ),
    );
  }

  bool _readingRecordChanged(ReadingRecord? before, ReadingRecord after) {
    if (before == null) return true;
    final beforeUpdatedAt = before.updatedAt;
    final afterUpdatedAt = after.updatedAt;
    if (beforeUpdatedAt != null && afterUpdatedAt != null) {
      return afterUpdatedAt.isAfter(beforeUpdatedAt);
    }
    return before.chapterUuid != after.chapterUuid ||
        before.chapterName != after.chapterName;
  }

  Widget _buildAnimeGrid(BuildContext context, double hp) {
    final skeletonCount = _loadingMore ? 6 : 0;
    final totalCount = _animeItems.length + skeletonCount;
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: hp),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate((_, i) {
          if (i >= _animeItems.length) {
            return const ComicCardSkeleton();
          }
          final item = _animeItems[i];
          return _AnimeBookshelfCard(
            anime: item.anime,
            onTap: () => context
                .pushNamed(
                  AppRoutes.animeDetail,
                  pathParameters: {'pathWord': item.anime.pathWord},
                  extra: AnimeDetailExtra(initialAnime: item.anime),
                )
                .then((_) => _refreshLoaded()),
          );
        }, childCount: totalCount),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 130,
          childAspectRatio: 0.55,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
      ),
    );
  }
}

class _UpdateBadge extends StatelessWidget {
  const _UpdateBadge();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: const BoxDecoration(
          color: Color(0xFFBA1A1A),
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(12),
            bottomLeft: Radius.circular(10),
          ),
        ),
        child: Text(
          AppLocalizations.of(context)!.updateBadge,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _AnimeBookshelfCard extends StatelessWidget {
  final Anime anime;
  final VoidCallback onTap;

  const _AnimeBookshelfCard({required this.anime, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final meta = anime.count > 0
        ? AppLocalizations.of(context)!.totalEpisodes(anime.count)
        : (anime.company?.name ?? anime.years ?? '');

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              margin: EdgeInsets.zero,
              child: CoverBrightnessFilter(
                child: CachedNetworkImage(
                  imageUrl: anime.cover,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  placeholder: (_, _) => _ImagePlaceholder(
                    icon: Icons.movie_outlined,
                    color: cs.surfaceContainerHighest,
                    iconColor: cs.onSurfaceVariant,
                  ),
                  errorWidget: (_, _, _) => _ImagePlaceholder(
                    icon: Icons.broken_image,
                    color: cs.surfaceContainerHighest,
                    iconColor: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            anime.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tt.bodySmall,
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.local_fire_department, size: 12, color: cs.primary),
              const SizedBox(width: 2),
              Text(
                ComicCard.formatPopular(
                  anime.popular,
                  AppLocalizations.of(context)!,
                ),
                style: tt.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color iconColor;

  const _ImagePlaceholder({
    required this.icon,
    required this.color,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: color,
      child: Center(child: Icon(icon, color: iconColor, size: 32)),
    );
  }
}

class _OrderingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _OrderingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: selected ? cs.primary : null),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: selected ? Icon(Icons.check, color: cs.primary) : null,
      selected: selected,
      onTap: onTap,
    );
  }
}
