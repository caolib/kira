import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
import '../l10n/app_localizations.dart';
import '../models/api_ordering.dart';
import '../models/comic.dart' hide Theme;
import '../routing/app_router.dart';
import '../utils/app_logger.dart';
import '../widgets/comic_card_skeleton.dart';
import '../widgets/comic_hero_tags.dart';
import 'home_page.dart';

/// 漫画排行完整列表页，支持排序切换
class RankingPage extends StatefulWidget {
  final String? authorPathWord;
  final String? authorName;
  final String? themePathWord;
  final String? themeName;

  const RankingPage({
    super.key,
    this.authorPathWord,
    this.authorName,
    this.themePathWord,
    this.themeName,
  });

  const RankingPage.author({
    super.key,
    required this.authorPathWord,
    required this.authorName,
  }) : themePathWord = null,
       themeName = null;

  const RankingPage.theme({
    super.key,
    required this.themePathWord,
    required this.themeName,
  }) : authorPathWord = null,
       authorName = null;

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
  late String _ordering;

  bool get _isAuthorMode => widget.authorPathWord?.isNotEmpty == true;
  bool get _isThemeMode => widget.themePathWord?.isNotEmpty == true;
  String _title(AppLocalizations l10n) => _isAuthorMode
      ? (widget.authorName?.isNotEmpty == true
            ? widget.authorName!
            : l10n.rankingAuthorWorks)
      : _isThemeMode
      ? (widget.themeName?.isNotEmpty == true
            ? widget.themeName!
            : l10n.rankingThemeWorks)
      : l10n.comicRanking;
  String get _scope => _isAuthorMode
      ? 'author-${widget.authorPathWord}'
      : _isThemeMode
      ? 'theme-${widget.themePathWord}'
      : 'ranking';
  String _emptyText(AppLocalizations l10n) => _isAuthorMode
      ? l10n.rankingNoAuthorWorks
      : _isThemeMode
      ? l10n.rankingNoThemeWorks
      : l10n.rankingNoComics;

  @override
  void initState() {
    super.initState();
    _ordering = _isFilteredMode
        ? ApiOrdering.popular
        : ApiOrdering.datetimeUpdated;
    _load();
  }

  bool get _isFilteredMode => _isAuthorMode || _isThemeMode;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _comics = [];
      _offset = 0;
    });
    try {
      final data = await _api.manga.getComicList(
        ordering: _ordering,
        author: widget.authorPathWord,
        theme: widget.themePathWord,
      );
      if (!mounted) return;
      setState(() {
        _comics = data.list;
        _total = data.total;
        _offset = data.list.length;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _offset >= _total) return;
    setState(() => _loadingMore = true);
    try {
      final data = await _api.manga.getComicList(
        ordering: _ordering,
        offset: _offset,
        author: widget.authorPathWord,
        theme: widget.themePathWord,
      );
      if (!mounted) return;
      setState(() {
        _comics.addAll(data.list);
        _offset = _comics.length;
      });
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'ranking_page.load_more',
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
    final contentWidth = screenWidth.clamp(0.0, 900.0);
    final hp = (screenWidth - contentWidth) / 2 + 16;

    const gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 130,
      childAspectRatio: 0.55,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_title(l10n), maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: ApiOrdering.popular,
                  label: Text(l10n.popularOrder),
                  icon: const Icon(Icons.whatshot, size: 16),
                ),
                ButtonSegment(
                  value: ApiOrdering.datetimeUpdated,
                  label: Text(l10n.updateOrder),
                  icon: const Icon(Icons.schedule, size: 16),
                ),
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
                  if (_comics.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: Text(_emptyText(l10n))),
                    )
                  else
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
                  const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
                ],
              ),
            ),
    );
  }
}
