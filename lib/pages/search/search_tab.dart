part of '../search_page.dart';

/// 「搜索」标签页：只做关键词搜索，固定使用 HOT 源。
///
/// 不提供源切换与筛选——`/api/v3/search/comic` 不认 `theme` / `top`，
/// 摆出筛选控件只会误导用户以为能叠加。要按 tag 浏览请用「发现」页。
class _SearchTab extends StatefulWidget {
  const _SearchTab();

  @override
  State<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<_SearchTab>
    with AutomaticKeepAliveClientMixin {
  static const _kHotSearchExpanded = 'search_hot_search_expanded';

  final _api = ApiClient();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _scrollController = ScrollController();
  // 热门搜索词来自 HOT 源；COPY 源没有这个接口，此页固定用 HOT。
  // 走 SearchInitRepository 以复用带缓存的那条路径（TTL 内不发请求）。
  final _initRepo = SearchInitRepository();

  List<String> _keywords = [];
  List<Comic> _comics = [];
  bool _searching = false;
  bool _loadingMore = false;
  bool _hasSearchText = false;
  bool _hotSearchExpanded = true;
  // 列表是否可向上滚动（内容超出视口且不在顶部）。回到顶部按钮据此显隐。
  bool _canScrollUp = false;
  int _offset = 0;
  int _total = 0;
  int _loadEpoch = 0;
  String? _searchQuery;

  bool get _hasResults => _comics.isNotEmpty;

  /// TabBarView 会销毁离屏 tab 的 State（底部导航栏那种保活不适用于这里），
  /// 不声明保活的话切到「发现」再切回来，搜索结果与滚动位置就没了。
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchTextChanged);
    _loadKeywords();
    _restoreCollapseState();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchTextChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchTextChanged() {
    final hasText = _searchController.text.isNotEmpty;
    if (!mounted || hasText == _hasSearchText) return;
    setState(() => _hasSearchText = hasText);
  }

