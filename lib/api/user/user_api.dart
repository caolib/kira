import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import '../../models/comic.dart';
import '../../utils/app_dio.dart';
import '../../utils/network_error.dart';
import '../api_transport.dart';

/// 拷贝漫画在 IP 被风控时返回的固定服务端文案关键词。
/// 该错误并非密码错误，而是当前出口 IP 被服务端封禁，需换网络/开代理后重试。
const _ipBlockedKeywords = <String>[
  '請到官網更新最新APP',
  '請到官网更新最新APP',
  '下載過破解版本',
  '下载过破解版本',
  '限制會自動解除',
  '限制会自动解除',
];

/// 判断登录错误是否为 IP 风控封禁（拷贝官方对破解 IP 的拦截文案）。
bool isIpBlockedLoginError(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    final candidate = <String>[
      if (error.message != null) error.message!,
      NetworkError.message(error),
      if (data is Map) ...[
        if (data['message'] is String) data['message'] as String,
        if (data['detail'] is String) data['detail'] as String,
        if (data['results'] is Map) ...[
          if ((data['results'] as Map)['detail'] is String)
            (data['results'] as Map)['detail'] as String,
          if ((data['results'] as Map)['message'] is String)
            (data['results'] as Map)['message'] as String,
        ],
      ],
    ];
    for (final text in candidate) {
      if (text.isEmpty) continue;
      for (final keyword in _ipBlockedKeywords) {
        if (text.contains(keyword)) return true;
      }
    }
  }
  return false;
}

class UserApi {
  final ApiTransport _t;

  UserApi(this._t);

  // ── 用户相关 ──

  /// 登录，返回用户信息
  Future<Map<String, dynamic>> login(String username, String password) async {
    final salt = Random().nextInt(9000) + 1000;
    final encoded = base64Encode(utf8.encode('$password-$salt'));
    final resp = await _t.dio.post(
      _t.url('/api/v3/login'),
      data:
          'username=$username&password=$encoded&salt=$salt&source=Official&version=2.2.0&platform=3',
      options: Options(
        contentType: 'application/x-www-form-urlencoded;charset=utf-8',
      ),
    );
    return resp.data['results'];
  }

