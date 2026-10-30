import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/novel/novel_api.dart' show novelErrorMessage;
import '../l10n/app_localizations.dart';
import '../models/novel.dart';
import '../providers/novel_providers.dart';
import '../repositories/novel_home_repository.dart';
import '../routing/app_router.dart';
import '../routing/branch_activation.dart';
import '../theme/app_icon_sizes.dart';
import '../theme/app_spacing.dart';
import '../utils/app_logger.dart';
import '../utils/screen_layout.dart';
import '../widgets/back_to_top_button.dart';
import '../widgets/branch_bottom_slack.dart';
import '../widgets/error_retry_view.dart';
import '../widgets/filter_chip_row.dart';
import '../widgets/load_more_footer.dart';
import '../widgets/nav_bar_inset.dart';
import '../widgets/novel_hero_tags.dart';
import '../widgets/novel_paged_controller.dart';
import '../widgets/novel_widgets.dart';
import '../widgets/result_scroll_listener.dart';
import '../widgets/section_header.dart';
import '../widgets/shimmer_skeleton.dart';

enum _NovelOrdering {
  popular('-popular'),
  updated('-datetime_updated');

  const _NovelOrdering(this.value);

  final String value;

  String label(AppLocalizations l10n) => switch (this) {
    _NovelOrdering.popular => l10n.popularOrder,
    _NovelOrdering.updated => l10n.updateOrder,
  };
}

/// 轻小说标签页：上方是体裁筛选 + 热度/更新排序的书籍列表（与「发现」页同构），
/// 输入关键词后切换为 `/api/v3/search/books` 的搜索结果。
///
/// 小说题材来自 `/api/v3/theme/book/count`，与漫画的 `/api/v3/theme/comic/count`
/// 是两套数据，所以筛选必须留在这里而不能并入「发现」页。
class NovelSearchTab extends ConsumerStatefulWidget {
  const NovelSearchTab({super.key});

  @override
  ConsumerState<NovelSearchTab> createState() => _NovelSearchTabState();
}

