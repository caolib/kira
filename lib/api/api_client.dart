import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import '../models/comic.dart';
import '../models/chapter.dart';
import '../models/chapter_comment.dart';
import '../models/user_manager.dart';

class ApiClient {
  static const _hostSg = 'mapi.hotmangasg.com';
  static const _hostSf = 'mapi.hotmangasf.com';
  static const _hostSd = 'mapi.hotmangasd.com';
  static const _hostComment = 'api.mangacopy.com';
  static const _hostCopy = 'www.mangacopy.com';
  static const _hostWeb = 'www.manga2026.xyz';

  static final ApiClient _instance = ApiClient._();
  factory ApiClient() => _instance;

  late final Dio _dio;
  late final Dio _commentDio;
  final _user = UserManager();
  // 手动管理 cookie: host → {name: value}
  final Map<String, Map<String, String>> _cookies = {};
  // 防止并发 401 触发多次自动登录
  Completer<bool>? _autoLoginCompleter;

  ApiClient._() {
    _dio = Dio();
    _commentDio = Dio(
      BaseOptions(
        headers: {
          'accept': 'application/json, text/plain, */*',
          'accept-language':
              'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7,en-GB;q=0.6,ru;q=0.5,ja;q=0.4,zh-TW;q=0.3',
          'cache-control': 'no-cache',
          'origin': 'https://www.mangacopy.com',
          'pragma': 'no-cache',
          'priority': 'u=1, i',
          'sec-ch-ua':
              '"Not:A-Brand";v="99", "Microsoft Edge";v="145", "Chromium";v="145"',
          'sec-ch-ua-mobile': '?0',
          'sec-ch-ua-platform': '"Windows"',
          'sec-fetch-dest': 'empty',
          'sec-fetch-mode': 'cors',
          'sec-fetch-site': 'same-site',
          'user-agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36 Edg/145.0.0.0',
          'Host': _hostComment,
          'Connection': 'keep-alive',
        },
      ),
    );
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
            options.headers['Cookie'] = hostCookies.entries
                .map((e) => '${e.key}=${e.value}')
                .join('; ');
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
                final name = nameValue.substring(0, eqIdx);
                final value = nameValue.substring(eqIdx + 1);
                if (value.isEmpty || value == '""') {
                  _cookies[host]!.remove(name);
                } else {
                  _cookies[host]![name] = value;
                }
              }
            }
          }
          // 业务错误码（如 210 账号密码错误）视为请求失败
          final data = response.data;
          if (data is Map) {
            final code = data['code'];
            if (code != null && code != 200) {
              final message =
                  data['message']?.toString() ??
                  (data['results'] is Map
                      ? data['results']['detail']?.toString()
                      : null) ??
                  '请求失败（code: $code）';
              return handler.reject(
                DioException(
                  requestOptions: response.requestOptions,
                  response: response,
                  message: message,
                  error: message,
                  type: DioExceptionType.badResponse,
                ),
              );
            }
          }
          handler.next(response);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401 && _user.autoLogin) {
            final username = _user.savedUsername;
            final password = _user.savedPassword;
            if (username != null &&
                username.isNotEmpty &&
                password != null &&
                password.isNotEmpty) {
              try {
                // 防止并发 401 同时触发多次登录
                if (_autoLoginCompleter != null) {
                  final success = await _autoLoginCompleter!.future;
                  if (!success) return handler.next(error);
                } else {
                  _autoLoginCompleter = Completer<bool>();
                  try {
                    final result = _user.loginSource == 'copy'
                        ? await copyLogin(username, password)
                        : await login(username, password);
                    await _user.saveLogin(
                      token: result['token'],
                      userId: result['user_id'],
                      username: result['username'],
                      nickname: result['nickname'] ?? result['username'],
                      avatar: result['avatar'] ?? '',
                    );
                    _autoLoginCompleter!.complete(true);
                  } catch (_) {
                    _autoLoginCompleter!.complete(false);
                    _autoLoginCompleter = null;
                    return handler.next(error);
                  }
                  _autoLoginCompleter = null;
                }
                // 用新 token 重试原请求
                final opts = error.requestOptions;
                opts.headers['Authorization'] = 'Token ${_user.token}';
                final resp = await _dio.fetch(opts);
                return handler.resolve(resp);
              } catch (_) {
                return handler.next(error);
              }
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  String _url(String path, [String host = _hostSg]) => 'https://$host$path';

  String _buildRegisterCookie() {
    final random = Random();

    String segment(int length) => List.generate(
      length,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();

    return 'uncer=${segment(8)}-${segment(4)}-${segment(4)}-${segment(4)}-${segment(12)}; age=18; webp=1';
  }

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
      data:
          'username=$username&password=$encoded&salt=$salt&source=Official&version=2.2.0&platform=3',
      options: Options(
        contentType: 'application/x-www-form-urlencoded;charset=utf-8',
      ),
    );
    return resp.data['results'];
  }

  /// 拷贝登录
  Future<Map<String, dynamic>> copyLogin(
    String username,
    String password,
  ) async {
    final salt = Random().nextInt(900000) + 100000;
    final encoded = base64Encode(utf8.encode('$password-$salt'));
    final dio = Dio(
      BaseOptions(
        validateStatus: (_) => true,
        headers: {
          'accept': 'application/json, text/plain, */*',
          'accept-language':
              'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7,en-GB;q=0.6,ru;q=0.5,ja;q=0.4,zh-TW;q=0.3',
          'content-type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'platform': '2',
          'origin': 'https://$_hostCopy',
          'referer': 'https://$_hostCopy/web/login/loginByAccount',
          'priority': 'u=1, i',
          'sec-ch-ua':
              '"Not:A-Brand";v="99", "Microsoft Edge";v="145", "Chromium";v="145"',
          'sec-ch-ua-mobile': '?0',
          'sec-ch-ua-platform': '"Windows"',
          'sec-fetch-dest': 'empty',
          'sec-fetch-mode': 'cors',
          'sec-fetch-site': 'same-origin',
          'user-agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36 Edg/145.0.0.0',
        },
      ),
    );

    final resp = await dio.post(
      'https://$_hostCopy/api/kb/web/login',
      data: Uri(
        queryParameters: {
          'username': username,
          'password': encoded,
          'salt': salt.toString(),
          'platform': '2',
          'version': '2025.12.10',
          'source': 'freeSite',
        },
      ).query,
    );

    final data = resp.data;
    if (data is Map && data['code'] == 200) {
      return Map<String, dynamic>.from(data['results']);
    }

    final message =
        data is Map ? (data['message']?.toString() ?? '登录失败') : '登录失败';
    throw DioException(
      requestOptions: resp.requestOptions,
      response: resp,
      message: message,
      error: message,
      type: DioExceptionType.badResponse,
    );
  }

  /// 获取个人信息
  Future<Map<String, dynamic>> getUserInfo() async {
    return await _get('/api/v3/member/info', host: _hostSf);
  }

  Future<void> logout() async {
    await _dio.post(
      _url('/api/v3/logout', _hostSf),
      options: Options(contentType: 'application/x-www-form-urlencoded'),
    );
  }

  void clearAuthState() {
    _cookies.clear();
  }

  Future<List<String>> getSecurityQuestions() async {
    final resp = await _dio.get(
      _url('/api/v3/member/securityquestionall/', _hostSd),
    );
    final results = resp.data['results'] as List? ?? const [];
    return results
        .map((e) => e['code']?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<Map<String, dynamic>> register({
    required String username,
    required String password,
    required String question,
    required String answer,
  }) async {
    Map<String, dynamic> parseResponse(dynamic raw) {
      if (raw is Map) return Map<String, dynamic>.from(raw);
      if (raw is String && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) return Map<String, dynamic>.from(decoded);
        } catch (_) {
          return {'message': raw};
        }
      }
      return {};
    }

    String resolveMessage(Map<String, dynamic> data, Response<dynamic>? resp) {
      final results = data['results'];
      return data['message']?.toString() ??
          data['detail']?.toString() ??
          (results is Map ? results['detail']?.toString() : null) ??
          resp?.statusMessage ??
          '注册失败';
    }

    final dio = Dio(
      BaseOptions(
        validateStatus: (_) => true,
        headers: {
          'accept': 'application/json, text/plain, */*',
          'accept-language':
              'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7,en-GB;q=0.6,ru;q=0.5,ja;q=0.4,zh-TW;q=0.3',
          'cache-control': 'no-cache',
          'content-type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'platform': '2',
          'pragma': 'no-cache',
          'origin': 'https://$_hostWeb',
          'referer': 'https://$_hostWeb/web/login/loginByAccount',
          'priority': 'u=1, i',
          'sec-ch-ua':
              '"Not:A-Brand";v="99", "Microsoft Edge";v="145", "Chromium";v="145"',
          'sec-ch-ua-mobile': '?0',
          'sec-ch-ua-platform': '"Windows"',
          'sec-fetch-dest': 'empty',
          'sec-fetch-mode': 'cors',
          'sec-fetch-site': 'same-origin',
          'user-agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36 Edg/145.0.0.0',
          'Cookie': _buildRegisterCookie(),
        },
      ),
    );

    final resp = await dio.post(
      'https://$_hostWeb/api/v2/register',
      data: Uri(
        queryParameters: {
          'username': username,
          'password': password,
          'source': '',
          'platform': '2',
          'code': '',
          'invite_code': '',
          'version': '2025.12.10',
          'question': question,
          'answer': answer,
        },
      ).query,
    );

    final data = parseResponse(resp.data);
    if (resp.statusCode == 200 && data['code'] == 200) {
      final results = data['results'];
      return results is Map ? Map<String, dynamic>.from(results) : {};
    }

    final message = resolveMessage(data, resp);
    throw DioException(
      requestOptions: resp.requestOptions,
      response: resp,
      message: message,
      error: message,
      type: DioExceptionType.badResponse,
    );
  }

  /// 获取浏览记录
  Future<({List<BrowseHistoryItem> list, int total})> getBrowseHistory({
    int limit = 20,
    int offset = 0,
  }) async {
    final data = await _get(
      '/api/v3/member/browse/comics',
      params: {
        'free_type': 1,
        'offset': offset,
        'limit': limit,
        '_update': true,
      },
      host: _hostSf,
    );
    final list = (data['list'] as List).map((e) {
      final item = Map<String, dynamic>.from(e);
      return BrowseHistoryItem(
        id: item['id'] as int? ?? 0,
        lastBrowseId: item['last_chapter_id']?.toString(),
        lastBrowseName: item['last_chapter_name']?.toString(),
        comic: Comic.fromJson(Map<String, dynamic>.from(item['comic'])),
      );
    }).toList();
    return (list: list, total: data['total'] as int? ?? list.length);
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

  // 2. 全部漫画标签
  Future<List<Theme>> getComicTags() async {
    final data = await _get(
      '/api/v3/theme/comic/count',
      params: {'free_type': 1, 'limit': 500, 'offset': 0, '_update': true},
      host: _hostSd,
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
    String chapterUuid,
  ) async {
    final data = await _get(
      '/api/v3/comic/$pathWord/chapter/$chapterUuid',
      params: {'platform': 3},
      host: _hostSd,
    );
    return ChapterDetail.fromJson(data);
  }

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
    );
    final results = resp.data['results'] as Map<String, dynamic>;
    final list = (results['list'] as List)
        .map((e) => ChapterComment.fromJson(Map<String, dynamic>.from(e)))
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
      host: _hostSf,
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
    final host = collect ? _hostSg : _hostSd;
    await _dio.post(
      _url('/api/v3/member/collect/comic', host),
      data: 'comic_id=$comicId&is_collect=${collect ? 1 : 0}',
      options: Options(contentType: 'application/x-www-form-urlencoded'),
    );
  }
}
