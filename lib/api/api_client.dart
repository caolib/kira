import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import '../models/anime.dart';
import '../models/comic.dart';
import '../models/chapter.dart';
import '../models/chapter_comment.dart';
import '../models/comic_comment.dart';
import '../models/user_manager.dart';
import '../utils/data_cache.dart';
import '../utils/network_error.dart';

part 'anime/anime_api.dart';
part 'manga/manga_api.dart';
part 'network/network_api.dart';
part 'user/user_api.dart';

const _hostComment = 'api.copy2000.online';
const _hostCopy = 'www.mangacopy.com';
const _hostWeb = 'www.manga2026.xyz';

const _extraApiHosts = [_hostComment, _hostCopy, _hostWeb];
const _extraApiHostLabels = {
  _hostComment: '评论',
  _hostCopy: '拷贝登录',
  _hostWeb: '热辣登录',
};

const _routes = [
  ['mapi.hotmangasg.com', 'mapi.hotmangasd.com', 'mapi.hotmangasf.com'],
  ['mapi.elfgjfghkk.club', 'mapi.fgjfghkkcenter.club', 'mapi.fgjfghkk.club'],
];

abstract class _ApiClientBase {
  late final Dio _dio;
  late final Dio _commentDio;
  final _user = UserManager();
  final _cache = DataCache();
  int _hostIndex = 0;
  // 手动管理 cookie: host → {name: value}
  final Map<String, Map<String, String>> _cookies = {};
  // 防止并发 401 触发多次自动登录
  Completer<bool>? _autoLoginCompleter;

  Future<Map<String, dynamic>> login(String username, String password);
  Future<Map<String, dynamic>> copyLogin(String username, String password);

  _ApiClientBase() {
    _dio = Dio()..interceptors.add(NetworkError.rateLimitInterceptor());
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
              '"Chromium";v="148", "Microsoft Edge";v="148", "Not/A)Brand";v="99"',
          'sec-ch-ua-mobile': '?0',
          'sec-ch-ua-platform': '"Windows"',
          'sec-fetch-dest': 'empty',
          'sec-fetch-mode': 'cors',
          'sec-fetch-site': 'same-site',
          'user-agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36 Edg/148.0.0.0',
          'Host': _hostComment,
          'Connection': 'keep-alive',
        },
      ),
    )..interceptors.add(NetworkError.rateLimitInterceptor());
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

  final Map<String, double> _hostWeights = {};

  String _nextHost() {
    final route = _routes[_user.apiRoute];

    double totalWeight = 0.0;
    for (final host in route) {
      if (!_hostWeights.containsKey(host)) {
        _hostWeights[host] = 1.0;
      }
      totalWeight += _hostWeights[host]!;
    }

    if (totalWeight <= 0) {
      // 如果所有节点都超时（权重为0），或者未测试，退回到轮询
      final host = route[_hostIndex % route.length];
      _hostIndex++;
      return host;
    }

    double r = Random().nextDouble() * totalWeight;
    for (final host in route) {
      r -= _hostWeights[host]!;
      if (r <= 0) return host;
    }

    final host = route[_hostIndex % route.length];
    _hostIndex++;
    return host;
  }

  String _url(String path) => 'https://${_nextHost()}$path';

  Options _browserRequestOptions(
    String host, {
    String secFetchSite = 'same-site',
    String? contentType,
    Map<String, dynamic>? headers,
  }) {
    return Options(
      contentType: contentType,
      headers: {
        'Host': host,
        'referer': 'https://www.mangacopy.com/',
        'sec-fetch-site': secFetchSite,
        if (headers != null) ...headers,
      },
    );
  }

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
  }) async {
    final resp = await _dio.get(_url(path), queryParameters: params);
    return resp.data['results'];
  }
}

class ApiClient extends _ApiClientBase
    with _UserApi, _MangaApi, _AnimeApi, _NetworkApi {
  static const routeLabels = ['线路 1', '线路 2'];

  static final ApiClient _instance = ApiClient._();
  factory ApiClient() => _instance;

  ApiClient._() : super();
}
