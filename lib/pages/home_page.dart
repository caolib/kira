import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/api_client.dart';
import '../models/comic.dart' hide Theme;
import '../utils/data_cache.dart';
import 'comic_detail_page.dart';
import 'recommend_page.dart';
import 'ranking_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _api = ApiClient();
  final _cache = DataCache();
  List<Comic> _recommendations = [];
  List<Comic> _rankingPreview = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFromCache();
    _load();
  }

  Future<void> _loadFromCache() async {
    final cached = await _cache.get('home');
    if (cached != null && _loading) {
      setState(() {
        _recommendations = (cached['recommendations'] as List?)
                ?.map((j) => Comic.fromJson(j))
                .toList() ??
            [];
        _rankingPreview = (cached['ranking'] as List?)
                ?.map((j) => Comic.fromJson(j))
                .toList() ??
            [];
        _loading = false;
      });
    }
  }

  Future<void> _load() async {
    if (_recommendations.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final recsFuture = _api.getRecommendations(limit: 10);
      final rankingFuture = _api.getComicList(ordering: '-popular', limit: 6);
      final recs = await recsFuture;
      final ranking = await rankingFuture;
      if (!mounted) return;
      setState(() {
        _recommendations = recs;
        _rankingPreview = ranking.list;
        _loading = false;
      });
      _cache.put('home', {
        'recommendations': recs.map((c) => c.toJson()).toList(),
        'ranking': ranking.list.map((c) => c.toJson()).toList(),
      });
    } catch (e) {
      debugPrint('HomePage load error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _openComic(Comic comic) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ComicDetailPage(pathWord: comic.pathWord),
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

    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null && _recommendations.isEmpty) {
      return Center(
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
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: MediaQuery.of(context).padding.top)),

          // ── 推荐区 ──
          if (_recommendations.isNotEmpty) ...[
            _SectionTitle(
              title: '热门推荐',
              icon: Icons.auto_awesome,
              hp: hp,
              onMore: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RecommendPage()),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 210,
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.mouse,
                    },
                  ),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: hp),
                    itemCount: _recommendations.length,
                    itemBuilder: (_, i) {
                      final c = _recommendations[i];
                      return _RecommendCard(
                        comic: c,
                        onTap: () => _openComic(c),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],

          // ── 排行区 ──
          if (_rankingPreview.isNotEmpty) ...[
            _SectionTitle(
              title: '漫画排行',
              icon: Icons.leaderboard,
              hp: hp,
              onMore: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RankingPage()),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: hp),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => ComicCard(
                    comic: _rankingPreview[i],
                    onTap: () => _openComic(_rankingPreview[i]),
                  ),
                  childCount: _rankingPreview.length,
                ),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 130,
                  childAspectRatio: 0.55,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
              ),
            ),
          ],
          const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
        ],
      ),
    );
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
        padding: EdgeInsets.fromLTRB(hp, 20, hp - 8, 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: cs.primary),
            const SizedBox(width: 6),
            Text(title,
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
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

class _RecommendCard extends StatelessWidget {
  final Comic comic;
  final VoidCallback onTap;
  const _RecommendCard({required this.comic, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 130,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Card(
                margin: EdgeInsets.zero,
                child: CachedNetworkImage(
                  imageUrl: comic.cover,
                  fit: BoxFit.cover,
                  width: 130,
                  height: double.infinity,
                  placeholder: (_, _) => Container(
                    color: cs.surfaceContainerHighest,
                    child: Center(
                        child: Icon(Icons.image,
                            color: cs.onSurfaceVariant, size: 32)),
                  ),
                  errorWidget: (_, _, _) => Container(
                    color: cs.surfaceContainerHighest,
                    child: Center(
                        child: Icon(Icons.broken_image,
                            color: cs.onSurfaceVariant, size: 32)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(comic.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall),
            if (comic.authors.isNotEmpty)
              Text(
                comic.authors.map((a) => a.name).join(' / '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

/// 漫画网格卡片，多页面复用
class ComicCard extends StatelessWidget {
  final Comic comic;
  final VoidCallback onTap;
  const ComicCard({super.key, required this.comic, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Card(
              margin: EdgeInsets.zero,
              child: CachedNetworkImage(
                imageUrl: comic.cover,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                placeholder: (_, _) => Container(
                  color: cs.surfaceContainerHighest,
                  child: Center(
                      child: Icon(Icons.image,
                          color: cs.onSurfaceVariant, size: 32)),
                ),
                errorWidget: (_, _, _) => Container(
                  color: cs.surfaceContainerHighest,
                  child: Center(
                      child: Icon(Icons.broken_image,
                          color: cs.onSurfaceVariant, size: 32)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(comic.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.bodySmall),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.local_fire_department, size: 12, color: cs.primary),
              const SizedBox(width: 2),
              Text(formatPopular(comic.popular),
                  style: tt.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant, fontSize: 10)),
              const Spacer(),
              if (comic.datetimeUpdated != null)
                Text(formatRelativeTime(comic.datetimeUpdated!),
                    style: tt.labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
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
