import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
import '../l10n/app_localizations.dart';
import '../models/anime.dart';
import '../models/comic.dart' hide Theme;
import '../models/user_manager.dart';
import '../routing/app_router.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/app_logger.dart';
import '../utils/cover_brightness_filter.dart';
import '../utils/network_error.dart';
import '../utils/screen_layout.dart';
import '../utils/time_format.dart';
import '../utils/toast.dart';
import '../widgets/comic_hero_tags.dart';
import '../widgets/load_more_footer.dart';

enum _HistoryMode { comic, anime }

class BrowseHistoryPage extends StatefulWidget {
  final WidgetBuilder loginPageBuilder;

  const BrowseHistoryPage({super.key, required this.loginPageBuilder});

  @override
  State<BrowseHistoryPage> createState() => _BrowseHistoryPageState();
}

class _BrowseHistoryPageState extends State<BrowseHistoryPage> {
  final _api = ApiClient();
  final _user = UserManager();

  _HistoryMode _mode = _HistoryMode.comic;
  List<BrowseHistoryItem> _comicItems = [];
  List<AnimeBrowseHistoryItem> _animeItems = [];
  bool _loading = true;
  bool _refreshing = false;
  bool _loadingMore = false;
  bool _showingLoginPrompt = false;
  int _offset = 0;
  int _total = 0;

  bool get _animeFeatureEnabled => _user.animeFeatureEnabled;
  bool get _isAnimeMode => _animeFeatureEnabled && _mode == _HistoryMode.anime;
  String _modeLabel(AppLocalizations l10n) =>
      _isAnimeMode ? l10n.animeLabel : l10n.comicLabel;
  bool get _currentItemsEmpty =>
      _isAnimeMode ? _animeItems.isEmpty : _comicItems.isEmpty;
  int get _currentLength =>
      _isAnimeMode ? _animeItems.length : _comicItems.length;

