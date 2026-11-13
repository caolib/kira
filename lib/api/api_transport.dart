import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import '../models/user_manager.dart';
import '../utils/app_dio.dart';
import '../utils/data_cache.dart';

const defaultCopyApiHost = 'api.copy202601.com';
const defaultCopyAppVersion = '3.0.9';

/// 默认 COPY versionCode，与 [defaultCopyAppVersion] 配套（3.0.9 ↔ 83）。
/// 服务端对 version 与 versioncode 做交叉校验，升级 app version 时两者都要
/// 跟着改；高级设置里可手动覆盖。
const defaultCopyVersionCode = '83';

/// 默认拷贝登录域名（高级设置中可切换）。
const defaultCopyLoginHost = 'copy4000.com';

/// 可选的拷贝登录域名列表，用于高级设置中的切换。
const copyLoginHostOptions = [defaultCopyLoginHost, 'copy5000.com'];

/// 默认 COPY App 版本号，用于 copy 接口请求头（User-Agent / version）。
const copyAppVersion = defaultCopyAppVersion;

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

  final Map<String, double> _hostWeights = {};

  ApiTransport({
    required this.dio,
    required this.commentDio,
    required this.user,
    required this.cache,
  }) {
    dio.interceptors.add(
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
          return rejectIfBusinessError(response, handler);
        },
        onError: (error, handler) {
          // 令牌过期不再自动重登：重登依赖本地保存的账号密码，密码一旦轮换
          // 或服务端风控就会静默失败，用户看到的是「一直登录不上又不说原因」。
          // 统一交给调用方弹「登录已过期」，让用户重新登录一次。
          handler.next(error);
        },
      ),
    );
    AppDio.attachCommonInterceptors(dio, source: 'api', enableRateLimit: false);

    // 评论接口走独立的 commentDio（自带一套浏览器请求头），但错误语义必须
    // 与主 dio 一致：否则服务端返回 HTTP 200 + 业务错误码时不会抛出可处理的
    // 网络异常，而是在调用点解析 results 时崩溃。
    commentDio.interceptors.add(
      InterceptorsWrapper(onResponse: rejectIfBusinessError),
    );
  }

  /// 把业务错误码（HTTP 200 但 `code != 200`）转成 [DioException]。
  ///
  /// 两个 Dio 实例共用，确保调用方只需处理一种失败形态。
  static void rejectIfBusinessError(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final data = response.data;
    if (data is Map) {
      final code = data['code'];
      if (code != null && code != 200) {
        final results = data['results'];
        final message = code.toString() == '210'
            ? jsonEncode(data)
            : data['message']?.toString() ??
                  (results is Map ? results['detail']?.toString() : null) ??
                  'Request failed (code: $code)';
        // callFollowingErrorInterceptor: 让后续错误拦截器（统一网络日志）
        // 也能看到这次业务失败，否则 200 + 业务错误码的请求完全不留痕。
        return handler.reject(
          DioException(
            requestOptions: response.requestOptions,
            response: response,
            message: message,
            error: message,
            type: DioExceptionType.badResponse,
          ),
          true,
        );
      }
    }
    handler.next(response);
  }

  String nextHost() => _pickRouteHost(advance: true);

  /// 预览下一次请求将使用的节点：与 [nextHost] 选择逻辑一致
  /// （固定节点优先，其次按测速权重随机），但不推进轮询序号。
  String previewNextHost() => _pickRouteHost(advance: false);

  String _pickRouteHost({required bool advance}) {
    if (user.networkSelectionMode == NetworkSelectionMode.fixedNode) {
      final fixed = user.fixedNodeHost;
      if (fixed != null && routes.expand((route) => route).contains(fixed)) {
        return fixed;
      }
    }
    // 线路索引来自持久化设置：脏数据或路由表缩短都会越界，
    // 那会让每个请求都抛 RangeError 而不是退回可用线路。
    final route = routes[user.apiRoute.clamp(0, routes.length - 1)];

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
      if (advance) _hostIndex++;
      return host;
    }

    double r = Random().nextDouble() * totalWeight;
    for (final host in route) {
      r -= _hostWeights[host]!;
      if (r <= 0) return host;
    }

    final host = route[_hostIndex % route.length];
    if (advance) _hostIndex++;
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
        'origin': 'https://${user.copyLoginHost}',
        'referer': 'https://${user.copyLoginHost}/',
        'sec-fetch-site': secFetchSite,
        ...?headers,
      },
    );
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

  /// 探测失败后保留的最小权重。
  ///
  /// 归零意味着该节点永久出局——一次瞬断就把它拉黑到进程结束，且没有任何
  /// 自动恢复路径。留一个极小值，它仍有极低概率被选中，一旦恢复正常，
  /// 下一次测速就会把权重调回去。
  static const minHostWeight = 0.01;

  /// 由网络页测速调用:依据测得的延迟更新线路权重(供线路模式加权选优)。
  /// 旧版会同步反馈给已删除的自动节点选择器,现在仅用于权重调整。
  void recordNodeProbe(String host, int? latencyMs) {
    if (latencyMs == null || latencyMs <= 0) {
      setHostWeight(host, minHostWeight);
    } else {
      setHostWeight(host, 1000.0 / latencyMs);
    }
  }
}
