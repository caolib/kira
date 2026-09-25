part of '../search_page.dart';

/// 「发现」标签页：按题材 tag / 大分类浏览漫画，可切换 HOT / COPY 两个源。
///
/// 没有搜索框——关键字搜索走的是另一个接口（见 [_SearchTab]）。
/// 数据源独立于首页，用 [UserManager.discoverSource] 单独持久化。
class _DiscoverTab extends StatefulWidget {
  const _DiscoverTab({required this.api, required this.initRepository});

  final ApiClient api;
  final SearchInitRepository initRepository;

  @override
  State<_DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends State<_DiscoverTab>
    with AutomaticKeepAliveClientMixin {
  final _user = UserManager();
  final _scrollController = ScrollController();

  // 请求与界面都使用同一个源快照，不在设置通知到达前混用新旧源。
  late String _source = _user.discoverSource;
  late SearchInitRepository _initRepo = _repositoryForSource(_source);
  late final _copyFilterRepo = CopyFilterRepository(api: widget.api);

  List<m.Theme> _tags = [];
  List<Comic> _comics = [];
  m.CopyFilterOptions _copyFilters = m.CopyFilterOptions.empty;

  String? _selectedTag;
  String? _selectedTop;
  String _ordering = ApiOrdering.popular;
  bool _tagsExpanded = false;
  bool _loadingMore = false;
  bool _searching = false;
  bool _canScrollUp = false;
  bool _metadataLoading = false;
  bool _tagsFailed = false;
  bool _copyFiltersFailed = false;
  bool _listFailed = false;
  bool _loadMoreFailed = false;
  bool _hasMore = false;
  int _offset = 0;
  int _total = 0;

  // 元数据不受筛选变化影响；列表的每次首屏请求则使旧首屏和分页一起失效。
  int _metadataEpoch = 0;
  int _listEpoch = 0;

  bool get _isCopySource => _source == 'copy';
  bool get _hasResults => _comics.isNotEmpty;
  bool get _metadataFailed => _tagsFailed || _copyFiltersFailed;
  bool get _canLoadMore =>
      _hasResults &&
      _hasMore &&
      !_searching &&
      !_loadingMore &&
      !_listFailed &&
      !_loadMoreFailed;

  /// 切到「搜索」再切回来时保留筛选、漫画列表与滚动位置。
  @override
  bool get wantKeepAlive => true;

  bool get _canResetFilters =>
      _selectedTop != null ||
      _selectedTag != null ||
      _ordering != ApiOrdering.popular;

  @override
  void initState() {
    super.initState();
    _user.addListener(_onUserChanged);
    unawaited(_reload());
  }

  @override
  void dispose() {
    _user.removeListener(_onUserChanged);
    _scrollController.dispose();
    super.dispose();
  }

  SearchInitRepository _repositoryForSource(String source) =>
      widget.initRepository.source == source
      ? widget.initRepository
      : SearchInitRepository(source: source, api: widget.api);

  bool _isCurrentMetadata(int epoch, String source) =>
      mounted &&
      epoch == _metadataEpoch &&
      source == _source &&
      source == _user.discoverSource;

  bool _isCurrentList(int epoch, String source) =>
      mounted &&
      epoch == _listEpoch &&
      source == _source &&
      source == _user.discoverSource;

  void _onUserChanged() {
    if (!mounted) return;
    final source = _user.discoverSource;
    if (source != _source) unawaited(_switchSource(source));
  }

  /// 先同步页面快照再启动请求，避免设置异步落盘/通知期间刷新到旧源。
  Future<void> _selectSource(String source) async {
    if (source == _source) return;
    final saveSource = _user.setDiscoverSource(source);
    unawaited(_switchSource(source));
    try {
      await saveSource;
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'discover_tab.set_source',
        ),
      );
    }
  }

  Future<void> _switchSource(String source, {bool forceRefresh = false}) {
    setState(() {
      _source = source;
      _initRepo = _repositoryForSource(source);
      _tags = [];
      _copyFilters = m.CopyFilterOptions.empty;
      _selectedTag = null;
      _selectedTop = null;
      _ordering = ApiOrdering.popular;
      _tagsExpanded = false;
    });
    final reload = _reload(forceRefresh: forceRefresh);
    unawaited(_scrollToTop());
    return reload;
  }

  /// 列表与筛选元数据并行更新，刷新手势会等到两者都完成。
  Future<void> _reload({
    bool forceRefresh = false,
    bool keepResults = false,
  }) async {
    await Future.wait<void>([
      _loadMetadata(forceRefresh: forceRefresh),
      _loadComics(keepResults: keepResults),
    ]);
  }

  Future<void> _refresh() {
    final source = _user.discoverSource;
    if (source != _source) {
      return _switchSource(source, forceRefresh: true);
    }
    return _reload(forceRefresh: true, keepResults: true);
  }

  /// 重置仍然展示「全部 + 热度」列表，不再退回只有题材的空白态。
  void _resetFilters() {
    setState(() {
      _selectedTop = null;
      _selectedTag = null;
      _ordering = ApiOrdering.popular;
    });
    unawaited(_loadComics());
    unawaited(_scrollToTop());
  }

  Future<void> _loadMetadata({bool forceRefresh = false}) async {
    final epoch = ++_metadataEpoch;
    final source = _source;
    final repository = _initRepo;
    setState(() {
      _metadataLoading = true;
      _tagsFailed = false;
      _copyFiltersFailed = false;
    });
    try {
      await Future.wait<void>([
        _loadInit(repository, epoch, source, forceRefresh: forceRefresh),
        if (source == 'copy')
          _loadCopyFilters(epoch, source, forceRefresh: forceRefresh),
      ]);
    } finally {
      if (_isCurrentMetadata(epoch, source)) {
        setState(() => _metadataLoading = false);
      }
    }
  }

  Future<void> _loadInit(
    SearchInitRepository repository,
    int epoch,
    String source, {
    required bool forceRefresh,
  }) async {
    try {
      final data = forceRefresh
          ? await repository.forceRefreshApi()
          : await repository.load();
      if (!_isCurrentMetadata(epoch, source)) return;
      setState(() => _tags = data.tags);
    } catch (e, stack) {
      if (!_isCurrentMetadata(epoch, source)) return;
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'discover_tab.load_init',
        ),
      );
      // 刷新可能使尚未显示的缓存回包失效；失败后在当前代次恢复缓存。
      if (_tags.isEmpty) {
        try {
          final cached = await repository.loadFromCache();
          if (!_isCurrentMetadata(epoch, source)) return;
          if (cached != null) setState(() => _tags = cached.tags);
        } catch (cacheError, cacheStack) {
          if (!_isCurrentMetadata(epoch, source)) return;
          unawaited(
            AppLogger.instance.recordWarning(
              cacheError,
              stackTrace: cacheStack,
              source: 'discover_tab.restore_tags_cache',
            ),
          );
        }
      }
      setState(() => _tagsFailed = true);
    }
  }

  Future<void> _loadCopyFilters(
    int epoch,
    String source, {
    required bool forceRefresh,
  }) async {
    try {
      final options = forceRefresh
          ? await _copyFilterRepo.forceRefreshApi()
          : await _copyFilterRepo.load();
      if (!_isCurrentMetadata(epoch, source)) return;
      setState(() => _copyFilters = options);
    } catch (e, stack) {
      if (!_isCurrentMetadata(epoch, source)) return;
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'discover_tab.load_copy_filters',
        ),
      );
      if (_copyFilters.tops.isEmpty) {
        try {
          final cached = await _copyFilterRepo.loadFromCache();
          if (!_isCurrentMetadata(epoch, source)) return;
          if (cached != null) setState(() => _copyFilters = cached);
        } catch (cacheError, cacheStack) {
          if (!_isCurrentMetadata(epoch, source)) return;
          unawaited(
            AppLogger.instance.recordWarning(
              cacheError,
              stackTrace: cacheStack,
              source: 'discover_tab.restore_copy_filters_cache',
            ),
          );
        }
      }
      setState(() => _copyFiltersFailed = true);
    }
  }

  Future<({List<Comic> list, int total})> _fetchComicPage({
    required String source,
    required String ordering,
    required int offset,
    required String? tag,
    required String? top,
  }) => source == 'copy'
      ? widget.api.manga.getCopyComicList(
          ordering: ordering,
          offset: offset,
          theme: tag,
          top: top,
        )
      : widget.api.manga.getComicList(
          ordering: ordering,
          offset: offset,
          theme: tag,
        );

  Future<void> _loadComics({bool keepResults = false}) async {
    final epoch = ++_listEpoch;
    final source = _source;
    final ordering = _ordering;
    final tag = _selectedTag;
    final top = _selectedTop;
    setState(() {
      if (!keepResults) {
        _comics = [];
        _offset = 0;
        _total = 0;
        _hasMore = false;
        _tagsExpanded = false;
      }
      _searching = true;
      _loadingMore = false;
      _listFailed = false;
      _loadMoreFailed = false;
    });
    try {
      final result = await _fetchComicPage(
        source: source,
        ordering: ordering,
        offset: 0,
        tag: tag,
        top: top,
      );
      if (!_isCurrentList(epoch, source)) return;
      setState(() {
        _comics = List.of(result.list);
        _total = result.total;
        _offset = result.list.length;
        _hasMore = result.list.isNotEmpty && _offset < _total;
      });
    } catch (e, stack) {
      if (!_isCurrentList(epoch, source)) return;
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'discover_tab.load_comics',
        ),
      );
      setState(() => _listFailed = true);
    } finally {
      if (_isCurrentList(epoch, source)) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _loadMore({bool retry = false}) async {
    if (_searching ||
        _loadingMore ||
        !_hasResults ||
        !_hasMore ||
        _listFailed ||
        (_loadMoreFailed && !retry)) {
      return;
    }
    final epoch = _listEpoch;
    final source = _source;
    final ordering = _ordering;
    final tag = _selectedTag;
    final top = _selectedTop;
    final offset = _offset;
    setState(() {
      _loadingMore = true;
      _loadMoreFailed = false;
    });
    try {
      final result = await _fetchComicPage(
        source: source,
        ordering: ordering,
        offset: offset,
        tag: tag,
        top: top,
      );
      if (!_isCurrentList(epoch, source)) return;
      setState(() {
        _comics.addAll(result.list);
        _offset = offset + result.list.length;
        _total = result.total;
        // 某些源的 total 会滞后；空页必须终止，不能反复请求同一 offset。
        _hasMore = result.list.isNotEmpty && _offset < _total;
      });
    } catch (e, stack) {
      if (!_isCurrentList(epoch, source)) return;
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'discover_tab.load_more',
        ),
      );
      setState(() => _loadMoreFailed = true);
    } finally {
      if (_isCurrentList(epoch, source)) {
        setState(() => _loadingMore = false);
      }
    }
  }

  void _setOrdering(String value) {
    if (_ordering == value) return;
    setState(() => _ordering = value);
    unawaited(_loadComics());
    unawaited(_scrollToTop());
  }

  /// 题材与 COPY 地区可叠加；null 表示「全部」。
  void _selectTag(String? tagPathWord) {
    setState(() => _selectedTag = tagPathWord);
    unawaited(_loadComics());
    unawaited(_scrollToTop());
  }

  void _selectTop(String? topPathWord) {
    setState(() => _selectedTop = topPathWord);
    unawaited(_loadComics());
    unawaited(_scrollToTop());
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _toggleTagsExpanded() {
    setState(() => _tagsExpanded = !_tagsExpanded);
  }

  List<_ChipOption> _topOptions(AppLocalizations l10n) => [
    _ChipOption(
      label: l10n.searchFilterAll,
      value: '',
      icon: Icons.public,
      selected: _selectedTop == null,
    ),
    for (final t in _copyFilters.tops)
      _ChipOption(
        label: t.name,
        value: t.pathWord,
        selected: _selectedTop == t.pathWord,
      ),
  ];

  List<_ChipOption> _tagOptions(AppLocalizations l10n) => [
    _ChipOption(
      label: l10n.searchFilterAll,
      value: '',
      icon: Icons.local_offer_outlined,
      selected: _selectedTag == null,
    ),
    for (final t in _tags)
      _ChipOption(
        label: t.name,
        value: t.pathWord,
        selected: _selectedTag == t.pathWord,
      ),
  ];

  List<_ChipOption> _orderingOptions(AppLocalizations l10n) => [
    _ChipOption(
      label: l10n.popularOrder,
      value: ApiOrdering.popular,
      icon: Icons.whatshot,
      selected: _ordering == ApiOrdering.popular,
    ),
    _ChipOption(
      label: l10n.updateOrder,
      value: ApiOrdering.datetimeUpdated,
      icon: Icons.schedule,
      selected: _ordering == ApiOrdering.datetimeUpdated,
    ),
  ];

  Widget _buildFilters(BuildContext context, double hp) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: EdgeInsets.fromLTRB(hp, AppSpacing.md, hp, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_metadataLoading || (_searching && _hasResults)) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (_metadataFailed)
            _DiscoverRetryNotice(
              message: l10n.discoverFiltersFailed,
              onRetry: () => unawaited(_loadMetadata(forceRefresh: true)),
            ),
          if (_isCopySource && _copyFilters.tops.isNotEmpty) ...[
            _FilterChipRow(
              options: _topOptions(l10n),
              onTap: (o) => _selectTop(o.value.isEmpty ? null : o.value),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          // 展开时只渲染下面的题材网格，不再重复一条横向 chip 行。
          if (_tags.isNotEmpty && !_tagsExpanded) ...[
            _FilterChipRow(
              options: _tagOptions(l10n),
              onTap: (o) => _selectTag(o.value.isEmpty ? null : o.value),
              trailing: _filterRowButton(
                onPressed: _toggleTagsExpanded,
                icon: Icons.expand_more,
                label: l10n.tagsExpandAll,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          _FilterChipRow(
            options: _orderingOptions(l10n),
            onTap: (o) => _setOrdering(o.value),
            // 行尾固定：数据源切换在左，重置在右（重置只在有筛选时出现）。
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SourceToggle(
                  isCopy: _isCopySource,
                  onPressed: () =>
                      unawaited(_selectSource(_isCopySource ? 'hot' : 'copy')),
                ),
                if (_canResetFilters)
                  _filterRowButton(
                    onPressed: _resetFilters,
                    icon: Icons.restart_alt,
                    label: l10n.resetButton,
                  ),
              ],
            ),
          ),
          if (_tagsExpanded && _tags.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            SectionHeader(
              title: l10n.allTagsTitle,
              trailing: _filterRowButton(
                onPressed: _toggleTagsExpanded,
                icon: Icons.expand_less,
                label: l10n.tagsCollapseAll,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _AllTagsGrid(
              tags: _tags,
              selectedTag: _selectedTag,
              onSelected: _selectTag,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final hp = ScreenLayout.horizontalPadding(screenWidth);
    final cardExtent = ScreenLayout.cardExtent(screenWidth);

    return Stack(
      children: [
        RefreshIndicator(
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
                // 全部筛选和题材网格一起滚出视口，只有外层 TabBar 固定。
                SliverToBoxAdapter(child: _buildFilters(context, hp)),
                if (_searching && !_hasResults)
                  SliverComicGridSkeleton(
                    horizontalPadding: hp,
                    cardExtent: cardExtent,
                  ),
                if (!_searching && _listFailed && !_hasResults)
                  SliverErrorRetryView(
                    message: l10n.discoverRequestFailed,
                    onRetry: () => unawaited(_loadComics()),
                  ),
                if (!_searching && !_listFailed && !_hasResults)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: EdgeInsets.all(hp),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.auto_stories_outlined,
                            size: AppIconSize.empty,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            l10n.discoverEmptyResults,
                            textAlign: TextAlign.center,
                            style: tt.bodyLarge?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_hasResults)
                  _ComicGrid(
                    comics: _comics,
                    hp: hp,
                    cardExtent: cardExtent,
                    loadingMore: _loadingMore,
                    scope: 'discover',
                    onOpen: (comic, heroTagBase) => context.pushNamed(
                      AppRoutes.comicDetail,
                      pathParameters: {'pathWord': comic.pathWord},
                      extra: ComicDetailExtra(
                        initialComic: comic,
                        heroTagBase: heroTagBase,
                      ),
                    ),
                  ),
                if (_listFailed && _hasResults)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: hp),
                      child: _DiscoverRetryNotice(
                        message: l10n.discoverRequestFailed,
                        onRetry: () =>
                            unawaited(_loadComics(keepResults: true)),
                      ),
                    ),
                  ),
                if (_loadMoreFailed)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: hp),
                      child: _DiscoverRetryNotice(
                        message: l10n.searchLoadMoreFailed,
                        onRetry: () => unawaited(_loadMore(retry: true)),
                      ),
                    ),
                  )
                else if (_hasResults && _hasMore && !_listFailed && !_searching)
                  SliverToBoxAdapter(
                    child: LoadMoreFooter(
                      loading: _loadingMore,
                      onPressed: _loadMore,
                      label: l10n.loadMoreProgress(_offset, _total),
                      horizontalPadding: hp,
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 72)),
              ],
            ),
          ),
        ),
        if (_canScrollUp)
          Positioned(
            right: AppSpacing.md,
            bottom: AppSpacing.md,
            child: SafeArea(
              top: false,
              child: BackToTopButton(onPressed: _scrollToTop),
            ),
          ),
      ],
    );
  }
}

/// 非阻断错误：保留已有筛选/漫画，且只有显式点击才会重试。
class _DiscoverRetryNotice extends StatelessWidget {
  const _DiscoverRetryNotice({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Semantics(
        liveRegion: true,
        child: Row(
          children: [
            Expanded(child: Text(message)),
            const SizedBox(width: AppSpacing.sm),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: AppIconSize.lg),
              label: Text(l10n.retryButton),
            ),
          ],
        ),
      ),
    );
  }
}
