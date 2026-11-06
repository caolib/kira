part of '../search_page.dart';

/// 「搜索」标签页：只做关键词搜索，固定使用 HOT 源。
///
/// 不提供源切换与筛选——`/api/v3/search/comic` 不认 `theme` / `top`，
/// 摆出筛选控件只会误导用户以为能叠加。要按 tag 浏览请用「发现」页。
class _SearchTab extends StatefulWidget {
  const _SearchTab({
    required this.api,
    required this.initRepository,
    required this.isActive,
  });

  final ApiClient api;
  final SearchInitRepository initRepository;
  final bool isActive;

  @override
  State<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<_SearchTab>
    with AutomaticKeepAliveClientMixin, BranchDeferredInit {
  static const _kHotSearchExpanded = 'search_hot_search_expanded';

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _scrollController = ScrollController();

  List<String> _keywords = [];
  List<Comic> _comics = [];
  bool _keywordsLoading = true;
  bool _keywordsFailed = false;
  Object? _keywordsError;
  bool _searching = false;
  bool _searchFailed = false;
  Object? _searchError;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;
  Object? _loadMoreError;
  bool _hasMore = false;
  bool _hasSearchText = false;
  bool _hotSearchExpanded = true;
  bool _canScrollUp = false;
  int _offset = 0;
  int _total = 0;
  // 结果、元数据各用自己的代次，互不丢弃对方的完成通知。
  int _resultsEpoch = 0;
  int _keywordsEpoch = 0;
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
    deferInitialLoadToBranchActivation();
  }

  @override
  void onBranchFirstActivated() {
    unawaited(_loadKeywords());
    unawaited(_restoreCollapseState());
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
      setState(() {
        _keywordsFailed = true;
        _keywordsError = error;
      });
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

  Future<void> _doSearch(String query) async {
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
      _loadMoreError = null;
      _hasMore = false;
      _searchQuery = keyword;
      _comics = [];
      _offset = 0;
      _total = 0;
      _canScrollUp = false;
    });
    _resetScroll();

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
      setState(() {
        _searchFailed = true;
        _searchError = error;
      });
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
      _loadMoreError = null;
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
      setState(() {
        _loadMoreFailed = true;
        _loadMoreError = error;
      });
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
      _loadMoreError = null;
      _hasMore = false;
      _canScrollUp = false;
    });
    _resetScroll();
  }

  void _onKeywordTap(String keyword) {
    _searchController.text = keyword;
    unawaited(_doSearch(keyword));
  }

  Future<void> _refresh() async {
    final query = _searchQuery;
    if (query != null) {
      await _doSearch(query);
    } else {
      await _loadKeywords(forceRefresh: true);
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

    final body = Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                hp,
                AppSpacing.md,
                hp,
                AppSpacing.sm,
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
                            message: _keywordsError == null
                                ? null
                                : NetworkError.message(_keywordsError!),
                            onRetry: () => _loadKeywords(forceRefresh: true),
                          ),
                      ],
                      if (!_idle && !_searching && _searchFailed)
                        SliverErrorRetryView(
                          message: _searchError == null
                              ? l10n.searchRequestFailed
                              : NetworkError.message(_searchError!),
                          onRetry: () => _doSearch(_searchQuery!),
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
                                    l10n.loadMoreFailed,
                                    style: tt.bodyMedium?.copyWith(
                                      color: cs.error,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  if (_loadMoreError != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      NetworkError.describe(_loadMoreError!),
                                      style: tt.bodySmall?.copyWith(
                                        color: cs.error,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
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
                      // 底部留白：让开悬浮底栏，并给右下角回到顶部按钮让位。
                      const SliverToBoxAdapter(
                        child: BranchBottomSlack(extra: 72),
                      ),
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
            // 叠加悬浮导航栏高度，底栏隐藏时按钮落到屏幕底部。
            bottom: AppSpacing.lg + NavBarInset.of(context),
            child: BackToTopButton(onPressed: _scrollToTop),
          ),
      ],
    );

    // 只消费当前搜索标签的返回，发现页保留原来的退出行为。
    return PopScope<Object?>(
      canPop: !widget.isActive || (!_hasSearchText && _idle),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !widget.isActive) return;
        _searchFocus.unfocus();
        _clearSearch();
      },
      child: body,
    );
  }
}
