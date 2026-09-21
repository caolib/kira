part of '../search_page.dart';

/// 「发现」标签页：按题材 tag / 大分类浏览漫画，可切换 HOT / COPY 两个源。
///
/// 没有搜索框——关键字搜索走的是另一个接口（见 [_SearchTab]）。
/// 两个源的数据源设置与首页共用 [UserManager.mangaHomeSource]。
class _DiscoverTab extends StatefulWidget {
  const _DiscoverTab();

  @override
  State<_DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends State<_DiscoverTab>
    with AutomaticKeepAliveClientMixin {
  final _api = ApiClient();
  final _user = UserManager();
  final _scrollController = ScrollController();

  // 当前生效的数据源（'hot' / 'copy'），与首页共用同一个设置。
  late String _source = _user.mangaHomeSource;
  late SearchInitRepository _initRepo = SearchInitRepository(source: _source);

  List<m.Theme> _tags = [];
  List<Comic> _comics = [];
  // COPY 源的大分类筛选项（全部/日漫/韓漫/美漫/已完結），hot 源为空。
  m.CopyFilterOptions _copyFilters = m.CopyFilterOptions.empty;
  final _copyFilterRepo = CopyFilterRepository();

  String? _selectedTag;
  String? _selectedTop;
  String _ordering = ApiOrdering.popular;
  // 全部题材网格是否展开。空白态（还没筛选、没结果）默认展开填满页面；
  // 一旦有了筛选或结果就自动收起，把纵向空间让给漫画列表。
  bool _tagsExpanded = true;
  bool _loadingMore = false;
  bool _searching = false;
  bool _canScrollUp = false;
  bool _refreshing = false;
  int _offset = 0;
  int _total = 0;
  int _loadEpoch = 0;

  bool get _isCopySource => _user.mangaHomeSource == 'copy';
  bool get _hasResults => _comics.isNotEmpty;

  /// 同 [_SearchTabState.wantKeepAlive]：切到「搜索」再切回来时，
  /// 保留已选 tag、漫画列表与滚动位置，不被重置成空白态。
  @override
  bool get wantKeepAlive => true;

  /// 是否有可重置的筛选（大分类 / 题材 / 非默认排序）。
  bool get _canResetFilters =>
      _selectedTop != null ||
      _selectedTag != null ||
      _ordering != ApiOrdering.popular;

  @override
  void initState() {
    super.initState();
    _user.addListener(_onUserChanged);
    _loadInit();
    _loadCopyFilters();
  }

  @override
  void dispose() {
    _user.removeListener(_onUserChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onUserChanged() {
    if (!mounted) return;
    final source = _user.mangaHomeSource;
    if (source != _source) {
      _switchSource(source);
      return;
    }
    setState(() {});
  }

  /// 切换数据源：重建 init 仓库（缓存按源隔离），重置筛选并重载标签。
  /// [_loadEpoch] 自增使旧源的飞行中请求作废，避免其回包覆盖新源结果。
  void _switchSource(String source) {
    _source = source;
    _initRepo = SearchInitRepository(source: source);
    _loadEpoch++;
    setState(() {
      _tags = [];
      _comics = [];
      _copyFilters = m.CopyFilterOptions.empty;
      _selectedTag = null;
      _selectedTop = null;
      _tagsExpanded = true;
      _searching = false;
      _loadingMore = false;
      _offset = 0;
      _total = 0;
      _ordering = ApiOrdering.popular;
    });
    _loadInit();
    _loadCopyFilters();
  }

  /// 重置筛选：清空题材、大分类与排序，回到初始浏览视图。
  /// [_loadEpoch] 自增让在途的结果请求作废，避免它回包后又把列表填上。
  void _resetFilters() {
    _loadEpoch++;
    setState(() {
      _selectedTop = null;
      _selectedTag = null;
      // 回到空白态：重新铺开全部题材，与刚进页面时一致。
      _tagsExpanded = true;
      _comics = [];
      _searching = false;
      _loadingMore = false;
      _offset = 0;
      _total = 0;
      _ordering = ApiOrdering.popular;
    });
  }

  /// 读取题材标签。TTL 内命中缓存直接返回；[forceRefresh] 用于下拉刷新，
  /// 绕过缓存强制拉取。
  Future<void> _loadInit({bool forceRefresh = false}) async {
    final epoch = _loadEpoch;
    // 刷新时不显示整屏 loading（列表还在，只是重新拉标签）。
    if (!forceRefresh && !_refreshing) setState(() => _refreshing = true);
    try {
      final data = forceRefresh
          ? await _initRepo.forceRefreshApi()
          : await _initRepo.load();
      if (!mounted || epoch != _loadEpoch) return;
      setState(() {
        _tags = data.tags;
        _refreshing = false;
      });
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'discover_tab.load_init',
        ),
      );
      if (mounted && epoch == _loadEpoch) {
        setState(() => _refreshing = false);
      }
    }
  }

  /// COPY 源专用：拉取大分类筛选项。hot 源不调（它的维度是题材 tag）。
  ///
  /// 走 [CopyFilterRepository]，TTL 内直接命中缓存不发请求——这些分类是
  /// 服务端固定枚举，没必要每次进页面都拉一遍。
  Future<void> _loadCopyFilters() async {
    if (!_isCopySource) return;
    final epoch = _loadEpoch;
    try {
      final options = await _copyFilterRepo.load();
      if (!mounted || epoch != _loadEpoch) return;
      setState(() => _copyFilters = options);
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'discover_tab.load_copy_filters',
        ),
      );
    }
  }

  Future<void> _loadComics({bool reset = true}) async {
    final epoch = _loadEpoch;
    final isCopy = _isCopySource;
    if (reset) {
      setState(() {
        _offset = 0;
        _total = 0;
        _comics = [];
        _searching = true;
        // 一旦要出结果列表就收起全部题材网格，把纵向空间让给漫画。
        // 判据是「是否加载了结果」而不是「选的是不是全部」——点「全部」
        // 同样会拉出列表，那时也该收起。
        _tagsExpanded = false;
      });
    }
    try {
      final result = isCopy
          ? await _api.manga.getCopyComicList(
              ordering: _ordering,
              offset: _offset,
              theme: _selectedTag,
              top: _selectedTop,
            )
          : await _api.manga.getComicList(
              ordering: _ordering,
              offset: _offset,
              theme: _selectedTag,
            );
      if (!mounted || epoch != _loadEpoch) return;
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
          source: 'discover_tab.load_comics',
        ),
      );
      if (mounted && epoch == _loadEpoch) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _offset >= _total) return;
    final epoch = _loadEpoch;
    setState(() => _loadingMore = true);
    try {
      await _loadComics(reset: false);
      if (!mounted || epoch != _loadEpoch) return;
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
      } else {
        _loadingMore = false;
      }
    }
  }

  void _setOrdering(String value) {
    if (_ordering == value) return;
    setState(() => _ordering = value);
    _loadComics();
    _scrollToTop();
  }

  /// 选中题材 tag；传 null（点「全部」）即取消题材筛选，两者都重新拉列表。
  ///
  /// 与地区行是**可叠加**的维度（服务端实测 `top` + `theme` 同时生效），
  /// 所以这里不动 [_selectedTop]。收起网格由 [_loadComics] 统一处理。
  void _selectTag(String? tagPathWord) {
    setState(() {
      _selectedTag = tagPathWord;
      _searching = true;
      _offset = 0;
      _total = 0;
      _comics = [];
    });
    _loadComics();
  }

  /// 选中 / 切换 COPY 源的大分类（全部/日漫/韓漫/美漫/已完結），重新拉列表。
  ///
  /// 传 null（点「全部」）即不传 `top`，返回全量结果。
  /// 服务端的「日漫」本身也等价于不过滤——COPY 站以日漫为主体。
  ///
  /// 大分类与题材 tag 是**可叠加**的维度（服务端实测 `top` + `theme` 同时生效），
  /// 所以这里不动 [_selectedTag]，两者一起传下去。
  /// 收起网格由 [_loadComics] 统一处理。
  void _selectTop(String? topPathWord) {
    setState(() {
      _selectedTop = topPathWord;
      _searching = true;
      _offset = 0;
      _total = 0;
      _comics = [];
    });
    _loadComics();
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  /// 展开 / 收起全部题材网格。
  void _toggleTagsExpanded() {
    setState(() => _tagsExpanded = !_tagsExpanded);
  }

  /// 地区行选项：首位「全部」（值空串 = 不传 `top`）。
  ///
  /// 服务端的「日漫」本身也等价于不过滤（COPY 站以日漫为主体），但保留
  /// 「全部」作为语义明确的默认项。
  List<_ChipOption> _topOptions(AppLocalizations l10n) => [
    _ChipOption(
      label: l10n.downloadQueueFilterAll,
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

  /// 题材行选项：首位「全部」。不显示数量——横向单行里长数字会挤掉别的 tag。
  List<_ChipOption> _tagOptions(AppLocalizations l10n) => [
    _ChipOption(
      label: l10n.downloadQueueFilterAll,
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

  /// 排序行选项：热度 / 更新时间（必选其一，没有「全部」）。
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
            // 三行筛选固定在顶部、不参与滚动：地区（仅 COPY 源）/ 题材 / 排序。
            // 每行横向滚动、首项都是「全部」，选中态直接可见。
            Padding(
              padding: EdgeInsets.fromLTRB(hp, 12, hp, 0),
              child: Column(
                children: [
                  if (_copyFilters.tops.isNotEmpty) ...[
                    _FilterChipRow(
                      options: _topOptions(l10n),
                      onTap: (o) =>
                          _selectTop(o.value.isEmpty ? null : o.value),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  if (_tags.isNotEmpty) ...[
                    _FilterChipRow(
                      options: _tagOptions(l10n),
                      onTap: (o) =>
                          _selectTag(o.value.isEmpty ? null : o.value),
                      // 行尾展开/收起：题材有几十个，单行横向滚动只适合快速
                      // 切换常用项，找具体 tag 要铺开看（网格带数量）。
                      trailing: _tagsExpanded
                          ? null
                          : TextButton.icon(
                              onPressed: _toggleTagsExpanded,
                              icon: const Icon(Icons.expand_more, size: 20),
                              label: Text(l10n.tagsExpandAll),
                              style: TextButton.styleFrom(
                                foregroundColor: cs.primary,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                minimumSize: const Size(0, 34),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  _FilterChipRow(
                    options: _orderingOptions(l10n),
                    onTap: (o) => _setOrdering(o.value),
                    // 重置放在排序行尾（行内固定，不随 chips 滚动）。
                    trailing: _canResetFilters
                        ? TextButton.icon(
                            onPressed: _resetFilters,
                            icon: const Icon(Icons.restart_alt, size: 20),
                            label: Text(l10n.resetButton),
                            style: TextButton.styleFrom(
                              foregroundColor: cs.primary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              minimumSize: const Size(0, 34),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          )
                        : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _loadInit(forceRefresh: true),
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
                      if (_refreshing && _tags.isEmpty)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(child: ExpressiveLoadingIndicator()),
                        ),
                      // 全部题材网格：展开时铺在列表上方（带数量）。
                      if (_tagsExpanded && _tags.isNotEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(hp, 8, hp, 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        l10n.allTagsTitle,
                                        style: tt.titleSmall?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: _toggleTagsExpanded,
                                      icon: const Icon(
                                        Icons.expand_less,
                                        size: AppIconSize.lg,
                                      ),
                                      label: Text(l10n.tagsCollapseAll),
                                      style: TextButton.styleFrom(
                                        foregroundColor: cs.primary,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                        minimumSize: const Size(0, 34),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                _AllTagsGrid(
                                  tags: _tags,
                                  selectedTag: _selectedTag,
                                  onSelected: _selectTag,
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (_searching)
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(hp, 8, hp, 0),
                          sliver: SliverGrid(
                            delegate: SliverChildBuilderDelegate(
                              (_, _) => const ComicCardSkeleton(),
                              childCount: 21,
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
                      if (_comics.isNotEmpty)
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
                      if (_hasResults && _offset < _total)
                        SliverToBoxAdapter(
                          child: LoadMoreFooter(
                            loading: _loadingMore,
                            onPressed: _loadMore,
                            label: l10n.loadMoreProgress(_offset, _total),
                            horizontalPadding: hp,
                          ),
                        ),
                      // 底部留白：给悬浮按钮让位，并保证结果少时列表仍可滚动。
                      const SliverToBoxAdapter(child: SizedBox(height: 72)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        // 右下角：回到顶部（列表可向上滚动时）。
        // tag / 排序 / 重置都在顶部固定区可见可点，这里不再重复。
        if (_canScrollUp)
          Positioned(
            right: 16,
            bottom: 16,
            child: _BackToTopButton(onPressed: _scrollToTop),
          ),
        // 左下角常驻：数据源切换（与首页共用设置，默认 hot 并持久化）。
        Positioned(
          left: 16,
          bottom: 16,
          child: _SourceFab(
            isCopy: _isCopySource,
            onPressed: () =>
                _user.setMangaHomeSource(_isCopySource ? 'hot' : 'copy'),
          ),
        ),
      ],
    );
  }
}
