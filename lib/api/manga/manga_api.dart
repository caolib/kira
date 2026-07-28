import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../models/api_ordering.dart';
import '../../models/chapter.dart';
import '../../models/chapter_comment.dart';
import '../../models/comic.dart';
import '../../models/comic_comment.dart';
import '../../utils/app_dio.dart';
import '../../utils/comment_text.dart';
import '../../utils/json_helpers.dart';
import '../../utils/network_error.dart';
import '../api_transport.dart';

class MangaApi {
  final ApiTransport _t;

  MangaApi(this._t);

  /// 从 JSON 中安全取出对象列表，跳过结构不符的条目。
  ///
  /// 取代 `(data['list'] as List).map(...)`：接口返回异常 payload 时
  /// 应当得到空列表，而不是在解析处抛 TypeError。
  static List<T> _mapList<T>(
    Map<String, dynamic>? json,
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    return jsonList(json, key)
        .whereType<Map>()
        .map((e) => fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  // Manga APIs

  /// Manga home.
  Future<MangaHome> getMangaHome() async {
    final data = await _t.get(
      '/api/v3/h5/discoverIndex/freeComic',
      params: {'platform': 3, '_update': true},
    );
    return MangaHome.fromJson(data);
  }

  /// COPY manga home.
  Future<CopyMangaHome> getCopyMangaHome() async {
    final data = await _copyGet(
      '/api/v3/h5/homeIndex2',
      params: {'platform': 3},
      errorMessage: 'Failed to load COPY home',
    );
    return CopyMangaHome.fromJson(data);
  }

  /// More COPY recommendations.
  Future<({List<Comic> list, int total})> getCopyRecommendations({
    int limit = 21,
    int offset = 0,
  }) async {
    final data = await _copyGet(
      '/api/v3/recs',
      params: {'pos': 3200102, 'limit': limit, 'offset': offset, 'platform': 3},
      errorMessage: 'Failed to load COPY recommendations',
    );
    return _parseCopyNestedComicResult(data);
  }

  /// More COPY newest comics.
  Future<({List<Comic> list, int total})> getCopyNewestComics({
    int limit = 21,
    int offset = 0,
  }) async {
    final data = await _copyGet(
      '/api/v3/update/newest',
      params: {'date': '', 'limit': limit, 'offset': offset, 'platform': 3},
      errorMessage: 'Failed to load COPY newest comics',
    );
    return _parseCopyNestedComicResult(data);
  }

  /// More COPY finished comics.
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
      errorMessage: 'Failed to load COPY finished comics',
    );
    return _parseCopyDirectComicResult(data);
  }

