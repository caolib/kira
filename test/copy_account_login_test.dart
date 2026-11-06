import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kira/api/api_client.dart';
import 'package:kira/api/api_transport.dart';
import 'package:kira/api/user/user_api.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/models/copy_account_store.dart';
import 'package:kira/models/secure_credential_store.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/login_page.dart';
import 'package:kira/pages/profile_page.dart';
import 'package:kira/pages/webview_login_page.dart';
import 'package:kira/routing/app_router.dart';
import 'package:kira/utils/copy_web_login.dart';
import 'package:kira/utils/data_cache.dart';
import 'package:kira/widgets/login_node_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class _TestSecureStore extends InMemorySecureCredentialStore {
  bool failCopyWrite = false;

  @override
  Future<void> writeCopyAccountRecord(String value) {
    if (failCopyWrite) throw StateError('Storage unavailable');
    return super.writeCopyAccountRecord(value);
  }
}

class _FakeApiClient implements ApiClient {
  @override
  final UserApi user;

  _FakeApiClient(this.user);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected API access in offline test: ${invocation.memberName}',
  );
}

ResponseBody _jsonResponse(Object data, [int status = 200]) =>
    ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );

const _oldSession = CopyAccountSession(
  token: 'old-copy',
  userId: 'old-copy-id',
  username: 'old-copy-user',
);

