import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:go_router/go_router.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';

import '../api/api_client.dart';
import '../l10n/app_localizations.dart';
import '../models/anime.dart';
import '../models/api_ordering.dart';
import '../models/comic.dart' as m;
import '../models/comic.dart' hide Theme;
import '../models/user_manager.dart';
import '../repositories/search_init_repository.dart';
import '../routing/app_router.dart';
import '../theme/app_spacing.dart';
import '../utils/app_logger.dart';
import '../utils/cover_brightness_filter.dart';
import '../widgets/comic_card_skeleton.dart';
import '../widgets/comic_hero_tags.dart';
import 'home_page.dart' show ComicCard;

enum _SearchMode { comic, anime }

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const _tagSpacing = 8.0;
  bool _refreshing = false;

  final _api = ApiClient();
  final _searchInitRepo = SearchInitRepository();
  final _user = UserManager();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _scrollController = ScrollController();

  List<String> _keywords = [];
  List<m.Theme> _tags = [];
  List<Comic> _comics = [];
  List<Anime> _animes = [];

  _SearchMode _mode = _SearchMode.comic;
  String? _selectedTag;
  String _ordering = ApiOrdering.popular;
  bool _loadingMore = false;
  bool _searching = false;
  bool _hasSearchText = false;
  bool _showBackToTop = false;
  bool _headerVisible = true;
  int _offset = 0;
  int _total = 0;
  String? _searchQuery;

  bool get _animeFeatureEnabled => _user.animeFeatureEnabled;
  bool get _isAnimeMode => _animeFeatureEnabled && _mode == _SearchMode.anime;
  String _modeLabel(AppLocalizations l10n) =>
      _isAnimeMode ? l10n.animeLabel : l10n.comicLabel;
  bool get _hasResults => _comics.isNotEmpty || _animes.isNotEmpty;
  bool get _canClearSearch => _hasSearchText || _searchQuery != null;

  @override
  void initState() {
    super.initState();
    _user.addListener(_onUserChanged);
    _searchController.addListener(_onSearchTextChanged);
    _searchFocus.addListener(_onSearchFocusChanged);
    _loadFromCache();
    _loadInit();
  }

  @override
  void dispose() {
    _user.removeListener(_onUserChanged);
    _searchController.removeListener(_onSearchTextChanged);
    _searchController.dispose();
    _searchFocus.removeListener(_onSearchFocusChanged);
    _searchFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _scrollToTop() async {
    // 回到顶部时把搜索框一起带回来，不然滚动停下后头部还是收着的。
    _setHeaderVisible(true);
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _setHeaderVisible(bool visible) {
    if (!mounted || visible == _headerVisible) return;
    setState(() => _headerVisible = visible);
  }

  /// 输入框拿到焦点时确保它露在外面（例如键盘弹出引起的布局变化）。
  void _onSearchFocusChanged() {
    if (_searchFocus.hasFocus) _setHeaderVisible(true);
  }

  /// 只在「有内容 / 没内容」翻转时重建，避免每次按键都刷新整页。
  void _onSearchTextChanged() {
    final hasText = _searchController.text.isNotEmpty;
    if (!mounted || hasText == _hasSearchText) return;
    setState(() => _hasSearchText = hasText);
  }

  void _onUserChanged() {
    if (!mounted) return;
    if (!_animeFeatureEnabled && _mode == _SearchMode.anime) {
      _setMode(_SearchMode.comic);
      return;
    }
    setState(() {});
  }

  Future<void> _loadFromCache() async {
    final cached = await _searchInitRepo.loadFromCache();
    if (!mounted || cached == null) return;
    setState(() {
      _keywords = cached.keywords;
      _tags = cached.tags;
    });
  }

  Future<void> _loadInit({bool forceRefresh = false}) async {
    setState(() => _refreshing = true);
    try {
      final data = await _searchInitRepo.load();
      if (!mounted) return;
      setState(() {
        _keywords = data.keywords;
        _tags = data.tags;
        _refreshing = false;
      });
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'search_page.load_init',
        ),
      );
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _doSearch(String query) async {
    final keyword = query.trim();
    if (keyword.isEmpty) return;
    final mode = _animeFeatureEnabled ? _mode : _SearchMode.comic;
    setState(() {
      _mode = mode;
      _searching = true;
      _searchQuery = keyword;
      _comics = [];
      _animes = [];
      _offset = 0;
      _total = 0;
      _selectedTag = null;
    });

    try {
      if (mode == _SearchMode.anime) {
        final result = await _api.anime.searchAnimes(keyword);
        if (!mounted || _mode != mode || _searchQuery != keyword) return;
        setState(() {
          _animes = result.list;
          _total = result.total;
          _offset = result.list.length;
          _searching = false;
        });
      } else {
        final result = await _api.manga.searchComics(keyword);
        if (!mounted || _mode != mode || _searchQuery != keyword) return;
        setState(() {
          _comics = result.list;
          _total = result.total;
          _offset = result.list.length;
          _searching = false;
        });
      }
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'search_page.search',
        ),
      );
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _loadComics({bool reset = true}) async {
    if (reset) {
      setState(() {
        _mode = _SearchMode.comic;
        _offset = 0;
        _total = 0;
        _comics = [];
        _animes = [];
        _searchQuery = null;
        if (_selectedTag != null) _searching = true;
      });
    }
    try {
      final result = await _api.manga.getComicList(
        ordering: _ordering,
        offset: _offset,
        theme: _selectedTag,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _comics = result.list;
        } else {
          _comics.addAll(result.list);
        }
        _total = result.total;
        _offset = _comics.length;
        _searching = false;
      });
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'search_page.load_comics',
        ),
      );
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _offset >= _total) return;
    setState(() => _loadingMore = true);
    try {
      if (_searchQuery != null) {
        if (_isAnimeMode) {
          final result = await _api.anime.searchAnimes(
            _searchQuery!,
            offset: _offset,
          );
          if (!mounted) return;
          setState(() {
            _animes.addAll(result.list);
            _offset = _animes.length;
          });
        } else {
          final result = await _api.manga.searchComics(
            _searchQuery!,
            offset: _offset,
          );
          if (!mounted) return;
          setState(() {
            _comics.addAll(result.list);
            _offset = _comics.length;
          });
        }
      } else if (!_isAnimeMode) {
        await _loadComics(reset: false);
      }
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'search_page.load_more',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
      } else {
        _loadingMore = false;
      }
    }
  }

  void _setMode(_SearchMode mode) {
    if (mode == _SearchMode.anime && !_animeFeatureEnabled) return;
    if (_mode == mode) return;
    final keyword = _searchController.text.trim();
    setState(() {
      _mode = mode;
      _selectedTag = null;
      _comics = [];
      _animes = [];
      _offset = 0;
      _total = 0;
      _searchQuery = keyword.isEmpty ? null : keyword;
    });
    if (keyword.isNotEmpty) {
      _doSearch(keyword);
    }
  }

  void _selectTag(String? tagPathWord) {
    _searchController.clear();
    final isToggleOff = tagPathWord != null && _selectedTag == tagPathWord;
    final next = isToggleOff ? null : tagPathWord;
    setState(() {
      _mode = _SearchMode.comic;
      _selectedTag = next;
      _searchQuery = null;
      _searching = next != null;
      _offset = 0;
      _total = 0;
      _comics = [];
      _animes = [];
    });
    if (next != null) {
      _loadComics();
    }
  }

  void _clearSearch() {
    _searchController.clear();
    // 只是清空输入框时不动列表（可能正在看标签结果）；
    // 只有确实搜索过才把结果重置回推荐/标签视图。
    if (_searchQuery == null) return;
    setState(() {
      _searchQuery = null;
      _comics = [];
      _animes = [];
      _offset = 0;
      _total = 0;
    });
  }

  void _onKeywordTap(String keyword) {
    _searchController.text = keyword;
    _doSearch(keyword);
  }

  void _openAnime(Anime anime) {
    if (!_animeFeatureEnabled) return;
    if (anime.pathWord.isEmpty) return;
    context.pushNamed(
      AppRoutes.animeDetail,
      pathParameters: {'pathWord': anime.pathWord},
      extra: AnimeDetailExtra(initialAnime: anime),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth.clamp(0.0, 900.0);
    final hp = (screenWidth - contentWidth) / 2 + 16;

    final topInset = MediaQuery.of(context).padding.top;
    final headerHeight = topInset + _headerContentHeight();

    return Scaffold(
      floatingActionButton: _showBackToTop
          ? FloatingActionButton.small(
              heroTag: 'search_back_to_top',
              onPressed: _scrollToTop,
              tooltip: l10n.backToTop,
              child: const Icon(Icons.arrow_upward_rounded),
            )
          : null,
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () => _loadInit(forceRefresh: true),
            edgeOffset: headerHeight,
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.axis == Axis.vertical) {
                  final shouldShow = n.metrics.pixels > 400;
                  if (shouldShow != _showBackToTop) {
                    setState(() => _showBackToTop = shouldShow);
                  }
                  _updateHeaderVisibility(n);
                  if (_hasResults &&
                      n.metrics.pixels > n.metrics.maxScrollExtent - 300) {
                    _loadMore();
                  }
                }
                return false;
              },
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  // 给悬浮搜索框留出位置（搜索框本身不在滚动视图里）。
                  SliverToBoxAdapter(child: SizedBox(height: headerHeight)),
                  if (_refreshing &&
                      _searchQuery == null &&
                      _selectedTag == null &&
                      !_searching &&
                      _keywords.isEmpty &&
                      _tags.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: ExpressiveLoadingIndicator()),
                    ),
                  if (_searching && _selectedTag == null)
                    SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: hp),
                      sliver: SliverGrid(
                        delegate: SliverChildBuilderDelegate(
                          (_, _) => const ComicCardSkeleton(),
                          childCount: 20,
                        ),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 130,
                              childAspectRatio: 0.55,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                            ),
                      ),
                    ),
                  if (_keywords.isNotEmpty &&
                      _selectedTag == null &&
                      !_hasResults &&
                      !_searching)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(hp, 8, hp, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.local_fire_department,
                                  size: 20,
                                  color: cs.primary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  l10n.hotSearchTitle,
                                  style: tt.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _keywords
                                  .map(
                                    (k) => ActionChip(
                                      label: Text(k),
                                      onPressed: () => _onKeywordTap(k),
                                      avatar: Icon(
                                        Icons.trending_up,
                                        size: 16,
                                        color: cs.primary,
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                            const SizedBox(height: AppSpacing.xl),
                          ],
                        ),
                      ),
                    ),
                  if (!_isAnimeMode &&
                      _tags.isNotEmpty &&
                      _searchQuery == null &&
                      (_selectedTag != null || !_searching))
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(hp, 0, hp, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.category,
                                  size: 20,
                                  color: cs.primary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  l10n.allTagsTitle,
                                  style: tt.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Text(
                                  l10n.tagCount(_tags.length),
                                  style: tt.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Wrap(
                              spacing: _tagSpacing,
                              runSpacing: _tagSpacing,
                              children: [
                                for (final t in _tags)
                                  if (_selectedTag == null ||
                                      _selectedTag == t.pathWord)
                                    FilterChip(
                                      label: Text(
                                        t.count > 0
                                            ? '${t.name} ${t.count}'
                                            : t.name,
                                      ),
                                      selected: _selectedTag == t.pathWord,
                                      showCheckmark: false,
                                      onSelected: (_) => _selectTag(t.pathWord),
                                    ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.md),
                          ],
                        ),
                      ),
                    ),
                  if (!_isAnimeMode && _selectedTag != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(hp, 0, hp, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SegmentedButton<String>(
                              segments: [
                                ButtonSegment(
                                  value: ApiOrdering.popular,
                                  label: Text(l10n.popularOrder),
                                  icon: const Icon(Icons.whatshot),
                                ),
                                ButtonSegment(
                                  value: ApiOrdering.datetimeUpdated,
                                  label: Text(l10n.updateOrder),
                                  icon: const Icon(Icons.schedule),
                                ),
                              ],
                              selected: {_ordering},
                              onSelectionChanged: (v) {
                                setState(() => _ordering = v.first);
                                _loadComics();
                              },
                            ),
                            const SizedBox(height: AppSpacing.md),
                          ],
                        ),
                      ),
                    ),
                  if (_searching && _selectedTag != null)
                    SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: hp),
                      sliver: SliverGrid(
                        delegate: SliverChildBuilderDelegate(
                          (_, _) => const ComicCardSkeleton(),
                          childCount: 21,
                        ),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 130,
                              childAspectRatio: 0.55,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                            ),
                      ),
                    ),
                  if (_searchQuery != null && _hasResults)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(hp, 4, hp, 12),
                        child: Text(
                          l10n.searchResultSummary(
                            _searchQuery!,
                            _total,
                            _modeLabel(l10n),
                          ),
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  if (!_isAnimeMode && _comics.isNotEmpty)
                    _ComicGrid(
                      comics: _comics,
                      hp: hp,
                      loadingMore: _loadingMore,
                      onOpen: (comic, heroTagBase) => context.pushNamed(
                        AppRoutes.comicDetail,
                        pathParameters: {'pathWord': comic.pathWord},
                        extra: ComicDetailExtra(
                          initialComic: comic,
                          heroTagBase: heroTagBase,
                        ),
                      ),
                    ),
                  if (_isAnimeMode && _animes.isNotEmpty)
                    _AnimeGrid(
                      animes: _animes,
                      hp: hp,
                      loadingMore: _loadingMore,
                      onOpen: _openAnime,
                    ),
                  const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
                ],
              ),
            ),
          ),
          // 搜索框固定在顶部、不参与滚动。放在滚动视图里（floating SliverAppBar）时，
          // 输入框一聚焦就会触发框架的「把焦点控件滚进可视区」，
          // 头部被一起滚走后失焦，键盘随之收起。
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: AnimatedSlide(
              offset: _headerVisible ? Offset.zero : const Offset(0, -1),
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: Material(
                color: cs.surface,
                child: Padding(
                  padding: EdgeInsets.only(top: topInset),
                  child: _buildSearchHeader(context, hp),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 下滑浏览时把搜索框收起，上滑或回到顶部再放出来；输入过程中不收。
  void _updateHeaderVisibility(ScrollNotification n) {
    if (n is! UserScrollNotification) return;
    if (n.metrics.pixels <= n.metrics.minScrollExtent) {
      _setHeaderVisible(true);
      return;
    }
    switch (n.direction) {
      case ScrollDirection.forward:
        _setHeaderVisible(true);
      case ScrollDirection.reverse:
        _setHeaderVisible(_searchFocus.hasFocus);
      case ScrollDirection.idle:
        break;
    }
  }

  /// 悬浮头占位高度：上下内边距 + SearchBar（M3 默认 56）+ 可选的类型切换行。
  double _headerContentHeight() {
    const searchRow = 12.0 + 56.0 + AppSpacing.sm;
    if (!_animeFeatureEnabled) return searchRow;
    return searchRow + 48.0 + AppSpacing.sm;
  }

  Widget _buildSearchHeader(BuildContext context, double hp) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 12, hp, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SearchBar(
            controller: _searchController,
            focusNode: _searchFocus,
            hintText: l10n.searchHint(_modeLabel(l10n)),
            leading: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.search),
            ),
            trailing: _canClearSearch
                ? [
                    IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: l10n.searchClearTooltip,
                      onPressed: _clearSearch,
                    ),
                  ]
                : null,
            onSubmitted: _doSearch,
          ),
          if (_animeFeatureEnabled) ...[
            const SizedBox(height: AppSpacing.sm),
            SegmentedButton<_SearchMode>(
              segments: [
                ButtonSegment(
                  value: _SearchMode.comic,
                  label: Text(l10n.comicLabel),
                  icon: const Icon(Icons.menu_book_outlined),
                ),
                ButtonSegment(
                  value: _SearchMode.anime,
                  label: Text(l10n.animeLabel),
                  icon: const Icon(Icons.movie_outlined),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (v) => _setMode(v.first),
            ),
          ],
        ],
      ),
    );
  }
}

