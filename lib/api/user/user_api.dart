part of '../api_client.dart';

mixin _UserApi on _ApiClientBase {
  // ── 用户相关 ──

  /// 登录，返回用户信息
  @override
  Future<Map<String, dynamic>> login(String username, String password) async {
    final salt = Random().nextInt(9000) + 1000;
    final encoded = base64Encode(utf8.encode('$password-$salt'));
    final resp = await _dio.post(
      _url('/api/v3/login'),
      data:
          'username=$username&password=$encoded&salt=$salt&source=Official&version=2.2.0&platform=3',
      options: Options(
        contentType: 'application/x-www-form-urlencoded;charset=utf-8',
      ),
    );
    return resp.data['results'];
  }

  /// 拷贝登录
  @override
  Future<Map<String, dynamic>> copyLogin(
    String username,
    String password,
  ) async {
    final salt = Random().nextInt(900000) + 100000;
    final encoded = base64Encode(utf8.encode('$password-$salt'));
    final dio = AppDio.create(
      source: 'copy_login',
      options: BaseOptions(
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

    final message = data is Map
        ? (data['message']?.toString() ?? '登录失败')
        : '登录失败';
    NetworkError.throwBadResponse(
      response: resp,
      message: message,
      source: 'copy_login',
    );
  }

  /// 获取个人信息
  Future<Map<String, dynamic>> getUserInfo() async {
    return await _get('/api/v3/member/info');
  }

  Future<void> logout() async {
    await _dio.post(
      _url('/api/v3/logout'),
      options: Options(contentType: 'application/x-www-form-urlencoded'),
    );
  }

  void clearAuthState() {
    _cookies.clear();
  }

  Future<List<String>> getSecurityQuestions() async {
    final resp = await _dio.get(_url('/api/v3/member/securityquestionall/'));
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
    NetworkError.throwBadResponse(
      response: resp,
      message: message,
      source: 'register',
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
}
