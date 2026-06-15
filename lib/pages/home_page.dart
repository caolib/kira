import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/comic.dart' hide Theme;
import '../models/user_manager.dart';
import '../utils/cover_brightness_filter.dart';
import '../utils/comic_hero_tags.dart';
import '../utils/data_cache.dart';
import 'comic_detail_page.dart';
import 'copy_manga_list_page.dart';
import 'recommend_page.dart';
import 'ranking_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

const _mangaHomeCardWidth = 112.0;
const _mangaHomeCardAspectRatio = 0.55;
const _mangaHomeCardSpacing = 12.0;

int _mangaHomeGridColumnCount(double crossAxisExtent) {
  return math.max(
    1,
    (crossAxisExtent / (_mangaHomeCardWidth + _mangaHomeCardSpacing)).ceil(),
  );
}

double _mangaHomeGridCardWidth(double crossAxisExtent) {
  final crossAxisCount = _mangaHomeGridColumnCount(crossAxisExtent);
  final usableCrossAxisExtent = math.max(
    0.0,
    crossAxisExtent - _mangaHomeCardSpacing * (crossAxisCount - 1),
  );
  return usableCrossAxisExtent / crossAxisCount;
}

double _copySectionContentWidth(
  BuildContext context,
  BoxConstraints constraints,
) {
  if (constraints.maxWidth.isFinite && constraints.maxWidth > 0) {
    return constraints.maxWidth;
  }
  final screenWidth = MediaQuery.of(context).size.width;
  final contentWidth = screenWidth.clamp(0.0, 900.0).toDouble();
  return math.max(1.0, contentWidth - 56);
}

class _HomePageState extends State<HomePage> {
  static const _cacheKey = 'manga_home_v1';
  static const _copyCacheKey = 'manga_home_copy_v1';
  static const _rankingOrdering = '-datetime_updated';

