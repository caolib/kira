import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';

import '../l10n/app_localizations.dart';
import '../models/comic.dart' hide Theme;
import '../models/user_manager.dart';
import '../providers/app_providers.dart';
import '../providers/repository_providers.dart';
import '../repositories/manga_home_repository.dart';
import '../routing/app_router.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/app_logger.dart';
import '../utils/cover_brightness_filter.dart';
import '../utils/settings_rebuild_guard.dart';
import '../utils/time_format.dart';
import '../widgets/comic_card_surface.dart';
import '../widgets/comic_hero_tags.dart';

part 'home/home_banner.dart';
part 'home/home_cards.dart';
part 'home/home_copy_widgets.dart';
part 'home/home_sections.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

const _mangaHomeCardWidth = 112.0;
const _mangaHomeCardAspectRatio = 0.55;
const _mangaHomeCardSpacing = 12.0;

/// 卡片最大宽度随可用宽度增大：手机保持 112，宽屏（横屏/桌面窗口）
/// 提到 150，避免大屏幕上一排挤十几张小卡片。
double _mangaHomeCardMaxExtent(double availableWidth) =>
    availableWidth >= 720 ? 150.0 : _mangaHomeCardWidth;

double _mangaHomeGridCardWidth(
  double crossAxisExtent, {
  double? maxCardExtent,
}) {
  final extent = maxCardExtent ?? _mangaHomeCardWidth;
  // 列数向上取整后再均分，与 maxCrossAxisExtent 网格的铺排一致。
  final crossAxisCount = math.max(
    1,
    (crossAxisExtent / (extent + _mangaHomeCardSpacing)).ceil(),
  );
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

class _HomePageState extends ConsumerState<HomePage>
    with SettingsRebuildGuard<HomePage> {
  MangaHomeRepository get _repo => ref.read(mangaHomeRepositoryProvider);
  UserManager get _user => ref.read(userManagerProvider);
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
    _user.addListener(handleSettingsChanged);
    _activeSource = _user.mangaHomeSource;
    _loadFromCache();
    _load();
  }

  @override
  void dispose() {
    _user.removeListener(handleSettingsChanged);
    super.dispose();
  }

  /// 首页只用到这两项；其余设置（阅读器亮度等）变化时不再重建整棵树。
  @override
  Object watchedSettings() => (_user.bannerVisible, _user.mangaHomeSource);

  @override
  void onWatchedSettingsChanged() {
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
      final cached = await _repo.loadBFromCache();
      if (!mounted || cached == null || !_loading) return;
      setState(() {
        _copyHome = cached.home;
        _loading = false;
      });
      return;
    }
    final cached = await _repo.loadAFromCache();
    if (!mounted || cached == null || !_loading) return;
    setState(() {
      _home = cached.home;
      _rankingPreview = cached.ranking;
      _loading = false;
    });
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (_isCopySource) return _loadCopy(forceRefresh: forceRefresh);
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
      final data = await _repo.loadA();
      if (!mounted) return;
      setState(() {
        _home = data.home;
        _rankingPreview = data.ranking;
        _loading = false;
        _refreshing = false;
      });
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'home_page.load',
        ),
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadCopy({bool forceRefresh = false}) async {
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
      final data = await _repo.loadB();
      if (!mounted) return;
      setState(() {
        _copyHome = data.home;
        _loading = false;
        _refreshing = false;
      });
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'home_page.load_copy',
        ),
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = e.toString();
      });
    }
  }

  void _openComic(Comic comic, String heroTagBase) {
    context.pushNamed(
      AppRoutes.comicDetail,
      pathParameters: {'pathWord': comic.pathWord},
      extra: ComicDetailExtra(initialComic: comic, heroTagBase: heroTagBase),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    // 不再 clamp 到 900：横屏双栏 + 卡片上限 150 自适应铺满，宽屏不留大空白。
    const hp = 16.0;
    final home = _home;
    final copyHome = _copyHome;
    final isCopy = _isCopySource;

    if (_loading) {
      return Scaffold(
        floatingActionButton: _buildSourceFab(),
        body: const Center(child: ExpressiveLoadingIndicator()),
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
              const SizedBox(height: AppSpacing.lg),
              Text(
                AppLocalizations.of(context)!.loadingFailed,
                style: tt.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton.tonal(
                onPressed: _load,
                child: Text(AppLocalizations.of(context)!.retryButton),
              ),
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
      final Widget? bannerCarousel =
          bannerItems.isNotEmpty && _user.bannerVisible
          ? _MangaBannerCarousel(
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
            )
          : null;
      // 宽屏：推荐（左）与排行榜（右）并排，避免纵向叠加留大片空白。
      final twoPane =
          screenWidth >= 720 &&
          home.recommendations.isNotEmpty &&
          _rankingPreview.isNotEmpty;
      if (twoPane) {
        slivers.add(
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final halfWidth =
                    (constraints.crossAxisExtent - _mangaHomeCardSpacing) / 2;
                return SliverToBoxAdapter(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 宽屏下 banner 与推荐同栏同宽（半栏 16:9），不再整行居中。
                            if (bannerCarousel != null) ...[
                              _PaneScope(
                                width: halfWidth,
                                child: bannerCarousel,
                              ),
                              const SizedBox(height: 12),
                            ],
                            _SectionHeader(
                              title: AppLocalizations.of(context)!.hotRecommend,
                              icon: Icons.auto_awesome,
                              onMore: () =>
                                  context.pushNamed(AppRoutes.recommend),
                            ),
                            const SizedBox(height: 6),
                            _PaneScope(
                              width: halfWidth,
                              child: _MangaHorizontalList(
                                items: home.recommendations,
                                onTap: _openComic,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: _mangaHomeCardSpacing),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SectionHeader(
                              title: AppLocalizations.of(context)!.comicRanking,
                              icon: Icons.leaderboard,
                              onMore: () =>
                                  context.pushNamed(AppRoutes.ranking),
                            ),
                            const SizedBox(height: 6),
                            _PaneScope(
                              width: halfWidth,
                              child: _RankingPaneGrid(
                                items: _rankingPreview,
                                onTap: _openComic,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      } else if (home.recommendations.isNotEmpty) {
        if (!twoPane && bannerCarousel != null) {
          slivers.add(SliverToBoxAdapter(child: bannerCarousel));
        }
        slivers.add(
          _MangaSection(
            title: AppLocalizations.of(context)!.hotRecommend,
            icon: Icons.auto_awesome,
            hp: hp,
            onMore: () => context.pushNamed(AppRoutes.recommend),
            child: _MangaHorizontalList(
              items: home.recommendations,
              onTap: _openComic,
            ),
          ),
        );
      }
      if (!twoPane && bannerCarousel != null && home.recommendations.isEmpty) {
        slivers.add(SliverToBoxAdapter(child: bannerCarousel));
      }
      if (!twoPane && _rankingPreview.isNotEmpty) {
        slivers.add(
          _SectionTitle(
            title: AppLocalizations.of(context)!.comicRanking,
            icon: Icons.leaderboard,
            hp: hp,
            onMore: () => context.pushNamed(AppRoutes.ranking),
          ),
        );
        slivers.add(
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: hp),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final cardExtent = _mangaHomeCardMaxExtent(
                  constraints.crossAxisExtent,
                );
                return SliverGrid(
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
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: cardExtent,
                    childAspectRatio: _mangaHomeCardAspectRatio,
                    mainAxisSpacing: _mangaHomeCardSpacing,
                    crossAxisSpacing: _mangaHomeCardSpacing,
                  ),
                );
              },
            ),
          ),
        );
      }
    }

    slivers.add(const SliverPadding(padding: EdgeInsets.only(bottom: 88)));

    return Scaffold(
      floatingActionButton: _buildSourceFab(),
      body: RefreshIndicator(
        onRefresh: () => _load(forceRefresh: true),
        child: CustomScrollView(slivers: slivers),
      ),
    );
  }

  /// 右下角切换 hot / copy 首页数据源的悬浮按钮，图标旁显示当前数据源
  Widget _buildSourceFab() {
    final isCopy = _isCopySource;
    return FloatingActionButton.extended(
      heroTag: 'home-source-switch',
      tooltip: isCopy
          ? AppLocalizations.of(context)!.switchToHotHome
          : AppLocalizations.of(context)!.switchToCopyHome,
      onPressed: () => _user.setMangaHomeSource(isCopy ? 'hot' : 'copy'),
      icon: const Icon(Icons.swap_horiz, size: 20),
      label: Text(
        isCopy
            ? AppLocalizations.of(context)!.homeSourceCopy
            : AppLocalizations.of(context)!.homeSourceHot,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  /// COPY 首页各板块
  List<Widget> _buildCopySlivers(CopyMangaHome home, double hp) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final bannerSlivers = <Widget>[];
    final sections = <Widget>[];
    final primarySections = <Widget>[];
    final secondarySections = <Widget>[];
    Widget? bannerCarousel;

    final bannerItems = home.banners
        .map(_MangaBannerItem.fromBanner)
        .where((item) => item.cover.isNotEmpty)
        .toList();
    if (bannerItems.isNotEmpty && _user.bannerVisible) {
      bannerCarousel = _MangaBannerCarousel(
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
      );
      bannerSlivers.add(SliverToBoxAdapter(child: bannerCarousel));
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
      final section = _CopyCollapsibleSection(
        storageKey: scope,
        title: title,
        icon: icon,
        hp: hp,
        onMore: onMore,
        topPadding: topPadding,
        child: twoRowGrid
            ? _CopyTwoRowComicGrid(items: list, onTap: _openComic, scope: scope)
            : _CopyHorizontalComicList(
                items: list,
                onTap: _openComic,
                scope: scope,
              ),
      );
      // 宽屏双栏时推荐/排行榜进左窄栏，其余板块进右宽栏。
      (scope == 'copy-rec' || scope == 'copy-ranking'
              ? primarySections
              : secondarySections)
          .add(section);
      sections.add(section);
    }

    addSection(
      l10n.copyRecommend,
      Icons.auto_awesome,
      home.recComics,
      scope: 'copy-rec',
      topPadding: 8,
      onMore: () => context.pushNamed(
        AppRoutes.copyMangaList,
        pathParameters: {'kind': 'recommendations'},
      ),
    );
    if (home.rankDayComics.isNotEmpty ||
        home.rankWeekComics.isNotEmpty ||
        home.rankMonthComics.isNotEmpty) {
      final rankingSection = _CopyCollapsibleSection(
        storageKey: 'copy-ranking',
        title: l10n.copyRanking,
        icon: Icons.leaderboard,
        hp: hp,
        onMore: () => context.pushNamed(
          AppRoutes.copyMangaList,
          pathParameters: {'kind': 'ranking'},
        ),
        child: _CopyRankingTabs(
          dayItems: home.rankDayComics,
          weekItems: home.rankWeekComics,
          monthItems: home.rankMonthComics,
          onTap: _openComic,
        ),
      );
      primarySections.add(rankingSection);
      sections.add(rankingSection);
    }
    addSection(
      l10n.copyHotUpdate,
      Icons.local_fire_department,
      home.hotComics,
      scope: 'copy-hot',
    );
    addSection(
      l10n.copyNewArrival,
      Icons.fiber_new,
      home.newComics,
      scope: 'copy-new',
      onMore: () => context.pushNamed(
        AppRoutes.copyMangaList,
        pathParameters: {'kind': 'newest'},
      ),
    );
    addSection(
      l10n.copyFinished,
      Icons.done_all,
      home.finishComics,
      scope: 'copy-finish',
      onMore: () => context.pushNamed(
        AppRoutes.copyMangaList,
        pathParameters: {'kind': 'finished'},
      ),
    );

    final slivers = <Widget>[];
    if (sections.isEmpty) {
      slivers.addAll(bannerSlivers);
      slivers.add(
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 64,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(l10n.noContent, style: tt.titleMedium),
              ],
            ),
          ),
        ),
      );
    } else if (MediaQuery.sizeOf(context).width >= 720) {
      // 宽屏：左窄栏放 banner + 推荐 + 排行榜，右宽栏放其余板块（2:3）。
      final left = <Widget>[
        if (bannerCarousel != null)
          Padding(
            padding: EdgeInsets.fromLTRB(hp, 8, hp, 12),
            child: bannerCarousel,
          ),
        ...primarySections,
      ];
      final right = secondarySections;
      slivers.add(
        SliverToBoxAdapter(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(flex: 2, child: Column(children: left)),
              const SizedBox(width: _mangaHomeCardSpacing),
              Flexible(flex: 3, child: Column(children: right)),
            ],
          ),
        ),
      );
    } else {
      // 竖屏：banner 在顶部全宽，板块逐块纵向叠放。
      // _CopyCollapsibleSection 已是普通盒子组件，需各自包 SliverToBoxAdapter。
      slivers.addAll(bannerSlivers);
      slivers.addAll([
        for (final section in sections) SliverToBoxAdapter(child: section),
      ]);
    }

    return slivers;
  }
}
