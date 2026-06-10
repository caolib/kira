part of '../api_client.dart';

mixin _MangaApi on _ApiClientBase {
  // ── 漫画相关 ──

  /// 漫画主页
  Future<MangaHome> getMangaHome() async {
    final data = await _get(
      '/api/v3/h5/discoverIndex/freeComic',
      params: {'platform': 3, '_update': true},
    );
    return MangaHome.fromJson(data);
  }

  // 1. 热门搜索关键词
  Future<List<String>> getHotKeywords() async {
    final data = await _get(
      '/api/v3/search/key',
      params: {'limit': 20, 'offset': 0},
    );
    return (data['list'] as List).map((e) => e['keyword'] as String).toList();
  }

  // 2. 全部漫画标签
  Future<List<Theme>> getComicTags() async {
    final data = await _get(
      '/api/v3/theme/comic/count',
      params: {'free_type': 1, 'limit': 500, 'offset': 0, '_update': true},
    );
    return (data['list'] as List).map((e) => Theme.fromJson(e)).toList();
  }

  // 3. 推荐漫画
  Future<List<Comic>> getRecommendations({
    int pos = 2201202,
    int limit = 24,
    int offset = 0,
  }) async {
    final data = await _get(
      '/api/v3/recs',
      params: {'pos': pos, 'limit': limit, 'offset': offset, 'free_type': 1},
    );
    return (data['list'] as List)
        .where((e) => e['comic'] != null)
        .map((e) => Comic.fromJson(e['comic']))
        .toList();
  }

  // 4. 漫画列表
  Future<({List<Comic> list, int total})> getComicList({
    String ordering = '-popular',
    int limit = 21,
    int offset = 0,
    String? theme,
  }) async {
    final params = <String, dynamic>{
      'free_type': 1,
      'limit': limit,
      'offset': offset,
      'ordering': ordering,
    };
    if (theme != null) params['theme'] = theme;
    final data = await _get('/api/v3/comics', params: params);
    final list = (data['list'] as List).map((e) => Comic.fromJson(e)).toList();
    return (list: list, total: data['total'] as int);
  }

  // 5. 漫画详情
  Future<Comic> getComicDetail(String pathWord) async {
    final data = await _get(
      '/api/v3/comic2/$pathWord',
      params: {'platform': 3},
    );
    return Comic.fromDetailJson(data);
  }

  // 6. 用户状态查询
  Future<Map<String, dynamic>> getComicQuery(String pathWord) async {
    return await _get('/api/v3/comic2/$pathWord/query');
  }

  // 7. 章节列表
  Future<({List<Chapter> list, int total})> getChapterList(
    String pathWord, {
    String group = 'default',
    int limit = 100,
    int offset = 0,
  }) async {
    final data = await _get(
      '/api/v3/comic/$pathWord/group/$group/chapters',
      params: {'limit': limit, 'offset': offset},
    );
    final list = (data['list'] as List)
        .map((e) => Chapter.fromJson(e))
        .toList();
    return (list: list, total: data['total'] as int);
  }

  // 8. 搜索漫画
  Future<({List<Comic> list, int total})> searchComics(
    String query, {
    int limit = 20,
    int offset = 0,
  }) async {
    final data = await _get(
      '/api/v3/search/comic',
      params: {
        'platform': 3,
        'q': query,
        'limit': limit,
        'offset': offset,
        'free_type': 1,
        '_update': true,
      },
    );
    final list = (data['list'] as List).map((e) => Comic.fromJson(e)).toList();
    return (list: list, total: data['total'] as int);
  }

  // 9. 章节详情
  Future<ChapterDetail> getChapterDetail(
    String pathWord,
    String chapterUuid, {
    bool forceRefresh = false,
  }) async {
    final cacheKey = _chapterDetailCacheKey(pathWord, chapterUuid);
    if (!forceRefresh) {
      final cached = await _cache.get(cacheKey);
      if (cached is Map) {
        try {
          final detail = ChapterDetail.fromJson(
            Map<String, dynamic>.from(cached),
          );
          if (detail.contents.isNotEmpty) {
            return detail;
          }
          await _cache.remove(cacheKey);
        } catch (_) {
          await _cache.remove(cacheKey);
        }
      }
    }

    final params = <String, dynamic>{'platform': 3};
    if (forceRefresh) params['_update'] = true;

    final data = await _get(
      '/api/v3/comic/$pathWord/chapter/$chapterUuid',
      params: params,
    );
    final detail = ChapterDetail.fromJson(data);
    if (detail.contents.isNotEmpty) {
      await _cache.put(cacheKey, data);
    }
    return detail;
  }

  String _chapterDetailCacheKey(String pathWord, String chapterUuid) =>
      'manga_chapter_detail_v1_'
      '${Uri.encodeComponent(pathWord)}_'
      '${Uri.encodeComponent(chapterUuid)}';

  // 9.1 章节评论
  Future<({List<ChapterComment> list, int total})> getChapterComments(
    String chapterId, {
    int limit = 30,
    int offset = 0,
  }) async {
    final resp = await _commentDio.get(
      'https://$_hostComment/api/v3/roasts',
      queryParameters: {
        'chapter_id': chapterId,
        'limit': limit,
        'offset': offset,
        '_update': true,
      },
      options: _browserRequestOptions(_hostComment),
    );
    final results = resp.data['results'] as Map<String, dynamic>;
    final list = (results['list'] as List)
        .map((e) => ChapterComment.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return (list: list, total: results['total'] as int? ?? 0);
  }

  // 9.2 章节发表评论
  Future<void> postChapterComment(String chapterId, String content) async {
    final trimmed = content.trim();
    final length = trimmed.runes.length;
    if (length < 3 || length > 200) {
      throw ArgumentError('评论字数需在 3-200 之间');
    }

    final token = _user.token;
    if (token == null || token.isEmpty) {
      throw const HttpException('请先登录后再发表评论');
    }

    final resp = await _commentDio.post(
      'https://$_hostComment/api/v3/member/roast',
      data: {'chapter_id': chapterId, 'roast': trimmed, '_update': true},
      options: _browserRequestOptions(
        _hostComment,
        contentType: Headers.formUrlEncodedContentType,
        headers: {'Authorization': 'Token $token'},
      ),
    );

    final data = resp.data;
    if (data is Map) {
      final code = data['code'];
      if (code != null && code != 200) {
        final message = data['message']?.toString() ?? '发表评论失败';
        throw DioException(
          requestOptions: resp.requestOptions,
          response: resp,
          message: message,
          error: message,
          type: DioExceptionType.badResponse,
        );
      }
    }
  }

  // 9.3 漫画评论 / 评论回复
  Future<({List<ComicComment> list, int total})> getComicComments(
    String comicId, {
    String replyId = '',
    int limit = 10,
    int offset = 0,
  }) async {
    final resp = await _commentDio.get(
      'https://$_hostComment/api/v3/comments',
      queryParameters: {
        'comic_id': comicId,
        'reply_id': replyId,
        'limit': limit,
        'offset': offset,
        'platform': 3,
      },
      options: _browserRequestOptions(_hostComment, secFetchSite: 'cross-site'),
    );
    final results = resp.data['results'] as Map<String, dynamic>;
    final list = (results['list'] as List)
        .map((e) => ComicComment.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return (list: list, total: results['total'] as int? ?? 0);
  }

  // 10. 个人书架
  Future<({List<BookshelfItem> list, int total})> getBookshelf({
    int limit = 12,
    int offset = 0,
    String ordering = '-datetime_modifier',
  }) async {
    final data = await _get(
      '/api/v3/member/collect/comics',
      params: {
        'free_type': 1,
        'limit': limit,
        'offset': offset,
        'ordering': ordering,
        '_update': true,
      },
    );
    final list = (data['list'] as List).map((e) {
      final comic = Comic.fromJson(e['comic']);
      final browse = e['last_browse'];
      return BookshelfItem(
        comic: comic,
        lastBrowseId: browse is Map
            ? browse['last_browse_id']?.toString()
            : null,
        lastBrowseName: browse is Map
            ? browse['last_browse_name']?.toString()
            : null,
      );
    }).toList();
    return (list: list, total: data['total'] as int);
  }

  // 11. 收藏/取消收藏漫画
  Future<void> toggleCollect(String comicId, {required bool collect}) async {
    await _dio.post(
      _url('/api/v3/member/collect/comic'),
      data: 'comic_id=$comicId&is_collect=${collect ? 1 : 0}',
      options: Options(contentType: 'application/x-www-form-urlencoded'),
    );
  }
}
