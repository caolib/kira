import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/comic.dart' hide Theme;
import '../models/user_manager.dart';
import 'comic_detail_page.dart';
import 'home_page.dart';

class BookshelfPage extends StatefulWidget {
  const BookshelfPage({super.key});

  @override
  State<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends State<BookshelfPage> {
  final _api = ApiClient();
  final _user = UserManager();
  List<Comic> _comics = [];
  bool _loading = true;
  int _offset = 0;
  int _total = 0;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _user.addListener(_onUserChanged);
    if (_user.isLoggedIn) {
      _load();
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
    if (_user.isLoggedIn) {
      _load();
    } else {
      setState(() {
        _comics = [];
        _total = 0;
        _loading = false;
      });
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _comics = [];
      _offset = 0;
    });
    try {
      final data = await _api.getBookshelf();
      setState(() {
        _comics = data.list;
        _total = data.total;
        _offset = data.list.length;
        _loading = false;
      });
    } catch (e) {
      debugPrint('BookshelfPage load error: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _offset >= _total) return;
    _loadingMore = true;
    try {
      final data = await _api.getBookshelf(offset: _offset);
      setState(() {
        _comics.addAll(data.list);
        _offset = _comics.length;
      });
    } catch (e) {
      debugPrint('BookshelfPage loadMore error: $e');
    }
    _loadingMore = false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth.clamp(0.0, 900.0);
    final hp = (screenWidth - contentWidth) / 2 + 16;

    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _comics.isEmpty
              ? CustomScrollView(
                  slivers: [
                    const SliverAppBar(title: Text('书架'), pinned: true),
                    SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bookmark_border,
                                size: 64, color: cs.onSurfaceVariant),
                            const SizedBox(height: 16),
                            Text('书架空空如也',
                                style: tt.titleMedium?.copyWith(
                                    color: cs.onSurfaceVariant)),
                            const SizedBox(height: 8),
                            Text('去发现页找点好看的漫画吧',
                                style: tt.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n.metrics.pixels >
                          n.metrics.maxScrollExtent - 300) {
                        _loadMore();
                      }
                      return false;
                    },
                    child: CustomScrollView(
                      slivers: [
                        const SliverAppBar(title: Text('书架'), pinned: true),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(hp, 0, hp, 12),
                            child: Text(
                              '共 $_total 部收藏',
                              style: tt.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant),
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: EdgeInsets.symmetric(horizontal: hp),
                          sliver: SliverGrid(
                            delegate: SliverChildBuilderDelegate(
                              (_, i) => ComicCard(
                                comic: _comics[i],
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ComicDetailPage(
                                        pathWord: _comics[i].pathWord),
                                  ),
                                ).then((_) => _load()),
                              ),
                              childCount: _comics.length,
                            ),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 160,
                              childAspectRatio: 0.55,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                            ),
                          ),
                        ),
                        const SliverPadding(
                            padding: EdgeInsets.only(bottom: 24)),
                      ],
                    ),
                  ),
                ),
    );
  }
}