class _ComicGrid extends StatelessWidget {
  final List<Comic> comics;
  final double hp;
  final bool loadingMore;
  final void Function(Comic comic, String heroTagBase) onOpen;

  const _ComicGrid({
    required this.comics,
    required this.hp,
    required this.loadingMore,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: hp),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate((_, i) {
          if (i >= comics.length) {
            return const ComicCardSkeleton();
          }
          final comic = comics[i];
          final heroTagBase = ComicHeroTags.base(
            scope: 'search',
            pathWord: comic.pathWord,
            index: i,
          );
          return ComicCard(
            comic: comic,
            heroTagBase: heroTagBase,
            onTap: () => onOpen(comic, heroTagBase),
          );
        }, childCount: comics.length + (loadingMore ? 6 : 0)),
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

class _AnimeGrid extends StatelessWidget {
  final List<Anime> animes;
  final double hp;
  final bool loadingMore;
  final ValueChanged<Anime> onOpen;

  const _AnimeGrid({
    required this.animes,
    required this.hp,
    required this.loadingMore,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: hp),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate((_, i) {
          if (i >= animes.length) {
            return const ComicCardSkeleton();
          }
          final anime = animes[i];
          return _AnimeGridItem(anime: anime, onTap: () => onOpen(anime));
        }, childCount: animes.length + (loadingMore ? 6 : 0)),
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

class _AnimeGridItem extends StatelessWidget {
  final Anime anime;
  final VoidCallback onTap;

  const _AnimeGridItem({required this.anime, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

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
                  placeholder: (_, _) => Container(
                    color: cs.surfaceContainerHighest,
                    child: Center(
                      child: Icon(
                        Icons.movie_outlined,
                        color: cs.onSurfaceVariant,
                        size: 32,
                      ),
                    ),
                  ),
                  errorWidget: (_, _, _) => Container(
                    color: cs.surfaceContainerHighest,
                    child: Center(
                      child: Icon(
                        Icons.broken_image,
                        color: cs.onSurfaceVariant,
                        size: 32,
                      ),
                    ),
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
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
