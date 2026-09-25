part of '../search_page.dart';

/// 「搜索」标签页：只做关键词搜索，固定使用 HOT 源。
///
/// 不提供源切换与筛选——`/api/v3/search/comic` 不认 `theme` / `top`，
/// 摆出筛选控件只会误导用户以为能叠加。要按 tag 浏览请用「发现」页。
class _SearchTab extends StatefulWidget {
  const _SearchTab({required this.api, required this.initRepository});

  final ApiClient api;
  final SearchInitRepository initRepository;

  @override
  State<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<_SearchTab>
    with AutomaticKeepAliveClientMixin {
  static const _kHotSearchExpanded = 'search_hot_search_expanded';

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _scrollController = ScrollController();
  final _history = SearchHistory();
  final _user = UserManager();

  List<String> _keywords = [];
  List<String> _historyKeywords = [];
  List<Comic> _comics = [];
  bool _keywordsLoading = true;
  bool _keywordsFailed = false;
  bool _searching = false;
  bool _searchFailed = false;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;
  bool _hasMore = false;
  bool _hasSearchText = false;
  bool _hotSearchExpanded = true;
  bool _canScrollUp = false;
  int _offset = 0;
  int _total = 0;
  // 结果、元数据和本地历史各用自己的代次，互不丢弃对方的完成通知。
  int _resultsEpoch = 0;
  int _keywordsEpoch = 0;
  int _historyEpoch = 0;
  int _collapseEpoch = 0;
  Future<void> _collapseWrites = Future<void>.value();
  String? _searchQuery;

  bool get _idle => _searchQuery == null;
  bool get _hasResults => _comics.isNotEmpty;
  bool get _canLoadMore =>
      !_idle &&
      _hasResults &&
      _hasMore &&
      !_searching &&
      !_loadingMore &&
      !_loadMoreFailed;

  /// 保留切换标签前的结果、输入与滚动位置。
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchTextChanged);
    // 缓存管理/重置会重新初始化 UserManager 并通知；切换标签也会通知。
    // 历史不是全局单例，在这里重读即可同步保活页面，无需 settings_reload。
    _user.addListener(_onUserChanged);
    unawaited(_loadKeywords());
    unawaited(_loadHistory());
    unawaited(_restoreCollapseState());
  }

  @override
  void dispose() {
    _user.removeListener(_onUserChanged);
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

  void _onUserChanged() => unawaited(_loadHistory());

  Future<void> _loadHistory() => _updateHistory(_history.load());

  Future<void> _updateHistory(Future<List<String>> operation) async {
    final epoch = ++_historyEpoch;
    final entries = await operation;
    if (!mounted || epoch != _historyEpoch) return;
    setState(() => _historyKeywords = entries);
  }

  void _removeHistory(String keyword) {
    setState(() {
      _historyKeywords = _historyKeywords
          .where((entry) => entry != keyword)
          .toList();
    });
    unawaited(_updateHistory(_history.remove(keyword)));
  }

  void _clearHistory() {
    setState(() => _historyKeywords = []);
    unawaited(_updateHistory(_history.clear()));
  }

  /// 热搜经 HOT 仓库读取；TTL 内读缓存，下拉或错误重试强制刷新。
  Future<void> _loadKeywords({bool forceRefresh = false}) async {
    final epoch = ++_keywordsEpoch;
    setState(() {
      _keywordsLoading = true;
      _keywordsFailed = false;
    });
    try {
      final data = forceRefresh
          ? await widget.initRepository.forceRefreshApi()
          : await widget.initRepository.load();
      if (!mounted || epoch != _keywordsEpoch) return;
      setState(() => _keywords = data.keywords);
    } catch (error, stack) {
      if (!mounted || epoch != _keywordsEpoch) return;
      _recordWarning(error, stack, 'load_keywords');
      setState(() => _keywordsFailed = true);
    } finally {
      if (mounted && epoch == _keywordsEpoch) {
        setState(() => _keywordsLoading = false);
      }
    }
  }

  Future<void> _restoreCollapseState() async {
    final epoch = _collapseEpoch;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted || epoch != _collapseEpoch) return;
      setState(() {
        _hotSearchExpanded = prefs.getBool(_kHotSearchExpanded) ?? true;
      });
    } catch (error, stack) {
      _recordWarning(error, stack, 'restore_collapse');
    }
  }

  void _toggleHotSearchExpanded() {
    final next = !_hotSearchExpanded;
    _collapseEpoch++;
    setState(() => _hotSearchExpanded = next);
    _collapseWrites = _collapseWrites.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.setBool(_kHotSearchExpanded, next)) {
          throw StateError('Hot search collapse preference persistence failed');
        }
      } catch (error, stack) {
        _recordWarning(error, stack, 'save_collapse');
      }
    });
  }

  bool _isCurrentResult(int epoch) => mounted && epoch == _resultsEpoch;

  Future<void> _doSearch(String query, {bool recordHistory = true}) async {
    final keyword = query.trim();
    if (keyword.isEmpty) return;
    // 即使同词再次提交，也是一轮新搜索；旧分页和旧首屏不能回写。
    final epoch = ++_resultsEpoch;
    _searchFocus.unfocus();
    setState(() {
      _searching = true;
      _searchFailed = false;
      _loadingMore = false;
      _loadMoreFailed = false;
      _hasMore = false;
      _searchQuery = keyword;
      _comics = [];
      _offset = 0;
      _total = 0;
      _canScrollUp = false;
    });
    _resetScroll();
    if (recordHistory) unawaited(_updateHistory(_history.add(keyword)));

    try {
      final result = await widget.api.manga.searchComics(keyword);
      if (!_isCurrentResult(epoch)) return;
      setState(() {
        _comics = List.of(result.list);
        _total = result.total;
        _offset = result.list.length;
        _hasMore = result.list.isNotEmpty && _offset < _total;
      });
    } catch (error, stack) {
      if (!_isCurrentResult(epoch)) return;
      _recordWarning(error, stack, 'search');
      setState(() => _searchFailed = true);
    } finally {
      if (_isCurrentResult(epoch)) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _loadMore({bool retry = false}) async {
    final query = _searchQuery;
    if (_searching ||
        _loadingMore ||
        (_loadMoreFailed && !retry) ||
        query == null ||
        !_hasResults ||
        !_hasMore) {
      return;
    }
    final epoch = _resultsEpoch;
    final offset = _offset;
    setState(() {
      _loadingMore = true;
      _loadMoreFailed = false;
    });
    try {
      final result = await widget.api.manga.searchComics(query, offset: offset);
      if (!_isCurrentResult(epoch)) return;
      setState(() {
        _comics.addAll(result.list);
        _offset = offset + result.list.length;
        _total = result.total;
        // 服务端 total 可能滞后，空分页必须停止后续请求。
        _hasMore = result.list.isNotEmpty && _offset < _total;
      });
    } catch (error, stack) {
      if (!_isCurrentResult(epoch)) return;
      _recordWarning(error, stack, 'load_more');
      setState(() => _loadMoreFailed = true);
    } finally {
      if (_isCurrentResult(epoch)) {
        setState(() => _loadingMore = false);
      }
    }
  }

  void _clearSearch() {
    _resultsEpoch++;
    _searchController.clear();
    setState(() {
      _searchQuery = null;
      _comics = [];
      _offset = 0;
      _total = 0;
      _searching = false;
      _searchFailed = false;
      _loadingMore = false;
      _loadMoreFailed = false;
      _hasMore = false;
      _canScrollUp = false;
    });
    _resetScroll();
    unawaited(_loadHistory());
  }

  void _onKeywordTap(String keyword) {
    _searchController.text = keyword;
    unawaited(_doSearch(keyword));
  }

  Future<void> _refresh() async {
    final query = _searchQuery;
    if (query != null) {
      await _doSearch(query, recordHistory: false);
    } else {
      await Future.wait([_loadKeywords(forceRefresh: true), _loadHistory()]);
    }
  }

  void _resetScroll() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.minScrollExtent);
    }
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      _scrollController.position.minScrollExtent,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _recordWarning(Object error, StackTrace stack, String action) {
    unawaited(
      AppLogger.instance.recordWarning(
        error,
        stackTrace: stack,
        source: 'search_tab.$action',
      ),
    );
  }

  Widget _buildHistory(AppLocalizations l10n, double hp) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(hp, AppSpacing.sm, hp, AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              icon: Icons.history_rounded,
              title: l10n.searchHistoryTitle,
              trailing: TextButton.icon(
                onPressed: _clearHistory,
                icon: const Icon(Icons.delete_sweep_outlined),
                label: Text(l10n.searchHistoryClear),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final keyword in _historyKeywords)
                  InputChip(
                    label: Text(
                      keyword,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () => _onKeywordTap(keyword),
                    onDeleted: () => _removeHistory(keyword),
                    deleteButtonTooltipMessage: l10n.searchHistoryDelete,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHotKeywords(AppLocalizations l10n, ColorScheme cs, double hp) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(hp, AppSpacing.sm, hp, AppSpacing.xs),
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
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final keyword in _keywords)
                    ActionChip(
                      label: Text(keyword),
                      onPressed: () => _onKeywordTap(keyword),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final hp = ScreenLayout.horizontalPadding(screenWidth);
    final cardExtent = ScreenLayout.cardExtent(screenWidth);

    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                hp,
                AppSpacing.md,
                hp,
                AppSpacing.lg,
              ),
              child: SearchBar(
                controller: _searchController,
                focusNode: _searchFocus,
                hintText: l10n.searchHint(l10n.comicLabel),
                leading: const Padding(
                  padding: EdgeInsets.only(left: AppSpacing.sm),
                  child: Icon(Icons.search),
                ),
                trailing: _hasSearchText || !_idle
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
                onRefresh: _refresh,
                child: ResultScrollListener(
                  canScrollUp: _canScrollUp,
                  onCanScrollUpChanged: (value) =>
                      setState(() => _canScrollUp = value),
                  onLoadMore: _canLoadMore ? _loadMore : null,
                  child: CustomScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      if (_searching)
                        SliverComicGridSkeleton(
                          horizontalPadding: hp,
                          cardExtent: cardExtent,
                        ),
                      if (_idle) ...[
                        if (_historyKeywords.isNotEmpty)
                          _buildHistory(l10n, hp),
                        if (_keywordsLoading && _keywords.isEmpty)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.all(AppSpacing.xl),
                              child: Center(
                                child: ExpressiveLoadingIndicator(),
                              ),
                            ),
                          ),
                        if (_keywords.isNotEmpty)
                          _buildHotKeywords(l10n, cs, hp),
                        if (_keywordsFailed)
                          SliverErrorRetryView(
                            onRetry: () => _loadKeywords(forceRefresh: true),
                          ),
                      ],
                      if (!_idle && !_searching && _searchFailed)
                        SliverErrorRetryView(
                          message: l10n.searchRequestFailed,
                          onRetry: () =>
                              _doSearch(_searchQuery!, recordHistory: false),
                        ),
                      if (!_idle &&
                          !_searching &&
                          !_searchFailed &&
                          !_hasResults)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Padding(
                            padding: EdgeInsets.all(hp),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.search_off_rounded,
                                    size: AppIconSize.empty,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: AppSpacing.lg),
                                  Text(
                                    l10n.searchEmptyResults,
                                    style: tt.titleMedium,
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (!_idle && _hasResults) ...[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              hp,
                              AppSpacing.sm,
                              hp,
                              AppSpacing.md,
                            ),
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
                        if (_loadMoreFailed)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.all(hp),
                              child: Column(
                                children: [
                                  Text(
                                    l10n.searchLoadMoreFailed,
                                    style: tt.bodyMedium?.copyWith(
                                      color: cs.error,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  OutlinedButton.icon(
                                    onPressed: () => _loadMore(retry: true),
                                    icon: const Icon(Icons.refresh_rounded),
                                    label: Text(l10n.retryButton),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else if (_hasMore)
                          SliverToBoxAdapter(
                            child: LoadMoreFooter(
                              loading: _loadingMore,
                              onPressed: _loadMore,
                              label: l10n.loadMoreProgress(_offset, _total),
                              horizontalPadding: hp,
                            ),
                          ),
                      ],
                      // 底部留白：给右下角回到顶部按钮让位。
                      const SliverToBoxAdapter(child: SizedBox(height: 72)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_canScrollUp)
          Positioned(
            right: AppSpacing.lg,
            bottom: AppSpacing.lg,
            child: SafeArea(
              top: false,
              child: BackToTopButton(onPressed: _scrollToTop),
            ),
          ),
      ],
    );
  }
}
