part of '../api_client.dart';

mixin _AnimeApi on _ApiClientBase {
  // ── 动漫相关 ──

  Future<({List<AnimeBrowseHistoryItem> list, int total})>
  getAnimeBrowseHistory({int limit = 20, int offset = 0}) async {
    final data = await _get(
      '/api/v3/member/browse/cartoons',
      params: {
        'free_type': 1,
        'offset': offset,
        'limit': limit,
        '_update': true,
      },
    );
    final list = (data['list'] as List? ?? const []).whereType<Map>().map((e) {
      final item = Map<String, dynamic>.from(e);
      return AnimeBrowseHistoryItem(
        id: item['id'] as int? ?? 0,
        lastBrowseId: item['last_chapter_id']?.toString(),
        lastBrowseName: item['last_chapter_name']?.toString(),
        anime: Anime.fromJson(Map<String, dynamic>.from(item['cartoon'] ?? {})),
      );
    }).toList();
    return (list: list, total: data['total'] as int? ?? list.length);
  }

  Future<({List<Anime> list, int total})> searchAnimes(
    String query, {
    int limit = 20,
    int offset = 0,
  }) async {
    final data = await _get(
      '/api/v3/search/cartoon',
      params: {
        'platform': 3,
        'q': query,
        'limit': limit,
        'offset': offset,
        'free_type': 1,
        '_update': true,
      },
    );
    final list = (data['list'] as List)
        .map((e) => Anime.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return (list: list, total: data['total'] as int);
  }

  Future<({List<AnimeBookshelfItem> list, int total})> getAnimeBookshelf({
    int limit = 30,
    int offset = 0,
    String ordering = '-datetime_modifier',
  }) async {
    final data = await _get(
      '/api/v3/member/collect/cartoons',
      params: {
        'free_type': 1,
        'limit': limit,
        'offset': offset,
        'ordering': ordering,
        '_update': true,
      },
    );
    final list = (data['list'] as List? ?? const []).whereType<Map>().map((e) {
      final item = Map<String, dynamic>.from(e);
      final browse = item['last_browse'];
      return AnimeBookshelfItem(
        anime: Anime.fromJson(Map<String, dynamic>.from(item['cartoon'] ?? {})),
        lastBrowseId: browse is Map
            ? browse['last_chapter_id']?.toString()
            : null,
        lastBrowseName: browse is Map
            ? browse['last_chapter_name']?.toString()
            : null,
      );
    }).toList();
    return (list: list, total: data['total'] as int? ?? list.length);
  }

  /// 动漫首页
  Future<AnimeHome> getAnimeHome() async {
    final data = await _get('/api/v3/h5/homeIndex/cartoonsfree');
    return AnimeHome.fromJson(data);
  }

  Future<({List<Anime> list, int total})> getAnimeRecommendations({
    required int pos,
    int limit = 24,
    int offset = 0,
  }) async {
    final data = await _get(
      '/api/v3/recs',
      params: {'pos': pos, 'limit': limit, 'offset': offset},
    );
    final rawList = data['list'] as List? ?? const [];
    final list = rawList
        .where((e) => e is Map && e['comic'] is Map)
        .map(
          (e) => Anime.fromJson(Map<String, dynamic>.from((e as Map)['comic'])),
        )
        .toList();
    return (list: list, total: data['total'] as int? ?? list.length);
  }

  Future<({List<AnimeUpdate> list, int total})> getAnimeUpdates({
    int limit = 21,
    int offset = 0,
  }) async {
    final data = await _get(
      '/api/v3/updates',
      params: {'date': 'weekly-cartoon-free', 'limit': limit, 'offset': offset},
    );
    final rawList = data['list'] as List? ?? const [];
    final list = rawList
        .where((e) => e is Map && e['cartoon'] is Map)
        .map((e) => AnimeUpdate.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return (list: list, total: data['total'] as int? ?? list.length);
  }

  Future<Anime> getAnimeDetail(String pathWord) async {
    final data = await _get(
      '/api/v3/cartoon2/$pathWord',
      params: {'platform': 3, '_update': true},
    );
    return Anime.fromDetailJson(data);
  }

  Future<AnimeQuery> getAnimeQuery(String pathWord) async {
    final data = await _get(
      '/api/v3/cartoon2/$pathWord/query',
      params: {'platform': 3, '_update': true},
    );
    return AnimeQuery.fromJson(data);
  }

  Future<({List<AnimeChapter> list, int total})> getAnimeChapters(
    String pathWord, {
    int limit = 100,
    int offset = 0,
  }) async {
    final data = await _get(
      '/api/v3/cartoon/$pathWord/chapters2',
      params: {'limit': limit, 'offset': offset, '_update': true},
    );
    final rawList = data['list'] as List? ?? const [];
    final list = rawList
        .whereType<Map>()
        .map((e) => AnimeChapter.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return (list: list, total: data['total'] as int? ?? list.length);
  }

  Future<void> toggleAnimeCollect(
    String cartoonId, {
    required bool collect,
  }) async {
    await _dio.post(
      _url('/api/v3/member/collect/cartoon'),
      data: 'cartoon_id=$cartoonId&is_collect=${collect ? 1 : 0}',
      options: Options(contentType: 'application/x-www-form-urlencoded'),
    );
  }

  Future<AnimePlayback> getAnimePlayback(
    String pathWord,
    String chapterUuid, {
    required String line,
    bool forceRefresh = false,
  }) async {
    final cacheKey = _animePlaybackCacheKey(pathWord, chapterUuid, line);
    if (!forceRefresh) {
      final cached = await _cache.get(cacheKey);
      if (cached is Map) {
        try {
          final playback = AnimePlayback.fromJson(
            Map<String, dynamic>.from(cached),
          );
          if (_resolveAnimeVideoUrl(playback.chapter).isNotEmpty) {
            return playback;
          }
        } catch (_) {
          await _cache.remove(cacheKey);
        }
      }
    } else {
      await _cache.remove(cacheKey);
    }

    final data = await _get(
      '/api/v3/cartoon/$pathWord/chapter/$chapterUuid',
      params: {'platform': 3, 'line': line},
    );
    final playback = AnimePlayback.fromJson(data);
    if (_resolveAnimeVideoUrl(playback.chapter).isNotEmpty) {
      await _cache.put(
        cacheKey,
        playback.toJson(),
        ttl: const Duration(hours: 6),
      );
    }
    return playback;
  }

  Future<void> clearAnimePlaybackCache(String pathWord) async {
    await _cache.removeByPrefix(_animePlaybackCachePrefix(pathWord));
  }

  String _animePlaybackCachePrefix(String pathWord) =>
      'anime_video_link_v1_${pathWord}_';

  String _animePlaybackCacheKey(
    String pathWord,
    String chapterUuid,
    String line,
  ) => '${_animePlaybackCachePrefix(pathWord)}${chapterUuid}_$line';

  String _resolveAnimeVideoUrl(AnimePlaybackChapter chapter) {
    if (chapter.video.isNotEmpty) return chapter.video;
    for (final url in chapter.videoList) {
      if (url.isNotEmpty) return url;
    }
    return '';
  }
}
