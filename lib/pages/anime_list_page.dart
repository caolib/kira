import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
import '../models/anime.dart';
import '../routing/app_router.dart';
import '../utils/cover_brightness_filter.dart';
import '../widgets/comic_card_skeleton.dart';
import 'home_page.dart';

enum AnimeListType {
  editor(title: '编辑推荐', icon: Icons.auto_awesome, pos: 1202002),
  updates(title: '最近更新', icon: Icons.update),
  classics(title: '经典动画', icon: Icons.workspace_premium, pos: 1202003),
  hots(title: '热门推荐', icon: Icons.local_fire_department, pos: 1202004);

  final String title;
  final IconData icon;
  final int? pos;

  const AnimeListType({required this.title, required this.icon, this.pos});
}

class AnimeListPage extends StatefulWidget {
  final AnimeListType type;

  const AnimeListPage({super.key, required this.type});

  @override
  State<AnimeListPage> createState() => _AnimeListPageState();
}

class _AnimeListPageState extends State<AnimeListPage> {
  static const _pageSize = 24;

  final _api = ApiClient();
  final _scrollController = ScrollController();
  List<Anime> _items = [];
  int _offset = 0;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels > position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<({List<Anime> list, int total})> _fetch({
    required int limit,
    required int offset,
  }) async {
    if (widget.type == AnimeListType.updates) {
      final data = await _api.anime.getAnimeUpdates(
        limit: limit,
        offset: offset,
      );
      return (list: data.list.map((e) => e.anime).toList(), total: data.total);
    }

    return _api.anime.getAnimeRecommendations(
      pos: widget.type.pos!,
      limit: limit,
      offset: offset,
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _items = [];
      _offset = 0;
      _total = 0;
    });

    try {
      final data = await _fetch(limit: _pageSize, offset: 0);
      if (!mounted) return;
      setState(() {
        _items = data.list;
        _offset = data.list.length;
        _total = data.total;
        _loading = false;
      });
    } catch (e) {
      debugPrint('AnimeListPage load error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _offset >= _total) return;
    setState(() => _loadingMore = true);

    try {
      final data = await _fetch(limit: _pageSize, offset: _offset);
      if (!mounted) return;
      setState(() {
        _items.addAll(data.list);
        _offset = _items.length;
        _total = data.total;
        _loadingMore = false;
      });
    } catch (e) {
      debugPrint('AnimeListPage loadMore error: $e');
      if (mounted) {
        setState(() => _loadingMore = false);
      } else {
        _loadingMore = false;
      }
    }
  }

  void _openAnime(Anime anime) {
    context.pushNamed(
      AppRoutes.animeDetail,
      pathParameters: {'pathWord': anime.pathWord},
      extra: AnimeDetailExtra(initialAnime: anime),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth < 900 ? screenWidth : 900.0;
    final hp = (screenWidth - contentWidth) / 2 + 16;

    const gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 130,
      childAspectRatio: 0.5,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
    );

    Widget body;
    if (_loading) {
      body = GridView.builder(
        padding: EdgeInsets.symmetric(horizontal: hp, vertical: 12),
        itemCount: _pageSize,
        gridDelegate: gridDelegate,
        itemBuilder: (_, _) => const ComicCardSkeleton(),
      );
    } else if (_error != null && _items.isEmpty) {
      body = Center(
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
      );
    } else if (_items.isEmpty) {
      body = Center(child: Text('暂无内容', style: tt.titleMedium));
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(hp, 12, hp, 0),
              sliver: SliverGrid(
                gridDelegate: gridDelegate,
                delegate: SliverChildBuilderDelegate((_, i) {
                  if (i >= _items.length) return const ComicCardSkeleton();
                  final anime = _items[i];
                  return _AnimeGridCard(
                    anime: anime,
                    onTap: () => _openAnime(anime),
                  );
                }, childCount: _items.length + (_loadingMore ? 6 : 0)),
              ),
            ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.type.title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(widget.type.icon, color: cs.primary),
          ),
        ],
      ),
      body: body,
    );
  }
}

class _AnimeGridCard extends StatelessWidget {
  final Anime anime;
  final VoidCallback onTap;

  const _AnimeGridCard({required this.anime, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final meta = anime.count > 0
        ? '共 ${anime.count} 集'
        : (anime.company?.name ?? anime.years ?? '');

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              margin: EdgeInsets.zero,
              child: CoverBrightnessFilter(
                child: CachedNetworkImage(
                  imageUrl: anime.cover,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  placeholder: (_, _) =>
                      const _ImagePlaceholder(icon: Icons.movie_outlined),
                  errorWidget: (_, _, _) =>
                      const _ImagePlaceholder(icon: Icons.broken_image),
                ),
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
                ComicCard.formatPopular(anime.popular),
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
