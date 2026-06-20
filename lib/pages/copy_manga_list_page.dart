import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/comic.dart' hide Theme;
import '../utils/comic_card_skeleton.dart';
import '../utils/comic_hero_tags.dart';
import '../utils/cover_brightness_filter.dart';
import '../utils/time_format.dart';
import 'comic_detail_page.dart';

enum CopyMangaListKind { recommendations, ranking, newest, finished }

class CopyMangaListPage extends StatefulWidget {
  final CopyMangaListKind kind;

  const CopyMangaListPage({super.key, required this.kind});

  const CopyMangaListPage.recommendations({super.key})
    : kind = CopyMangaListKind.recommendations;

  const CopyMangaListPage.ranking({super.key})
    : kind = CopyMangaListKind.ranking;

  const CopyMangaListPage.newest({super.key}) : kind = CopyMangaListKind.newest;

  const CopyMangaListPage.finished({super.key})
    : kind = CopyMangaListKind.finished;

  @override
  State<CopyMangaListPage> createState() => _CopyMangaListPageState();
}

class _CopyMangaListPageState extends State<CopyMangaListPage> {
  static const _pageSize = 21;

  final _api = ApiClient();
  final List<Comic> _comics = [];
  bool _loading = true;
  bool _loadingMore = false;
  int _offset = 0;
  int _total = 0;
  String? _error;
  String _rankDateType = 'day';
  String _rankAudienceType = 'male';

  final _scrollController = ScrollController();
  bool _showBackToTop = false;

  String get _title {
    switch (widget.kind) {
      case CopyMangaListKind.recommendations:
        return '推荐';
      case CopyMangaListKind.ranking:
        return '排行榜';
      case CopyMangaListKind.newest:
        return '全新上架';
      case CopyMangaListKind.finished:
        return '已完结';
    }
  }

  String get _scope {
    switch (widget.kind) {
      case CopyMangaListKind.recommendations:
        return 'copy-more-rec';
      case CopyMangaListKind.ranking:
        return 'copy-more-rank-$_rankDateType-$_rankAudienceType';
      case CopyMangaListKind.newest:
        return 'copy-more-new';
      case CopyMangaListKind.finished:
        return 'copy-more-finish';
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<({List<Comic> list, int total})> _fetch(int offset) {
    switch (widget.kind) {
      case CopyMangaListKind.recommendations:
        return _api.getCopyRecommendations(limit: _pageSize, offset: offset);
      case CopyMangaListKind.ranking:
        return _api.getCopyRankComics(
          dateType: _rankDateType,
          audienceType: _rankAudienceType,
          limit: _pageSize,
          offset: offset,
        );
      case CopyMangaListKind.newest:
        return _api.getCopyNewestComics(limit: _pageSize, offset: offset);
      case CopyMangaListKind.finished:
        return _api.getCopyFinishedComics(limit: _pageSize, offset: offset);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _comics.clear();
      _offset = 0;
      _total = 0;
    });
    try {
      final data = await _fetch(0);
      if (!mounted) return;
      setState(() {
        _comics.addAll(data.list);
        _offset = _comics.length;
        _total = data.total;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _offset >= _total) return;
    setState(() => _loadingMore = true);
    try {
      final data = await _fetch(_offset);
      if (!mounted) return;
      setState(() {
        _comics.addAll(data.list);
        _offset = _comics.length;
        _total = data.total;
      });
    } catch (_) {
      // Keep the current list visible; the next scroll can retry.
    }
    if (mounted) {
      setState(() => _loadingMore = false);
    } else {
      _loadingMore = false;
    }
  }

  void _setRankDateType(String value) {
    if (_rankDateType == value) return;
    _rankDateType = value;
    _load();
  }

  void _setRankAudienceType(String value) {
    if (_rankAudienceType == value) return;
    _rankAudienceType = value;
    _load();
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
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth.clamp(0.0, 900.0);
    final hp = (screenWidth - contentWidth) / 2 + 16;

    const gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 130,
      childAspectRatio: 0.55,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
    );

    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      floatingActionButton: _showBackToTop
          ? FloatingActionButton.small(
              heroTag: 'copy_list_back_to_top_${widget.kind.name}',
              onPressed: _scrollToTop,
              tooltip: '回到顶部',
              child: const Icon(Icons.arrow_upward_rounded),
            )
          : null,
      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.axis != Axis.vertical) return false;
          final shouldShow = notification.metrics.pixels > 400;
          if (shouldShow != _showBackToTop) {
            setState(() => _showBackToTop = shouldShow);
          }
          if (notification.metrics.extentAfter < 300) {
            _loadMore();
          }
          return false;
        },
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            if (widget.kind == CopyMangaListKind.ranking)
              SliverToBoxAdapter(
                child: _CopyRankControls(
                  hp: hp,
                  dateType: _rankDateType,
                  audienceType: _rankAudienceType,
                  onDateTypeChanged: _setRankDateType,
                  onAudienceTypeChanged: _setRankAudienceType,
                ),
              ),
            if (_loading)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(hp, 12, hp, 0),
                sliver: SliverGrid(
                  gridDelegate: gridDelegate,
                  delegate: SliverChildBuilderDelegate(
                    (_, _) => const ComicCardSkeleton(),
                    childCount: _pageSize,
                  ),
                ),
              )
            else if (_error != null && _comics.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _CopyListError(onRetry: _load),
              )
            else ...[
              SliverPadding(
                padding: EdgeInsets.fromLTRB(hp, 12, hp, 0),
                sliver: SliverGrid(
                  gridDelegate: gridDelegate,
                  delegate: SliverChildBuilderDelegate((_, i) {
                    if (i >= _comics.length) {
                      return const ComicCardSkeleton();
                    }
                    final comic = _comics[i];
                    final heroTagBase = ComicHeroTags.base(
                      scope: _scope,
                      pathWord: comic.pathWord,
                      index: i,
                    );
                    return _CopyListComicCard(
                      comic: comic,
                      heroTagBase: heroTagBase,
                      onTap: () => _openComic(comic, heroTagBase),
                    );
                  }, childCount: _comics.length + (_loadingMore ? 6 : 0)),
                ),
              ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
            ],
          ],
        ),
      ),
    );
  }
}