Map<String, Object?> _mainSnapshot(UserManager user) => {
  'token': user.token,
  'source': user.loginSource,
  'username': user.username,
  'id': user.userId,
  'accountId': user.currentCredential?.accountId,
  'nickname': user.nickname,
  'avatar': user.avatar,
  'savedUsername': user.savedUsername,
  'savedPassword': user.savedPassword,
  'saved': jsonEncode(user.savedCredentials.map((e) => e.toJson()).toList()),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final user = UserManager();
  final originalApi = ApiClient();
  late UserApi api;
  late _FakeAdapter copyAdapter;
  late _FakeAdapter copyProfileAdapter;
  late _FakeAdapter mainAdapter;
  late Dio primaryDio;
  late Dio commentDio;
  late ApiTransport transport;
  late _TestSecureStore secure;
  late FutureOr<ResponseBody> Function(RequestOptions) response;
  late FutureOr<ResponseBody> Function(RequestOptions) primaryResponse;
  var expectedPrimaryRequests = 0;
  var probes = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'login_source': 'hotmanga',
      'user_token': 'hot-token',
      'user_id': 'hot-id',
      'user_username': 'same-username',
      'user_nickname': 'HOT name',
      'user_avatar': '',
      'saved_username': 'same-username',
      'saved_password': 'hot-password',
      'saved_credentials': jsonEncode([
        {
          'username': 'same-username',
          'password': 'hot-password',
          'login_source': 'hotmanga',
          'token': 'hot-token',
        },
      ]),
    });
    secure = _TestSecureStore();
    SecureCredentialStore.setInstance(secure);
    await user.init();
    probes = 0;
    expectedPrimaryRequests = 0;
    LoginNodeStatusCard.probeOverride = (hosts, {onHostResult}) async {
      probes++;
      for (final host in hosts) {
        onHostResult?.call(host, 1);
      }
      return {for (final host in hosts) host: 1};
    };
    LoginNodeStatusCard.hotHostOverride = () => 'mapi.hotmangasg.com';
    response = (_) => _jsonResponse({
      'code': 200,
      'results': {'list': <Object>[], 'total': 0},
    });
    copyAdapter = _FakeAdapter((request) => response(request));
    copyProfileAdapter = _FakeAdapter(
      (_) => _jsonResponse({'code': 200, 'results': <String, Object>{}}),
    );
    primaryResponse = (_) => throw StateError('Unexpected primary request');
    mainAdapter = _FakeAdapter((request) => primaryResponse(request));
    primaryDio = Dio()..httpClientAdapter = mainAdapter;
    commentDio = Dio()..httpClientAdapter = mainAdapter;
    transport = ApiTransport(
      dio: primaryDio,
      commentDio: commentDio,
      user: user,
      cache: DataCache(),
    );
    api = UserApi(
      transport,
      copyDioFactory: (options) =>
          Dio(options)..httpClientAdapter = copyAdapter,
      profileDioFactory: (options) =>
          Dio(options)..httpClientAdapter = mainAdapter,
      copyProfileDioFactory: (options) =>
          Dio(options)..httpClientAdapter = copyProfileAdapter,
    );
    // Any accidental refresh/logout through the global facade must hit a fake,
    // never the singleton's platform HttpClientAdapter.
    ApiClient.setTestInstance(_FakeApiClient(api));
  });

  tearDown(() {
    primaryDio.close();
    commentDio.close();
    LoginNodeStatusCard.probeOverride = null;
    LoginNodeStatusCard.hotHostOverride = null;
    ApiClient.setTestInstance(originalApi);
    SecureCredentialStore.resetInstance();
    expect(mainAdapter.requests, hasLength(expectedPrimaryRequests));
  });

  Future<void> settleLogin(WidgetTester tester) async {
    final watch = Stopwatch()..start();
    do {
      // Login futures run outside fakeAsync. Yield real work until the busy
      // indicator disappears; a fixed 30ms sleep races slower hosts.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      if (watch.elapsed > const Duration(seconds: 5)) {
        fail('Login did not finish within 5 seconds');
      }
    } while (true);
    await tester.pumpAndSettle();
  }

  Future<void> pumpLogin(
    WidgetTester tester, {
    bool profile = false,
    bool copyOnly = true,
  }) async {
    final router = GoRouter(
      initialLocation: profile ? '/' : '/login',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => profile
              ? const ProfilePage()
              : const Scaffold(body: Text('test-home')),
          routes: [
            GoRoute(
              name: 'login',
              path: 'login',
              builder: (_, state) => LoginPage(
                copyOnly: profile
                    ? state.uri.queryParameters['copyOnly'] == 'true'
                    : copyOnly,
                userApi: api,
              ),
            ),
          ],
        ),
        GoRoute(
          name: AppRoutes.webviewLogin,
          path: '/webview-login',
          builder: (context, state) {
            final extra = state.extra;
            final fill = extra is ({String username, String password})
                ? '${extra.username}:${extra.password}'
                : 'no-fill';
            return Scaffold(
              appBar: AppBar(title: const Text('test-official-login')),
              body: Column(
                children: [
                  Text('test-fill:$fill'),
                  TextButton(
                    onPressed: () => context.pop(false),
                    child: const Text('test-web-cancel'),
                  ),
                  TextButton(
                    onPressed: () => context.pop(true),
                    child: const Text('test-web-success'),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> submitHotPassword(
    WidgetTester tester, {
    String password = 'hot-password',
    bool useKeyboard = false,
  }) async {
    await tester.enterText(find.byType(TextField).at(0), 'same-username');
    await tester.enterText(find.byType(TextField).at(1), password);
    await tester.ensureVisible(find.widgetWithText(FilledButton, '登录'));
    await tester.runAsync(() async {
      if (useKeyboard) {
        await tester.testTextInput.receiveAction(TextInputAction.done);
      } else {
        await tester.tap(find.widgetWithText(FilledButton, '登录'));
      }
    });
    await settleLogin(tester);
  }

  // COPY's password API remains for legacy auto-login, but is no longer
  // reachable from LoginPage. Exercise its account transaction directly.
  Future<bool> authenticateCopyPassword() => user.authenticateAndLogin(
    source: 'copy',
    authenticate: () => api.copyLogin('same-username', 'copy-password'),
  );

  Future<void> submitToken(
    WidgetTester tester, {
    String token = 'candidate-copy',
  }) async {
    await tester.tap(find.byIcon(Icons.key).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, token);
    final button = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, '登录'),
    );
    await tester.runAsync(() async {
      await tester.tap(button);
    });
    await settleLogin(tester);
  }

  test(
    'token validation uses only the explicit candidate and dynamic COPY headers',
    () async {
      await user.copyAccount.saveSession(_oldSession);
      final before = _mainSnapshot(user);
      final result = await api.validateCopyToken('  candidate-copy  ');
      expect(result.token, 'candidate-copy');
      expect(user.copyToken, 'old-copy');
      expect(_mainSnapshot(user), before);
      // Collection validation never invents a profile lookup.
      final validation = copyAdapter.requests.single;
      expect(result.username, isEmpty);
      final request = validation;
      expect(request.uri.host, user.copyApiHost);
      expect(request.method, 'GET');
      expect(request.path, endsWith('/api/v3/member/collect/books'));
      expect(request.headers['Authorization'], 'Token candidate-copy');
      expect(request.headers['User-Agent'], 'COPY/${user.copyAppVersion}');
      expect(request.headers['source'], 'copyApp');
      expect(request.headers['platform'], '3');
      expect(request.headers['version'], user.copyAppVersion);
      expect(request.headers['webp'], '1');
      expect(request.followRedirects, isFalse);
      expect(request.uri.queryParameters, {
        'limit': '1',
        'offset': '0',
        'free_type': '1',
        'ordering': '-datetime_modifier',
        'platform': '3',
      });
      await user.setCopyApiHost('copy-test.invalid');
      await user.setCopyAppVersion('9.8.7');
      await api.validateCopyToken('second-copy');
      final changed = copyAdapter.requests
          .where((r) => r.path.endsWith('/member/collect/books'))
          .last;
      expect(changed.uri.host, 'copy-test.invalid');
      expect(changed.headers['User-Agent'], 'COPY/9.8.7');
      expect(changed.headers['Authorization'], 'Token second-copy');
    },
  );

  test('validated known token reuses only its exact stored identity', () async {
    await user.copyAccount.saveSession(_oldSession);
    final before = _mainSnapshot(user);
    final result = await api.validateCopyToken(_oldSession.token);
    expect(result.userId, _oldSession.userId);
    expect(result.username, _oldSession.username);
    expect(user.copyToken, _oldSession.token);
    expect(_mainSnapshot(user), before);
    expect(copyAdapter.requests, hasLength(1));
  });

  test(
    'unknown valid token remains identity-less without guessing APIs',
    () async {
      await user.copyAccount.saveSession(_oldSession);
      final result = await api.validateCopyToken('candidate-copy');
      expect(result.token, 'candidate-copy');
      expect(result.id, isNull);
      expect(copyAdapter.requests, hasLength(1));
      expect(
        copyAdapter.requests.single.path,
        endsWith('/member/collect/books'),
      );
    },
  );

  test(
    'HTTP/business 401, redirects and malformed successes never affect either account',
    () async {
      await user.copyAccount.saveSession(_oldSession);
      final before = _mainSnapshot(user);
      for (final scenario in [
        (status: 401, data: <String, Object>{'code': 401}),
        (status: 200, data: <String, Object>{'code': 401}),
        (
          status: 302,
          data: <String, Object>{
            'code': 200,
            'results': {'list': []},
          },
        ),
        (status: 200, data: <String, Object>{'code': 200, 'results': {}}),
      ]) {
        response = (_) => _jsonResponse(scenario.data, scenario.status);
        await expectLater(
          user.copyAccount.login(() => api.validateCopyToken('bad-copy')),
          throwsA(isA<DioException>()),
        );
        expect(user.copyToken, 'old-copy');
        expect(_mainSnapshot(user), before);
      }
    },
  );

  test(
    'COPY password API returns a session without any UserManager side effect',
    () async {
      final before = _mainSnapshot(user);
      response = (_) => _jsonResponse({
        'code': 200,
        'results': {
          'token': 'password-copy',
          'username': 'same-username',
          'user_id': 'copy-id',
        },
      });
      final result = await api.copyLogin('same-username', 'copy-password');
      expect(result['token'], 'password-copy');
      expect(user.copyToken, isNull);
      expect(_mainSnapshot(user), before);
      expect(copyAdapter.requests.single.uri.path, '/api/kb/web/login');
      expect(
        copyAdapter.requests.single.headers.containsKey('Authorization'),
        isFalse,
      );
    },
  );

  testWidgets(
    'switching HOT to COPY rejects a HOT-valid token without touching accounts',
    (tester) async {
      await tester.runAsync(() => user.copyAccount.saveSession(_oldSession));
      final before = _mainSnapshot(user);
      // This candidate is valid only on HOT. The selected COPY validator must
      // reject it instead of silently using HOT member/info and marking COPY.
      primaryResponse = (_) => _jsonResponse({
        'code': 200,
        'results': {'user_id': 'hot-new', 'username': 'hot-new'},
      });
      response = (_) => _jsonResponse({'code': 401}, 401);
      await pumpLogin(tester, copyOnly: false);
      await tester.tap(find.text('拷贝漫画'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(2));
      await submitToken(tester, token: 'valid-hot-only');
      expect(_mainSnapshot(user), before);
      expect(user.copyToken, 'old-copy');
      expect(
        copyAdapter.requests.single.headers['Authorization'],
        'Token valid-hot-only',
      );
      expect(find.byType(AlertDialog), findsOneWidget);
    },
  );

  testWidgets(
    'explicit HOT token selection persists HOT provenance and cannot migrate as COPY',
    (tester) async {
      await tester.runAsync(() async {
        await user.setLoginSource('copy');
        await user.copyAccount.saveSession(_oldSession);
      });
      expectedPrimaryRequests = 1;
      primaryResponse = (_) => _jsonResponse({
        'code': 200,
        'results': {'user_id': 'hot-new', 'username': 'hot-new'},
      });
      await pumpLogin(tester, copyOnly: false);
      await tester.tap(find.text('热辣漫画'));
      await tester.pumpAndSettle();
      await submitToken(tester, token: 'valid-hot-only');
      // 漫画已登录（setUp 的 hot-token）→ 保持，但热辣来源照样记进列表。
      expect(user.token, 'hot-token');
      expect(user.copyToken, 'old-copy');
      expect(copyAdapter.requests, isEmpty);
      expect(
        user.savedCredentials.any(
          (item) => item.source == 'hotmanga' && item.token == 'valid-hot-only',
        ),
        isTrue,
      );
      await tester.runAsync(() async {
        // A missing record also models startup when secure migration could
        // not run before this login. Persisted HOT provenance must stay safe.
        await secure.deleteAll();
        await user.init();
      });
      expect(user.copyToken, isNull);
      expect(jsonDecode((await secure.readCopyAccountRecord())!), {
        'migrationHandled': true,
        'activeId': null,
        'accounts': <Object?>[],
      });
    },
  );

  testWidgets(
    'ordinary COPY token validation explicitly synchronizes the independent account',
    (tester) async {
      await tester.runAsync(() => user.setLoginSource('copy'));
      await tester.runAsync(
        () => user.copyAccount.saveSession(
          const CopyAccountSession(
            token: 'validated-copy',
            userId: 'validated-id',
            username: 'validated-user',
          ),
        ),
      );
      await pumpLogin(tester, copyOnly: false);
      await submitToken(tester, token: 'validated-copy');
      // 漫画已登录（setUp 的 hot-token）→ 保持不动。
      expect(user.token, 'hot-token');
      expect(user.copyToken, 'validated-copy');
      expect(user.copyAccount.activeId, 'u:validated-id');
      expect(
        copyAdapter.requests.first.uri.path,
        '/api/v3/member/collect/books',
      );
      expect(find.text('test-home'), findsOneWidget);
    },
  );

  test(
    'legacy COPY password authentication fills the unselected novel domain',
    () async {
      await user.setLoginSource('copy');
      response = (_) => _jsonResponse({
        'code': 200,
        'results': {
          'token': 'authenticated-copy',
          'user_id': 'copy-id',
          'username': 'copy-main',
          'nickname': 'COPY main',
        },
      });
      expect(await authenticateCopyPassword(), isTrue);
      expect(user.copyToken, 'authenticated-copy');
      // 漫画已登录，登录只入库不接管。
      expect(user.token, 'hot-token');
      expect(copyAdapter.requests.single.uri.path, '/api/kb/web/login');
    },
  );

  testWidgets('COPY-only mode exposes the account form and token login entry', (
    tester,
  ) async {
    await pumpLogin(tester);
    expect(find.byType(SegmentedButton<bool>), findsNothing);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.widgetWithText(FilledButton, '登录'), findsOneWidget);
    expect(find.text('热辣漫画'), findsNothing);
    expect(find.text('same-username'), findsNothing);
    expect(
      find.byKey(const ValueKey('official-register-copy')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.key), findsOneWidget);
    // 通道选择器始终展示：网页接口与网页都不需要签名密钥。
    // App 接口登录是否出现取决于密钥，这里不断言（见 login_page_test）。
    expect(find.text('网页接口'), findsOneWidget);
    expect(find.text('网页'), findsOneWidget);
    expect(
      tester
          .widget<LoginNodeStatusCard>(find.byType(LoginNodeStatusCard))
          .useCopyLogin,
      isTrue,
    );
    expect(probes, 1);
    expect(copyAdapter.requests, isEmpty);
  });

  testWidgets(
    'COPY account login requires both fields before opening the official page',
    (tester) async {
      await pumpLogin(tester);
      await tester.enterText(find.byType(TextField).at(0), 'auto-user');
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pumpAndSettle();
      expect(find.text('请输入用户名和密码'), findsOneWidget);
      expect(find.text('test-official-login'), findsNothing);
    },
  );

  Future<void> selectCopyChannel(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('网页接口登录打官网登录接口并直接落库', (tester) async {
    response = (_) => _jsonResponse({
      'code': 200,
      'results': {
        'token': 'web-api-copy',
        'user_id': 'web-api-id',
        'username': 'auto-user',
        'nickname': 'COPY web api',
      },
    });
    await pumpLogin(tester);
    await selectCopyChannel(tester, '网页接口');

    await tester.enterText(find.byType(TextField).at(0), 'auto-user');
    await tester.enterText(find.byType(TextField).at(1), 'auto-password');
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    // 不再经过 WebView：请求直接由客户端发出，域名是官网登录域名。
    expect(find.text('test-official-login'), findsNothing);
    final request = copyAdapter.requests.first;
    expect(request.method, 'POST');
    expect(request.uri.host, user.copyLoginHost);
    expect(request.uri.path, '/api/kb/web/login');
    expect(user.copyToken, 'web-api-copy');
    expect(find.text('test-home'), findsOneWidget);
  });

  testWidgets('接口登录直连失败后静默改用代理重试一次', (tester) async {
    // 两次都失败：直连一趟 + 代理重试一趟，共两次请求。
    var attempts = 0;
    response = (_) {
      attempts++;
      return _jsonResponse({'code': 500, 'message': '服务端异常'});
    };
    await pumpLogin(tester);
    await selectCopyChannel(tester, '网页接口');

    await tester.enterText(find.byType(TextField).at(0), 'auto-user');
    await tester.enterText(find.byType(TextField).at(1), 'auto-password');
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    // 重试对用户静默：只报最后一次失败，不暴露「用过代理」。
    expect(find.text('登录失败：服务端异常'), findsOneWidget);
    expect(find.textContaining('代理'), findsNothing);
    expect(user.copyToken, isNull);
  });

  testWidgets('IP 风控封禁用警告框提示在登录按钮下方', (tester) async {
    response = (_) => _jsonResponse({
      'code': 210,
      'message': '請到官網更新最新APP',
      'results': {'detail': '請到官網更新最新APP'},
    });
    await pumpLogin(tester);
    await selectCopyChannel(tester, '网页接口');

    await tester.enterText(find.byType(TextField).at(0), 'auto-user');
    await tester.enterText(find.byType(TextField).at(1), 'auto-password');
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    expect(find.text('当前 IP 被封禁，请更换网络环境或代理节点后重试'), findsOneWidget);
    // 警告框带警示图标，且位置在登录按钮下方。
    expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
    final buttonY = tester
        .getCenter(find.widgetWithText(FilledButton, '登录'))
        .dy;
    final warningY = tester
        .getCenter(find.byIcon(Icons.warning_amber_outlined))
        .dy;
    expect(warningY, greaterThan(buttonY));
  });

  testWidgets('代理模式为直连时不重试', (tester) async {
    await user.setNetworkProxyMode(NetworkProxyMode.direct);
    var attempts = 0;
    response = (_) {
      attempts++;
      return _jsonResponse({'code': 500, 'message': '服务端异常'});
    };
    await pumpLogin(tester);
    await selectCopyChannel(tester, '网页接口');

    await tester.enterText(find.byType(TextField).at(0), 'auto-user');
    await tester.enterText(find.byType(TextField).at(1), 'auto-password');
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    // 用户明确选了直连，没有可退回的代理，重试没有意义。
    expect(attempts, 1);
    expect(find.textContaining('登录失败：'), findsOneWidget);
  });

  testWidgets(
    'username field offers saved accounts of the active login source only',
    (tester) async {
      // 存一个拷贝账号（含登录名与密码），模拟自动填表登录后的本机状态。
      await tester.runAsync(() async {
        await completeCopyWebLogin(
          user: user,
          api: api,
          credentials: const CopyWebCredentials(
            token: 'suggest-copy',
            userId: 'copy-id',
            username: 'copy-user',
            nickname: '拷贝昵称',
            avatar: '',
            profileBoundToToken: true,
          ),
        );
        await user.saveLoginFormPasswords({
          'copy-user': 'copy-password',
        }, anchorToken: 'suggest-copy');
      });

      await pumpLogin(tester);
      expect(
        find.byKey(const ValueKey('login-saved-account-copy-user')),
        findsOneWidget,
      );
      expect(find.text('拷贝昵称'), findsOneWidget);
      // 热辣账号不出现在拷贝 tab 的列表里。
      expect(
        find.byKey(const ValueKey('login-saved-account-same-username')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('login-saved-account-copy-user')),
      );
      await tester.pump();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('login-username-field')),
            )
            .controller!
            .text,
        'copy-user',
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('login-password-field')),
            )
            .controller!
            .text,
        'copy-password',
      );
      // 回填后切到网页通道，点登录即可把账密带进官网登录页。
      await selectCopyChannel(tester, '网页');
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pumpAndSettle();
      expect(find.text('test-fill:copy-user:copy-password'), findsOneWidget);
    },
  );

  testWidgets(
    'username field lists saved HOT accounts on the ordinary login tab',
    (tester) async {
      await pumpLogin(tester, copyOnly: false);
      expect(
        find.byKey(const ValueKey('login-saved-account-same-username')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('login-saved-account-same-username')),
      );
      await tester.pump();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('login-password-field')),
            )
            .controller!
            .text,
        'hot-password',
      );
    },
  );

  testWidgets(
    'COPY account login opens the official page with the entered credentials',
    (tester) async {
      await pumpLogin(tester);
      // 默认通道是网页接口登录，先切到网页（WebView）通道。
      await selectCopyChannel(tester, '网页');
      await tester.enterText(find.byType(TextField).at(0), 'auto-user');
      await tester.enterText(find.byType(TextField).at(1), 'auto-password');
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pumpAndSettle();
      expect(find.text('test-official-login'), findsOneWidget);
      expect(find.text('test-fill:auto-user:auto-password'), findsOneWidget);
      expect(find.text('test-fill:no-fill'), findsNothing);

      // 官网页面里取消登录，返回登录页且账号状态不变。
      await tester.tap(find.text('test-web-cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(copyAdapter.requests, isEmpty);
    },
  );

  group('buildCopyLoginFillScript', () {
    test('targets the official login form structure', () {
      final script = buildCopyLoginFillScript(
        username: 'user',
        password: 'pass',
      );
      // 防重入标记 + 桥名。
      expect(script, contains('__copyAutoLoginInjected'));
      expect(script, contains("callHandler('copyAutoLogin'"));
      // 桌面版选择器（Element UI）：el-form + 可见 primary 按钮。
      expect(script, contains("querySelector('form.el-form')"));
      expect(script, contains('.el-input__inner'));
      expect(script, contains('button.el-button--primary'));
      // 移动版选择器（Vant UI h5）：van-form + 登錄按钮。
      expect(script, contains("querySelector('form.van-form')"));
      expect(script, contains('.van-field__control'));
      expect(script, contains('.van-button-login'));
      // 可见性过滤，避开注册 pane 的隐藏按钮。
      expect(script, contains('offsetParent'));
      // Element UI / Vant 都需要 native setter + input 事件更新 v-model。
      expect(script, contains('HTMLInputElement.prototype'));
      expect(script, contains("new Event('input'"));
      // 错误回报：Element 的红色 toast 与 Vant 的 toast（「成功」字样过滤），
      // 以及两种表单的红字校验兜底。
      expect(script, contains('.el-message--error'));
      expect(script, contains('.van-toast'));
      expect(script, contains('--success'));
      expect(script, contains('/成功|success/i'));
      expect(script, contains('.el-form-item__error'));
      expect(script, contains('.van-field__error-message'));
      // 表单找不到的超时回报。
      expect(script, contains('form_not_found'));
    });

    test('can be re-injected after an SPA navigation to the login page', () {
      final script = buildCopyLoginFillScript(
        username: 'user',
        password: 'pass',
      );
      // 官网 h5 站是 history 路由 SPA：用户选完线路才 replace 回 /h5/login，
      // 表单出现可能晚于首次注入，所以每次注入都要重置状态并重新计时。
      expect(script, contains('window.__copyAutoLoginTimer'));
      expect(script, contains('clearInterval(window.__copyAutoLoginTimer)'));
      expect(script, contains('window.__copyLoginProbeReset'));
      // 已填过时默认不重复点击，只有显式要求才重填。
      expect(script, contains('window.__copyAutoLoginFilled'));
      expect(script, contains('var skipFilled = false;'));
    });

    test('skipFilled refills a password the user corrected', () {
      final script = buildCopyLoginFillScript(
        username: 'user',
        password: 'pass',
        skipFilled: true,
      );
      expect(script, contains('var skipFilled = true;'));
    });

    test('watches the h5 login endpoint as well as the desktop one', () {
      // 桌面站打 /api/kb/web/login，h5 站打 /api/v3/login。
      expect(copyLoginSubmitPaths, contains('/api/kb/web/login'));
      expect(copyLoginSubmitPaths, contains('/api/v3/login'));
      final script = buildCopyLoginFormScript();
      expect(script, contains(jsonEncode(copyLoginSubmitPaths)));
    });

    test('embeds credentials as a legal JSON literal', () {
      const username = 'user"1</script>\n';
      const password = r"pass'2\3${}";
      final payload = jsonEncode({'username': username, 'password': password});
      final script = buildCopyLoginFillScript(
        username: username,
        password: password,
      );
      expect(script, contains('var params = $payload;'));
      // 嵌入的字面量可被完整还原，特殊字符无转义损失。
      expect(jsonDecode(payload), {'username': username, 'password': password});
    });
  });

  for (final copyOnly in [false, true]) {
    testWidgets(
      'web login route supports cancel and success in copyOnly=$copyOnly',
      (tester) async {
        await pumpLogin(tester, copyOnly: copyOnly);
        if (!copyOnly) {
          await tester.tap(find.text('拷贝漫画'));
          await tester.pumpAndSettle();
        }
        final before = _mainSnapshot(user);
        expect(find.byType(TextField), findsNWidgets(2));
        expect(find.byType(CheckboxListTile), findsNothing);
        expect(find.byIcon(Icons.key), findsOneWidget);
        expect(
          find.byKey(const ValueKey('official-register-copy')),
          findsOneWidget,
        );

        // 网页通道（WebView）是最后一项，需显式切换；默认通道是网页接口登录。
        await selectCopyChannel(tester, '网页');
        await tester.enterText(find.byType(TextField).at(0), 'auto-user');
        await tester.enterText(find.byType(TextField).at(1), 'auto-password');
        await tester.tap(find.widgetWithText(FilledButton, '登录'));
        await tester.pumpAndSettle();
        expect(find.text('test-official-login'), findsOneWidget);
        await tester.tap(find.text('test-web-cancel'));
        await tester.pumpAndSettle();
        expect(find.byType(LoginPage), findsOneWidget);
        expect(find.byType(TextField), findsNWidgets(2));
        expect(_mainSnapshot(user), before);

        await tester.tap(find.widgetWithText(FilledButton, '登录'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('test-web-success'));
        await tester.pumpAndSettle();
        expect(find.text('test-home'), findsOneWidget);
        expect(copyAdapter.requests, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'ordinary login retains the source switch and saved primary credential',
    (tester) async {
      await pumpLogin(tester, copyOnly: false);
      expect(find.byType(SegmentedButton<bool>), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsOneWidget);
      // 表单预填主账号，下方列表同时列出该账号供一键回填。
      expect(find.text('same-username'), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('login-saved-account-same-username')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('official-register-hotmanga')),
        findsOneWidget,
      );
      expect(copyAdapter.requests, isEmpty);
    },
  );

  test(
    'legacy COPY password authentication fills only the unselected novel domain',
    () async {
      response = (_) => _jsonResponse({
        'code': 200,
        'results': {
          'token': 'password-copy',
          'username': 'same-username',
          'user_id': 'copy-id',
          'nickname': 'COPY name',
        },
      });
      expect(await authenticateCopyPassword(), isTrue);
      expect(user.copyToken, 'password-copy');
      // 漫画已经登录（setUp 里的 hot-token），登录不抢占，只进列表。
      expect(user.token, 'hot-token');
      expect(user.loginSource, 'hotmanga');
      expect(
        user.savedCredentials.where((item) => item.username == 'same-username'),
        hasLength(2),
      );
      expect(
        user.savedCredentials
            .singleWhere((item) => item.source == 'hotmanga')
            .token,
        'hot-token',
      );
      expect(copyAdapter.requests, hasLength(1));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('user_token'), isNull);
      expect(await secure.readToken(), 'hot-token');
      expect(
        prefs.getKeys().any((key) => key.startsWith('copy_account')),
        isFalse,
      );
      expect(await secure.readCopyAccountRecord(), contains('password-copy'));
    },
  );

  test(
    'legacy COPY password failure preserves primary and existing COPY',
    () async {
      await user.copyAccount.saveSession(_oldSession);
      final before = _mainSnapshot(user);
      response = (_) => _jsonResponse({'code': 401, 'message': 'invalid'}, 401);
      await expectLater(
        authenticateCopyPassword(),
        throwsA(isA<DioException>()),
      );
      expect(user.copyToken, 'old-copy');
      expect(_mainSnapshot(user), before);
    },
  );

  testWidgets(
    'COPY-only token login validates before persisting and never refreshes main profile',
    (tester) async {
      await tester.runAsync(
        () => user.copyAccount.saveSession(
          const CopyAccountSession(
            token: 'candidate-copy',
            userId: 'candidate-id',
            username: 'candidate-user',
          ),
        ),
      );
      await pumpLogin(tester);
      await submitToken(tester);
      expect(user.copyToken, 'candidate-copy');
      expect(user.copyAccount.activeId, 'u:candidate-id');
      expect(user.token, 'hot-token');
      expect(user.loginSource, 'hotmanga');
      expect(
        copyAdapter.requests.first.headers['Authorization'],
        'Token candidate-copy',
      );
      expect(find.text('test-home'), findsOneWidget);
    },
  );

  testWidgets(
    'COPY-only token failure does not clear either existing account',
    (tester) async {
      await tester.runAsync(() => user.copyAccount.saveSession(_oldSession));
      final before = _mainSnapshot(user);
      response = (_) => _jsonResponse({'code': 401}, 401);
      await pumpLogin(tester);
      await submitToken(tester);
      expect(user.copyToken, 'old-copy');
      expect(_mainSnapshot(user), before);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('profile no longer shows a standalone COPY account card', (
    tester,
  ) async {
    await tester.runAsync(() => user.copyAccount.saveSession(_oldSession));
    await pumpLogin(tester, profile: true);
    // 轻小说的拷贝账号统一走「我的」里已有的登录入口，
    // 不再单独放一张账号卡片。
    expect(find.byKey(const ValueKey('copy-account-card')), findsNothing);
    expect(find.byKey(const ValueKey('copy-account-login')), findsNothing);
    expect(find.byKey(const ValueKey('copy-account-logout')), findsNothing);
    expect(find.text('old-copy'), findsNothing);
    expect(user.copyToken, 'old-copy');
    expect(copyAdapter.requests, isEmpty);
  });

  test(
    'COPY password response without profile still binds the novel domain by login name',
    () async {
      response = (_) => _jsonResponse({
        'code': 200,
        'results': {'token': 'minimal-copy'},
      });
      expect(await authenticateCopyPassword(), isTrue);
      expect(user.copyToken, 'minimal-copy');
      expect(user.token, 'hot-token');
      expect(user.copyAccount.session?.username, 'same-username');
      expect(user.copyAccount.activeId, isNotNull);
    },
  );

  for (final remember in [false, true]) {
    testWidgets(
      'HOT password login preserves COPY and honors remember=$remember',
      (tester) async {
        await tester.runAsync(() => user.copyAccount.saveSession(_oldSession));
        expectedPrimaryRequests = 1;
        primaryResponse = (_) async {
          // Longer than the old helper's fixed wait, for both tap and keyboard.
          await Future<void>.delayed(const Duration(milliseconds: 80));
          return _jsonResponse({
            'code': 200,
            'results': {
              'token': 'new-hot',
              'user_id': 'new-hot-id',
              'username': 'same-username',
            },
          });
        };
        await pumpLogin(tester, copyOnly: false);
        if (!remember) {
          await tester.ensureVisible(find.byType(CheckboxListTile));
          await tester.tap(find.byType(CheckboxListTile));
          await tester.pumpAndSettle();
        }
        await submitHotPassword(
          tester,
          password: 'new-hot-password',
          useKeyboard: remember,
        );
        expect(user.token, 'new-hot');
        expect(user.loginSource, 'hotmanga');
        expect(user.copyToken, _oldSession.token);
        expect(user.savedPassword, remember ? 'new-hot-password' : '');
        expect(
          user.savedCredentials
              .singleWhere((item) => item.source == 'hotmanga')
              .password,
          remember ? 'new-hot-password' : '',
        );
        expect(mainAdapter.requests.single.path, endsWith('/api/v3/login'));
        expect(copyAdapter.requests, isEmpty);
        expect(find.text('test-home'), findsOneWidget);
      },
    );
  }

  testWidgets('HOT password login failure surfaces the server message', (
    tester,
  ) async {
    expectedPrimaryRequests = 1;
    primaryResponse = (_) =>
        _jsonResponse({'code': 401, 'message': '账号或密码错误'}, 401);
    await pumpLogin(tester, copyOnly: false);
    await submitHotPassword(tester, password: 'wrong-password');
    expect(user.token, 'hot-token');
    expect(find.text('登录失败：账号或密码错误'), findsOneWidget);
  });

  testWidgets('HOT token login failure surfaces the HTTP status', (
    tester,
  ) async {
    expectedPrimaryRequests = 1;
    primaryResponse = (_) => _jsonResponse({'code': 401}, 401);
    await pumpLogin(tester, copyOnly: false);
    await submitToken(tester, token: 'expired-token');
    expect(user.token, 'hot-token');
    expect(find.text('请求失败（code: 401）'), findsOneWidget);
    expect(find.text('令牌无效或已过期'), findsNothing);
  });

  for (final copyOnly in [false, true]) {
    testWidgets(
      'unknown valid COPY token in copyOnly=$copyOnly is stored without profile',
      (tester) async {
        await tester.runAsync(() => user.copyAccount.saveSession(_oldSession));
        await pumpLogin(tester, copyOnly: copyOnly);
        if (!copyOnly) {
          await tester.tap(find.text('拷贝漫画'));
          await tester.pumpAndSettle();
        }
        await submitToken(tester, token: 'unknown-valid-token');
        // 轻小说已选中旧账号 → 登录只入库，不接管。
        expect(user.copyToken, 'old-copy');
        expect(user.token, 'hot-token');
        final added = user.copyAccount.accounts.firstWhere(
          (account) => account.token == 'unknown-valid-token',
        );
        expect(added.hasIdentity, isFalse);
        expect(added.id, startsWith('local:'));
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('test-home'), findsOneWidget);
        await tester.runAsync(() => user.init());
        expect(user.copyToken, 'old-copy');
        expect(user.token, 'hot-token');
        expect(
          user.copyAccount.accounts.any(
            (account) => account.token == 'unknown-valid-token',
          ),
          isTrue,
        );
        expect(copyAdapter.requests, hasLength(1));
        expect(
          copyAdapter.requests.single.path,
          endsWith('/member/collect/books'),
        );
      },
    );
  }

  test(
    'COPY secure write failure rolls back primary login rather than reporting success',
    () async {
      await user.copyAccount.saveSession(_oldSession);
      final before = _mainSnapshot(user);
      final beforeCredentials = await secure.readCredentials();
      secure.failCopyWrite = true;
      await expectLater(
        user.authenticateAndLogin(
          source: 'copy',
          authenticate: () async => {
            'token': 'failed-copy',
            'username': 'copy-user',
            'user_id': 'copy-id',
          },
        ),
        throwsA(isA<CopyAccountStorageException>()),
      );
      expect(_mainSnapshot(user), before);
      expect(user.copyToken, _oldSession.token);
      expect(await secure.readToken(), before['token']);
      // 回滚把内存发布态写回 secure：同一账号的资料字段（id/昵称/头像）
      // 可能在 init 时已合并进内存版本，所以按账号有效字段比较而非字节。
      final afterCredentials = await secure.readCredentials();
      expect(afterCredentials.length, beforeCredentials.length);
      for (var i = 0; i < afterCredentials.length; i++) {
        expect(afterCredentials[i].username, beforeCredentials[i].username);
        expect(afterCredentials[i].password, beforeCredentials[i].password);
        expect(afterCredentials[i].token, beforeCredentials[i].token);
        expect(
          afterCredentials[i].loginSource,
          beforeCredentials[i].loginSource,
        );
      }
    },
  );

  test(
    'late COPY login cannot overwrite a manual novel selection or primary logout',
    () async {
      await user.copyAccount.saveSession(_oldSession);
      for (final logout in [false, true]) {
        final pending = Completer<Map<String, dynamic>>();
        final signingIn = user.authenticateAndLogin(
          source: 'copy',
          authenticate: () => pending.future,
        );
        if (logout) {
          await user.logout();
        } else {
          await user.copyAccount.selectAccount(_oldSession.id);
        }
        final before = _mainSnapshot(user);
        pending.complete({
          'token': 'late-copy',
          'username': 'late-user',
          'user_id': 'late-id',
        });
        expect(await signingIn, isFalse);
        expect(_mainSnapshot(user), before);
        expect(user.copyToken, _oldSession.token);
      }
    },
  );

  test(
    'COPY login adds the novel account and leaves the selected comic account alone',
    () async {
      final observations = <({String? comic, String? novel})>[];
      void listener() =>
          observations.add((comic: user.token, novel: user.copyToken));
      user.addListener(listener);
      try {
        expect(
          await user.authenticateAndLogin(
            source: 'copy',
            authenticate: () async => {
              'token': 'new-copy',
              'username': 'new-copy-user',
              'user_id': 'new-copy-id',
            },
          ),
          isTrue,
        );
      } finally {
        user.removeListener(listener);
      }
      expect(observations, isNotEmpty);
      // 漫画已登录（setUp 的 hot-token）→ 保持不动；轻小说未登录 → 接管。
      expect(
        observations.every(
          (item) => item.comic == 'hot-token' && item.novel == 'new-copy',
        ),
        isTrue,
      );
    },
  );

  Future<bool> webTokenLogin(String token) => completeCopyWebLogin(
    user: user,
    api: api,
    credentials: CopyWebCredentials(
      token: token,
      userId: '',
      nickname: '',
      avatar: '',
    ),
  );

  test('h5 web logins of one account collapse into a single card', () async {
    // 手机端官网把登录态写在 localStorage["user"]，字段名是 userid（无下划线）。
    // 旧解析漏掉这个键，提取到的凭证没有身份，而官网每次登录都轮换 token，
    // 于是同一账号每次都新建一条，账号中心堆出重复卡片。
    CopyWebCredentials? creds;
    void extract(String token, String userId) {
      creds = parseCopyWebStorage({
        'ls': {'user': '{"token":"$token","userid":"$userId"}'},
      });
    }

    extract('h5-token-1', 'h5-user-id');
    expect(creds?.userId, 'h5-user-id');
    expect(
      await completeCopyWebLogin(user: user, api: api, credentials: creds!),
      isTrue,
    );

    // 第二次登录：官网轮换了 token，身份不变。
    extract('h5-token-2', 'h5-user-id');
    expect(
      await completeCopyWebLogin(user: user, api: api, credentials: creds!),
      isTrue,
    );

    expect(
      user.copyAccount.accounts,
      hasLength(1),
      reason: '同一账号两次手机端登录只能有一张卡片',
    );
    expect(user.copyAccount.accounts.single.userId, 'h5-user-id');
    expect(user.copyAccount.token, 'h5-token-2', reason: '卡片上的令牌必须跟着轮换');
    expect(
      user.savedCredentials.where((item) => item.source == 'copy'),
      hasLength(1),
    );
  });

  test(
    'successful token login returns before its optional profile request completes',
    () async {
      final profileStarted = Completer<void>();
      final profileResponse = Completer<ResponseBody>();
      copyProfileAdapter.respond = (_) {
        profileStarted.complete();
        return profileResponse.future;
      };

      expect(await webTokenLogin('profile-after-login'), isTrue);
      final accountId = user.copyAccount.session!.id;
      expect(user.copyAccount.session?.hasIdentity, isFalse);
      await profileStarted.future;
      expect(user.token, 'hot-token');
      expect(user.copyToken, 'profile-after-login');
      expect(user.copyAccount.activeId, accountId);

      profileResponse.complete(
        _jsonResponse({
          'code': 200,
          'results': {
            'user_id': 'loaded-profile-id',
            'username': 'loaded-profile-user',
            'nickname': '已获取昵称',
            'avatar': 'loaded-avatar',
          },
        }),
      );
      for (
        var attempt = 0;
        attempt < 30 && user.copyAccount.session?.userId != 'loaded-profile-id';
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(user.token, 'hot-token');
      expect(user.copyToken, 'profile-after-login');
      expect(user.copyAccount.activeId, accountId);
      expect(user.copyAccount.session?.userId, 'loaded-profile-id');
      expect(user.copyAccount.session?.nickname, '已获取昵称');
    },
  );

  test(
    'token-only web login survives restart without inventing identity',
    () async {
      expect(await webTokenLogin('unknown-web-token'), isTrue);
      final id = user.copyAccount.activeId;
      expect(id, matches(r'^local:[0-9a-f]{32}$'));
      final stored = user.copyAccount.session!;
      expect(stored.accountId, id);
      expect(stored.hasIdentity, isFalse);
      // 漫画保持 setUp 的热辣账号，令牌登录只补轻小说。
      expect(user.token, 'hot-token');
      expect(user.copyToken, 'unknown-web-token');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('user_account_id'), isNull);
      expect(prefs.getString('user_token'), isNull);
      await user.init();
      expect(user.token, 'hot-token');
      expect(user.copyToken, 'unknown-web-token');
      expect(user.copyAccount.activeId, id);
      expect(
        user.savedCredentials.where((item) => item.source == 'copy'),
        hasLength(1),
      );
    },
  );

  test(
    'token-only accounts deduplicate, switch and remove by exact handle',
    () async {
      await webTokenLogin('unknown-a');
      final a = user.copyAccount.session!;
      await webTokenLogin('unknown-b');
      // 登录不再接管已选中的轻小说账号，新账号只在列表里。
      final b = user.copyAccount.accounts.firstWhere(
        (account) => account.token == 'unknown-b',
      );
      expect(user.copyAccount.activeId, a.id);
      expect(await user.copyAccount.selectAccount(b.id), isTrue);
      expect(user.copyAccount.activeId, b.id);
      await webTokenLogin('unknown-a');
      expect(user.copyAccount.accounts, hasLength(2));
      expect(
        user.savedCredentials.where((item) => item.source == 'copy'),
        hasLength(2),
      );
      // 显式选择仍然切换轻小说账号（账号中心下拉就是走这条路）。
      expect(await user.copyAccount.selectAccount(b.id), isTrue);
      expect(user.copyAccount.activeId, b.id);
      expect(
        await user.switchToCredential(
          SavedCredential(
            username: b.username,
            password: '',
            token: b.token,
            loginSource: 'copy',
            userId: b.userId,
            nickname: b.nickname,
            avatar: b.avatar,
            accountId: b.id,
          ),
        ),
        isTrue,
      );
      expect(user.token, b.token);
      expect(user.copyToken, b.token);
      await user.removeSavedCredential(
        '',
        loginSource: 'copy',
        accountId: a.accountId,
      );
      await user.copyAccount.removeAccount(a.accountId!);
      await user.init();
      expect(user.token, b.token);
      expect(user.copyToken, b.token);
      expect(
        user.savedCredentials.where((item) => item.source == 'copy'),
        hasLength(1),
      );
      expect(user.currentCredential?.accountId, b.accountId);
    },
  );

  test(
    'stale cookie and unbound storage profile cannot overwrite another account',
    () async {
      // 先让轻小说选中旧账号，之后的登录都不该改写它的资料与令牌。
      await user.copyAccount.saveSession(_oldSession);
      final candidates = [
        parseCopyWebCookies({
          'token': 'new-cookie-token',
          'user_id': _oldSession.userId,
          'username': _oldSession.username,
          'name': 'old-name',
        })!,
        parseCopyWebStorage({
          'ls': {
            'token': 'new-storage-token',
            'userInfo': jsonEncode({
              'user_id': _oldSession.userId,
              'username': _oldSession.username,
            }),
          },
        })!,
      ];
      for (final credentials in candidates) {
        expect(
          await completeCopyWebLogin(
            user: user,
            api: api,
            credentials: credentials,
          ),
          isTrue,
        );
        expect(user.copyAccount.session?.hasIdentity, isTrue);
        // 登录不改写当前选中账号（这里是旧账号），密码槽位也不会被顶掉。
        expect(user.savedPassword, 'hot-password');
        expect(user.copyAccount.byId(_oldSession.id)?.token, _oldSession.token);
      }
      // 两个候选各自入库；旧账号的身份没有被它们的 cookie 资料污染。
      expect(user.copyAccount.accounts, hasLength(3));
    },
  );

  test(
    'profile enrichment keeps the token-only account handle in the novel domain',
    () async {
      await webTokenLogin('unknown-a');
      final id = user.copyAccount.activeId;
      expect(
        await completeCopyWebLogin(
          user: user,
          api: api,
          credentials: const CopyWebCredentials(
            token: 'unknown-a',
            userId: 'learned-id',
            username: 'learned-name',
            nickname: 'learned-nickname',
            avatar: '',
            profileBoundToToken: true,
          ),
        ),
        isTrue,
      );
      expect(user.copyAccount.session?.hasIdentity, isTrue);
      expect(user.copyAccount.session?.accountId, id);
      expect(user.copyAccount.activeId, id);
      expect(user.copyAccount.accounts, hasLength(1));
      await user.init();
      expect(user.copyAccount.activeId, id);
    },
  );

  test(
    'existing novel handle wins over a restored primary handle for the same token',
    () async {
      await user.copyAccount.saveSession(
        const CopyAccountSession(
          token: 'shared-token',
          accountId: 'local:novel',
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      await secure.writeToken('shared-token');
      await prefs.setString('login_source', 'copy');
      await prefs.setString('user_account_id', 'local:primary');
      for (final key in [
        'user_id',
        'user_username',
        'user_nickname',
        'user_avatar',
      ]) {
        await prefs.setString(key, '');
      }
      await secure.writeCredentials(const [
        SavedCredential(
          username: '',
          password: '',
          token: 'shared-token',
          loginSource: 'copy',
          accountId: 'local:primary',
        ),
      ]);
      await user.init(persistMigrations: false);
      // 令牌登录同一账号：轻小说已有的句柄胜出，主凭据被并成一条。
      expect(await webTokenLogin('shared-token'), isTrue);
      expect(user.copyAccount.activeId, 'local:novel');
      expect(user.savedCredentials, hasLength(1));
      expect(
        user.savedCredentials.single.accountId,
        'local:novel',
        reason: '轻小说侧的已有句柄必须保留，否则同一账号会渲染两条',
      );
      await user.init();
      expect(user.copyAccount.activeId, 'local:novel');
    },
  );

  test(
    'empty and non-string login tokens never modify account state',
    () async {
      final before = _mainSnapshot(user);
      for (final token in [null, '', '  ', 42, <String, Object>{}]) {
        await expectLater(
          user.authenticateAndLogin(
            source: 'copy',
            authenticate: () async => {'token': token},
          ),
          throwsFormatException,
        );
        expect(_mainSnapshot(user), before);
        expect(user.copyToken, isNull);
      }
      await expectLater(
        user.authenticateAndLogin(
          source: 'hotmanga',
          authenticate: () async => {'token': 'hot-no-identity'},
        ),
        throwsFormatException,
      );
      expect(_mainSnapshot(user), before);
    },
  );

  test(
    'failed token-only web authentication or persistence keeps previous accounts',
    () async {
      await user.copyAccount.saveSession(_oldSession);
      final before = _mainSnapshot(user);
      final previousId = (await SharedPreferences.getInstance()).getString(
        'user_account_id',
      );
      response = (_) => _jsonResponse({'code': 401}, 401);
      await expectLater(
        webTokenLogin('invalid-token'),
        throwsA(isA<DioException>()),
      );
      expect(_mainSnapshot(user), before);
      response = (_) => _jsonResponse({
        'code': 200,
        'results': {'list': []},
      });
      secure.failCopyWrite = true;
      await expectLater(
        webTokenLogin('valid-token'),
        throwsA(isA<CopyAccountStorageException>()),
      );
      expect(_mainSnapshot(user), before);
      expect(user.copyToken, _oldSession.token);
      expect(
        (await SharedPreferences.getInstance()).getString('user_account_id'),
        previousId,
      );
      secure.failCopyWrite = false;
      await user.init();
      expect(user.token, before['token']);
      expect(user.copyToken, _oldSession.token);
    },
  );

  test(
    'WebView official login stores a new novel account without switching',
    () async {
      await user.copyAccount.saveSession(_oldSession);
      final saved = await completeCopyWebLogin(
        user: user,
        api: api,
        credentials: const CopyWebCredentials(
          token: 'web-copy-token',
          profileBoundToToken: true,
          userId: 'web-id',
          nickname: 'web-copy',
          avatar: '',
        ),
      );
      expect(saved, isTrue);
      // 漫画已登录 → 保持；轻小说已选中旧账号 → 也保持，只入库。
      expect(user.copyToken, 'old-copy');
      expect(user.token, 'hot-token');
      expect(user.loginSource, 'hotmanga');
      expect(user.copyAccount.activeId, _oldSession.id);
      expect(user.copyAccount.accounts, hasLength(2));
      expect(
        user.savedCredentials.any((item) => item.token == 'hot-token'),
        isTrue,
      );
      await user.init();
      expect(user.token, 'hot-token');
      expect(user.copyToken, 'old-copy');
      expect(
        user.savedCredentials.any((item) => item.userId == 'web-id'),
        isTrue,
      );
    },
  );

  test(
    'web login form password is stored for the matching account only',
    () async {
      // 官网登录拿不到表单密码，只能由登录页注入的脚本回报；这里验证只有
      // 用户名对得上的账号会拿到密码，不匹配的用户名不会误存。
      await completeCopyWebLogin(
        user: user,
        api: api,
        credentials: const CopyWebCredentials(
          token: 'form-token',
          userId: 'form-id',
          username: 'form-user',
          nickname: 'form-user',
          avatar: '',
          profileBoundToToken: true,
        ),
      );
      await user.saveLoginFormPasswords({'unknown-user': 'wrong-password'});
      expect(
        user.savedCredentials.any((item) => item.password == 'wrong-password'),
        isFalse,
      );

      await user.saveLoginFormPasswords({'form-user': 'form-password'});
      expect(
        user.savedCredentials
            .firstWhere((item) => item.token == 'form-token')
            .password,
        'form-password',
      );
      // 漫画保持 setUp 的热辣账号，密码槽位不动。
      expect(user.savedPassword, 'hot-password');

      await user.init();
      expect(
        user.savedCredentials
            .firstWhere((item) => item.token == 'form-token')
            .password,
        'form-password',
      );
      expect(user.savedPassword, 'hot-password');
    },
  );

  test(
    'auto-fill password anchors on the logged-in token for token-only accounts',
    () async {
      // 自动填表登录的新账号是 token-only（username 为空），用户名匹配规则
      // 永远对不上；按本次登录的 token 锚定才能把密码并回正确的账号。
      response = (_) => _jsonResponse({
        'code': 200,
        'results': {'list': <Object>[]},
      });
      await completeCopyWebLogin(
        user: user,
        api: api,
        credentials: const CopyWebCredentials(
          token: 'auto-token',
          userId: '',
          nickname: '',
          avatar: '',
        ),
      );
      final tokenOnly = user.savedCredentials.firstWhere(
        (item) => item.token == 'auto-token',
      );
      expect(tokenOnly.username, isEmpty);

      // token 对不上时不写入，防止把密码并到别的账号。
      await user.saveLoginFormPasswords({
        'auto-user': 'auto-password',
      }, anchorToken: 'another-token');
      expect(
        user.savedCredentials
            .firstWhere((item) => item.token == 'auto-token')
            .password,
        isEmpty,
      );

      await user.saveLoginFormPasswords({
        'auto-user': 'auto-password',
      }, anchorToken: 'auto-token');
      expect(
        user.savedCredentials
            .firstWhere((item) => item.token == 'auto-token')
            .password,
        'auto-password',
      );
      // 登录名一并补上，登录页才能按名字回填。
      expect(
        user.savedCredentials
            .firstWhere((item) => item.token == 'auto-token')
            .username,
        'auto-user',
      );
      // 已有登录名不被覆盖（密码相同则不产生变更）。
      await user.saveLoginFormPasswords({
        'other-name': 'auto-password',
      }, anchorToken: 'auto-token');
      expect(
        user.savedCredentials
            .firstWhere((item) => item.token == 'auto-token')
            .username,
        'auto-user',
      );
      // 现有账号（其它 token）不受锚定写入影响。
      final others = user.savedCredentials.where(
        (item) => item.token != 'auto-token' && item.source == 'copy',
      );
      for (final item in others) {
        expect(item.password, isNot('auto-password'));
      }
      await user.init();
      expect(
        user.savedCredentials
            .firstWhere((item) => item.token == 'auto-token')
            .password,
        'auto-password',
      );
    },
  );

  test(
    'repeated password logins of one account collapse into a single entry',
    () async {
      Map<String, Object?> results(String token) => {
        'token': token,
        'user_id': 'copy-id',
        'username': 'copy-main',
        'nickname': 'COPY main',
        'avatar': 'user/cover/copymanga.png',
      };
      Future<bool> loginAs(String token) => user.authenticateAndLogin(
        source: 'copy',
        password: 'copy-password',
        authenticate: () async => results(token),
      );

      expect(await loginAs('password-copy-1'), isTrue);
      expect(await loginAs('password-copy-2'), isTrue);
      expect(user.copyAccount.accounts, hasLength(1));
      expect(user.copyAccount.activeId, 'u:copy-id');
      expect(user.copyAccount.token, 'password-copy-2');
      expect(
        user.savedCredentials.where((item) => item.source == 'copy'),
        hasLength(1),
        reason: '主凭据列表同样不得重复同一身份',
      );
    },
  );
}
