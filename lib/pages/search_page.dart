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
import '../utils/screen_layout.dart';
import '../widgets/comic_card_skeleton.dart';
import '../widgets/comic_hero_tags.dart';
import '../widgets/load_more_footer.dart';
import 'home_page.dart' show ComicCard;

part 'search/search_data.dart';
part 'search/search_grids.dart';
part 'search/search_header.dart';

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

  /// extension part 文件里的成员不是 State 子类成员，不能直接调用受保护的
  /// [setState]，统一经由这个转发方法。
  void _setState(VoidCallback fn) => setState(fn);

  bool get _animeFeatureEnabled => _user.animeFeatureEnabled;
  bool get _isAnimeMode => _animeFeatureEnabled && _mode == _SearchMode.anime;
  String _modeLabel(AppLocalizations l10n) =>
      _isAnimeMode ? l10n.animeLabel : l10n.comicLabel;

  /// tag 数量的紧凑显示：11376 -> 1.1万。与漫画详情页 formatPopular 同规则。
  String _formatTagCount(AppLocalizations l10n, int n) {
    if (n >= 100000000) {
      return l10n.hundredMillionUnit((n / 100000000).toStringAsFixed(1));
    }
    if (n >= 10000) {
      return l10n.tenThousandUnit((n / 10000).toStringAsFixed(1));
    }
    return n.toString();
  }
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
    final hp = ScreenLayout.horizontalPadding(screenWidth);
    final cardExtent = ScreenLayout.cardExtent(screenWidth);

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
                  // 近底自动翻页只在用户确实滚动过后才触发（pixels > 0）。
                  // 否则首屏结果不满一屏时（宽屏），布局期通知的
                  // pixels=0 > maxScrollExtent-300 恒成立，一搜索就连发两页；
                  // 不满屏的场景交给显式「加载更多」按钮兜底。
                  if (_hasResults &&
                      n.metrics.pixels > 0 &&
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
                      padding: EdgeInsets.fromLTRB(hp, 8, hp, 0),
                      sliver: SliverGrid(
                        delegate: SliverChildBuilderDelegate(
                          (_, _) => const ComicCardSkeleton(),
                          childCount: 20,
                        ),
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: cardExtent,
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
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
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
                                      // 数字作为次级信息内联在名字后：
                                      // 小一号 + onSurfaceVariant，避免
                                      // 4~5 位长数字喧宾夺主。
                                      label: Text.rich(
                                        TextSpan(
                                          text: t.name,
                                          children: [
                                            if (t.count > 0)
                                              TextSpan(
                                                text:
                                                    ' ${_formatTagCount(l10n, t.count)}',
                                                // chip 未选中态 label 默认色
                                                // 就是 onSurfaceVariant，需再
                                                // 降透明度才能与名字拉开层次。
                                                style: tt.bodySmall?.copyWith(
                                                  color: cs.onSurfaceVariant
                                                      .withValues(
                                                        alpha: 0.7,
                                                      ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      showCheckmark: false,
                                      onSelected: (_) =>
                                          _selectTag(t.pathWord),
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
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
                      padding: EdgeInsets.fromLTRB(hp, 8, hp, 0),
                      sliver: SliverGrid(
                        delegate: SliverChildBuilderDelegate(
                          (_, _) => const ComicCardSkeleton(),
                          childCount: 21,
                        ),
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: cardExtent,
                          childAspectRatio: 0.55,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
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
                      cardExtent: cardExtent,
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
                      cardExtent: cardExtent,
                      loadingMore: _loadingMore,
                      onOpen: _openAnime,
                    ),
                  // 显式加载更多按钮：宽屏下一页结果不满屏、列表不可滚动时，
                  // 近底自动加载永远等不到触发，这里是兜底入口。
                  if (_hasResults && _offset < _total)
                    SliverToBoxAdapter(
                      child: LoadMoreFooter(
                        loading: _loadingMore,
                        onPressed: _loadMore,
                        label: l10n.loadMoreProgress(_offset, _total),
                        horizontalPadding: hp,
                      ),
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
}