  /// 拷贝登录（域名可在高级设置中切换）
  Future<Map<String, dynamic>> copyLogin(
    String username,
    String password,
  ) async {
    final hostCopy = _t.user.copyLoginHost;
    final salt = Random().nextInt(900000) + 100000;
    final encoded = base64Encode(utf8.encode('$password-$salt'));
    final dio = AppDio.create(
      source: 'copy_login',
      options: BaseOptions(
        validateStatus: (_) => true,
        // 头顺序对齐官方浏览器请求（ref/用户/拷贝登录-最新.txt）
        headers: {
          'sec-ch-ua-platform': '"Windows"',
          'user-agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36 Edg/150.0.0.0',
          'accept': 'application/json, text/plain, */*',
          'sec-ch-ua':
              '"Not;A=Brand";v="8", "Chromium";v="150", "Microsoft Edge";v="150"',
          'content-type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'sec-ch-ua-mobile': '?0',
          'platform': '2',
          'origin': 'https://$hostCopy',
          'sec-fetch-site': 'same-origin',
          'sec-fetch-mode': 'cors',
          'sec-fetch-dest': 'empty',
          'referer':
              'https://$hostCopy/web/login/loginByAccount?url=person%2Fhome',
          'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6',
          'cookie': 'webp=1',
          'priority': 'u=1, i',
        },
      ),
    );

    try {
      final resp = await dio.post(
        'https://$hostCopy/api/kb/web/login',
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

      String? serverMessage;
      if (data is Map) {
        final raw = (data['message'] ?? data['detail'])?.toString().trim();
        if (raw != null && raw.isNotEmpty) serverMessage = raw;
      }
      final message =
          serverMessage ??
          (data is Map
              ? 'Login failed (code: ${data['code'] ?? resp.statusCode ?? 'unknown'})'
              : 'Login failed (HTTP ${resp.statusCode ?? 'unknown'})');
      NetworkError.throwBadResponse(
        response: resp,
        message: message,
        source: 'copy_login',
      );
    } finally {
      dio.close();
    }
  }

  /// 获取个人信息
  Future<Map<String, dynamic>> getUserInfo() async {
    return _t.get('/api/v3/member/info');
  }

  Future<void> logout() async {
    await _t.dio.post(
      _t.url('/api/v3/logout'),
      options: Options(contentType: 'application/x-www-form-urlencoded'),
    );
  }

  void clearAuthState() {
    _t.clearCookies();
  }

  Future<List<String>> getSecurityQuestions() async {
    final resp = await _t.dio.get(
      _t.url('/api/v3/member/securityquestionall/'),
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
    const hostWeb = 'www.manga2026.xyz';

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
          'Registration failed';
    }

    final dio = AppDio.create(
      source: 'register',
      options: BaseOptions(
        validateStatus: (_) => true,
        headers: {
          'accept': 'application/json, text/plain, */*',
          'accept-language':
              'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7,en-GB;q=0.6,ru;q=0.5,ja;q=0.4,zh-TW;q=0.3',
          'cache-control': 'no-cache',
          'content-type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'platform': '2',
          'pragma': 'no-cache',
          'origin': 'https://$hostWeb',
          'referer': 'https://$hostWeb/web/login/loginByAccount',
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
          'Cookie': _t.buildRegisterCookie(),
        },
      ),
    );

    try {
      final resp = await dio.post(
        'https://$hostWeb/api/v2/register',
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
      NetworkError.throwBadResponse(
        response: resp,
        message: message,
        source: 'register',
      );
    } finally {
      dio.close();
    }
  }

  /// 获取浏览记录
  Future<({List<BrowseHistoryItem> list, int total})> getBrowseHistory({
    int limit = 20,
    int offset = 0,
  }) async {
    final data = await _t.get(
      '/api/v3/member/browse/comics',
      params: {
        'free_type': 1,
        'offset': offset,
        'limit': limit,
        '_update': true,
      },
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

  Future<void> clearBrowseHistory() async {
    if (_t.user.loginSource == 'copy') {
      final dio = AppDio.create(
        source: 'copy_api',
        options: BaseOptions(
          validateStatus: (_) => true,
          headers: {
            'User-Agent': 'COPY/${_t.user.copyAppVersion}',
            'Accept': 'application/json',
            'source': 'copyApp',
            'platform': '3',
            'version': _t.user.copyAppVersion,
            'Connection': 'keep-alive',
            'Accept-Encoding': 'gzip',
            'webp': '1',
            'Authorization': 'Token ${_t.user.token}',
          },
        ),
      );
      try {
        final resp = await dio.delete(
          'https://${_t.user.copyApiHost}/api/v3/member/browse/comics',
          queryParameters: {'platform': 3},
          options: Options(contentType: 'application/x-www-form-urlencoded'),
        );
        final data = resp.data;
        if (data is Map && data['code'] == 200) return;
        final message = data is Map
            ? (data['message']?.toString() ?? 'Failed to clear browse history')
            : 'Failed to clear browse history';
        NetworkError.throwBadResponse(
          response: resp,
          message: message,
          source: 'copy_api',
        );
      } finally {
        dio.close();
      }
    } else {
      await _t.dio.delete(
        _t.url('/api/v3/member/browse/comics'),
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );
    }
  }

  Future<void> clearAnimeBrowseHistory() async {
    if (_t.user.loginSource == 'copy') {
      final dio = AppDio.create(
        source: 'copy_api',
        options: BaseOptions(
          validateStatus: (_) => true,
          headers: {
            'User-Agent': 'COPY/${_t.user.copyAppVersion}',
            'Accept': 'application/json',
            'source': 'copyApp',
            'platform': '3',
            'version': _t.user.copyAppVersion,
            'Connection': 'keep-alive',
            'Accept-Encoding': 'gzip',
            'webp': '1',
            'Authorization': 'Token ${_t.user.token}',
          },
        ),
      );
      try {
        final resp = await dio.delete(
          'https://${_t.user.copyApiHost}/api/v3/member/browse/cartoons',
          queryParameters: {'platform': 3},
          options: Options(contentType: 'application/x-www-form-urlencoded'),
        );
        final data = resp.data;
        if (data is Map && data['code'] == 200) return;
        final message = data is Map
            ? (data['message']?.toString() ?? 'Failed to clear browse history')
            : 'Failed to clear browse history';
        NetworkError.throwBadResponse(
          response: resp,
          message: message,
          source: 'copy_api',
        );
      } finally {
        dio.close();
      }
    } else {
      await _t.dio.delete(
        _t.url('/api/v3/member/browse/cartoons'),
        options: Options(contentType: 'application/x-www-form-urlencoded'),
      );
    }
  }
}
