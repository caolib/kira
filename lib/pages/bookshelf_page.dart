import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';
import '../models/anime.dart';
import '../models/comic.dart' hide Theme;
import '../models/user_manager.dart';
import '../utils/cover_brightness_filter.dart';
import '../utils/comic_hero_tags.dart';
import '../utils/comic_card_skeleton.dart';
import '../utils/data_cache.dart';
import '../utils/reading_history.dart';
import '../utils/time_format.dart';
import '../utils/toast.dart';
import 'anime_detail_page.dart';
import 'comic_detail_page.dart';
import 'home_page.dart';
import 'profile_page.dart';

enum _BookshelfType { comic, anime }

class BookshelfPage extends StatefulWidget {
  const BookshelfPage({super.key});

  @override
  State<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends State<BookshelfPage> {
  final _api = ApiClient();
  final _user = UserManager();
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

  static const _cacheTtl = Duration(minutes: 30);
  static const _comicCacheKey = 'bookshelf_comic';
  static const _animeCacheKey = 'bookshelf_anime';
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
    final cache = DataCache();
    final comicRaw = await cache.get(_comicCacheKey);
    if (comicRaw is Map<String, dynamic>) {
      final items =
          (comicRaw['items'] as List?)
              ?.map((e) => BookshelfItem.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          [];
      final total = comicRaw['total'] as int? ?? 0;
      final cacheTimeMs = comicRaw['cache_time'] as int?;
      final cacheTime = cacheTimeMs != null
          ? DateTime.fromMillisecondsSinceEpoch(cacheTimeMs)
          : null;
      if (items.isNotEmpty &&
          cacheTime != null &&
          DateTime.now().difference(cacheTime) < _cacheTtl) {
        setState(() {
          _items = items;
          _total = total;
          _comicTotal = total;
          _offset = items.length;
          _comicCacheTime = cacheTime;
          _loading = false;
        });
      }
    }
    final animeRaw = await cache.get(_animeCacheKey);
    if (animeRaw is Map<String, dynamic>) {
      final items =
          (animeRaw['items'] as List?)
              ?.map(
                (e) =>
                    AnimeBookshelfItem.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList() ??
          [];
      final total = animeRaw['total'] as int? ?? 0;
      final cacheTimeMs = animeRaw['cache_time'] as int?;
      final cacheTime = cacheTimeMs != null
          ? DateTime.fromMillisecondsSinceEpoch(cacheTimeMs)
          : null;
      if (items.isNotEmpty &&
          cacheTime != null &&
          DateTime.now().difference(cacheTime) < _cacheTtl) {
        setState(() {
          _animeItems = items;
          _total = total;
          _animeTotal = total;
          _offset = items.length;
          _animeCacheTime = cacheTime;
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveComicCache(
    List<BookshelfItem> items,
    int total,
    DateTime cacheTime,
  ) async {
    final cache = DataCache();
    await cache.put(_comicCacheKey, {
      'items': items.map((e) => e.toJson()).toList(),
      'total': total,
      'cache_time': cacheTime.millisecondsSinceEpoch,
    }, ttl: _cacheTtl);
  }

  Future<void> _saveAnimeCache(
    List<AnimeBookshelfItem> items,
    int total,
    DateTime cacheTime,
  ) async {
    final cache = DataCache();
    await cache.put(_animeCacheKey, {
      'items': items.map((e) => e.toJson()).toList(),
      'total': total,
      'cache_time': cacheTime.millisecondsSinceEpoch,
    }, ttl: _cacheTtl);
  }

  Future<void> _load({bool silent = false, bool force = false}) async {
    if (!force && !_currentItemsEmpty) {
      final cacheTime = _type == _BookshelfType.comic
          ? _comicCacheTime
          : _animeCacheTime;
      if (cacheTime != null &&
          DateTime.now().difference(cacheTime) < _cacheTtl) {
        return;
      }
    }
    if (_refreshing && !force) return;
    final requestType = _type;
    _refreshing = true;
    final isInitial = _currentItemsEmpty;
    if (isInitial) {
      setState(() => _loading = true);
    } else {
      setState(() {}); // 触发 UI 显示刷新指示器
    }
    _offset = 0;
    try {
      if (requestType == _BookshelfType.comic) {
        final data = await _api.getBookshelf(ordering: _ordering);
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
        _saveComicCache(data.list, data.total, now);
      } else {
        final data = await _api.getAnimeBookshelf(ordering: _ordering);
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
        _saveAnimeCache(data.list, data.total, now);
      }
      if (!silent && mounted) {
        showToast(context, '刷新成功');
      }
    } catch (e) {
      debugPrint('BookshelfPage load error: $e');
      if (isInitial && mounted) setState(() => _loading = false);
      if (_isUnauthorized(e)) {
        await _handleUnauthorized();
      } else if (!silent && mounted) {
        showToast(context, '刷新失败', isError: true);
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
        final data = await _api.getBookshelf(
          limit: currentCount,
          offset: 0,
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
        final data = await _api.getAnimeBookshelf(
          limit: currentCount,
          offset: 0,
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
        final data = await _api.getBookshelf(
          offset: _offset,
          ordering: _ordering,
        );
        if (!mounted || requestType != _type) return;
        setState(() {
          _items.addAll(data.list);
          _offset = _items.length;
        });
      } else {
        final data = await _api.getAnimeBookshelf(
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
        showToast(context, '自动登录失败，请手动重新登录', isError: true);
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
      builder: (ctx) => AlertDialog(
        title: const Text('登录已过期'),
        content: const Text('书架需要登录后才能继续使用，是否现在重新登录？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('稍后再说'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('去登录'),
          ),
        ],
      ),
    );

    if (shouldLogin == true && mounted) {
      final loggedIn = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      if (loggedIn == true && mounted) {
        _load(silent: true);
      }
    } else if (mounted) {
      showToast(context, '登录后可继续查看书架', isError: true);
    }

    _showingLoginPrompt = false;
  }

  static String _orderingLabel(String ordering) {
    switch (ordering) {
      case '-datetime_updated':
        return '按更新';
      case '-datetime_modifier':
        return '按收藏';
      case '-datetime_browse':
        return '按阅读';
      default:
        return '排序';
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

  String get _typeLabel => _type == _BookshelfType.comic ? '漫画' : '动漫';
  bool get _animeFeatureEnabled => _user.animeFeatureEnabled;

  String get _cacheTimeLabel {
    final cacheTime = _type == _BookshelfType.comic
        ? _comicCacheTime
        : _animeCacheTime;
    if (cacheTime == null) return '';
    return '刷新于 ${TimeFormat.relative(cacheTime)}';
  }

  void _setType(_BookshelfType type) {
    if (type == _BookshelfType.anime && !_animeFeatureEnabled) return;
    if (type == _type) return;
    final cacheTime = type == _BookshelfType.comic
        ? _comicCacheTime
        : _animeCacheTime;
    final hasValidCache =
        cacheTime != null && DateTime.now().difference(cacheTime) < _cacheTtl;
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
              tooltip: '回到顶部',
              child: const Icon(Icons.arrow_upward_rounded),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () => _load(force: true),
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
              SliverToBoxAdapter(
                child: SizedBox(
                  height: MediaQuery.of(context).padding.top + 12,
                ),
              ),
              if (_refreshing)
                const SliverToBoxAdapter(
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              SliverToBoxAdapter(child: _buildToolbar(context, hp)),
              if (_loading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
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

  Widget _buildToolbar(BuildContext context, double hp) {
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
                    label: Text(_comicTotal > 0 ? '漫画（$_comicTotal）' : '漫画'),
                  ),
                  ButtonSegment(
                    value: _BookshelfType.anime,
                    icon: const Icon(Icons.movie_outlined),
                    label: Text(_animeTotal > 0 ? '动漫（$_animeTotal）' : '动漫'),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (v) => _setType(v.first),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              if (_type == _BookshelfType.comic)
                FilterChip(
                  label: const Text('有更新'),
                  selected: _showUpdateOnly,
                  onSelected: _setShowUpdateOnly,
                ),
              const SizedBox(width: 8),
              Text(
                _cacheTimeLabel,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const Spacer(),
              ActionChip(
                avatar: const Icon(Icons.sort, size: 18),
                label: Text(_orderingLabel(_ordering)),
                onPressed: () => _showOrderingSheet(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showOrderingSheet(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('排序方式', style: tt.titleMedium),
            ),
            _OrderingTile(
              icon: Icons.update,
              title: '作品更新时间',
              subtitle: '按$_typeLabel最新章节的更新时间排序',
              selected: _ordering == '-datetime_updated',
              onTap: () => _setOrdering(context, '-datetime_updated'),
            ),
            _OrderingTile(
              icon: Icons.bookmark_added,
              title: '收藏时间',
              subtitle: '按加入书架的时间排序',
              selected: _ordering == '-datetime_modifier',
              onTap: () => _setOrdering(context, '-datetime_modifier'),
            ),
            _OrderingTile(
              icon: Icons.history,
              title: '浏览时间',
              subtitle: '按最近浏览的时间排序',
              selected: _ordering == '-datetime_browse',
              onTap: () => _setOrdering(context, '-datetime_browse'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bookmark_border, size: 64, color: cs.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            '书架空空如也',
            style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            '去找点好看的$_typeLabel吧',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('刷新'),
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
          const SizedBox(height: 12),
          Text(
            '没有漫画更新',
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

    await Navigator.push(
      context,
      ComicDetailPage.route(
        pathWord: pathWord,
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
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AnimeDetailPage(
                  pathWord: item.anime.pathWord,
                  initialAnime: item.anime,
                ),
              ),
            ).then((_) => _refreshLoaded()),
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
        child: const Text(
          '更新',
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
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
        ? '共 ${anime.count} 集'
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
                ComicCard.formatPopular(anime.popular),
                style: tt.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontSize: 10,
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
