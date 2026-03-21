import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import '../models/comic.dart';
import '../models/chapter.dart';
import '../models/user_manager.dart';

class ApiClient {
  static const _hostSg = 'mapi.hotmangasg.com';
  static const _hostSf = 'mapi.hotmangasf.com';
  static const _hostSd = 'mapi.hotmangasd.com';

  static final ApiClient _instance = ApiClient._();
  factory ApiClient() => _instance;

  late final Dio _dio;
  final _user = UserManager();
  // 手动管理 cookie: host → {name: value}
  final Map<String, Map<String, String>> _cookies = {};

  ApiClient._() {
    _dio = Dio();
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.headers.addAll({
            'Accept': 'application/json',
            'Content-Encoding': 'gzip, compress, br',
            'platform': '3',
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 15; 23113RKC6C Build/AQ3A.240812.002; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/131.0.6778.200 Mobile Safari/537.36',
            'webp': '1',
            'version': '2024.04.28',
            'X-Requested-With': 'com.manga2020.app',
          });

          // 动态注入 token
          final token = _user.token;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Token $token';
          }

          // 注入已保存的 cookie
          final hostCookies = _cookies[options.uri.host];
          if (hostCookies != null && hostCookies.isNotEmpty) {
            options.headers['Cookie'] =
                hostCookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
          }

          handler.next(options);
        },
        onResponse: (response, handler) {
          // 宽松解析 set-cookie，避免 Dart 严格解析报错
          final setCookies = response.headers['set-cookie'];
          if (setCookies != null) {
            final host = response.requestOptions.uri.host;
            _cookies.putIfAbsent(host, () => {});
            for (final raw in setCookies) {
              final nameValue = raw.split(';').first.trim();
              final eqIdx = nameValue.indexOf('=');
              if (eqIdx > 0) {
                _cookies[host]![nameValue.substring(0, eqIdx)] =
                    nameValue.substring(eqIdx + 1);
              }
            }
          }
          handler.next(response);
        },
      ),
    );
  }

  String _url(String path, [String host = _hostSg]) => 'https://$host$path';

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, dynamic>? params,
    String host = _hostSg,
  }) async {
    final resp = await _dio.get(_url(path, host), queryParameters: params);
    return resp.data['results'];
  }

  // ── 用户相关 ──

  /// 登录，返回用户信息
  Future<Map<String, dynamic>> login(String username, String password) async {
    final salt = Random().nextInt(9000) + 1000;
    final encoded = base64Encode(utf8.encode('$password-$salt'));
    final resp = await _dio.post(
      _url('/api/v3/login', _hostSf),
      data: 'username=$username&password=$encoded&salt=$salt&source=Official&version=2.2.0&platform=3',
      options: Options(contentType: 'application/x-www-form-urlencoded;charset=utf-8'),
    );
    return resp.data['results'];
  }

  /// 获取个人信息
  Future<Map<String, dynamic>> getUserInfo() async {
    return await _get('/api/v3/member/info', host: _hostSf);
  }

  // ── 漫画相关 ──

  // 1. 热门搜索关键词
  Future<List<String>> getHotKeywords() async {
    final data = await _get(
      '/api/v3/search/key',
      params: {'limit': 20, 'offset': 0},
    );
    return (data['list'] as List).map((e) => e['keyword'] as String).toList();
  }

  // 2. 分类标签
  Future<List<Theme>> getComicTags() async {
    final data = await _get(
      '/api/v3/h5/filterIndex/comic/tags',
      params: {'type': 1},
      host: _hostSf,
    );
    return (data['theme'] as List).map((e) => Theme.fromJson(e)).toList();
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
      host: _hostSf,
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
    final data = await _get('/api/v3/comics', params: params, host: _hostSf);
    final list = (data['list'] as List).map((e) => Comic.fromJson(e)).toList();
    return (list: list, total: data['total'] as int);
  }

  // 5. 漫画详情
  Future<Comic> getComicDetail(String pathWord) async {
    final data = await _get(
      '/api/v3/comic2/$pathWord',
      params: {'platform': 3},
      host: _hostSd,
    );
    return Comic.fromDetailJson(data);
  }

  // 6. 用户状态查询
  Future<Map<String, dynamic>> getComicQuery(String pathWord) async {
    return await _get('/api/v3/comic2/$pathWord/query', host: _hostSd);
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
      host: _hostSd,
    );
    final list =
        (data['list'] as List).map((e) => Chapter.fromJson(e)).toList();
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
    String chapterUuid,
  ) async {
    final data = await _get(
      '/api/v3/comic/$pathWord/chapter/$chapterUuid',
      params: {'platform': 3},
      host: _hostSd,
    );
    return ChapterDetail.fromJson(data);
  }

  // 10. 个人书架
  Future<({List<Comic> list, int total})> getBookshelf({
    int limit = 21,
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
      host: _hostSf,
    );
    final list = (data['list'] as List)
        .map((e) => Comic.fromJson(e['comic']))
        .toList();
    return (list: list, total: data['total'] as int);
  }

  // 11. 收藏/取消收藏漫画
  Future<void> toggleCollect(String comicId, {required bool collect}) async {
    final host = collect ? _hostSg : _hostSd;
    await _dio.post(
      _url('/api/v3/member/collect/comic', host),
      data: 'comic_id=$comicId&is_collect=${collect ? 1 : 0}',
      options: Options(contentType: 'application/x-www-form-urlencoded'),
    );
  }
}