  final _api = ApiClient();
  final _cache = DataCache();
  final _user = UserManager();
  MangaHome? _home;
  CopyMangaHome? _copyHome;
  String? _activeSource; // 当前已加载的数据源
  List<Comic> _rankingPreview = [];
  bool _loading = true;
  bool _refreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _user.addListener(_onUserChanged);
    _activeSource = _user.mangaHomeSource;
    _loadFromCache();
    _load();
  }

  @override
  void dispose() {
    _user.removeListener(_onUserChanged);
    super.dispose();
  }

  void _onUserChanged() {
    if (!mounted) return;
    // 数据源切换时重新加载对应数据
    if (_activeSource != _user.mangaHomeSource) {
      _activeSource = _user.mangaHomeSource;
      _loading = true;
      _error = null;
      _home = null;
      _copyHome = null;
      _loadFromCache();
      _load();
    }
    setState(() {});
  }

  bool get _isCopySource => _user.mangaHomeSource == 'copy';

  Future<void> _loadFromCache() async {
    if (_isCopySource) {
      final cached = await _cache.get(_copyCacheKey);
      if (!mounted || cached == null || !_loading) return;
      setState(() {
        _copyHome = CopyMangaHome.fromJson(
          Map<String, dynamic>.from(cached['home']),
        );
        _loading = false;
      });
      return;
    }
    final cached = await _cache.get(_cacheKey);
    if (!mounted || cached == null || !_loading) return;
    setState(() {
      _home = MangaHome.fromJson(Map<String, dynamic>.from(cached['home']));
      _rankingPreview =
          (cached['ranking'] as List?)
              ?.map((j) => Comic.fromJson(j))
              .toList() ??
          [];
      _loading = false;
    });
  }

  Future<void> _load() async {
    if (_isCopySource) return _loadCopy();
    final hasData = _home != null;
    if (!hasData) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _refreshing = true);
    }
    try {
      final homeFuture = _api.getMangaHome();
      final rankingFuture = _api.getComicList(
        ordering: _rankingOrdering,
        limit: 6,
      );
      final home = await homeFuture;
      final ranking = await rankingFuture;
      if (!mounted) return;
      setState(() {
        _home = home;
        _rankingPreview = ranking.list;
        _loading = false;
        _refreshing = false;
      });
      _cache.put(_cacheKey, {
        'home': home.toJson(),
        'ranking': ranking.list.map((c) => c.toJson()).toList(),
      });
    } catch (e) {
      debugPrint('HomePage load error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadCopy() async {
    final hasData = _copyHome != null;
    if (!hasData) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _refreshing = true);
    }
    try {
      final home = await _api.getCopyMangaHome();
      if (!mounted) return;
      setState(() {
        _copyHome = home;
        _loading = false;
        _refreshing = false;
      });
      _cache.put(_copyCacheKey, {'home': home.toJson()});
    } catch (e) {
      debugPrint('HomePage copy load error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = e.toString();
      });
    }
  }

  void _openComic(Comic comic, String heroTagBase) {
    Navigator.push(
      context,
      ComicDetailPage.route(
        pathWord: comic.pathWord,
        initialComic: comic,
        heroTagBase: heroTagBase,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth.clamp(0.0, 900.0);
    final hp = (screenWidth - contentWidth) / 2 + 16;
    final home = _home;
    final copyHome = _copyHome;
    final isCopy = _isCopySource;

    if (_loading) {
      return Scaffold(
        floatingActionButton: _buildSourceFab(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final hasData = isCopy ? copyHome != null : home != null;
    if (_error != null && !hasData) {
      return Scaffold(
        floatingActionButton: _buildSourceFab(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 64, color: cs.onSurfaceVariant),
              const SizedBox(height: 16),
              Text('加载失败', style: tt.titleMedium),
              const SizedBox(height: 8),
              FilledButton.tonal(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: SizedBox(height: MediaQuery.of(context).padding.top),
      ),
      if (_refreshing)
        const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
    ];

    if (isCopy && copyHome != null) {
      slivers.addAll(_buildCopySlivers(copyHome, hp));
    } else if (home != null) {
      final bannerItems = home.banners
          .map(_MangaBannerItem.fromBanner)
          .where((item) => item.cover.isNotEmpty)
          .toList();
      if (bannerItems.isNotEmpty && _user.bannerVisible) {
        slivers.add(
          SliverToBoxAdapter(
            child: _MangaBannerCarousel(
              items: bannerItems,
              hp: hp,
              onTap: (comic) => _openComic(
                comic,
                ComicHeroTags.base(
                  scope: 'home-banner',
                  pathWord: comic.pathWord,
                  index: 0,
                ),
              ),
            ),
          ),
        );
      }
      if (home.recommendations.isNotEmpty) {
        slivers.add(
          _MangaSection(
            title: '热门推荐',
            icon: Icons.auto_awesome,
            hp: hp,
            onMore: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RecommendPage()),
            ),
            child: _MangaHorizontalList(
              items: home.recommendations,
              onTap: _openComic,
            ),
          ),
        );
      }
      if (_rankingPreview.isNotEmpty) {
        slivers.add(
          _SectionTitle(
            title: '漫画排行',
            icon: Icons.leaderboard,
            hp: hp,
            onMore: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RankingPage()),
            ),
          ),
        );
        slivers.add(
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: hp),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate((_, i) {
                final comic = _rankingPreview[i];
                final heroTagBase = ComicHeroTags.base(
                  scope: 'home-ranking',
                  pathWord: comic.pathWord,
                  index: i,
                );
                return ComicCard(
                  comic: comic,
                  heroTagBase: heroTagBase,
                  onTap: () => _openComic(comic, heroTagBase),
                );
              }, childCount: _rankingPreview.length),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: _mangaHomeCardWidth,
                childAspectRatio: _mangaHomeCardAspectRatio,
                mainAxisSpacing: _mangaHomeCardSpacing,
                crossAxisSpacing: _mangaHomeCardSpacing,
              ),
            ),
          ),
        );
      }
    }

    slivers.add(const SliverPadding(padding: EdgeInsets.only(bottom: 88)));

    return Scaffold(
      floatingActionButton: _buildSourceFab(),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(slivers: slivers),
      ),
    );
  }

  /// 右下角切换 hot / copy 首页数据源的悬浮按钮
  Widget _buildSourceFab() {
    final isCopy = _isCopySource;
    return FloatingActionButton.small(
      heroTag: 'home-source-switch',
      tooltip: isCopy ? '切换到 HOT 首页' : '切换到 COPY 首页',
      onPressed: () => _user.setMangaHomeSource(isCopy ? 'hot' : 'copy'),
      child: const Icon(Icons.swap_horiz),
    );
  }

  /// COPY 首页各板块
  List<Widget> _buildCopySlivers(CopyMangaHome home, double hp) {
    final slivers = <Widget>[];

    final bannerItems = home.banners
        .map(_MangaBannerItem.fromBanner)
        .where((item) => item.cover.isNotEmpty)
        .toList();
    if (bannerItems.isNotEmpty && _user.bannerVisible) {
      slivers.add(
        SliverToBoxAdapter(
          child: _MangaBannerCarousel(
            items: bannerItems,
            hp: hp,
            onTap: (comic) => _openComic(
              comic,
              ComicHeroTags.base(
                scope: 'copy-banner',
                pathWord: comic.pathWord,
                index: 0,
              ),
            ),
          ),
        ),
      );
    }

    void addSection(
      String title,
      IconData icon,
      List<Comic> list, {
      required String scope,
      bool twoRowGrid = false,
      VoidCallback? onMore,
      double topPadding = 0,
    }) {
      if (list.isEmpty) return;
      slivers.add(
        _CopyCollapsibleSection(
          storageKey: scope,
          title: title,
          icon: icon,
          hp: hp,
          onMore: onMore,
          topPadding: topPadding,
          child: twoRowGrid
              ? _CopyTwoRowComicGrid(
                  items: list,
                  onTap: _openComic,
                  scope: scope,
                )
              : _CopyHorizontalComicList(
                  items: list,
                  onTap: _openComic,
                  scope: scope,
                ),
        ),
      );
    }

    addSection(
      '推荐',
      Icons.auto_awesome,
      home.recComics,
      scope: 'copy-rec',
      topPadding: 8,
      onMore: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const CopyMangaListPage.recommendations(),
        ),
      ),
    );
    if (home.rankDayComics.isNotEmpty ||
        home.rankWeekComics.isNotEmpty ||
        home.rankMonthComics.isNotEmpty) {
      slivers.add(
        _CopyCollapsibleSection(
          storageKey: 'copy-ranking',
          title: '排行榜',
          icon: Icons.leaderboard,
          hp: hp,
          onMore: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const CopyMangaListPage.ranking(),
            ),
          ),
          child: _CopyRankingTabs(
            dayItems: home.rankDayComics,
            weekItems: home.rankWeekComics,
            monthItems: home.rankMonthComics,
            onTap: _openComic,
          ),
        ),
      );
    }
    addSection(
      '热门更新',
      Icons.local_fire_department,
      home.hotComics,
      scope: 'copy-hot',
    );
    addSection(
      '全新上架',
      Icons.fiber_new,
      home.newComics,
      scope: 'copy-new',
      onMore: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CopyMangaListPage.newest()),
      ),
    );
    addSection(
      '已完结',
      Icons.done_all,
      home.finishComics,
      scope: 'copy-finish',
      onMore: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CopyMangaListPage.finished()),
      ),
    );

    return slivers;
  }
}

