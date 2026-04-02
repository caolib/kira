import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../api/api_client.dart';
import '../models/comic.dart' hide Theme;
import '../models/user_manager.dart';
import '../utils/toast.dart';
import 'comic_detail_page.dart';
import 'home_page.dart';
import 'profile_page.dart';

class BookshelfPage extends StatefulWidget {
  const BookshelfPage({super.key});

  @override
  State<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends State<BookshelfPage> {
  final _api = ApiClient();
  final _user = UserManager();
  List<BookshelfItem> _items = [];
  bool _loading = true;
  int _offset = 0;
  int _total = 0;
  bool _loadingMore = false;
  bool _refreshing = false;
  bool _showingLoginPrompt = false;
  late String _ordering = _user.bookshelfOrdering;

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
    if (_user.isLoggedIn) {
      _load(silent: true);
    } else {
      setState(() {
        _items = [];
        _total = 0;
        _loading = false;
      });
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    final isInitial = _items.isEmpty;
    if (isInitial) {
      setState(() => _loading = true);
    } else {
      setState(() {});  // 触发 UI 显示刷新指示器
    }
    _offset = 0;
    try {
      final data = await _api.getBookshelf(ordering: _ordering);
      if (!mounted) return;
      setState(() {
        _items = data.list;
        _total = data.total;
        _offset = data.list.length;
        _loading = false;
      });
      if (!silent && mounted) {
        showToast(context, '刷新成功');
      }
    } catch (e) {
      debugPrint('BookshelfPage load error: $e');
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
    _loadingMore = true;
    try {
      final data = await _api.getBookshelf(
        offset: _offset,
        ordering: _ordering,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(data.list);
        _offset = _items.length;
      });
    } catch (e) {
      debugPrint('BookshelfPage loadMore error: $e');
      if (_isUnauthorized(e)) {
        await _handleUnauthorized();
      }
    } finally {
      _loadingMore = false;
    }
  }

  bool _isUnauthorized(Object error) =>
      error is DioException && error.response?.statusCode == 401;

  Future<void> _handleUnauthorized() async {
    if (_showingLoginPrompt || !mounted) return;

    // 自动登录开启时，拦截器已尝试自动登录但失败了，静默提示即可
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
        content: const Text('书架需要登录后才能继续使用，是否现在重新登录？'),
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
      final loggedIn = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      if (loggedIn == true && mounted) {
        _load(silent: true);
      }
    } else if (mounted) {
      showToast(context, '登录后可继续查看书架', isError: true);
    }

    _showingLoginPrompt = false;
  }

  static String _orderingLabel(String ordering) {
    switch (ordering) {
      case '-datetime_updated':
        return '按更新';
      case '-datetime_modifier':
        return '按收藏';
      case '-datetime_browse':
        return '按阅读';
      default:
        return '排序';
    }
  }

  void _setOrdering(BuildContext context, String ordering) {
    Navigator.pop(context);
    setState(() => _ordering = ordering);
    _user.setBookshelfOrdering(ordering);
    _load(silent: true);
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
          : _items.isEmpty
          ? CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: SizedBox(height: MediaQuery.of(context).padding.top),
                ),
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.bookmark_border,
                          size: 64,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '书架空空如也',
                          style: tt.titleMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '去发现页找点好看的漫画吧',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.tonalIcon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('刷新'),
                        ),
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
                  if (n.metrics.pixels > n.metrics.maxScrollExtent - 300) {
                    _loadMore();
                  }
                  return false;
                },
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: MediaQuery.of(context).padding.top,
                      ),
                    ),
                    if (_refreshing)
                      const SliverToBoxAdapter(
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(hp, 4, hp, 8),
                        child: Row(
                          children: [
                            Text(
                              '共 $_total 部收藏',
                              style: tt.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const Spacer(),
                            ActionChip(
                              avatar: const Icon(Icons.sort, size: 18),
                              label: Text(_orderingLabel(_ordering)),
                              onPressed: () {
                                showModalBottomSheet(
                                  context: context,
                                  builder: (_) => SafeArea(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            16,
                                            16,
                                            16,
                                            8,
                                          ),
                                          child: Text(
                                            '排序方式',
                                            style: tt.titleMedium,
                                          ),
                                        ),
                                        _OrderingTile(
                                          icon: Icons.update,
                                          title: '作品更新时间',
                                          subtitle: '按漫画最新章节的更新时间排序',
                                          selected:
                                              _ordering == '-datetime_updated',
                                          onTap: () => _setOrdering(
                                            context,
                                            '-datetime_updated',
                                          ),
                                        ),
                                        _OrderingTile(
                                          icon: Icons.bookmark_added,
                                          title: '收藏时间',
                                          subtitle: '按加入书架的时间排序',
                                          selected:
                                              _ordering == '-datetime_modifier',
                                          onTap: () => _setOrdering(
                                            context,
                                            '-datetime_modifier',
                                          ),
                                        ),
                                        _OrderingTile(
                                          icon: Icons.menu_book,
                                          title: '阅读时间',
                                          subtitle: '按最近阅读/浏览的时间排序',
                                          selected:
                                              _ordering == '-datetime_browse',
                                          onTap: () => _setOrdering(
                                            context,
                                            '-datetime_browse',
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: hp),
                      sliver: SliverGrid(
                        delegate: SliverChildBuilderDelegate((_, i) {
                          final item = _items[i];
                          return Stack(
                            children: [
                              ComicCard(
                                comic: item.comic,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ComicDetailPage(
                                      pathWord: item.comic.pathWord,
                                      lastBrowseId: item.lastBrowseId,
                                      lastBrowseName: item.lastBrowseName,
                                    ),
                                  ),
                                ).then((_) => _load(silent: true)),
                              ),
                              if (item.hasUpdate)
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: cs.error,
                                      borderRadius: const BorderRadius.only(
                                        topRight: Radius.circular(12),
                                        bottomLeft: Radius.circular(10),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: cs.error.withValues(
                                            alpha: 0.6,
                                          ),
                                          blurRadius: 8,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: Text(
                                      '有更新',
                                      style: TextStyle(
                                        color: cs.onError,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        }, childCount: _items.length),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 130,
                              childAspectRatio: 0.55,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                            ),
                      ),
                    ),
                    const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
                  ],
                ),
              ),
            ),
    );
  }
}

class _OrderingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _OrderingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: selected ? cs.primary : null),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: selected ? Icon(Icons.check, color: cs.primary) : null,
      selected: selected,
      onTap: onTap,
    );
  }
}