class _CopyRankControls extends StatelessWidget {
  final double hp;
  final String dateType;
  final String audienceType;
  final ValueChanged<String> onDateTypeChanged;
  final ValueChanged<String> onAudienceTypeChanged;

  const _CopyRankControls({
    required this.hp,
    required this.dateType,
    required this.audienceType,
    required this.onDateTypeChanged,
    required this.onAudienceTypeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 12, hp, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              selected: {dateType},
              onSelectionChanged: (value) => onDateTypeChanged(value.first),
              segments: const [
                ButtonSegment(value: 'day', label: Text('日榜')),
                ButtonSegment(value: 'week', label: Text('周榜')),
                ButtonSegment(value: 'month', label: Text('月榜')),
                ButtonSegment(value: 'total', label: Text('总榜')),
              ],
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              selected: {audienceType},
              onSelectionChanged: (value) => onAudienceTypeChanged(value.first),
              segments: const [
                ButtonSegment(value: 'male', label: Text('男生')),
                ButtonSegment(value: 'female', label: Text('女生')),
              ],
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyListError extends StatelessWidget {
  final VoidCallback onRetry;

  const _CopyListError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 64, color: cs.onSurfaceVariant),
          const SizedBox(height: 16),
          Text('加载失败', style: tt.titleMedium),
          const SizedBox(height: 8),
          FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _CopyListComicCard extends StatelessWidget {
  final Comic comic;
  final String heroTagBase;
  final VoidCallback onTap;

  const _CopyListComicCard({
    required this.comic,
    required this.heroTagBase,
    required this.onTap,
  });

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
            child: Hero(
              tag: ComicHeroTags.cover(heroTagBase),
              createRectTween: ComicHeroTags.createRectTween,
              placeholderBuilder: (_, heroSize, _) =>
                  SizedBox(width: heroSize.width, height: heroSize.height),
              child: Card(
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
                    placeholder: (_, _) => _CopyImagePlaceholder(
                      color: cs.surfaceContainerHighest,
                      iconColor: cs.onSurfaceVariant,
                      icon: Icons.image,
                    ),
                    errorWidget: (_, _, _) => _CopyImagePlaceholder(
                      color: cs.surfaceContainerHighest,
                      iconColor: cs.onSurfaceVariant,
                      icon: Icons.broken_image,
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
              Flexible(
                child: Text(
                  _formatPopular(comic.popular),
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
                  TimeFormat.relativeOf(comic.datetimeUpdated!),
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

  static String _formatPopular(int n) {
    if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}亿';
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    return n.toString();
  }
}

class _CopyImagePlaceholder extends StatelessWidget {
  final Color color;
  final Color iconColor;
  final IconData icon;

  const _CopyImagePlaceholder({
    required this.color,
    required this.iconColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      child: Center(child: Icon(icon, color: iconColor, size: 32)),
    );
  }
}