  /// More COPY ranking comics.
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
      errorMessage: 'Failed to load COPY ranking',
    );
    return _parseCopyNestedComicResult(data);
  }

  /// Fetches latest COPY app version automatically.
  Future<String> fetchCopyLatestAppVersion() async {
    final resp = await _copyMinimalDio().get(
      'https://${_t.user.copyApiHost}/api/v3/system/appVersion/last',
      queryParameters: {'platform': 3},
    );
    final data = _decodeCopyResponse(resp.data);
    final version = _copyAppVersionFromResponse(data);
    if (resp.statusCode == 200 && version != null) {
      return version;
    }

    final message = data is Map
        ? (data['message']?.toString() ?? 'Failed to fetch COPY app version')
        : 'Failed to fetch COPY app version';
    NetworkError.throwBadResponse(
      response: resp,
      message: message,
      source: 'copy_api',
    );
  }

  Map<String, String> _copyBasicHeaders() {
    final version = _t.user.copyAppVersion;
    return {
      'User-Agent': 'COPY/$version',
      'Accept': 'application/json',
      'source': 'copyApp',
      'platform': '3',
      'version': version,
    };
  }

  /// Long-lived COPY clients.
  ///
  /// These are reused across requests so the underlying HttpClient connection
  /// pool survives — creating a Dio per call leaked sockets and forced a fresh
  /// TLS handshake every time. Headers depend on the user-configurable app
  /// version, so they are injected per request instead of baked into
  /// [BaseOptions].
  late final Dio _copyDioInstance = _createCopyDio(
    extraHeaders: const {
      'Connection': 'keep-alive',
      'Accept-Encoding': 'gzip',
      'webp': '1',
    },
  );

  late final Dio _copyMinimalDioInstance = _createCopyDio();

  Dio _createCopyDio({Map<String, String> extraHeaders = const {}}) {
    return AppDio.create(
      source: 'copy_api',
      options: BaseOptions(validateStatus: (_) => true),
      interceptors: [
        InterceptorsWrapper(
          onRequest: (options, handler) {
            options.headers.addAll({..._copyBasicHeaders(), ...extraHeaders});
            handler.next(options);
          },
        ),
      ],
    );
  }

  Dio _copyDio() => _copyDioInstance;

  Dio _copyMinimalDio() => _copyMinimalDioInstance;

  Future<Map<String, dynamic>> _copyGet(
    String path, {
    Map<String, dynamic>? params,
    required String errorMessage,
  }) async {
    final resp = await _copyDio().get(
      'https://${_t.user.copyApiHost}$path',
      queryParameters: params,
    );

    final data = resp.data;
    if (data is Map && data['code'] == 200) {
      final results = jsonMap(Map<String, dynamic>.from(data), 'results');
      if (results != null) return results;
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
              .whereType<Map>()
              .map((e) => jsonMap(Map<String, dynamic>.from(e), 'comic'))
              .whereType<Map<String, dynamic>>()
              .map(Comic.fromJson)
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

  // 1. Hot search keywords
  Future<List<String>> getHotKeywords() async {
    final data = await _t.get(
      '/api/v3/search/key',
      params: {'limit': 20, 'offset': 0},
    );
    return jsonList(data, 'list')
        .whereType<Map>()
        .map((e) => jsonString(Map<String, dynamic>.from(e), 'keyword'))
        .where((keyword) => keyword.isNotEmpty)
        .toList();
  }

  // 2. All comic tags
  Future<List<Theme>> getComicTags() async {
    final data = await _t.get(
      '/api/v3/theme/comic/count',
      params: {'free_type': 1, 'limit': 500, 'offset': 0, '_update': true},
    );
    return _mapList(data, 'list', Theme.fromJson);
  }

  // 3. Recommended comics
  Future<List<Comic>> getRecommendations({
    int pos = 2201202,
    int limit = 24,
    int offset = 0,
  }) async {
    final data = await _t.get(
      '/api/v3/recs',
      params: {'pos': pos, 'limit': limit, 'offset': offset, 'free_type': 1},
    );
    return jsonList(data, 'list')
        .whereType<Map>()
        .map((e) => jsonMap(Map<String, dynamic>.from(e), 'comic'))
        .whereType<Map<String, dynamic>>()
        .map(Comic.fromJson)
        .toList();
  }

  // 4. Comic list
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
    final data = await _t.get('/api/v3/comics', params: params);
    final list = _mapList(data, 'list', Comic.fromJson);
    return (list: list, total: jsonInt(data, 'total', fallback: list.length));
  }

  // 5. Comic detail
  Future<Comic> getComicDetail(String pathWord) async {
    final data = await _t.get(
      '/api/v3/comic2/$pathWord',
      params: {'platform': 3},
    );
    return Comic.fromDetailJson(data);
  }

  // 6. User status query
  Future<Map<String, dynamic>> getComicQuery(String pathWord) async {
    return _t.get('/api/v3/comic2/$pathWord/query');
  }

  // 7. Chapter list
  Future<({List<Chapter> list, int total})> getChapterList(
    String pathWord, {
    String group = 'default',
    int limit = 100,
    int offset = 0,
  }) async {
    final data = await _t.get(
      '/api/v3/comic/$pathWord/group/$group/chapters',
      params: {'limit': limit, 'offset': offset},
    );
    final list = _mapList(data, 'list', Chapter.fromJson);
    return (list: list, total: jsonInt(data, 'total', fallback: list.length));
  }

  // 8. Search comics
  Future<({List<Comic> list, int total})> searchComics(
    String query, {
    int limit = 20,
    int offset = 0,
  }) async {
    final data = await _t.get(
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
    final list = _mapList(data, 'list', Comic.fromJson);
    return (list: list, total: jsonInt(data, 'total', fallback: list.length));
  }

  // 9. Chapter detail
  Future<ChapterDetail> getChapterDetail(
    String pathWord,
    String chapterUuid, {
    bool forceRefresh = false,
  }) async {
    final cacheKey = _chapterDetailCacheKey(pathWord, chapterUuid);
    if (!forceRefresh) {
      final cached = await _t.cache.get(cacheKey);
      if (cached is Map) {
        try {
          final detail = ChapterDetail.fromJson(
            Map<String, dynamic>.from(cached),
          );
          if (detail.contents.isNotEmpty) {
            return detail;
          }
          await _t.cache.remove(cacheKey);
        } catch (_) {
          await _t.cache.remove(cacheKey);
        }
      }
    }

    final params = <String, dynamic>{'platform': 3};
    if (forceRefresh) params['_update'] = true;

    final data = await _t.get(
      '/api/v3/comic/$pathWord/chapter/$chapterUuid',
      params: params,
    );
    final detail = ChapterDetail.fromJson(data);
    if (detail.contents.isNotEmpty) {
      await _t.cache.put(cacheKey, data);
    }
    return detail;
  }

  String _chapterDetailCacheKey(String pathWord, String chapterUuid) =>
      'manga_chapter_detail_v1_'
      '${Uri.encodeComponent(pathWord)}_'
      '${Uri.encodeComponent(chapterUuid)}';

  // 9.1 Chapter comments
  Future<({List<ChapterComment> list, int total})> getChapterComments(
    String chapterId, {
    int limit = 30,
    int offset = 0,
  }) async {
    final host = _t.user.copyApiHost;
    final resp = await _t.commentDio.get(
      'https://$host/api/v3/roasts',
      queryParameters: {
        'chapter_id': chapterId,
        'limit': limit,
        'offset': offset,
        '_update': true,
      },
      options: _t.browserRequestOptions(host),
    );
    final results = jsonMap(
      resp.data is Map ? Map<String, dynamic>.from(resp.data as Map) : null,
      'results',
    );
    final list = _mapList(results, 'list', ChapterComment.fromJson);
    return (
      list: list,
      total: jsonInt(results, 'total', fallback: list.length),
    );
  }

  // 9.2 Post chapter comment
  Future<void> postChapterComment(String chapterId, String content) async {
    final trimmed = content.trim();
    if (!CommentText.isValid(trimmed)) {
      throw ArgumentError(
        'comment length must be '
        '${CommentText.minLength}-${CommentText.maxLength} characters',
      );
    }

    final token = _t.user.token;
    if (token == null || token.isEmpty) {
      throw const HttpException('login required to post comment');
    }

    final host = _t.user.copyApiHost;
    final resp = await _t.commentDio.post(
      'https://$host/api/v3/member/roast',
      data: {'chapter_id': chapterId, 'roast': trimmed, '_update': true},
      options: _t.browserRequestOptions(
        host,
        contentType: Headers.formUrlEncodedContentType,
        headers: {'Authorization': 'Token $token'},
      ),
    );

    final data = resp.data;
    if (data is Map) {
      final code = data['code'];
      if (code != null && code != 200) {
        final message = data['message']?.toString() ?? 'Failed to post comment';
        NetworkError.throwBadResponse(
          response: resp,
          message: message,
          source: 'api_comment',
        );
      }
    }
  }

  // 9.3 Post comic comment / reply
  Future<void> postComicComment(
    String comicId,
    String content, {
    int? replyId,
  }) async {
    final trimmed = content.trim();
    if (!CommentText.isValid(trimmed)) {
      throw ArgumentError(
        'comment length must be '
        '${CommentText.minLength}-${CommentText.maxLength} characters',
      );
    }

    final token = _t.user.token;
    if (token == null || token.isEmpty) {
      throw const HttpException('login required to post comment');
    }

    final host = _t.user.copyApiHost;
    final data = <String, dynamic>{'comic_id': comicId, 'comment': trimmed};
    if (replyId != null) {
      data['reply_id'] = replyId.toString();
    }

    final resp = await _t.commentDio.post(
      'https://$host/api/v3/member/comment',
      data: data,
      queryParameters: {'platform': 3},
      options: _t.browserRequestOptions(
        host,
        contentType: Headers.formUrlEncodedContentType,
        headers: {'Authorization': 'Token $token'},
      ),
    );

    final body = resp.data;
    if (body is Map) {
      final code = body['code'];
      if (code != null && code != 200) {
        final message = body['message']?.toString() ?? 'Failed to post comment';
        NetworkError.throwBadResponse(
          response: resp,
          message: message,
          source: 'api_comment',
        );
      }
    }
  }

  // 9.4 Comic comments / replies
  Future<({List<ComicComment> list, int total})> getComicComments(
    String comicId, {
    String replyId = '',
    int limit = 10,
    int offset = 0,
  }) async {
    final host = _t.user.copyApiHost;
    final resp = await _t.commentDio.get(
      'https://$host/api/v3/comments',
      queryParameters: {
        'comic_id': comicId,
        'reply_id': replyId,
        'limit': limit,
        'offset': offset,
        'platform': 3,
      },
      options: _t.browserRequestOptions(host, secFetchSite: 'cross-site'),
    );
    final results = jsonMap(
      resp.data is Map ? Map<String, dynamic>.from(resp.data as Map) : null,
      'results',
    );
    final list = _mapList(results, 'list', ComicComment.fromJson);
    return (
      list: list,
      total: jsonInt(results, 'total', fallback: list.length),
    );
  }

  // 10. 个人书架
  Future<({List<BookshelfItem> list, int total})> getBookshelf({
    int limit = 12,
    int offset = 0,
    String ordering = ApiOrdering.datetimeModifier,
  }) async {
    final data = await _t.get(
      '/api/v3/member/collect/comics',
      params: {
        'free_type': 1,
        'limit': limit,
        'offset': offset,
        'ordering': ordering,
        '_update': true,
      },
    );
    final list = jsonList(data, 'list')
        .whereType<Map>()
        .map((raw) {
          final entry = Map<String, dynamic>.from(raw);
          final comicJson = jsonMap(entry, 'comic');
          if (comicJson == null) return null;
          final browse = entry['last_browse'];
          return BookshelfItem(
            comic: Comic.fromJson(comicJson),
            lastBrowseId: browse is Map
                ? browse['last_browse_id']?.toString()
                : null,
            lastBrowseName: browse is Map
                ? browse['last_browse_name']?.toString()
                : null,
          );
        })
        .nonNulls
        .toList();
    return (list: list, total: jsonInt(data, 'total', fallback: list.length));
  }

  // 11. 收藏/取消收藏漫画
  Future<void> toggleCollect(String comicId, {required bool collect}) async {
    await _t.dio.post(
      _t.url('/api/v3/member/collect/comic'),
      data: 'comic_id=$comicId&is_collect=${collect ? 1 : 0}',
      options: Options(contentType: 'application/x-www-form-urlencoded'),
    );
  }
}
