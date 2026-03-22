import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/comic.dart' hide Theme;
import 'comic_detail_page.dart';
import 'home_page.dart';

/// 漫画排行完整列表页，支持排序切换
class RankingPage extends StatefulWidget {
  const RankingPage({super.key});

  @override
  State<RankingPage> createState() => _RankingPageState();
}

class _RankingPageState extends State<RankingPage> {
  final _api = ApiClient();
  List<Comic> _comics = [];
  bool _loading = true;
  int _offset = 0;
  int _total = 0;
  bool _loadingMore = false;
  String _ordering = '-popular';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _comics = [];
      _offset = 0;
    });
    try {
      final data = await _api.getComicList(ordering: _ordering, limit: 21);
      setState(() {
        _comics = data.list;
        _total = data.total;
        _offset = data.list.length;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _offset >= _total) return;
    _loadingMore = true;
    try {
      final data = await _api.getComicList(
          ordering: _ordering, limit: 21, offset: _offset);
      setState(() {
        _comics.addAll(data.list);
        _offset = _comics.length;
      });
    } catch (_) {}
    _loadingMore = false;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth.clamp(0.0, 900.0);
    final hp = (screenWidth - contentWidth) / 2 + 16;

    return Scaffold(
      appBar: AppBar(
        title: const Text('漫画排行'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: '-popular',
                    label: Text('热度'),
                    icon: Icon(Icons.whatshot, size: 16)),
                ButtonSegment(
                    value: '-datetime_updated',
                    label: Text('更新'),
                    icon: Icon(Icons.schedule, size: 16)),
              ],
              selected: {_ordering},
              onSelectionChanged: (v) {
                _ordering = v.first;
                _load();
              },
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.pixels > n.metrics.maxScrollExtent - 300) {
                  _loadMore();
                }
                return false;
              },
              child: GridView.builder(
                padding: EdgeInsets.symmetric(horizontal: hp, vertical: 12),
                itemCount: _comics.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 130,
                  childAspectRatio: 0.55,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemBuilder: (_, i) => ComicCard(
                  comic: _comics[i],
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ComicDetailPage(pathWord: _comics[i].pathWord),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
