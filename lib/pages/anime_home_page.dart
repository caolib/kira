import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';

import '../l10n/app_localizations.dart';
import '../models/anime.dart';
import '../models/user_manager.dart';
import '../providers/app_providers.dart';
import '../providers/repository_providers.dart';
import '../repositories/anime_home_repository.dart';
import '../routing/app_router.dart';
import '../utils/app_logger.dart';
import '../utils/cover_brightness_filter.dart';
import '../utils/toast.dart';
import 'anime_list_page.dart';
import 'home_page.dart';

class AnimeHomePage extends ConsumerStatefulWidget {
  const AnimeHomePage({super.key});

  @override
  ConsumerState<AnimeHomePage> createState() => _AnimeHomePageState();
}

const _animeHomeCardWidth = 112.0;

class _AnimeHomePageState extends ConsumerState<AnimeHomePage> {
  AnimeHomeRepository get _repo => ref.read(animeHomeRepositoryProvider);
  UserManager get _user => ref.read(userManagerProvider);
  AnimeHome? _home;
  bool _loading = true;
  bool _refreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _user.addListener(_onUserChanged);
    _loadFromCache();
    _load();
  }

  @override
  void dispose() {
    _user.removeListener(_onUserChanged);
    super.dispose();
  }

  void _onUserChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadFromCache() async {
    final cached = await _repo.loadFromCache();
    if (!mounted || cached == null || !_loading) return;
    setState(() {
      _home = cached;
      _loading = false;
    });
  }

  Future<void> _load() async {
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
      final home = await _repo.load();
      if (!mounted) return;
      setState(() {
        _home = home;
        _loading = false;
        _refreshing = false;
      });
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'anime_home_page.load',
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

  void _openAnime(Anime anime) {
    if (anime.pathWord.isEmpty) {
      showToast(
        context,
        AppLocalizations.of(context)!.animeUnavailableToast,
        isError: true,
      );
      return;
    }
    context.pushNamed(
      AppRoutes.animeDetail,
      pathParameters: {'pathWord': anime.pathWord},
      extra: AnimeDetailExtra(initialAnime: anime.cover.isEmpty ? null : anime),
    );
  }

  void _openList(AnimeListType type) {
    context.pushNamed(AppRoutes.animeList, pathParameters: {'type': type.name});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth < 900 ? screenWidth : 900.0;
    final hp = (screenWidth - contentWidth) / 2 + 16;
    final home = _home;
    final bannerItems = home == null
        ? const <_AnimeBannerItem>[]
        : home.banners
              .map(_AnimeBannerItem.fromBanner)
              .where((item) => item.cover.isNotEmpty)
              .toList();

    if (_loading) return const Center(child: ExpressiveLoadingIndicator());

    if (_error != null && home == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 64, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(l10n.loadingFailed, style: tt.titleMedium),
            const SizedBox(height: 8),
            FilledButton.tonal(onPressed: _load, child: Text(l10n.retryButton)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.of(context).padding.top),
          ),
          if (_refreshing)
            const SliverToBoxAdapter(
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (bannerItems.isNotEmpty && _user.bannerVisible)
            SliverToBoxAdapter(
              child: _AnimeBannerCarousel(
                items: bannerItems,
                hp: hp,
                onTap: _openAnime,
              ),
            ),
          if (home != null && home.recommendations.isNotEmpty)
            _AnimeSection(
              title: l10n.animeEditorRecommend,
              icon: Icons.auto_awesome,
              hp: hp,
              onMore: () => _openList(AnimeListType.editor),
              child: _AnimeHorizontalList(
                items: home.recommendations,
                onTap: _openAnime,
              ),
            ),
          if (home != null && home.updates.isNotEmpty)
            _AnimeSection(
              title: l10n.animeRecentUpdate,
              icon: Icons.update,
              hp: hp,
              onMore: () => _openList(AnimeListType.updates),
              child: _AnimeUpdateGrid(items: home.updates, onTap: _openAnime),
            ),
          if (home != null && home.classics.isNotEmpty)
            _AnimeSection(
              title: l10n.animeClassicRecommend,
              icon: Icons.workspace_premium,
              hp: hp,
              onMore: () => _openList(AnimeListType.classics),
              child: _AnimeHorizontalList(
                items: home.classics,
                onTap: _openAnime,
              ),
            ),
          if (home != null && home.hots.isNotEmpty)
            _AnimeSection(
              title: l10n.animeHotAnime,
              icon: Icons.local_fire_department,
              hp: hp,
              onMore: () => _openList(AnimeListType.hots),
              child: _AnimeHorizontalList(items: home.hots, onTap: _openAnime),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
        ],
      ),
    );
  }
}

