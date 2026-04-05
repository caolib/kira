import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/comic.dart' hide Theme;
import '../models/user_manager.dart';
import '../utils/toast.dart';
import 'comic_detail_page.dart';

class BrowseHistoryPage extends StatefulWidget {
  final WidgetBuilder loginPageBuilder;

  const BrowseHistoryPage({super.key, required this.loginPageBuilder});

  @override
  State<BrowseHistoryPage> createState() => _BrowseHistoryPageState();
}

class _BrowseHistoryPageState extends State<BrowseHistoryPage> {
  final _api = ApiClient();
  final _user = UserManager();

  List<BrowseHistoryItem> _items = [];
  bool _loading = true;
  bool _refreshing = false;
  bool _loadingMore = false;
  bool _showingLoginPrompt = false;
  int _offset = 0;
  int _total = 0;

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
        _offset = 0;
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
      setState(() {});
    }
    _offset = 0;
    try {
      final data = await _api.getBrowseHistory();
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
    _loadingMore = true;
    try {
      final data = await _api.getBrowseHistory(offset: _offset);
      if (!mounted) return;
      setState(() {
        _items.addAll(data.list);
        _offset = _items.length;
      });
    } catch (e) {
      debugPrint('BrowseHistoryPage loadMore error: $e');
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth.clamp(0.0, 900.0);
    final hp = (screenWidth - contentWidth) / 2 + 16;

    return Scaffold(
      appBar: AppBar(title: const Text('浏览记录')),
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
                      '浏览过的漫画会同步显示在这里',
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
          : _items.isEmpty
          ? CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  child: Center(
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
                          '还没有浏览记录',
                          style: tt.titleMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '去看几部漫画后，这里会显示最近浏览内容',
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
                    if (_refreshing)
                      const SliverToBoxAdapter(
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(hp, 12, hp, 8),
                        child: Text(
                          '共 $_total 条浏览记录',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(hp, 0, hp, 24),
                      sliver: SliverList.builder(
                        itemCount: _items.length,
                        itemBuilder: (_, i) {
                          final item = _items[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _BrowseHistoryCard(item: item),
                          );
                        },
                      ),
                    ),
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

class _BrowseHistoryCard extends StatelessWidget {
  final BrowseHistoryItem item;
  const _BrowseHistoryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final comic = item.comic;
    final authors = comic.authors.map((e) => e.name).where((e) => e.isNotEmpty);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ComicDetailPage(
              pathWord: comic.pathWord,
              lastBrowseId: item.lastBrowseId,
              lastBrowseName: item.lastBrowseName,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 84,
                child: AspectRatio(
                  aspectRatio: 0.72,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: comic.cover,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(
                        color: cs.surfaceContainerHighest,
                        child: Center(
                          child: Icon(
                            Icons.image,
                            color: cs.onSurfaceVariant,
                            size: 28,
                          ),
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
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comic.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (authors.isNotEmpty)
                      Text(
                        authors.join(' / '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    if (item.lastBrowseName != null &&
                        item.lastBrowseName!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            Icons.menu_book_outlined,
                            size: 16,
                            color: cs.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '上次看到 ${item.lastBrowseName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (comic.lastChapterName != null &&
                        comic.lastChapterName!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        '最新 ${comic.lastChapterName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _HistoryMetaChip(
                          icon: Icons.local_fire_department,
                          label: _BrowseHistoryPageState.formatPopular(
                            comic.popular,
                          ),
                        ),
                        if (comic.datetimeUpdated != null)
                          _HistoryMetaChip(
                            icon: Icons.schedule,
                            label: _BrowseHistoryPageState.formatRelativeTime(
                              comic.datetimeUpdated!,
                            ),
                          ),
                      ],
                    ),
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