  /// 热门搜索词来自 HOT 源；COPY 源没有这个接口，此页固定用 HOT。
  /// 经仓库读取，TTL 内命中缓存不发请求。
  Future<void> _loadKeywords({bool forceRefresh = false}) async {
    final epoch = _loadEpoch;
    try {
      final data = forceRefresh
          ? await _initRepo.forceRefreshApi()
          : await _initRepo.load();
      if (!mounted || epoch != _loadEpoch) return;
      setState(() => _keywords = data.keywords);
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'search_tab.load_keywords',
        ),
      );
    }
  }

  Future<void> _restoreCollapseState() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _hotSearchExpanded = prefs.getBool(_kHotSearchExpanded) ?? true;
    });
  }

  void _toggleHotSearchExpanded() {
    final next = !_hotSearchExpanded;
    setState(() => _hotSearchExpanded = next);
    SharedPreferences.getInstance().then(
      (p) => p.setBool(_kHotSearchExpanded, next),
    );
  }

  Future<void> _doSearch(String query) async {
    final keyword = query.trim();
    if (keyword.isEmpty) return;
    final epoch = _loadEpoch;
    setState(() {
      _searching = true;
      _searchQuery = keyword;
      _comics = [];
      _offset = 0;
      _total = 0;
    });

    try {
      final result = await _api.manga.searchComics(keyword);
      if (!mounted || _searchQuery != keyword || epoch != _loadEpoch) return;
      setState(() {
        _comics = result.list;
        _total = result.total;
        _offset = result.list.length;
        _searching = false;
      });
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'search_tab.search',
        ),
      );
      if (mounted && epoch == _loadEpoch) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _loadMore() async {
    final query = _searchQuery;
    if (_loadingMore || query == null || _offset >= _total) return;
    final epoch = _loadEpoch;
    setState(() => _loadingMore = true);
    try {
      final result = await _api.manga.searchComics(query, offset: _offset);
      if (!mounted || epoch != _loadEpoch) return;
      setState(() {
        _comics.addAll(result.list);
        _offset = _comics.length;
      });
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'search_tab.load_more',
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

  void _clearSearch() {
    _searchController.clear();
    if (_searchQuery == null) return;
    _loadEpoch++;
    setState(() {
      _searchQuery = null;
      _comics = [];
      _offset = 0;
      _total = 0;
      _searching = false;
    });
  }

  void _onKeywordTap(String keyword) {
    _searchController.text = keyword;
    _doSearch(keyword);
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 要求
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final hp = ScreenLayout.horizontalPadding(screenWidth);
    final cardExtent = ScreenLayout.cardExtent(screenWidth);

    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(hp, 12, hp, AppSpacing.lg),
              child: SearchBar(
                controller: _searchController,
                focusNode: _searchFocus,
                hintText: l10n.searchHint(l10n.comicLabel),
                leading: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.search),
                ),
                trailing: _hasSearchText || _searchQuery != null
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
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  if (_searchQuery != null) {
                    await _doSearch(_searchQuery!);
                  } else {
                    await _loadKeywords(forceRefresh: true);
                  }
                },
                child: NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n.metrics.axis != Axis.vertical) return false;
                    final canScrollUp =
                        n.metrics.pixels > n.metrics.minScrollExtent &&
                        n.metrics.maxScrollExtent > n.metrics.minScrollExtent;
                    if (canScrollUp != _canScrollUp) {
                      setState(() => _canScrollUp = canScrollUp);
                    }
                    if (_hasResults &&
                        n.metrics.pixels > 0 &&
                        n.metrics.pixels > n.metrics.maxScrollExtent - 300) {
                      _loadMore();
                    }
                    return false;
                  },
                  child: CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      if (_searching)
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(hp, 8, hp, 0),
                          sliver: SliverGrid(
                            delegate: SliverChildBuilderDelegate(
                              (_, _) => const ComicCardSkeleton(),
                              childCount: 20,
                            ),
                            gridDelegate:
                                SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: cardExtent,
                                  childAspectRatio: 0.55,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                ),
                          ),
                        ),
                      // 热门搜索：没有结果、也没在搜时展示。
                      if (_keywords.isNotEmpty && !_hasResults && !_searching)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(hp, 8, hp, 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SectionHeader(
                                  icon: Icons.local_fire_department,
                                  title: l10n.hotSearchTitle,
                                  onTap: _toggleHotSearchExpanded,
                                  trailing: AnimatedRotation(
                                    turns: _hotSearchExpanded ? 0.0 : 0.5,
                                    duration: const Duration(milliseconds: 180),
                                    curve: Curves.easeInOutCubic,
                                    child: Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      size: AppIconSize.lg,
                                      color: cs.onSurfaceVariant,
                                    ),
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
                                            materialTapTargetSize:
                                                MaterialTapTargetSize
                                                    .shrinkWrap,
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      if (_searchQuery != null && _hasResults)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(hp, 8, hp, 12),
                            child: Text(
                              l10n.searchResultSummary(
                                _searchQuery!,
                                _total,
                                l10n.comicLabel,
                              ),
                              style: tt.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      if (_comics.isNotEmpty)
                        _ComicGrid(
                          comics: _comics,
                          hp: hp,
                          cardExtent: cardExtent,
                          loadingMore: _loadingMore,
                          scope: 'search',
                          onOpen: (comic, heroTagBase) => context.pushNamed(
                            AppRoutes.comicDetail,
                            pathParameters: {'pathWord': comic.pathWord},
                            extra: ComicDetailExtra(
                              initialComic: comic,
                              heroTagBase: heroTagBase,
                            ),
                          ),
                        ),
                      if (_hasResults && _offset < _total)
                        SliverToBoxAdapter(
                          child: LoadMoreFooter(
                            loading: _loadingMore,
                            onPressed: _loadMore,
                            label: l10n.loadMoreProgress(_offset, _total),
                            horizontalPadding: hp,
                          ),
                        ),
                      // 底部留白：给右下角回到顶部按钮让位。
                      const SliverToBoxAdapter(child: SizedBox(height: 72)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        // 右下角：回到顶部（列表可向上滚动时出现）。
        if (_canScrollUp)
          Positioned(
            right: 16,
            bottom: 16,
            child: _BackToTopButton(onPressed: _scrollToTop),
          ),
      ],
    );
  }
}