class _AnimeBannerItem {
  final String cover;
  final String title;
  final String brief;
  final Anime? anime;

  const _AnimeBannerItem({
    required this.cover,
    required this.title,
    required this.brief,
    this.anime,
  });

  factory _AnimeBannerItem.fromBanner(AnimeBanner banner) {
    final anime = banner.anime;
    final title = anime != null && anime.name.isNotEmpty
        ? anime.name
        : banner.brief;
    return _AnimeBannerItem(
      cover: banner.cover.isNotEmpty ? banner.cover : (anime?.cover ?? ''),
      title: title,
      brief: banner.brief,
      anime: anime,
    );
  }
}

class _AnimeBannerCarousel extends StatefulWidget {
  final List<_AnimeBannerItem> items;
  final double hp;
  final ValueChanged<Anime> onTap;

  const _AnimeBannerCarousel({
    required this.items,
    required this.hp,
    required this.onTap,
  });

  @override
  State<_AnimeBannerCarousel> createState() => _AnimeBannerCarouselState();
}

class _AnimeBannerCarouselState extends State<_AnimeBannerCarousel> {
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
  void didUpdateWidget(covariant _AnimeBannerCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      _page = _initialPage(widget.items.length);
      if (_controller.hasClients) {
        _controller.jumpToPage(_page);
      }
    }
    if (oldWidget.items.length != widget.items.length) {
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
                    child: _AnimeBannerCard(
                      item: item,
                      onTap: item.anime == null
                          ? null
                          : () => widget.onTap(item.anime!),
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

class _AnimeSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final double hp;
  final Widget child;
  final VoidCallback? onMore;

  const _AnimeSection({
    required this.title,
    required this.icon,
    required this.hp,
    required this.child,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
                        Text(
                          l10n.moreButton,
                          style: TextStyle(color: cs.primary),
                        ),
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

class _AnimeBannerCard extends StatelessWidget {
  final _AnimeBannerItem item;
  final VoidCallback? onTap;

  const _AnimeBannerCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
                placeholder: (_, _) =>
                    const _ImagePlaceholder(icon: Icons.movie),
                errorWidget: (_, _, _) =>
                    const _ImagePlaceholder(icon: Icons.broken_image),
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
                      style: tt.bodySmall?.copyWith(color: cs.surface),
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

class _AnimeHorizontalList extends StatelessWidget {
  final List<Anime> items;
  final ValueChanged<Anime> onTap;

  const _AnimeHorizontalList({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth < 900 ? screenWidth : 900.0;
    final hp = (screenWidth - contentWidth) / 2 + 16;

    return SizedBox(
      height: 198,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: hp),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final anime = items[i];
          return _AnimeCard(anime: anime, onTap: () => onTap(anime));
        },
      ),
    );
  }
}

class _AnimeUpdateGrid extends StatelessWidget {
  final List<AnimeUpdate> items;
  final ValueChanged<Anime> onTap;

  const _AnimeUpdateGrid({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth < 900 ? screenWidth : 900.0;
    final hp = (screenWidth - contentWidth) / 2 + 16;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.symmetric(horizontal: hp),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: _animeHomeCardWidth,
        childAspectRatio: 0.5,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemBuilder: (_, i) {
        final anime = items[i].anime;
        return _AnimeCard(anime: anime, onTap: () => onTap(anime));
      },
    );
  }
}

class _AnimeCard extends StatelessWidget {
  final Anime anime;
  final VoidCallback onTap;

  const _AnimeCard({required this.anime, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final meta = anime.count > 0
        ? l10n.totalEpisodes(anime.count)
        : (anime.company?.name ?? anime.years ?? '');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: _animeHomeCardWidth,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Card(
                clipBehavior: Clip.antiAlias,
                margin: EdgeInsets.zero,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CoverBrightnessFilter(
                      child: CachedNetworkImage(
                        imageUrl: anime.cover,
                        fit: BoxFit.cover,
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                        placeholder: (_, _) =>
                            const _ImagePlaceholder(icon: Icons.movie_outlined),
                        errorWidget: (_, _, _) =>
                            const _ImagePlaceholder(icon: Icons.broken_image),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              anime.name,
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
                  ComicCard.formatPopular(
                    anime.popular,
                    AppLocalizations.of(context)!,
                  ),
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      meta,
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