class _NovelSearchTabState extends ConsumerState<NovelSearchTab>
    with AutomaticKeepAliveClientMixin, BranchDeferredInit {
  static const _kBodyExpanded = 'novel_search_tags_expanded';

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _scrollController = ScrollController();
  late final NovelPagedController<NovelBook> _books;
  late final NovelPagedController<NovelBook> _results;

  List<NovelTag> _themes = [];
  String _theme = '';
  _NovelOrdering _ordering = _NovelOrdering.popular;
  String? _query;
  bool _themesLoading = true;
  bool _themesFailed = false;
  Object? _themesError;
  bool _tagListExpanded = false;
  bool _hasSearchText = false;
  bool _canScrollUp = false;
  int _themesEpoch = 0;

  /// 仅分支首次激活的默认首屏读缓存仓库；消费一次后所有加载直连 API。
  bool _initialListLoad = true;

  late final _themesRepo = NovelThemesRepository(
    api: ref.read(novelApiProvider),
  );
  late final _popularListRepo = NovelPopularListRepository(
    api: ref.read(novelApiProvider),
  );

  bool get _idle => _query == null;

  /// 搜索态用 [_results]，浏览态用 [_books]；两者互斥显示。
  NovelPagedController<NovelBook> get _visible => _idle ? _books : _results;

  bool get _visibleEmpty => _visible.items.isEmpty;

  bool get _visibleFailed => _visible.items.isEmpty && _visible.error != null;

  bool get _canRequestMore =>
      !_visible.loading &&
      !_visibleEmpty &&
      _visible.hasMore &&
      _visible.refreshError == null;

  bool get _canLoadMore => _canRequestMore && _visible.error == null;

  /// 切走再切回时保留关键词、筛选与滚动位置。
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchTextChanged);
    _books = NovelPagedController<NovelBook>(
      loadPage: _loadBookPage,
      keyOf: (book) => book.pathWord,
    )..addListener(_rebuild);
    _results = NovelPagedController<NovelBook>(
      loadPage: (offset) => ref
          .read(novelApiProvider)
          .searchBooks(keyword: _query ?? '', offset: offset),
      keyOf: (book) => book.pathWord,
    )..addListener(_rebuild);
    deferInitialLoadToBranchActivation();
  }

  @override
  void onBranchFirstActivated() {
    unawaited(_loadThemes(useCache: true));
    unawaited(_restoreBodyState());
    unawaited(_books.refresh());
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchTextChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    _scrollController.dispose();
    _books.dispose();
    _results.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _onSearchTextChanged() {
    final hasText = _searchController.text.isNotEmpty;
    if (!mounted || hasText == _hasSearchText) return;
    setState(() => _hasSearchText = hasText);
  }

  /// 默认条件（全部题材 + 热度）的 offset 0 首屏在分支首次激活时走仓库
  /// 缓存（TTL 1 天，标志消费一次即失效）；切题材/排序/重置/下拉刷新/
  /// 加载更多一律直连 API，保证用户主动操作总能看到最新列表。
  Future<NovelPage<NovelBook>> _loadBookPage(int offset) async {
    final isDefaultQuery =
        _theme.isEmpty && _ordering == _NovelOrdering.popular;
    if (offset == 0 && _initialListLoad && isDefaultQuery) {
      _initialListLoad = false;
      final data = await _popularListRepo.load();
      return NovelPage<NovelBook>(
        list: data.list,
        total: data.total,
        limit: 18,
        offset: 0,
      );
    }
    return ref
        .read(novelApiProvider)
        .getBooks(theme: _theme, ordering: _ordering.value, offset: offset);
  }

  /// [useCache] 仅在分支首次激活时为 true：TTL 内直接读缓存不发请求。
  /// 下拉刷新等后续操作直连 API。
  Future<void> _loadThemes({bool useCache = false}) async {
    final epoch = ++_themesEpoch;
    setState(() {
      _themesLoading = true;
      _themesFailed = false;
    });
    try {
      final themes = useCache
          ? (await _themesRepo.load()).themes
          : await ref.read(novelApiProvider).getThemes();
      if (!mounted || epoch != _themesEpoch) return;
      setState(() => _themes = themes);
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'novel_search.themes',
        ),
      );
      if (mounted && epoch == _themesEpoch) {
        setState(() {
          _themesFailed = true;
          _themesError = e;
        });
      }
    } finally {
      if (mounted && epoch == _themesEpoch) {
        setState(() => _themesLoading = false);
      }
    }
  }

  Future<void> _restoreBodyState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _tagListExpanded = prefs.getBool(_kBodyExpanded) ?? false;
      });
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'novel_search.restore_state',
        ),
      );
    }
  }

  Future<void> _persistBodyState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kBodyExpanded, _tagListExpanded);
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'novel_search.save_state',
        ),
      );
    }
  }

  void _toggleTagList() {
    setState(() => _tagListExpanded = !_tagListExpanded);
    unawaited(_persistBodyState());
  }

  Future<void> _doSearch(String query) async {
    final keyword = query.trim();
    if (keyword.isEmpty) return;
    _searchFocus.unfocus();
    setState(() {
      _query = keyword;
      _tagListExpanded = false;
    });
    await _results.refresh();
    if (mounted) unawaited(_scrollToTop());
  }

  void _clearSearch() {
    // 浏览列表不受搜索请求影响，无需丢弃它的分页状态。
    _results.clear();
    _searchController.clear();
    setState(() => _query = null);
  }

  Future<void> _selectTheme(String theme) async {
    // 展开的题材网格中选中后收起，让结果列表直接可见。
    if (_tagListExpanded) {
      setState(() => _tagListExpanded = false);
      unawaited(_persistBodyState());
    }
    if (_theme == theme) return;
    setState(() => _theme = theme);
    await _books.refresh();
    if (mounted) unawaited(_scrollToTop());
  }

  Future<void> _selectOrdering(_NovelOrdering ordering) async {
    if (_ordering == ordering) return;
    setState(() => _ordering = ordering);
    await _books.refresh();
    if (mounted) unawaited(_scrollToTop());
  }

  void _resetFilters() {
    if (_theme.isEmpty && _ordering == _NovelOrdering.popular) return;
    setState(() {
      _theme = '';
      _ordering = _NovelOrdering.popular;
      _tagListExpanded = false;
    });
    unawaited(_books.refresh());
    unawaited(_scrollToTop());
  }

  Future<void> _refresh() async {
    if (!_idle) {
      await _results.refresh(keepItems: true);
      return;
    }
    await Future.wait([_books.refresh(keepItems: true), _loadThemes()]);
  }

  Future<void> _loadMore({bool retry = false}) async {
    if (!_canRequestMore || (_visible.error != null && !retry)) return;
    await _visible.loadMore();
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _openBook(NovelBook book, String? heroTagBase) =>
      context.pushNamed(
        AppRoutes.novelDetail,
        pathParameters: {'pathWord': book.pathWord},
        extra: NovelDetailExtra(initialBook: book, heroTagBase: heroTagBase),
      );

  List<FilterChipOption> _themeOptions(AppLocalizations l10n) => [
    FilterChipOption(
      label: l10n.novelAllThemes,
      value: '',
      icon: Icons.local_offer_outlined,
      selected: _theme.isEmpty,
    ),
    for (final theme in _themes)
      FilterChipOption(
        label: theme.name,
        value: theme.pathWord,
        selected: _theme == theme.pathWord,
      ),
  ];

  List<FilterChipOption> _orderingOptions(AppLocalizations l10n) => [
    for (final ordering in _NovelOrdering.values)
      FilterChipOption(
        label: ordering.label(l10n),
        value: ordering.value,
        icon: ordering == _NovelOrdering.popular
            ? Icons.whatshot
            : Icons.schedule,
        selected: _ordering == ordering,
      ),
  ];

  Widget _buildFilters(AppLocalizations l10n, double hp) {
    return Padding(
      padding: EdgeInsets.fromLTRB(hp, AppSpacing.md, hp, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_themesLoading || _books.loading) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (_themesFailed)
            InlineRetryNotice(
              message: novelErrorMessage(
                _themesError,
                fallback: l10n.novelThemesFailed,
              ),
              onRetry: () => unawaited(_loadThemes()),
            ),
          FilterChipRow(
            options: _orderingOptions(l10n),
            onTap: (option) => unawaited(
              _selectOrdering(
                _NovelOrdering.values.firstWhere(
                  (value) => value.value == option.value,
                ),
              ),
            ),
            // 行尾固定：重置只在有筛选时出现。
            trailing: _theme.isEmpty && _ordering == _NovelOrdering.popular
                ? null
                : FilterRowResetButton(
                    onPressed: _resetFilters,
                    icon: Icons.restart_alt,
                    label: l10n.resetButton,
                  ),
          ),
          // 展开时只渲染下面的题材网格，不再重复一条横向 chip 行。
          if (_themes.isNotEmpty && !_tagListExpanded) ...[
            const SizedBox(height: AppSpacing.sm),
            FilterChipRow(
              options: _themeOptions(l10n),
              onTap: (option) => unawaited(_selectTheme(option.value)),
              trailing: FilterTagsToggleButton(
                expanded: false,
                onPressed: _toggleTagList,
              ),
            ),
          ],
          if (_themes.isNotEmpty && _tagListExpanded) ...[
            const SizedBox(height: AppSpacing.sm),
            SectionHeader(
              title: l10n.allTagsTitle,
              trailing: FilterTagsToggleButton(
                expanded: true,
                onPressed: _toggleTagList,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            AllTagsGrid(
              tags: [
                for (final theme in _themes)
                  FilterTagOption(
                    name: theme.name,
                    pathWord: theme.pathWord,
                    count: theme.count,
                  ),
              ],
              selectedTag: _theme.isEmpty ? null : _theme,
              onSelected: (value) => unawaited(_selectTheme(value ?? '')),
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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final hp = ScreenLayout.horizontalPadding(screenWidth);

    return Stack(
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
                hintText: l10n.novelSearchHint,
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
                      // 浏览态保留筛选区，搜索态整块换成结果。
                      if (_idle)
                        SliverToBoxAdapter(child: _buildFilters(l10n, hp)),
                      if (_visible.loading && _visibleEmpty)
                        SliverPadding(
                          padding: EdgeInsets.symmetric(horizontal: hp),
                          sliver: ComicCoverSkeletonGrid(
                            count: 8,
                            gridDelegate: novelGridDelegate(
                              context,
                              screenWidth - hp * 2,
                            ),
                          ),
                        )
                      else if (_visibleFailed)
                        SliverErrorRetryView(
                          message: novelErrorMessage(
                            _idle ? _books.error : _results.error,
                            fallback: _idle
                                ? l10n.novelLoadFailed
                                : l10n.novelSearchFailed,
                          ),
                          onRetry: _idle
                              ? () => unawaited(_books.refresh())
                              : () => unawaited(_results.refresh()),
                        )
                      else if (_visibleEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Padding(
                            padding: EdgeInsets.all(hp),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off_rounded,
                                  size: AppIconSize.empty,
                                  color: cs.onSurfaceVariant,
                                ),
                                const SizedBox(height: AppSpacing.lg),
                                Text(
                                  _idle
                                      ? l10n.novelEmptyBooks
                                      : l10n.novelSearchEmpty,
                                  textAlign: TextAlign.center,
                                  style: tt.titleMedium,
                                ),
                              ],
                            ),
                          ),
                        )
                      else ...[
                        if (!_idle && _visible.refreshing)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                hp,
                                0,
                                hp,
                                AppSpacing.sm,
                              ),
                              child: const LinearProgressIndicator(),
                            ),
                          ),
                        if (_visible.refreshError != null)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: hp),
                              child: InlineRetryNotice(
                                message: novelErrorMessage(
                                  _visible.refreshError,
                                  fallback: _idle
                                      ? l10n.novelLoadFailed
                                      : l10n.novelSearchFailed,
                                ),
                                onRetry: () => unawaited(
                                  _visible.refresh(keepItems: true),
                                ),
                              ),
                            ),
                          ),
                        if (!_idle)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                hp,
                                0,
                                hp,
                                AppSpacing.md,
                              ),
                              child: Text(
                                l10n.searchResultSummary(
                                  _query!,
                                  _results.items.length,
                                  l10n.novelTitle,
                                ),
                                style: tt.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        SliverPadding(
                          padding: EdgeInsets.symmetric(horizontal: hp),
                          sliver: SliverGrid(
                            gridDelegate: novelGridDelegate(
                              context,
                              screenWidth - hp * 2,
                            ),
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final book = _visible.items[index];
                              final heroTagBase = NovelHeroTags.base(
                                scope: 'novel-search',
                                pathWord: book.pathWord,
                                index: index,
                              );
                              return NovelBookCard(
                                book: book,
                                heroTagBase: heroTagBase,
                                onTap: () =>
                                    unawaited(_openBook(book, heroTagBase)),
                              );
                            }, childCount: _visible.items.length),
                          ),
                        ),
                      ],
                      if (!_visibleEmpty &&
                          _visible.hasMore &&
                          !_visible.refreshing &&
                          _visible.refreshError == null)
                        SliverToBoxAdapter(
                          child: LoadMoreFooter(
                            loading: _visible.loading,
                            onPressed: () => _loadMore(retry: true),
                            label: _visible.error == null
                                ? l10n.loadMore
                                : l10n.novelLoadMoreFailed,
                            detail: _visible.error == null
                                ? null
                                : novelErrorMessage(_visible.error),
                            horizontalPadding: hp,
                          ),
                        ),
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
  }
}
