import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kira/api/api_client.dart';
import 'package:kira/api/manga/manga_api.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/models/api_ordering.dart';
import 'package:kira/models/comic.dart' as m;
import 'package:kira/pages/search_page.dart';
import 'package:kira/repositories/search_init_repository.dart';
import 'package:kira/routing/main_shell.dart';

/// 列表交互测试只保留封面占位，不访问图片网络、目录插件或磁盘缓存。
void installSearchImageCache() {
  CachedNetworkImageProvider.defaultCacheManager = _PlaceholderImageCache();
}

class _PlaceholderImageCache extends Fake
    implements BaseCacheManager, ImageCacheManager {
  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) => const Stream.empty();

  @override
  Stream<FileResponse> getImageFile(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
    int? maxHeight,
    int? maxWidth,
  }) => const Stream.empty();
}

typedef ComicPage = ({List<m.Comic> list, int total});

/// 每个请求独立持有 Completer，可让旧请求在新请求之前或之后成功/失败。
class PendingComicRequest {
  PendingComicRequest({
    required this.source,
    required this.offset,
    this.query,
    this.ordering,
    this.theme,
    this.top,
  });

  final String source;
  final int offset;
  final String? query;
  final String? ordering;
  final String? theme;
  final String? top;
  final response = Completer<ComicPage>();

  void succeed(List<String> names, {int? total}) {
    response.complete(comicPage(names, total: total));
  }

  void fail() => response.completeError(StateError('受控请求失败'));
}

ComicPage comicPage(List<String> names, {int? total}) => (
  list: [
    for (final name in names) m.Comic(name: name, pathWord: name, cover: ''),
  ],
  total: total ?? names.length,
);

List<m.Theme> hotTags() => [
  m.Theme(name: '冒险', pathWord: 'adventure'),
  m.Theme(name: '恋爱', pathWord: 'romance'),
];

SearchInitData hotInitData() =>
    SearchInitData(keywords: const ['测试热搜'], tags: hotTags());

class ControlledMangaApi extends Fake implements MangaApi {
  final searches = <PendingComicRequest>[];
  final listings = <PendingComicRequest>[];
  Future<List<m.Theme>> Function()? copyTagsLoader;
  Future<m.CopyFilterOptions> Function()? copyFiltersLoader;
  int copyTagsCalls = 0;
  int copyFiltersCalls = 0;

  @override
  Future<ComicPage> searchComics(
    String query, {
    int limit = 20,
    int offset = 0,
  }) {
    final request = PendingComicRequest(
      source: 'hot',
      offset: offset,
      query: query,
    );
    searches.add(request);
    return request.response.future;
  }

  @override
  Future<ComicPage> getComicList({
    String ordering = ApiOrdering.popular,
    int limit = 21,
    int offset = 0,
    String? theme,
    String? author,
  }) => _list(source: 'hot', ordering: ordering, offset: offset, theme: theme);

  @override
  Future<ComicPage> getCopyComicList({
    String ordering = ApiOrdering.popular,
    int limit = 21,
    int offset = 0,
    String? theme,
    String? top,
  }) => _list(
    source: 'copy',
    ordering: ordering,
    offset: offset,
    theme: theme,
    top: top,
  );

  Future<ComicPage> _list({
    required String source,
    required String ordering,
    required int offset,
    String? theme,
    String? top,
  }) {
    final request = PendingComicRequest(
      source: source,
      ordering: ordering,
      offset: offset,
      theme: theme,
      top: top,
    );
    listings.add(request);
    return request.response.future;
  }

  @override
  Future<List<String>> getHotKeywords() async => hotInitData().keywords;

  @override
  Future<List<m.Theme>> getComicTags() async => hotTags();

  @override
  Future<List<m.Theme>> getCopyComicTags() {
    copyTagsCalls++;
    return copyTagsLoader?.call() ?? Future.value(hotTags());
  }

  @override
  Future<m.CopyFilterOptions> getCopyFilterOptions() {
    copyFiltersCalls++;
    return copyFiltersLoader?.call() ??
        Future.value(
          m.CopyFilterOptions(
            themes: hotTags(),
            tops: [m.Theme(name: '韩漫', pathWord: 'korea')],
          ),
        );
  }
}

class SearchTestApiClient extends Fake implements ApiClient {
  SearchTestApiClient(this.manga);

  @override
  final ControlledMangaApi manga;
}

/// 保留真实仓库的 TTL / 并发请求合并，只把缓存替换为内存。
class MemorySearchInitRepository extends SearchInitRepository {
  MemorySearchInitRepository({required super.api}) : cached = hotInitData();

  SearchInitData? cached;
  Future<SearchInitData> Function()? loader;
  Future<SearchInitData?> Function()? cacheLoader;
  int fetchCalls = 0;

  @override
  Future<SearchInitData?> loadFromCache() =>
      cacheLoader?.call() ?? Future.value(cached);

  @override
  Future<void> saveToCache(SearchInitData data) async {
    cached = data;
  }

  @override
  Future<void> invalidateCache() async {
    cached = null;
  }

  @override
  Future<SearchInitData> fetchFromApi() {
    fetchCalls++;
    return loader?.call() ?? Future.value(hotInitData());
  }
}

class SearchTestRig {
  final manga = ControlledMangaApi();
  late final api = SearchTestApiClient(manga);
  late final init = MemorySearchInitRepository(api: api);

  Widget get page => SearchPage(api: api, initRepository: init);
}

Widget searchTestApp(Widget child, {double textScale = 1}) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: child,
);

/// 持续骨架动画不会停止调度帧，不能在受控请求完成前 pumpAndSettle。
Future<void> pumpSearchFrames(WidgetTester tester, {int count = 8}) async {
  for (var i = 0; i < count; i++) {
    // AppStorage 缓存的 prefs future 建于测试真实异步区，需让该区完成存储回调。
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> tapSearchTab(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(Tab, label));
  await pumpSearchFrames(tester);
}

Future<void> submitSearch(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await pumpSearchFrames(tester);
}

/// 与真实 app / main_shell_test 的分支序号保持一致，并挂真实 SearchPage。
GoRouter searchShellRouter(SearchTestRig rig) => GoRouter(
  initialLocation: '/search',
  routes: [
    StatefulShellRoute(
      navigatorContainerBuilder: buildMainShellNavigatorContainer,
      builder: (_, _, shell) => MainShell(navigationShell: shell),
      branches: [
        StatefulShellBranch(
          preload: true,
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) =>
                  const Scaffold(body: Center(child: Text('主导航-漫画'))),
            ),
          ],
        ),
        StatefulShellBranch(
          preload: true,
          routes: [GoRoute(path: '/search', builder: (_, _) => rig.page)],
        ),
        StatefulShellBranch(
          preload: true,
          routes: [
            GoRoute(
              path: '/bookshelf',
              builder: (_, _) =>
                  const Scaffold(body: Center(child: Text('主导航-书架'))),
            ),
          ],
        ),
        StatefulShellBranch(
          preload: true,
          routes: [
            GoRoute(
              path: '/profile',
              builder: (_, _) =>
                  const Scaffold(body: Center(child: Text('主导航-我的'))),
            ),
          ],
        ),
      ],
    ),
  ],
);
