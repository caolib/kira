import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';

import '../models/user_manager.dart';
import '../utils/app_dio.dart';
import '../utils/data_cache.dart';
import 'automatic_node_selector.dart';

const defaultCopyApiHost = 'api.copy202601.com';
const defaultCopyAppVersion = '3.0.9';

const _hostComment = defaultCopyApiHost;
const _hostCopy = 'www.mangacopy.com';
const _hostWeb = 'www.manga2026.xyz';

/// 默认 COPY App 版本号，用于 copy 接口请求头（User-Agent / version）。
const copyAppVersion = defaultCopyAppVersion;

const extraApiHosts = [_hostCopy, _hostWeb];

enum ExtraApiHostKind { copyApi, copyLogin, hotLogin, fixed }

const extraApiHostKinds = {
  _hostComment: ExtraApiHostKind.copyApi,
  _hostCopy: ExtraApiHostKind.copyLogin,
  _hostWeb: ExtraApiHostKind.hotLogin,
};

const routes = [
  ['mapi.hotmangasg.com', 'mapi.hotmangasd.com', 'mapi.hotmangasf.com'],
  ['mapi.elfgjfghkk.club', 'mapi.fgjfghkkcenter.club', 'mapi.fgjfghkk.club'],
];

/// Shared HTTP transport used by all API service classes.
/// Wraps the Dio instances and provides common request methods.
class ApiTransport {
  final Dio dio;
  final Dio commentDio;
  final UserManager user;
  final DataCache cache;

  int _hostIndex = 0;
  // 手动管理 cookie: host → {name: value}
  final Map<String, Map<String, String>> _cookies = {};
  // 防止并发 401 触发多次自动登录
  Completer<bool>? _autoLoginCompleter;

  final Map<String, double> _hostWeights = {};
  final AutomaticNodeSelector _automaticNodeSelector = AutomaticNodeSelector();

  /// Login callbacks used by the 401 auto-login interceptor.
  /// Set by ApiClient after constructing the transport and user API.
  Future<Map<String, dynamic>> Function(String, String)? loginHandler;
  Future<Map<String, dynamic>> Function(String, String)? copyLoginHandler;

  ApiTransport({
    required this.dio,
    required this.commentDio,
    required this.user,
    required this.cache,
  }) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_isApiNode(options.uri.host)) {
            options.extra['_nodeRequestStartedAt'] =
                DateTime.now().microsecondsSinceEpoch;
          }
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
          final token = user.token;
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
          _recordNodeSuccess(response.requestOptions);
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
                  'Request failed (code: $code)';
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
          _recordNodeError(error);
          if (error.response?.statusCode == 401 && user.autoLogin) {
            final username = user.savedUsername;
            final password = user.savedPassword;
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
                    final result = user.loginSource == 'copy'
                        ? await copyLoginHandler!(username, password)
                        : await loginHandler!(username, password);
                    await user.saveLogin(
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
                opts.headers['Authorization'] = 'Token ${user.token}';
                final resp = await dio.fetch(opts);
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
    AppDio.attachCommonInterceptors(dio, source: 'api', enableRateLimit: false);
  }

  String nextHost() {
    if (user.networkSelectionMode == NetworkSelectionMode.fixedNode) {
      final fixed = user.fixedNodeHost;
      if (fixed != null && routes.expand((route) => route).contains(fixed)) {
        return fixed;
      }
    }
    if (user.networkSelectionMode == NetworkSelectionMode.automatic) {
      return _automaticNodeSelector.select(
        routes.expand((route) => route).toList(),
      );
    }
    final route = routes[user.apiRoute];

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

  String url(String path) => 'https://${nextHost()}$path';

  Options browserRequestOptions(
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
        ...?headers,
      },
    );
  }

  String buildRegisterCookie() {
    final random = Random();

    String segment(int length) => List.generate(
      length,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();

    return 'uncer=${segment(8)}-${segment(4)}-${segment(4)}-${segment(4)}-${segment(12)}; age=18; webp=1';
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? params,
  }) async {
    final resp = await dio.get(url(path), queryParameters: params);
    return resp.data['results'];
  }

  void clearCookies() {
    _cookies.clear();
  }

  void setHostWeight(String host, double weight) {
    _hostWeights[host] = weight;
  }

  void recordNodeProbe(String host, int? latencyMs) {
    if (latencyMs == null || latencyMs <= 0) {
      _automaticNodeSelector.recordFailure(
        host,
        routes.expand((route) => route),
      );
    } else {
      _automaticNodeSelector.recordSuccess(
        host,
        Duration(milliseconds: latencyMs),
      );
    }
  }

  List<AutomaticNodeStatus> get automaticNodeStatuses =>
      _automaticNodeSelector.statuses(routes.expand((route) => route).toList());

  void addAutomaticNodeListener(void Function() listener) =>
      _automaticNodeSelector.addListener(listener);

  void removeAutomaticNodeListener(void Function() listener) =>
      _automaticNodeSelector.removeListener(listener);

  bool _isApiNode(String host) => routes.any((route) => route.contains(host));

  void _recordNodeSuccess(RequestOptions options) {
    if (options.extra['_nodePerformanceRecorded'] == true) return;
    final elapsed = _nodeRequestElapsed(options);
    if (elapsed == null) return;
    options.extra['_nodePerformanceRecorded'] = true;
    _automaticNodeSelector.recordSuccess(options.uri.host, elapsed);
  }

  void _recordNodeError(DioException error) {
    final options = error.requestOptions;
    if (options.extra['_nodePerformanceRecorded'] == true ||
        !_isApiNode(options.uri.host)) {
      return;
    }
    options.extra['_nodePerformanceRecorded'] = true;
    final statusCode = error.response?.statusCode;
    if (statusCode != null && statusCode < 500) {
      final elapsed = _nodeRequestElapsed(options);
      if (elapsed != null) {
        _automaticNodeSelector.recordSuccess(options.uri.host, elapsed);
      }
      return;
    }
    _automaticNodeSelector.recordFailure(
      options.uri.host,
      routes.expand((route) => route),
    );
  }

  Duration? _nodeRequestElapsed(RequestOptions options) {
    final startedAt = options.extra['_nodeRequestStartedAt'];
    if (startedAt is! int) return null;
    return Duration(
      microseconds: DateTime.now().microsecondsSinceEpoch - startedAt,
    );
  }
}
