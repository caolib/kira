import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/api_client.dart';
import '../models/comic.dart' hide Theme;
import '../models/comic.dart' as m;
import '../utils/data_cache.dart';
import 'comic_detail_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _api = ApiClient();
  final _searchController = TextEditingController();
  List<String> _keywords = [];
  List<m.Theme> _tags = [];
  String? _selectedTag;
  String _ordering = '-popular';
  List<Comic> _comics = [];
  bool _loading = true;
  int _offset = 0;
  int _total = 0;
  bool _loadingMore = false;
  bool _searching = false;
  String? _searchQuery;
  final _cache = DataCache();

  @override
  void initState() {
    super.initState();
    _loadFromCache();
    _loadInit();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFromCache() async {
    final cached = await _cache.get('search_init');
    if (cached != null && _loading) {
      setState(() {
        _keywords = List<String>.from(cached['keywords'] ?? []);
        _tags = (cached['tags'] as List?)
                ?.map((t) => m.Theme.fromJson(t))
                .toList() ??
            [];
        _loading = false;
      });
    }
  }

  Future<void> _loadInit() async {
    try {
      final keywordsFuture = _api.getHotKeywords();
      final tagsFuture = _api.getComicTags();
      final keywords = await keywordsFuture;
      final tags = await tagsFuture;
      if (!mounted) return;
      setState(() {
        _keywords = keywords;
        _tags = tags;
        _loading = false;
      });
      _cache.put('search_init', {
        'keywords': keywords,
        'tags': tags.map((t) => t.toJson()).toList(),
      });
    } catch (e) {
      debugPrint('SearchPage loadInit error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _doSearch(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _searching = true;
      _searchQuery = query.trim();
      _comics = [];
      _offset = 0;
      _selectedTag = null;
    });
    try {
      final result = await _api.searchComics(_searchQuery!);
      setState(() {
        _comics = result.list;
        _total = result.total;
        _offset = result.list.length;
        _searching = false;
      });
    } catch (_) {
      setState(() => _searching = false);
    }
  }

  Future<void> _loadComics({bool reset = true}) async {
    if (reset) {
      setState(() {
        _offset = 0;
        _comics = [];
        _searchQuery = null;
      });
    }
    try {
      final result = await _api.getComicList(
        ordering: _ordering,
        offset: _offset,
        theme: _selectedTag,
      );
      setState(() {
        if (reset) {
          _comics = result.list;
        } else {
          _comics.addAll(result.list);
        }
        _total = result.total;
        _offset = _comics.length;
      });
    } catch (_) {}
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _offset >= _total) return;
    _loadingMore = true;
    if (_searchQuery != null) {
      try {
        final result =
            await _api.searchComics(_searchQuery!, offset: _offset);
        setState(() {
          _comics.addAll(result.list);
          _offset = _comics.length;
        });
      } catch (_) {}
    } else {
      await _loadComics(reset: false);
    }
    _loadingMore = false;
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = null;
      _comics = [];
      _offset = 0;
      _total = 0;
    });
  }

  void _onKeywordTap(String keyword) {
    _searchController.text = keyword;
    _doSearch(keyword);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth.clamp(0.0, 900.0);
    final hp = (screenWidth - contentWidth) / 2 + 16;

    if (_loading) return const Center(child: CircularProgressIndicator());

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (_comics.isNotEmpty &&
            n.metrics.pixels > n.metrics.maxScrollExtent - 300) {
          _loadMore();
        }
        return false;
      },
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: MediaQuery.of(context).padding.top)),
          // 搜索框
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(hp, 12, hp, 8),
              child: SearchBar(
                controller: _searchController,
                hintText: '搜索漫画...',
                leading: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.search),
                ),
                trailing: _searchQuery != null
                    ? [
                        IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: _clearSearch,
                        )
                      ]
                    : null,
                onSubmitted: _doSearch,
              ),
            ),
          ),
          if (_searching)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
          // 热门关键词
          if (_keywords.isNotEmpty && _comics.isEmpty && !_searching)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(hp, 8, hp, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.local_fire_department,
                            size: 20, color: cs.primary),
                        const SizedBox(width: 6),
                        Text('热门搜索',
                            style: tt.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _keywords
                          .map((k) => ActionChip(
                                label: Text(k),
                                onPressed: () => _onKeywordTap(k),
                                avatar: Icon(Icons.trending_up,
                                    size: 16, color: cs.primary),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          // 分类标签
          if (_searchQuery == null && !_searching)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(hp, 0, hp, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.category, size: 20, color: cs.primary),
                        const SizedBox(width: 6),
                        Text('分类',
                            style: tt.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _tags.map((t) {
                        final selected = _selectedTag == t.pathWord;
                        return FilterChip(
                          label: Text(t.name),
                          selected: selected,
                          showCheckmark: false,
                          onSelected: (v) {
                            setState(() =>
                                _selectedTag = v ? t.pathWord : null);
                            if (v) _loadComics();
                          },
                        );
                      }).toList(),
                    ),
                    if (_comics.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: '-popular',
                            label: Text('热度'),
                            icon: Icon(Icons.whatshot),
                          ),
                          ButtonSegment(
                            value: '-datetime_updated',
                            label: Text('更新'),
                            icon: Icon(Icons.schedule),
                          ),
                        ],
                        selected: {_ordering},
                        onSelectionChanged: (v) {
                          setState(() => _ordering = v.first);
                          _loadComics();
                        },
                      ),
                    ],
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          // 搜索结果提示
          if (_searchQuery != null && _comics.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(hp, 4, hp, 12),
                child: Text(
                  '搜索 "$_searchQuery" 找到 $_total 个结果',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ),
          // 漫画网格
          if (_comics.isNotEmpty)
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: hp),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    final c = _comics[i];
                    return _ComicGridItem(
                      comic: c,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ComicDetailPage(pathWord: c.pathWord),
                        ),
                      ),
                    );
                  },
                  childCount: _comics.length,
                ),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 130,
                  childAspectRatio: 0.55,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
              ),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
        ],
      ),
    );
  }
}

class _ComicGridItem extends StatelessWidget {
  final Comic comic;
  final VoidCallback onTap;
  const _ComicGridItem({required this.comic, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
                        color: cs.onSurfaceVariant, size: 32),
                  ),
                ),
                errorWidget: (_, _, _) => Container(
                  color: cs.surfaceContainerHighest,
                  child: Center(
                    child: Icon(Icons.broken_image,
                        color: cs.onSurfaceVariant, size: 32),
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
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
