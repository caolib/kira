import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/anime.dart';
import '../models/comic.dart' hide Theme;
import '../models/user_manager.dart';
import '../utils/cover_brightness_filter.dart';
import '../utils/network_error.dart';
import '../utils/comic_hero_tags.dart';
import '../utils/time_format.dart';
import '../utils/toast.dart';
import 'anime_detail_page.dart';
import 'comic_detail_page.dart';

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
  String get _modeLabel => _isAnimeMode ? '动漫' : '漫画';
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空浏览记录'),
        content: Text('确定要清空所有$_modeLabel浏览记录吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      if (_isAnimeMode) {
        await _api.clearAnimeBrowseHistory();
      } else {
        await _api.clearBrowseHistory();
      }
      if (!mounted) return;
      showToast(context, '已清空$_modeLabel浏览记录');
      setState(_clearItems);
    } catch (e) {
      if (!mounted) return;
      showToast(context, '清空失败：${NetworkError.message(e)}', isError: true);
    }
  }

  Future<void> _load({bool silent = false, bool force = false}) async {
    if (_refreshing && !force) return;
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
        final data = await _api.getAnimeBrowseHistory();
        if (!mounted || _mode != mode) return;
        setState(() {
          _animeItems = data.list;
          _total = data.total;
          _offset = data.list.length;
          _loading = false;
        });
      } else {
        final data = await _api.getBrowseHistory();
        if (!mounted || _mode != mode) return;
        setState(() {
          _comicItems = data.list;
          _total = data.total;
          _offset = data.list.length;
          _loading = false;
        });
      }
      if (!silent && mounted) {
        showToast(context, '刷新成功');
      }
    } catch (e) {
      debugPrint('BrowseHistoryPage load error: $e');
      if (isInitial && mounted) setState(() => _loading = false);
      if (_isUnauthorized(e)) {
        await _handleUnauthorized();
      } else if (!silent && mounted) {
        showToast(context, '刷新失败', isError: true);
      }
    } finally {
      _refreshing = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _refreshing || _offset >= _total) return;
    final mode = _mode;
    _loadingMore = true;
    try {
      if (mode == _HistoryMode.anime) {
        final data = await _api.getAnimeBrowseHistory(offset: _offset);
        if (!mounted || _mode != mode) return;
        setState(() {
          _animeItems.addAll(data.list);
          _offset = _animeItems.length;
        });
      } else {
        final data = await _api.getBrowseHistory(offset: _offset);
        if (!mounted || _mode != mode) return;
        setState(() {
          _comicItems.addAll(data.list);
          _offset = _comicItems.length;
        });
      }
    } catch (e) {
      debugPrint('BrowseHistoryPage loadMore error: $e');
      if (_isUnauthorized(e)) {
        await _handleUnauthorized();
      }
    } finally {
      _loadingMore = false;
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

    if (_user.autoLogin) {
      await _user.logout();
      if (mounted) {
        showToast(context, '自动登录失败，请手动重新登录', isError: true);
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
        title: const Text('登录已过期'),
        content: const Text('浏览记录需要登录后才能继续查看，是否现在重新登录？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('稍后再说'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('去登录'),
          ),
        ],
      ),
    );

    if (shouldLogin == true && mounted) {
      await _goLogin();
    } else if (mounted) {
      showToast(context, '登录后可继续查看浏览记录', isError: true);
    }

    _showingLoginPrompt = false;
  }

  Future<void> _goLogin() async {
    final loggedIn = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: widget.loginPageBuilder),
    );
    if (loggedIn == true && mounted) {
      _load(silent: true);
    }
  }

  void _openAnime(AnimeBrowseHistoryItem item) {
    if (!_animeFeatureEnabled) return;
    if (item.anime.pathWord.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AnimeDetailPage(
          pathWord: item.anime.pathWord,
          initialAnime: item.anime,
        ),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('浏览记录'),
        actions: [
          if (_user.isLoggedIn && !_currentItemsEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '清空浏览记录',
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
                    const SizedBox(height: 16),
                    Text(
                      '登录后可查看浏览记录',
                      style: tt.titleMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _animeFeatureEnabled
                          ? '浏览过的漫画和动漫会同步显示在这里'
                          : '浏览过的漫画会同步显示在这里',
                      textAlign: TextAlign.center,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _goLogin,
                      icon: const Icon(Icons.login),
                      label: const Text('去登录'),
                    ),
                  ],
                ),
              ),
            )
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (!_currentItemsEmpty &&
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
                            segments: const [
                              ButtonSegment(
                                value: _HistoryMode.comic,
                                label: Text('漫画'),
                                icon: Icon(Icons.menu_book_outlined),
                              ),
                              ButtonSegment(
                                value: _HistoryMode.anime,
                                label: Text('动漫'),
                                icon: Icon(Icons.movie_outlined),
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
                                const SizedBox(height: 16),
                                Text(
                                  '还没有$_modeLabel浏览记录',
                                  style: tt.titleMedium?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '去看几部$_modeLabel后，这里会显示最近浏览内容',
                                  textAlign: TextAlign.center,
                                  style: tt.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                FilledButton.tonalIcon(
                                  onPressed: _user.isLoggedIn ? _load : null,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('刷新'),
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
                            '共 $_total 条$_modeLabel浏览记录',
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
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  static String formatPopular(int n) {
    if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}亿';
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
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
      onTap: () => Navigator.push(
        context,
        ComicDetailPage.route(
          pathWord: comic.pathWord,
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
          : '最新 ${comic.lastChapterName}',
      chips: [
        _HistoryMetaChip(
          icon: Icons.local_fire_department,
          label: _BrowseHistoryPageState.formatPopular(comic.popular),
        ),
        if (comic.datetimeUpdated != null)
          _HistoryMetaChip(
            icon: Icons.schedule,
            label: TimeFormat.relativeOf(comic.datetimeUpdated!),
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
      latestText: anime.count > 0 ? '共 ${anime.count} 集' : null,
      chips: [
        _HistoryMetaChip(
          icon: Icons.local_fire_department,
          label: _BrowseHistoryPageState.formatPopular(anime.popular),
        ),
        if (anime.datetimeUpdated != null)
          _HistoryMetaChip(
            icon: Icons.schedule,
            label: TimeFormat.relativeOf(anime.datetimeUpdated!),
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
              const SizedBox(width: 12),
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
                              '上次看到 $lastBrowseName',
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
              const SizedBox(width: 8),
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
      borderRadius: BorderRadius.circular(12),
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
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