// ── Banner ──

class _MangaBannerItem {
  final String cover;
  final String title;
  final String brief;
  final Comic? comic;

  const _MangaBannerItem({
    required this.cover,
    required this.title,
    required this.brief,
    this.comic,
  });

  factory _MangaBannerItem.fromBanner(MangaBanner banner) {
    final comic = banner.comic;
    final title = comic != null && comic.name.isNotEmpty
        ? comic.name
        : banner.brief;
    return _MangaBannerItem(
      cover: banner.cover.isNotEmpty ? banner.cover : (comic?.cover ?? ''),
      title: title,
      brief: banner.brief,
      comic: comic,
    );
  }
}

class _MangaBannerCarousel extends StatefulWidget {
  final List<_MangaBannerItem> items;
  final double hp;
  final ValueChanged<Comic> onTap;

  const _MangaBannerCarousel({
    required this.items,
    required this.hp,
    required this.onTap,
  });

  @override
  State<_MangaBannerCarousel> createState() => _MangaBannerCarouselState();
}

class _MangaBannerCarouselState extends State<_MangaBannerCarousel> {
  late final PageController _controller;
  Timer? _timer;
  late int _page;

  @override
  void initState() {
    super.initState();
    _page = _initialPage(widget.items.length);
    _controller = PageController(initialPage: _page);
    _restartTimer();
  }

