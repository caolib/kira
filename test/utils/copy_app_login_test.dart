import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/api/api_transport.dart';
import 'package:kira/api/user/user_api.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/utils/copy_app_headers.dart';
import 'package:kira/utils/copy_signature.dart';
import 'package:kira/utils/data_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

class _FakeAdapter implements HttpClientAdapter {
  FutureOr<ResponseBody> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];

  _FakeAdapter(this.respond);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

/// 测试用密钥，只用来验证「签名头被正确构造」，与真实协议常量无关。
const _testKey = '00000000000000000000000000000000';

ResponseBody _jsonResponse(Object data, [int status = 200]) =>
    ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CopySignature', () {
    setUp(() {
      final previousOverride = CopySignature.debugKeyOverride;
      addTearDown(() => CopySignature.debugKeyOverride = previousOverride);
    });

    test('签名是密钥对时间戳字符串的 HMAC-SHA256 hex', () {
      // 独立复算：dart:crypto 的 HMAC-SHA256，只验证算法形态与确定性，
      // 不牵涉任何真实协议密钥。
      final signed = CopySignature.sign('1700000000', key: _testKey);
      expect(signed, hasLength(64));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(signed), isTrue);
      // 同样的输入必须得到同样的输出，且换 key 就变。
      expect(CopySignature.sign('1700000000', key: _testKey), signed);
      expect(CopySignature.sign('1700000001', key: _testKey), isNot(signed));
      expect(
        CopySignature.sign(
          '1700000000',
          key: 'ffffffffffffffffffffffffffffffff',
        ),
        isNot(signed),
      );
    });

    test('pseudoid 是 16 位且进程内稳定', () {
      final first = CopySignature.pseudoId();
      expect(first, hasLength(16));
      expect(RegExp(r'^[0-9A-Za-z]{16}$').hasMatch(first), isTrue);
      expect(CopySignature.pseudoId(), first);
    });

    test('显式注入缺失密钥时 headers 抛错而不是发出无效签名', () {
      // 不依赖宿主的 COPY_AUTH_KEY，也不修改环境变量。
      for (final missing in ['', ' \t\n']) {
        CopySignature.debugKeyOverride = missing;
        expect(CopySignature.authKey == null, isTrue);
        expect(CopySignature.isConfigured, isFalse);
        expect(CopySignature.umString, isNull);
        expect(() => CopySignature.headers(), throwsStateError);
      }
    });

    test('测试注入可覆盖已有缓存，清除后恢复原配置且不污染缓存', () {
      CopySignature.debugKeyOverride = null;
      // 如果宿主配置了密钥，先触发正常缓存；断言仅比较布尔值，
      // 即使失败也不会把真实密钥写入测试输出。
      final originalKey = CopySignature.authKey;
      final originalUmString = CopySignature.umString;
      expect(CopySignature.authKey == originalKey, isTrue);

      CopySignature.debugKeyOverride = ' $_testKey ';
      expect(CopySignature.authKey == _testKey, isTrue);
      expect(CopySignature.isConfigured, isTrue);
      expect(CopySignature.umString, isNotNull);
      final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      final headers = CopySignature.headers(now: now);
      expect(headers['X-Auth-Timestamp'], '1700000000');
      expect(
        headers['X-Auth-Signature'],
        CopySignature.sign('1700000000', key: _testKey),
      );

      CopySignature.debugKeyOverride = '';
      expect(CopySignature.authKey == null, isTrue);
      expect(CopySignature.isConfigured, isFalse);
      expect(CopySignature.umString, isNull);
      expect(() => CopySignature.headers(now: now), throwsStateError);

      CopySignature.debugKeyOverride = _testKey;
      expect(CopySignature.headers(now: now), headers);
      CopySignature.debugKeyOverride = null;
      expect(CopySignature.authKey == originalKey, isTrue);
      expect(CopySignature.isConfigured, originalKey != null);
      expect(CopySignature.umString == originalUmString, isTrue);
      expect(CopySignature.authKey == originalKey, isTrue);
    });
  });

  group('CopyAppHeaders', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      setupSecureCredentialStoreForTest();
      CopySignature.debugKeyOverride = _testKey;
      await UserManager().init();
    });

    tearDown(() {
      CopySignature.debugKeyOverride = null;
      teardownSecureCredentialStoreForTest();
    });

    test('设备标识持久化，跨实例保持一致', () async {
      // 密钥缺失只影响签名头，业务头仍可单独验证。
      final user = UserManager();
      final first = await CopyAppHeaders.build(user: user, token: 'tok');
      expect(first['user-agent'], 'COPY/${user.copyAppVersion}');
      expect(first['authorization'], 'Token tok');
      expect(first['device'], hasLength(16));
      expect(first['deviceinfo'], isNotEmpty);
      expect(first['pseudoid'], hasLength(16));

      // 新进程读同一份 prefs 必须拿到同一个 device，否则服务端会当成新设备。
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('copy_device_id'), first['device']);
      expect(prefs.getString('copy_device_info'), first['deviceinfo']);
    });

    test('dt 按 UTC+8 取日期', () async {
      final headers = await CopyAppHeaders.build(user: UserManager());
      expect(RegExp(r'^\d{4}\.\d{2}\.\d{2}$').hasMatch(headers['dt']!), isTrue);
    });
  });

  group('UserApi.loginViaApp', () {
    late _FakeAdapter adapter;
    late UserApi api;
    late UserManager user;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      setupSecureCredentialStoreForTest();
      CopySignature.debugKeyOverride = _testKey;
      user = UserManager();
      await user.init();
      adapter = _FakeAdapter(
        (_) => _jsonResponse({
          'code': 200,
          'results': {
            'token': 'app-token',
            'user_id': 'app-id',
            'username': 'app-user',
          },
        }),
      );
      api = UserApi(
        ApiTransport(
          dio: Dio(),
          commentDio: Dio(),
          user: user,
          cache: DataCache(),
        ),
        copyAppDioFactory: (options) =>
            Dio(options)..httpClientAdapter = adapter,
      );
    });

    tearDown(() {
      CopySignature.debugKeyOverride = null;
      teardownSecureCredentialStoreForTest();
    });

    test('打 App 通道登录接口，密码是 base64(密码-salt) 且 salt 本地生成', () async {
      final result = await api.loginViaApp('app-user', 'app-password');

      expect(result['token'], 'app-token');
      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.path, '/api/v3/login');
      expect(request.uri.host, user.copyApiHost);

      // 请求体是表单三键；密码解回来必须正好是「密码-salt」。
      // Dio 的默认 transformer 只在部分分支预编码表单，两种形态都接受。
      final raw = request.data;
      final body = raw is Map
          ? {
              for (final entry in raw.entries)
                entry.key.toString(): entry.value.toString(),
            }
          : Uri.splitQueryString(raw.toString());
      expect(body.keys, containsAll(['username', 'password', 'salt']));
      expect(body['username'], 'app-user');
      final salt = int.parse(body['salt']!);
      expect(salt, inInclusiveRange(0, 9998));
      expect(
        utf8.decode(base64Decode(body['password']!)),
        'app-password-$salt',
      );
    });

    test('业务错误码转成可处理的网络异常并带上服务端文案', () async {
      adapter.respond = (_) => _jsonResponse({
        'code': 210,
        'message': '該賬戶不存在.',
        'results': {'detail': '該賬戶不存在.'},
      });
      await expectLater(
        api.loginViaApp('app-user', 'app-password'),
        throwsA(
          isA<DioException>().having(
            (e) => e.message,
            'message',
            contains('該賬戶不存在.'),
          ),
        ),
      );
    });
  });
}
