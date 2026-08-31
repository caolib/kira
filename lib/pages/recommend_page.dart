import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
import '../l10n/app_localizations.dart';
import '../models/comic.dart' hide Theme;
import '../routing/app_router.dart';
import '../utils/app_logger.dart';
import '../utils/screen_layout.dart';
import '../widgets/comic_card_skeleton.dart';
import '../widgets/comic_hero_tags.dart';
import '../widgets/load_more_footer.dart';
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
  // 推荐接口不返回 total：以「某页返回空列表」作为到底标志。
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _api.manga.getRecommendations(limit: 21);
      if (!mounted) return;
      setState(() {
        _comics = data;
        _offset = data.length;
        _hasMore = data.isNotEmpty;
        _loading = false;
      });
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'recommend_page.load',
        ),
      );
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final data = await _api.manga.getRecommendations(
        limit: 21,
        offset: _offset,
      );
      if (!mounted) return;
      setState(() {
        _comics.addAll(data);
        _offset = _comics.length;
        _hasMore = data.isNotEmpty;
      });
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'recommend_page.load_more',
        ),
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
    final l10n = AppLocalizations.of(context)!;
    final screenWidth = MediaQuery.of(context).size.width;
    final hp = ScreenLayout.horizontalPadding(screenWidth);
    final cardExtent = ScreenLayout.cardExtent(screenWidth);

    final gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: cardExtent,
      childAspectRatio: 0.55,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.hotRecommend)),
      body: _loading
          ? GridView.builder(
              padding: EdgeInsets.symmetric(horizontal: hp, vertical: 12),
              itemCount: 21,
              gridDelegate: gridDelegate,
              itemBuilder: (_, _) => const ComicCardSkeleton(),
            )
          : NotificationListener<ScrollNotification>(
              onNotification: (n) {
                // pixels > 0：只在用户确实滚动过后才自动翻页，
                // 否则宽屏首屏不满一页时会立刻连发第二页。
                if (n.metrics.pixels > 0 &&
                    n.metrics.pixels > n.metrics.maxScrollExtent - 300) {
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
                          onTap: () => context.pushNamed(
                            AppRoutes.comicDetail,
                            pathParameters: {'pathWord': comic.pathWord},
                            extra: ComicDetailExtra(
                              initialComic: comic,
                              heroTagBase: heroTagBase,
                            ),
                          ),
                        );
                      }, childCount: _comics.length + (_loadingMore ? 6 : 0)),
                    ),
                  ),
                  if (!_loading && _hasMore)
                    SliverToBoxAdapter(
                      child: LoadMoreFooter(
                        loading: _loadingMore,
                        onPressed: _loadMore,
                        label: l10n.loadMore,
                        horizontalPadding: hp,
                      ),
                    ),
                  const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
                ],
              ),
            ),
    );
  }
}