  @override
  void initState() {
    super.initState();
    _user.addListener(_onUserChanged);
    if (_user.isLoggedIn) {
      _load(silent: true);
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _user.removeListener(_onUserChanged);
    super.dispose();
  }

  void _onUserChanged() {
    if (!mounted) return;
    if (!_animeFeatureEnabled && _mode == _HistoryMode.anime) {
      setState(() {
        _mode = _HistoryMode.comic;
        _clearItems();
      });
    }
    if (_user.isLoggedIn) {
      _load(silent: true, force: true);
    } else {
      setState(() {
        _clearItems();
        _loading = false;
      });
    }
  }

  void _clearItems() {
    _comicItems = [];
    _animeItems = [];
    _offset = 0;
    _total = 0;
  }

  Future<void> _clearHistory() async {
    final l10n = AppLocalizations.of(context)!;
    final modeLabel = _modeLabel(l10n);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.browseHistoryClearTitle),
        content: Text(l10n.browseHistoryClearContent(modeLabel)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.cacheClearButton),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      if (_isAnimeMode) {
        await _api.user.clearAnimeBrowseHistory();
      } else {
        await _api.user.clearBrowseHistory();
      }
      if (!mounted) return;
      showToast(context, l10n.browseHistoryCleared(modeLabel));
      setState(_clearItems);
    } catch (e) {
      if (!mounted) return;
      showToast(
        context,
        l10n.browseHistoryClearFailed(NetworkError.message(e, l10n: l10n)),
        isError: true,
      );
    }
  }

  Future<void> _load({bool silent = false, bool force = false}) async {
    if (_refreshing && !force) return;
    final l10n = AppLocalizations.of(context)!;
    final mode = _mode;
    _refreshing = true;
    final isInitial = _currentItemsEmpty;
    if (isInitial) {
      setState(() => _loading = true);
    } else {
      setState(() {});
    }
    _offset = 0;

    try {
      if (mode == _HistoryMode.anime) {
        final data = await _api.anime.getAnimeBrowseHistory();
        if (!mounted || _mode != mode) return;
        setState(() {
          _animeItems = data.list;
          _total = data.total;
          _offset = data.list.length;
          _loading = false;
        });
      } else {
        final data = await _api.user.getBrowseHistory();
        if (!mounted || _mode != mode) return;
        setState(() {
          _comicItems = data.list;
          _total = data.total;
          _offset = data.list.length;
          _loading = false;
        });
      }
      if (!silent && mounted) {
        showToast(context, l10n.refreshSuccess);
      }
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'browse_history_page.load',
        ),
      );
      if (isInitial && mounted) setState(() => _loading = false);
      if (_isUnauthorized(e)) {
        await _handleUnauthorized();
      } else if (!silent && mounted) {
        showToast(context, l10n.refreshFailed, isError: true);
      }
    } finally {
      _refreshing = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _refreshing || _offset >= _total) return;
    final mode = _mode;
    setState(() => _loadingMore = true);
    try {
      if (mode == _HistoryMode.anime) {
        final data = await _api.anime.getAnimeBrowseHistory(offset: _offset);
        if (!mounted || _mode != mode) return;
        setState(() {
          _animeItems.addAll(data.list);
          _offset = _animeItems.length;
        });
      } else {
        final data = await _api.user.getBrowseHistory(offset: _offset);
        if (!mounted || _mode != mode) return;
        setState(() {
          _comicItems.addAll(data.list);
          _offset = _comicItems.length;
        });
      }
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'browse_history_page.load_more',
        ),
      );
      if (_isUnauthorized(e)) {
        await _handleUnauthorized();
      }
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
      } else {
        _loadingMore = false;
      }
    }
  }

  void _setMode(_HistoryMode mode) {
    if (mode == _HistoryMode.anime && !_animeFeatureEnabled) return;
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _clearItems();
    });
    if (_user.isLoggedIn) {
      _load(silent: true);
    }
  }

  bool _isUnauthorized(Object error) =>
      error is DioException && error.response?.statusCode == 401;

  Future<void> _handleUnauthorized() async {
    if (_showingLoginPrompt || !mounted) return;
    final l10n = AppLocalizations.of(context)!;

    if (_user.autoLogin) {
      await _user.logout();
      if (mounted) {
        showToast(context, l10n.autoLoginFailed, isError: true);
      }
      return;
    }

    _showingLoginPrompt = true;

    await _user.logout();
    if (!mounted) {
      _showingLoginPrompt = false;
      return;
    }

    final shouldLogin = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.loginExpiredTitle),
        content: Text(l10n.browseHistoryLoginExpiredContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.laterButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.goLoginButton),
          ),
        ],
      ),
    );

    if (shouldLogin == true && mounted) {
      await _goLogin();
    } else if (mounted) {
      showToast(context, l10n.browseHistoryLoginToView, isError: true);
    }

    _showingLoginPrompt = false;
  }

  Future<void> _goLogin() async {
    final loggedIn = await context.pushNamed<bool>(AppRoutes.login);
    if (loggedIn == true && mounted) {
      unawaited(_load(silent: true));
    }
  }

  void _openAnime(AnimeBrowseHistoryItem item) {
    if (!_animeFeatureEnabled) return;
    if (item.anime.pathWord.isEmpty) return;
    context.pushNamed(
      AppRoutes.animeDetail,
      pathParameters: {'pathWord': item.anime.pathWord},
      extra: AnimeDetailExtra(initialAnime: item.anime),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final modeLabel = _modeLabel(l10n);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final hp = ScreenLayout.horizontalPadding(screenWidth);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.browseHistoryTitle),
        actions: [
          if (_user.isLoggedIn && !_currentItemsEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.browseHistoryClearTitle,
              onPressed: _clearHistory,
            ),
        ],
      ),
      body: !_user.isLoggedIn
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 64,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      l10n.browseHistoryLoginToView,
                      style: tt.titleMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _animeFeatureEnabled
                          ? l10n.browseHistoryLoginHintWithAnime
                          : l10n.browseHistoryLoginHintComicOnly,
                      textAlign: TextAlign.center,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton.icon(
                      onPressed: _goLogin,
                      icon: const Icon(Icons.login),
                      label: Text(l10n.goLoginButton),
                    ),
                  ],
                ),
              ),
            )
          : _loading
          ? CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (_animeFeatureEnabled)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(hp, 12, hp, 8),
                      child: SegmentedButton<_HistoryMode>(
                        segments: [
                          ButtonSegment(
                            value: _HistoryMode.comic,
                            label: Text(l10n.comicLabel),
                            icon: const Icon(Icons.menu_book_outlined),
                          ),
                          ButtonSegment(
                            value: _HistoryMode.anime,
                            label: Text(l10n.animeLabel),
                            icon: const Icon(Icons.movie_outlined),
                          ),
                        ],
                        selected: {_mode},
                        onSelectionChanged: (v) => _setMode(v.first),
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(hp, 0, hp, 24),
                  sliver: SliverList.builder(
                    itemCount: 20,
                    itemBuilder: (_, _) => const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: _HistoryCardSkeleton(),
                    ),
                  ),
                ),
              ],
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  // pixels > 0：只在用户确实滚动过后才自动翻页，
                  // 否则宽屏首屏不满一页时会立刻连发第二页。
                  if (!_currentItemsEmpty &&
                      n.metrics.pixels > 0 &&
                      n.metrics.pixels > n.metrics.maxScrollExtent - 300) {
                    _loadMore();
                  }
                  return false;
                },
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    if (_refreshing)
                      const SliverToBoxAdapter(
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    if (_animeFeatureEnabled)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(hp, 12, hp, 8),
                          child: SegmentedButton<_HistoryMode>(
                            segments: [
                              ButtonSegment(
                                value: _HistoryMode.comic,
                                label: Text(l10n.comicLabel),
                                icon: const Icon(Icons.menu_book_outlined),
                              ),
                              ButtonSegment(
                                value: _HistoryMode.anime,
                                label: Text(l10n.animeLabel),
                                icon: const Icon(Icons.movie_outlined),
                              ),
                            ],
                            selected: {_mode},
                            onSelectionChanged: (v) => _setMode(v.first),
                          ),
                        ),
                      ),
                    if (_currentItemsEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.history,
                                  size: 64,
                                  color: cs.onSurfaceVariant,
                                ),
                                const SizedBox(height: AppSpacing.lg),
                                Text(
                                  l10n.browseHistoryEmptyTitle(modeLabel),
                                  style: tt.titleMedium?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  l10n.browseHistoryEmptySubtitle(modeLabel),
                                  textAlign: TextAlign.center,
                                  style: tt.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.lg),
                                FilledButton.tonalIcon(
                                  onPressed: _user.isLoggedIn ? _load : null,
                                  icon: const Icon(Icons.refresh),
                                  label: Text(l10n.refreshButton),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(hp, 4, hp, 8),
                          child: Text(
                            l10n.browseHistoryTotal(_total, modeLabel),
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(hp, 0, hp, 24),
                        sliver: SliverList.builder(
                          itemCount: _currentLength,
                          itemBuilder: (_, i) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _isAnimeMode
                                  ? _AnimeBrowseHistoryCard(
                                      item: _animeItems[i],
                                      onTap: () => _openAnime(_animeItems[i]),
                                    )
                                  : _ComicBrowseHistoryCard(
                                      item: _comicItems[i],
                                    ),
                            );
                          },
                        ),
                      ),
                      if (_offset < _total)
                        SliverToBoxAdapter(
                          child: LoadMoreFooter(
                            loading: _loadingMore,
                            onPressed: _loadMore,
                            label: l10n.loadMoreProgress(_offset, _total),
                            horizontalPadding: hp,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  static String formatPopular(BuildContext context, int n) {
    final l10n = AppLocalizations.of(context)!;
    if (n >= 100000000) {
      return l10n.hundredMillionUnit((n / 100000000).toStringAsFixed(1));
    }
    if (n >= 10000) {
      return l10n.tenThousandUnit((n / 10000).toStringAsFixed(1));
    }
    return n.toString();
  }
}

class _ComicBrowseHistoryCard extends StatelessWidget {
  final BrowseHistoryItem item;
  const _ComicBrowseHistoryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final comic = item.comic;
    final authors = comic.authors.map((e) => e.name).where((e) => e.isNotEmpty);
    final heroTagBase = ComicHeroTags.base(
      scope: 'browse-history',
      pathWord: comic.pathWord,
      index: item.id,
    );

    return _HistoryCardShell(
      onTap: () => context.pushNamed(
        AppRoutes.comicDetail,
        pathParameters: {'pathWord': comic.pathWord},
        extra: ComicDetailExtra(
          initialComic: comic,
          heroTagBase: heroTagBase,
          lastBrowseId: item.lastBrowseId,
          lastBrowseName: item.lastBrowseName,
        ),
      ),
      cover: _hero(
        heroTagBase,
        ComicHeroTags.cover,
        _HistoryCover(imageUrl: comic.cover, icon: Icons.image),
      ),
      title: comic.name,
      subtitle: authors.isEmpty ? null : authors.join(' / '),
      lastBrowseName: item.lastBrowseName,
      lastBrowseIcon: Icons.menu_book_outlined,
      latestText:
          comic.lastChapterName == null || comic.lastChapterName!.isEmpty
          ? null
          : AppLocalizations.of(
              context,
            )!.browseHistoryLatestChapter(comic.lastChapterName!),
      chips: [
        _HistoryMetaChip(
          icon: Icons.local_fire_department,
          label: _BrowseHistoryPageState.formatPopular(context, comic.popular),
        ),
        if (comic.datetimeUpdated != null)
          _HistoryMetaChip(
            icon: Icons.schedule,
            label: TimeFormat.relativeOf(
              comic.datetimeUpdated!,
              AppLocalizations.of(context)!,
            ),
          ),
      ],
    );
  }

  Widget _hero(
    String heroTagBase,
    String Function(String base) tagOf,
    Widget child,
  ) {
    return Hero(
      tag: tagOf(heroTagBase),
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

class _AnimeBrowseHistoryCard extends StatelessWidget {
  final AnimeBrowseHistoryItem item;
  final VoidCallback onTap;

  const _AnimeBrowseHistoryCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final anime = item.anime;
    final subtitle = [
      if (anime.company != null && anime.company!.name.isNotEmpty)
        anime.company!.name,
      if (anime.years != null && anime.years!.isNotEmpty) anime.years!,
    ].join(' / ');

    return _HistoryCardShell(
      onTap: onTap,
      cover: _HistoryCover(imageUrl: anime.cover, icon: Icons.movie_outlined),
      title: anime.name,
      subtitle: subtitle.isEmpty ? null : subtitle,
      lastBrowseName: item.lastBrowseName,
      lastBrowseIcon: Icons.play_circle_outline,
      latestText: anime.count > 0
          ? AppLocalizations.of(context)!.totalEpisodes(anime.count)
          : null,
      chips: [
        _HistoryMetaChip(
          icon: Icons.local_fire_department,
          label: _BrowseHistoryPageState.formatPopular(context, anime.popular),
        ),
        if (anime.datetimeUpdated != null)
          _HistoryMetaChip(
            icon: Icons.schedule,
            label: TimeFormat.relativeOf(
              anime.datetimeUpdated!,
              AppLocalizations.of(context)!,
            ),
          ),
      ],
    );
  }
}

class _HistoryCardShell extends StatelessWidget {
  final VoidCallback onTap;
  final Widget cover;
  final String title;
  final String? subtitle;
  final String? lastBrowseName;
  final IconData lastBrowseIcon;
  final String? latestText;
  final List<Widget> chips;

  const _HistoryCardShell({
    required this.onTap,
    required this.cover,
    required this.title,
    this.subtitle,
    this.lastBrowseName,
    required this.lastBrowseIcon,
    this.latestText,
    required this.chips,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 84,
                child: AspectRatio(aspectRatio: 0.72, child: cover),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (lastBrowseName != null &&
                        lastBrowseName!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(lastBrowseIcon, size: 16, color: cs.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              l10n.browseHistoryLastSeen(lastBrowseName!),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (latestText != null && latestText!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        latestText!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: chips),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryCover extends StatelessWidget {
  final String imageUrl;
  final IconData icon;

  const _HistoryCover({required this.imageUrl, required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: AppRadius.mdR,
      child: CoverBrightnessFilter(
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          placeholder: (_, _) => Container(
            color: cs.surfaceContainerHighest,
            child: Center(
              child: Icon(icon, color: cs.onSurfaceVariant, size: 28),
            ),
          ),
          errorWidget: (_, _, _) => Container(
            color: cs.surfaceContainerHighest,
            child: Center(
              child: Icon(
                Icons.broken_image,
                color: cs.onSurfaceVariant,
                size: 28,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _HistoryMetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: AppRadius.fullR,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.primary),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _HistoryCardSkeleton extends StatefulWidget {
  const _HistoryCardSkeleton();

  @override
  State<_HistoryCardSkeleton> createState() => _HistoryCardSkeletonState();
}

class _HistoryCardSkeletonState extends State<_HistoryCardSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final alpha = 0.15 + 0.15 * _controller.value;
        final color = cs.onSurfaceVariant.withValues(alpha: alpha);
        return Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 84,
                  child: AspectRatio(
                    aspectRatio: 0.72,
                    child: Container(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: AppRadius.mdR,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        height: 16,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: AppRadius.xsR,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Container(
                        width: 120,
                        height: 12,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: AppRadius.xsR,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Container(
                        width: 160,
                        height: 14,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: AppRadius.xsR,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Container(
                            width: 60,
                            height: 24,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: AppRadius.fullR,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Container(
                            width: 60,
                            height: 24,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: AppRadius.fullR,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
            ),
          ),
        );
      },
    );
  }
}
