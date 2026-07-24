import 'package:dio/dio.dart';

import '../models/user_manager.dart';
import '../utils/app_dio.dart';
import '../utils/data_cache.dart';
import 'anime/anime_api.dart';
import 'api_transport.dart';
import 'manga/manga_api.dart';
import 'network/network_api.dart';
import 'user/user_api.dart';

/// Facade that creates and exposes individual API services.
///
/// Consumers access domain-specific APIs via [manga], [anime], [network],
/// and [user].  The shared HTTP transport ([ApiTransport]) is internal.
class ApiClient {
  static int get routeCount => routes.length;

  static ApiClient _instance = ApiClient._();
  factory ApiClient() => _instance;

  /// Replace the singleton with a test-specific instance.
  static void setTestInstance(ApiClient client) => _instance = client;

  late final ApiTransport _transport;
  late final MangaApi manga;
  late final AnimeApi anime;
  late final NetworkApi network;
  late final UserApi user;

  ApiClient._() {
    final dio = AppDio.create(source: 'api', enableErrorLog: false);
    final commentDio = AppDio.create(
      source: 'api_comment',
      options: BaseOptions(
        headers: {
          'accept': 'application/json, text/plain, */*',
          'accept-language':
              'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7,en-GB;q=0.6,ru;q=0.5,ja;q=0.4,zh-TW;q=0.3',
          'cache-control': 'no-cache',
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
          'Connection': 'keep-alive',
        },
      ),
    );
    final userManager = UserManager();
    final cache = DataCache();

    _transport = ApiTransport(
      dio: dio,
      commentDio: commentDio,
      user: userManager,
      cache: cache,
    );

    manga = MangaApi(_transport);
    anime = AnimeApi(_transport);
    network = NetworkApi(_transport);
    user = UserApi(_transport);

    // Wire up login handlers for the 401 auto-login interceptor.
    _transport.loginHandler = user.login;
    _transport.copyLoginHandler = user.copyLogin;
  }
}
