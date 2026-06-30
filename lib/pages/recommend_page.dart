import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/comic.dart' hide Theme;
import '../utils/app_logger.dart';
import '../utils/comic_hero_tags.dart';
import '../utils/comic_card_skeleton.dart';
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
      if (!mounted) return;
      setState(() {
        _comics = data;
        _offset = data.length;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final data = await _api.getRecommendations(limit: 21, offset: _offset);
      if (!mounted) return;
      setState(() {
        _comics.addAll(data);
        _offset = _comics.length;
      });
    } catch (e, stack) {
      AppLogger.instance.recordWarning(
        e,
        stackTrace: stack,
        source: 'recommend_page.load_more',
      );
    }
    if (mounted) {
      setState(() => _loadingMore = false);
    } else {
      _loadingMore = false;
    }
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
      appBar: AppBar(title: const Text('热门推荐')),
      body: _loading
          ? GridView.builder(
              padding: EdgeInsets.symmetric(horizontal: hp, vertical: 12),
              itemCount: 21,
              gridDelegate: gridDelegate,
              itemBuilder: (_, _) => const ComicCardSkeleton(),
            )
          : NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.pixels > n.metrics.maxScrollExtent - 300) {
                  _loadMore();
                }
                return false;
              },
              child: CustomScrollView(
                slivers: [
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
                          scope: 'recommend',
                          pathWord: comic.pathWord,
                          index: i,
                        );
                        return ComicCard(
                          comic: comic,
                          heroTagBase: heroTagBase,
                          onTap: () => Navigator.push(
                            context,
                            ComicDetailPage.route(
                              pathWord: comic.pathWord,
                              initialComic: comic,
                              heroTagBase: heroTagBase,
                            ),
                          ),
                        );
                      }, childCount: _comics.length + (_loadingMore ? 6 : 0)),
                    ),
                  ),
                  const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
                ],
              ),
            ),
    );
  }
}
