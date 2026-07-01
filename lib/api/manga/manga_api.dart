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

  /// COPY 漫画主页
  Future<CopyMangaHome> getCopyMangaHome() async {
    final data = await _copyGet(
      '/api/v3/h5/homeIndex2',
      params: {'platform': 3},
      errorMessage: '加载 COPY 首页失败',
    );
    return CopyMangaHome.fromJson(data);
  }

  /// COPY 推荐更多
  Future<({List<Comic> list, int total})> getCopyRecommendations({
    int limit = 21,
    int offset = 0,
  }) async {
    final data = await _copyGet(
      '/api/v3/recs',
      params: {'pos': 3200102, 'limit': limit, 'offset': offset, 'platform': 3},
      errorMessage: '加载 COPY 推荐失败',
    );
    return _parseCopyNestedComicResult(data);
  }

  /// COPY 全新上架更多
  Future<({List<Comic> list, int total})> getCopyNewestComics({
    int limit = 21,
    int offset = 0,
  }) async {
    final data = await _copyGet(
      '/api/v3/update/newest',
      params: {'date': '', 'limit': limit, 'offset': offset, 'platform': 3},
      errorMessage: '加载 COPY 全新上架失败',
    );
    return _parseCopyNestedComicResult(data);
  }

  /// COPY 已完结更多
  Future<({List<Comic> list, int total})> getCopyFinishedComics({
    int limit = 21,
    int offset = 0,
  }) async {
    final data = await _copyGet(
      '/api/v3/comics',
      params: {
        'limit': limit,
        'offset': offset,
        'top': 'finish',
        'ordering': ApiOrdering.datetimeUpdated,
        'free_type': 1,
        'platform': 3,
      },
      errorMessage: '加载 COPY 已完结失败',
    );
    return _parseCopyDirectComicResult(data);
  }

  /// COPY 排行榜更多
  Future<({List<Comic> list, int total})> getCopyRankComics({
    String dateType = 'day',
    String audienceType = 'male',
    int limit = 21,
    int offset = 0,
  }) async {
    final data = await _copyGet(
      '/api/v3/ranks',
      params: {
        'type': 1,
        'date_type': dateType,
        'limit': limit,
        'offset': offset,
        'audience_type': audienceType,
        'platform': 3,
      },
      errorMessage: '加载 COPY 排行榜失败',
    );
    return _parseCopyNestedComicResult(data);
  }

  /// 自动获取 COPY App 最新版本号。
  Future<String> fetchCopyLatestAppVersion() async {
    final resp = await _copyMinimalDio().get(
      'https://${_user.copyApiHost}/api/v3/system/appVersion/last',
      queryParameters: {'platform': 3},
    );
    final data = _decodeCopyResponse(resp.data);
    final version = _copyAppVersionFromResponse(data);
    if (resp.statusCode == 200 && version != null) {
      return version;
    }

    final message = data is Map
        ? (data['message']?.toString() ?? '获取 COPY 版本号失败')
        : '获取 COPY 版本号失败';
    NetworkError.throwBadResponse(
      response: resp,
      message: message,
      source: 'copy_api',
    );
  }

  Map<String, String> _copyBasicHeaders() {
    final version = _user.copyAppVersion;
    return {
      'User-Agent': 'COPY/$version',
      'Accept': 'application/json',
      'source': 'copyApp',
      'platform': '3',
      'version': version,
    };
  }

  Dio _copyDio() {
    return AppDio.create(
      source: 'copy_api',
      options: BaseOptions(
        validateStatus: (_) => true,
        headers: {
          ..._copyBasicHeaders(),
          'Connection': 'keep-alive',
          'Accept-Encoding': 'gzip',
          'webp': '1',
        },
      ),
    );
  }

  Dio _copyMinimalDio() {
    return AppDio.create(
      source: 'copy_api',
      options: BaseOptions(
        validateStatus: (_) => true,
        headers: _copyBasicHeaders(),
      ),
    );
  }

  Future<Map<String, dynamic>> _copyGet(
    String path, {
    Map<String, dynamic>? params,
    required String errorMessage,
  }) async {
    final resp = await _copyDio().get(
      'https://${_user.copyApiHost}$path',
      queryParameters: params,
    );

    final data = resp.data;
    if (data is Map && data['code'] == 200 && data['results'] is Map) {
      return Map<String, dynamic>.from(data['results'] as Map);
    }

    final message = data is Map
        ? (data['message']?.toString() ?? errorMessage)
        : errorMessage;
    NetworkError.throwBadResponse(
      response: resp,
      message: message,
      source: 'copy_api',
    );
  }

  dynamic _decodeCopyResponse(dynamic data) {
    if (data is String && data.isNotEmpty) {
      try {
        return jsonDecode(data);
      } catch (_) {
        return data;
      }
    }
    return data;
  }

  String? _copyAppVersionFromResponse(dynamic data) {
    if (data is! Map) return null;
    final code = data['code'];
    if (code != 200 && code?.toString() != '200') return null;

    final results = data['results'];
    if (results is! Map) return null;

    final android = results['android'];
    final androidVersion = android is Map
        ? _nonEmptyCopyVersion(android['version'])
        : null;
    if (androidVersion != null) return androidVersion;

    final directVersion = _nonEmptyCopyVersion(results['version']);
    if (directVersion != null) return directVersion;

    for (final value in results.values) {
      if (value is Map) {
        final version = _nonEmptyCopyVersion(value['version']);
        if (version != null) return version;
      }
    }
    return null;
  }

  String? _nonEmptyCopyVersion(dynamic value) {
    final version = value?.toString().trim() ?? '';
    return version.isEmpty ? null : version;
  }

  ({List<Comic> list, int total}) _parseCopyNestedComicResult(
    Map<String, dynamic> data,
  ) {
    final rawList = data['list'];
    final list = rawList is List
        ? rawList
              .where((e) => e is Map && e['comic'] is Map)
              .map(
                (e) => Comic.fromJson(
                  Map<String, dynamic>.from((e as Map)['comic'] as Map),
                ),
              )
              .toList()
        : <Comic>[];
    return (list: list, total: _copyTotal(data, list.length));
  }

  ({List<Comic> list, int total}) _parseCopyDirectComicResult(
    Map<String, dynamic> data,
  ) {
    final rawList = data['list'];
    final list = rawList is List
        ? rawList
              .whereType<Map>()
              .map((e) => Comic.fromJson(Map<String, dynamic>.from(e)))
              .toList()
        : <Comic>[];
    return (list: list, total: _copyTotal(data, list.length));
  }

  int _copyTotal(Map<String, dynamic> data, int fallback) {
    final total = data['total'];
    if (total is int) return total;
    return int.tryParse(total?.toString() ?? '') ?? fallback;
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
    String ordering = ApiOrdering.popular,
    int limit = 21,
    int offset = 0,
    String? theme,
    String? author,
  }) async {
    final params = <String, dynamic>{
      'free_type': 1,
      'limit': limit,
      'offset': offset,
      'ordering': ordering,
    };
    if (theme != null) params['theme'] = theme;
    if (author != null) params['author'] = author;
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
    return _get('/api/v3/comic2/$pathWord/query');
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
    final host = _user.copyApiHost;
    final resp = await _commentDio.get(
      'https://$host/api/v3/roasts',
      queryParameters: {
        'chapter_id': chapterId,
        'limit': limit,
        'offset': offset,
        '_update': true,
      },
      options: _browserRequestOptions(host),
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

    final host = _user.copyApiHost;
    final resp = await _commentDio.post(
      'https://$host/api/v3/member/roast',
      data: {'chapter_id': chapterId, 'roast': trimmed, '_update': true},
      options: _browserRequestOptions(
        host,
        contentType: Headers.formUrlEncodedContentType,
        headers: {'Authorization': 'Token $token'},
      ),
    );

    final data = resp.data;
    if (data is Map) {
      final code = data['code'];
      if (code != null && code != 200) {
        final message = data['message']?.toString() ?? '发表评论失败';
        NetworkError.throwBadResponse(
          response: resp,
          message: message,
          source: 'api_comment',
        );
      }
    }
  }

  // 9.3 发表漫画评论 / 回复漫画评论
  Future<void> postComicComment(
    String comicId,
    String content, {
    int? replyId,
  }) async {
    final trimmed = content.trim();
    final length = trimmed.runes.length;
    if (length < 3 || length > 200) {
      throw ArgumentError('评论字数需在 3-200 之间');
    }

    final token = _user.token;
    if (token == null || token.isEmpty) {
      throw const HttpException('请先登录后再发表评论');
    }

    final host = _user.copyApiHost;
    final data = <String, dynamic>{'comic_id': comicId, 'comment': trimmed};
    if (replyId != null) {
      data['reply_id'] = replyId.toString();
    }

    final resp = await _commentDio.post(
      'https://$host/api/v3/member/comment',
      data: data,
      queryParameters: {'platform': 3},
      options: _browserRequestOptions(
        host,
        contentType: Headers.formUrlEncodedContentType,
        headers: {'Authorization': 'Token $token'},
      ),
    );

    final body = resp.data;
    if (body is Map) {
      final code = body['code'];
      if (code != null && code != 200) {
        final message = body['message']?.toString() ?? '发表评论失败';
        NetworkError.throwBadResponse(
          response: resp,
          message: message,
          source: 'api_comment',
        );
      }
    }
  }

  // 9.4 漫画评论 / 评论回复
  Future<({List<ComicComment> list, int total})> getComicComments(
    String comicId, {
    String replyId = '',
    int limit = 10,
    int offset = 0,
  }) async {
    final host = _user.copyApiHost;
    final resp = await _commentDio.get(
      'https://$host/api/v3/comments',
      queryParameters: {
        'comic_id': comicId,
        'reply_id': replyId,
        'limit': limit,
        'offset': offset,
        'platform': 3,
      },
      options: _browserRequestOptions(host, secFetchSite: 'cross-site'),
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
    String ordering = ApiOrdering.datetimeModifier,
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
