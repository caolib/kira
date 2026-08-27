import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:go_router/go_router.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../l10n/app_localizations.dart';
import '../models/anime.dart';
import '../models/api_ordering.dart';
import '../models/comic.dart' as m;
import '../models/comic.dart' hide Theme;
import '../models/user_manager.dart';
import '../repositories/search_init_repository.dart';
import '../routing/app_router.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
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
  // 折叠状态持久化 key（仅本地记忆，无导入导出）。
  static const _kHotSearchExpanded = 'search_hot_search_expanded';
  static const _kAllTagsExpanded = 'search_all_tags_expanded';
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
  bool _headerVisible = true;
  // 列表是否可向上滚回顶部（内容超出视口且当前不在顶部）。回到顶部按钮据此显隐。
  bool _canScrollUp = false;
  // 热门搜索 / 全部标签 两个区块的展开状态（持久化记忆，无需导入导出）。
  bool _hotSearchExpanded = true;
  bool _allTagsExpanded = true;
  int _offset = 0;
  int _total = 0;
  String? _searchQuery;

  bool get _animeFeatureEnabled => _user.animeFeatureEnabled;
  bool get _isAnimeMode => _animeFeatureEnabled && _mode == _SearchMode.anime;
  String _modeLabel(AppLocalizations l10n) =>
      _isAnimeMode ? l10n.animeLabel : l10n.comicLabel;
  bool get _hasResults => _comics.isNotEmpty || _animes.isNotEmpty;
  bool get _canClearSearch => _hasSearchText || _searchQuery != null;

  /// 当前选中 tag 的显示名（从初始化拿到的 tag 列表里按 pathWord 反查）。
  String get _selectedTagName {
    final tag = _selectedTag;
    if (tag == null) return '';
    final match = _tags.where((t) => t.pathWord == tag).firstOrNull;
    return match?.name ?? '';
  }

  /// 切换排序并重新加载，同时滚回顶部，方便用户从头看新排序的结果。
  void _setOrdering(String value) {
    if (_ordering == value) return;
    setState(() => _ordering = value);
    _loadComics();
    _scrollToTop();
  }

  /// 在热度 / 更新之间来回切换（右下角单按钮）。
  void _toggleOrdering() {
    _setOrdering(
      _ordering == ApiOrdering.popular
          ? ApiOrdering.datetimeUpdated
          : ApiOrdering.popular,
    );
  }

  @override
  void initState() {
    super.initState();
    _user.addListener(_onUserChanged);
    _searchController.addListener(_onSearchTextChanged);
    _searchFocus.addListener(_onSearchFocusChanged);
    _loadFromCache();
    _loadInit();
    _restoreCollapseStates();
  }

  /// 读取两个区块的折叠状态（仅本地记忆，无需导入导出）。
  Future<void> _restoreCollapseStates() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _hotSearchExpanded = prefs.getBool(_kHotSearchExpanded) ?? true;
      _allTagsExpanded = prefs.getBool(_kAllTagsExpanded) ?? true;
    });
  }

  /// 切换某区块折叠状态并落盘（[isHotSearch] 区分热门搜索 / 全部标签）。
  void _toggleCollapse({required bool isHotSearch}) {
    final next = !(isHotSearch ? _hotSearchExpanded : _allTagsExpanded);
    setState(() {
      if (isHotSearch) {
        _hotSearchExpanded = next;
      } else {
        _allTagsExpanded = next;
      }
    });
    final prefs = SharedPreferences.getInstance();
    prefs.then(
      (p) => p.setBool(
        isHotSearch ? _kHotSearchExpanded : _kAllTagsExpanded,
        next,
      ),
    );
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
      // 搜索结果太少不可滚动时，确保搜索框/悬浮按钮不会被卡在收起态。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final c = _scrollController;
        if (!c.hasClients || c.position.pixels <= c.position.minScrollExtent) {
          _setHeaderVisible(true);
        }
      });
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
      // 切到新结果列表后，若当前停在顶部（结果太少不可滚动的情况），
      // 主动把搜索框与悬浮按钮带回来，否则它们会卡在收起态回不来。
      if (reset) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final c = _scrollController;
          if (!c.hasClients ||
              c.position.pixels <= c.position.minScrollExtent) {
            _setHeaderVisible(true);
          }
        });
      }
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
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () => _loadInit(forceRefresh: true),
            edgeOffset: headerHeight,
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.axis == Axis.vertical) {
                  final canScrollUp =
                      n.metrics.pixels > n.metrics.minScrollExtent &&
                      n.metrics.maxScrollExtent > n.metrics.minScrollExtent;
                  if (canScrollUp != _canScrollUp) {
                    setState(() => _canScrollUp = canScrollUp);
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
                            _buildSectionHeader(
                              icon: Icons.local_fire_department,
                              color: cs.primary,
                              title: l10n.hotSearchTitle,
                              expanded: _hotSearchExpanded,
                              onTap: () => setState(
                                () => _toggleCollapse(isHotSearch: true),
                              ),
                            ),
                            if (_hotSearchExpanded) ...[
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
                          ],
                        ),
                      ),
                    ),
                  if (!_isAnimeMode &&
                      _tags.isNotEmpty &&
                      _selectedTag == null &&
                      _searchQuery == null &&
                      !_searching)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(hp, 0, hp, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader(
                              icon: Icons.category,
                              color: cs.primary,
                              title: l10n.allTagsTitle,
                              expanded: _allTagsExpanded,
                              trailing: Text(
                                l10n.tagCount(_tags.length),
                                style: tt.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              onTap: () => setState(
                                () => _toggleCollapse(isHotSearch: false),
                              ),
                            ),
                            if (_allTagsExpanded) ...[
                              const SizedBox(height: AppSpacing.md),
                              Wrap(
                                spacing: _tagSpacing,
                                runSpacing: _tagSpacing,
                                children: [
                                  for (final t in _tags)
                                    FilterChip(
                                      label: Text(
                                        t.count > 0
                                            ? '${t.name} ${t.count}'
                                            : t.name,
                                      ),
                                      showCheckmark: false,
                                      onSelected: (_) => _selectTag(t.pathWord),
                                    ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.md),
                            ],
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
                  // 底部留白：选了 tag 时为悬浮按钮组留出避让空间，
                  // 同时保证结果太少时列表仍可滚动（搜索框/按钮不会卡在收起态）。
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: _selectedTag != null && !_isAnimeMode ? 140 : 16,
                    ),
                  ),
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
          // 右下角悬浮层：上一行回到顶部（任何可滚列表都出现），
          // 下一行 tag 胶囊 + 排序（仅 tag 浏览态）。两者都跟随搜索框收显。
          if ((_canScrollUp || (_selectedTag != null && !_isAnimeMode)) &&
              !_isAnimeMode)
            Positioned(
              right: 16,
              bottom: 16,
              child: _buildFloatingToolbar(context, cs),
            ),
        ],
      ),
    );
  }

  /// 下滑浏览时把搜索框收起，上滑或回到顶部再放出来；输入过程中不收。
  /// 顶部判断对所有滚动通知生效（结果太少、不可滚动时不发 UserScroll，
  /// 否则切到短结果列表后搜索框会卡在收起态再也回不来）。
  void _updateHeaderVisibility(ScrollNotification n) {
    if (n.metrics.pixels <= n.metrics.minScrollExtent) {
      _setHeaderVisible(true);
      return;
    }
    if (n is! UserScrollNotification) return;
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

  /// 选中 tag 后右下角浮出的工具条：上一行回到顶部，下一行 tag 胶囊 + 热度/更新排序。
  /// 样式参照章节评论区右下角悬浮按钮（chapter_comments_sheet）。
  Widget _buildFloatingToolbar(BuildContext context, ColorScheme cs) {
    final l10n = AppLocalizations.of(context)!;

    // 胶囊（tag / 排序）：选中态用 primaryContainer，未选中用 surfaceContainerHighest。
    ButtonStyle chipStyle(bool selected) => FilledButton.styleFrom(
      backgroundColor: selected
          ? cs.primaryContainer
          : cs.surfaceContainerHighest,
      foregroundColor: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
      elevation: selected ? 4 : 0,
      shadowColor: AppShadows.floatingTint(0.22),
      minimumSize: const Size(0, 44),
      maximumSize: const Size.fromHeight(44),
      fixedSize: const Size.fromHeight(44),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.smR),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    // 方形按钮（回到顶部）。
    final squareStyle = FilledButton.styleFrom(
      backgroundColor: cs.primaryContainer,
      foregroundColor: cs.onPrimaryContainer,
      elevation: 6,
      shadowColor: AppShadows.floatingTint(0.22),
      minimumSize: const Size.square(48),
      maximumSize: const Size.square(48),
      fixedSize: const Size.square(48),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.smR),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    return SafeArea(
      top: false,
      child: AnimatedSlide(
        offset: _headerVisible ? Offset.zero : const Offset(0, 1.2),
        curve: Curves.easeInOutCubic,
        duration: const Duration(milliseconds: 200),
        child: AnimatedOpacity(
          opacity: _headerVisible ? 1.0 : 0.0,
          curve: Curves.easeInOutCubic,
          duration: const Duration(milliseconds: 200),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 回到顶部：任何可滚动列表都出现，不依赖 tag。
              if (_canScrollUp)
                SizedBox.square(
                  dimension: 48,
                  child: FilledButton(
                    style: squareStyle,
                    onPressed: _scrollToTop,
                    child: const Icon(Icons.arrow_upward_rounded),
                  ),
                ),
              // 回到顶部与 tag 工具条同时存在时的间距。
              if (_canScrollUp && _selectedTag != null)
                const SizedBox(height: AppSpacing.sm),
              // tag 胶囊 + 排序：仅 tag 浏览态。
              if (_selectedTag != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.icon(
                      style: chipStyle(true),
                      onPressed: () => _selectTag(null),
                      icon: const Icon(Icons.label_outline),
                      label: Text(_selectedTagName),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    FilledButton.icon(
                      style: chipStyle(true),
                      onPressed: _toggleOrdering,
                      icon: Icon(
                        _ordering == ApiOrdering.popular
                            ? Icons.whatshot
                            : Icons.schedule,
                      ),
                      label: Text(
                        _ordering == ApiOrdering.popular
                            ? l10n.popularOrder
                            : l10n.updateOrder,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 可折叠区块的标题行：左侧图标 + 标题（+ 可选 trailing），右侧旋转箭头随展开/收起翻转。
  Widget _buildSectionHeader({
    required IconData icon,
    required Color color,
    required String title,
    required bool expanded,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.xsR,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 6),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.sm),
              trailing,
            ],
            const Spacer(),
            AnimatedRotation(
              turns: expanded ? 0.0 : 0.5,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeInOutCubic,
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
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
