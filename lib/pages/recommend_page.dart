import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/comic.dart' hide Theme;
import 'comic_detail_page.dart';
import 'home_page.dart';

/// 推荐漫画完整列表页
class RecommendPage extends StatefulWidget {
  const RecommendPage({super.key});

  @override
  State<RecommendPage> createState() => _RecommendPageState();
}

class _RecommendPageState extends State<RecommendPage> {
  final _api = ApiClient();
  List<Comic> _comics = [];
  bool _loading = true;
  int _offset = 0;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _api.getRecommendations(limit: 21);
      setState(() {
        _comics = data;
        _offset = data.length;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    _loadingMore = true;
    try {
      final data = await _api.getRecommendations(limit: 21, offset: _offset);
      setState(() {
        _comics.addAll(data);
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
      appBar: AppBar(title: const Text('热门推荐')),
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
                  maxCrossAxisExtent: 160,
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