  @override
  void didUpdateWidget(covariant _MangaBannerCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      _page = _initialPage(widget.items.length);
      if (_controller.hasClients) {
        _controller.jumpToPage(_page);
      }
      _restartTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (widget.items.length <= 1) return;
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _nextPage(restartTimer: false),
    );
  }

  int _initialPage(int count) {
    return count > 1 ? count * 1000 : 0;
  }

  void _nextPage({bool restartTimer = true}) {
    if (!mounted || widget.items.length <= 1) return;
    if (!_controller.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _nextPage(restartTimer: restartTimer),
      );
      return;
    }
    _animateToPage(_page + 1, restartTimer: restartTimer);
  }

  void _animateToPage(int page, {bool restartTimer = true}) {
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
    if (restartTimer) {
      _restartTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        SizedBox(
          height: 176,
          child: Stack(
            children: [
              PageView.builder(
                controller: _controller,
                physics: const PageScrollPhysics(),
                itemCount: widget.items.length > 1 ? null : widget.items.length,
                onPageChanged: (page) => setState(() => _page = page),
                itemBuilder: (_, i) {
                  final item = widget.items[i % widget.items.length];
                  return Padding(
                    padding: EdgeInsets.only(
                      left: widget.hp,
                      right: widget.hp,
                      bottom: 8,
                    ),
                    child: _MangaBannerCard(
                      item: item,
                      onTap: item.comic == null
                          ? null
                          : () => widget.onTap(item.comic!),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        if (widget.items.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.items.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: i == _page % widget.items.length ? 16 : 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: i == _page % widget.items.length
                          ? cs.primary
                          : cs.onSurfaceVariant.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MangaBannerCard extends StatelessWidget {
  final _MangaBannerItem item;
  final VoidCallback? onTap;

  const _MangaBannerCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CoverBrightnessFilter(
              child: CachedNetworkImage(
                imageUrl: item.cover,
                fit: BoxFit.cover,
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                placeholder: (_, _) => _ImagePlaceholder(icon: Icons.book),
                errorWidget: (_, _, _) =>
                    _ImagePlaceholder(icon: Icons.broken_image),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.72),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (item.title.isNotEmpty)
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  if (item.brief.isNotEmpty && item.brief != item.title) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.brief,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section & Card ──

class _MangaSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final double hp;
  final Widget child;
  final VoidCallback? onMore;

  const _MangaSection({
    required this.title,
    required this.icon,
    required this.hp,
    required this.child,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(hp, 0, hp, 6),
            child: Row(
              children: [
                Icon(icon, size: 20, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (onMore != null)
                  TextButton(
                    onPressed: onMore,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('更多', style: TextStyle(color: cs.primary)),
                        Icon(Icons.chevron_right, size: 18, color: cs.primary),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _CopyCollapsibleSection extends StatefulWidget {
  final String storageKey;
  final String title;
  final IconData icon;
  final double hp;
  final Widget child;
  final VoidCallback? onMore;
  final double topPadding;

  const _CopyCollapsibleSection({
    required this.storageKey,
    required this.title,
    required this.icon,
    required this.hp,
    required this.child,
    this.onMore,
    this.topPadding = 0,
  });

  @override
  State<_CopyCollapsibleSection> createState() =>
      _CopyCollapsibleSectionState();
}

class _CopyCollapsibleSectionState extends State<_CopyCollapsibleSection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = !UserManager().isCopyHomeSectionCollapsed(widget.storageKey);
  }

  void _toggleExpanded() {
    final expanded = !_expanded;
    setState(() => _expanded = expanded);
    unawaited(
      UserManager().setCopyHomeSectionCollapsed(widget.storageKey, !expanded),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          widget.hp,
          widget.topPadding,
          widget.hp,
          12,
        ),
        child: Material(
          color: cs.surfaceContainerLow,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.72)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: _toggleExpanded,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                  child: Row(
                    children: [
                      Icon(widget.icon, size: 20, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (widget.onMore != null)
                        TextButton(
                          onPressed: widget.onMore,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('更多', style: TextStyle(color: cs.primary)),
                              Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: cs.primary,
                              ),
                            ],
                          ),
                        ),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        child: Icon(
                          Icons.expand_more,
                          size: 22,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ClipRect(
                child: AnimatedAlign(
                  alignment: Alignment.topCenter,
                  heightFactor: _expanded ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: widget.child,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CopyHorizontalComicList extends StatelessWidget {
  final List<Comic> items;
  final void Function(Comic, String) onTap;
  final String scope;

  const _CopyHorizontalComicList({
    required this.items,
    required this.onTap,
    required this.scope,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const _CopyEmptySectionMessage();

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = math.max(
          1.0,
          _copySectionContentWidth(context, constraints),
        );
        final cardWidth = _mangaHomeGridCardWidth(contentWidth);
        final cardHeight = cardWidth / _mangaHomeCardAspectRatio;

        return SizedBox(
          height: cardHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: items.length,
            itemBuilder: (_, i) {
              final comic = items[i];
              final heroTagBase = ComicHeroTags.base(
                scope: scope,
                pathWord: comic.pathWord,
                index: i,
              );
              return _MangaCard(
                comic: comic,
                width: cardWidth,
                heroTagBase: heroTagBase,
                onTap: () => onTap(comic, heroTagBase),
              );
            },
          ),
        );
      },
    );
  }
}

class _CopyTwoRowComicGrid extends StatelessWidget {
  final List<Comic> items;
  final void Function(Comic, String) onTap;
  final String scope;

  const _CopyTwoRowComicGrid({
    required this.items,
    required this.onTap,
    required this.scope,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const _CopyEmptySectionMessage();

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = math.max(
          1.0,
          _copySectionContentWidth(context, constraints),
        );
        final cardWidth = _mangaHomeGridCardWidth(contentWidth);
        final cardHeight = cardWidth / _mangaHomeCardAspectRatio;
        final visibleRows = math.min(2, items.length);
        final gridHeight =
            cardHeight * visibleRows +
            _mangaHomeCardSpacing * (visibleRows - 1);

        return SizedBox(
          height: gridHeight,
          child: GridView.builder(
            primary: false,
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            physics: const ClampingScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: visibleRows,
              childAspectRatio: 1 / _mangaHomeCardAspectRatio,
              mainAxisSpacing: _mangaHomeCardSpacing,
              crossAxisSpacing: _mangaHomeCardSpacing,
            ),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final comic = items[i];
              final heroTagBase = ComicHeroTags.base(
                scope: scope,
                pathWord: comic.pathWord,
                index: i,
              );
              return ComicCard(
                comic: comic,
                heroTagBase: heroTagBase,
                onTap: () => onTap(comic, heroTagBase),
              );
            },
          ),
        );
      },
    );
  }
}

class _CopyRankingTabs extends StatefulWidget {
  final List<Comic> dayItems;
  final List<Comic> weekItems;
  final List<Comic> monthItems;
  final void Function(Comic, String) onTap;

  const _CopyRankingTabs({
    required this.dayItems,
    required this.weekItems,
    required this.monthItems,
    required this.onTap,
  });

  @override
  State<_CopyRankingTabs> createState() => _CopyRankingTabsState();
}

class _CopyRankingTabsState extends State<_CopyRankingTabs>
    with SingleTickerProviderStateMixin {
  late final TabController _controller;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Comic> _itemsForIndex(int index) {
    if (index == 0) return widget.dayItems;
    if (index == 1) return widget.weekItems;
    return widget.monthItems;
  }

  String _scopeForIndex(int index) {
    if (index == 0) return 'copy-rank-day';
    if (index == 1) return 'copy-rank-week';
    return 'copy-rank-month';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final items = _itemsForIndex(_selectedIndex);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.44),
            borderRadius: BorderRadius.circular(8),
          ),
          child: TabBar(
            controller: _controller,
            onTap: (index) => setState(() => _selectedIndex = index),
            dividerColor: Colors.transparent,
            indicator: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            indicatorPadding: const EdgeInsets.all(4),
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: cs.onPrimaryContainer,
            unselectedLabelColor: cs.onSurfaceVariant,
            labelStyle: tt.labelMedium?.copyWith(fontWeight: FontWeight.bold),
            unselectedLabelStyle: tt.labelMedium,
            splashBorderRadius: BorderRadius.circular(8),
            tabs: const [
              Tab(text: '日榜'),
              Tab(text: '周榜'),
              Tab(text: '月榜'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _CopyTwoRowComicGrid(
          items: items,
          onTap: widget.onTap,
          scope: _scopeForIndex(_selectedIndex),
        ),
      ],
    );
  }
}

class _CopyEmptySectionMessage extends StatelessWidget {
  const _CopyEmptySectionMessage();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SizedBox(
      height: 96,
      child: Center(
        child: Text(
          '暂无内容',
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _MangaHorizontalList extends StatelessWidget {
  final List<Comic> items;
  final void Function(Comic, String) onTap;

  const _MangaHorizontalList({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth < 900 ? screenWidth : 900.0;
    final hp = (screenWidth - contentWidth) / 2 + 16;
    final cardWidth = _mangaHomeGridCardWidth(contentWidth - 32);
    final cardHeight = cardWidth / _mangaHomeCardAspectRatio;

    return SizedBox(
      height: cardHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: hp),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final comic = items[i];
          final heroTagBase = ComicHeroTags.base(
            scope: 'home-recommend',
            pathWord: comic.pathWord,
            index: i,
          );
          return _MangaCard(
            comic: comic,
            width: cardWidth,
            heroTagBase: heroTagBase,
            onTap: () => onTap(comic, heroTagBase),
          );
        },
      ),
    );
  }
}

class _MangaCard extends StatelessWidget {
  final Comic comic;
  final double width;
  final String? heroTagBase;
  final VoidCallback onTap;

  const _MangaCard({
    required this.comic,
    required this.width,
    this.heroTagBase,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        margin: const EdgeInsets.only(right: _mangaHomeCardSpacing),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _hero(
                ComicHeroTags.cover,
                Card(
                  clipBehavior: Clip.antiAlias,
                  margin: EdgeInsets.zero,
                  child: CoverBrightnessFilter(
                    child: CachedNetworkImage(
                      imageUrl: comic.cover,
                      fit: BoxFit.cover,
                      width: width,
                      height: double.infinity,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      placeholder: (_, _) => Container(
                        color: cs.surfaceContainerHighest,
                        child: Center(
                          child: Icon(
                            Icons.image,
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
            ),
            const SizedBox(height: 6),
            Text(
              comic.name,
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
                  ComicCard.formatPopular(comic.popular),
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
                if (comic.authors.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      comic.authors.map((a) => a.name).join(' / '),
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
      ),
    );
  }

  Widget _hero(String Function(String base) tagOf, Widget child) {
    final base = heroTagBase;
    if (base == null) return child;
    return Hero(
      tag: tagOf(base),
      createRectTween: ComicHeroTags.createRectTween,
      placeholderBuilder: _buildHeroPlaceholder,
      child: child,
    );
  }

  Widget _buildHeroPlaceholder(
    BuildContext context,
    Size heroSize,
    Widget child,
  ) {
    return SizedBox(width: heroSize.width, height: heroSize.height);
  }
}

// ── 通用组件 ──

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  final double hp;
  final VoidCallback? onMore;
  const _SectionTitle({
    required this.title,
    required this.icon,
    required this.hp,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(hp, 0, hp - 8, 6),
        child: Row(
          children: [
            Icon(icon, size: 20, color: cs.primary),
            const SizedBox(width: 6),
            Text(
              title,
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            if (onMore != null)
              TextButton(
                onPressed: onMore,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('更多', style: TextStyle(color: cs.primary)),
                    Icon(Icons.chevron_right, size: 18, color: cs.primary),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  final IconData icon;

  const _ImagePlaceholder({required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerHighest,
      child: Center(child: Icon(icon, color: cs.onSurfaceVariant, size: 32)),
    );
  }
}

/// 漫画网格卡片，多页面复用
class ComicCard extends StatelessWidget {
  final Comic comic;
  final String? heroTagBase;
  final VoidCallback onTap;
  const ComicCard({
    super.key,
    required this.comic,
    this.heroTagBase,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final title = Text(
      comic.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: tt.bodySmall,
    );

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _hero(
              ComicHeroTags.cover,
              Card(
                clipBehavior: Clip.antiAlias,
                margin: EdgeInsets.zero,
                child: CoverBrightnessFilter(
                  child: CachedNetworkImage(
                    imageUrl: comic.cover,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    placeholder: (_, _) => Container(
                      color: cs.surfaceContainerHighest,
                      child: Center(
                        child: Icon(
                          Icons.image,
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
          ),
          const SizedBox(height: 6),
          title,
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.local_fire_department, size: 12, color: cs.primary),
              const SizedBox(width: 2),
              Flexible(
                child: Text(
                  formatPopular(comic.popular),
                  overflow: TextOverflow.ellipsis,
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              ),
              if (comic.datetimeUpdated != null) ...[
                const SizedBox(width: 4),
                Text(
                  formatRelativeTime(comic.datetimeUpdated!),
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _hero(String Function(String base) tagOf, Widget child) {
    final base = heroTagBase;
    if (base == null) return child;
    return Hero(
      tag: tagOf(base),
      createRectTween: ComicHeroTags.createRectTween,
      placeholderBuilder: _buildHeroPlaceholder,
      child: child,
    );
  }

  Widget _buildHeroPlaceholder(
    BuildContext context,
    Size heroSize,
    Widget child,
  ) {
    return SizedBox(width: heroSize.width, height: heroSize.height);
  }

  static String formatPopular(int n) {
    if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}亿';
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    return n.toString();
  }

  static String formatRelativeTime(String dateStr) {
    final date = DateTime.tryParse(dateStr);
    if (date == null) return dateStr;
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 30) return '${diff.inDays}天前';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}个月前';
    return '${(diff.inDays / 365).floor()}年前';
  }
}
