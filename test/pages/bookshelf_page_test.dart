import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kira/api/api_client.dart';
import 'package:kira/api/manga/manga_api.dart';
import 'package:kira/api/novel/novel_api.dart';
import 'package:kira/models/api_ordering.dart';
import 'package:kira/models/comic.dart' hide Theme;
import 'package:kira/models/novel.dart';
import 'package:kira/pages/bookshelf_page.dart';
import 'package:kira/providers/app_providers.dart';
import 'package:kira/providers/novel_providers.dart';
import 'package:kira/providers/repository_providers.dart';
import 'package:kira/repositories/bookshelf_repository.dart';
import 'package:kira/repositories/novel_bookshelf_repository.dart';
import 'package:kira/routing/app_router.dart';
import 'package:kira/utils/reading_history.dart';
import 'package:kira/widgets/load_more_footer.dart';
import 'package:kira/widgets/update_badge.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../novel_api_test.dart' show NovelTestUser;
import '../test_helpers.dart';
import 'search_page_test_support.dart' show installSearchImageCache;

class _User extends NovelTestUser {
  @override
  bool get isLoggedIn => isCopyLoggedIn;

  @override
  bool get isCopyLoggedIn => copyToken?.isNotEmpty == true;

  @override
  String get bookshelfOrdering => ApiOrdering.datetimeUpdated;
}

class _MangaApi extends Fake implements MangaApi {
  int total = 42;
  int calls = 0;
  final pages = <int, List<BookshelfItem>>{};

  @override
  Future<({List<BookshelfItem> list, int total})> getBookshelf({
    int limit = 18,
    int offset = 0,
    String ordering = ApiOrdering.datetimeUpdated,
  }) async {
    calls++;
    return (
      list:
          pages[offset] ??
          (total == 0
              ? <BookshelfItem>[]
              : <BookshelfItem>[
                  BookshelfItem(
                    comic: Comic(
                      name: '漫画$offset',
                      pathWord: 'comic$offset',
                      cover: '',
                    ),
                  ),
                ]),
      total: total,
    );
  }
}

class _Client extends Fake implements ApiClient {
  _Client(this.manga);

  @override
  final MangaApi manga;
}

class _ComicRepo extends ComicBookshelfRepository {
  ComicBookshelfData? cached;

  @override
  Future<ComicBookshelfData?> loadFromCache() async => cached;

  @override
  Future<void> saveToCache(ComicBookshelfData data) async => cached = data;
}

class _NovelApi extends Fake implements NovelApi {
  _NovelApi(this.user);
  final _User user;

  @override
  String get cacheScope => user.copyToken ?? 'guest';
}

class _NovelRepo extends NovelBookshelfRepository {
  _NovelRepo(NovelApi api) : super(api: api);

  int total = 73;
  int calls = 0;

  @override
  Future<NovelShelfCache> load({String? ordering}) async {
    calls++;
    return NovelShelfCache(
      items: total == 0
          ? []
          : [
              const NovelShelfEntry(
                uuid: 1,
                book: NovelBook(uuid: 'novel', pathWord: 'novel', name: '小说'),
              ),
            ],
      total: total,
      scope: 'account',
      cacheTime: DateTime.now(),
    );
  }

  @override
  Future<NovelShelfCache> forceRefreshApi({String? ordering}) =>
      load(ordering: ordering);

  @override
  Future<NovelPage<NovelShelfEntry>> loadPage({
    required int offset,
    int limit = 18,
    String? ordering,
  }) async =>
      NovelPage(list: const [], total: total, limit: limit, offset: offset);
}

class _Harness {
  final user = _User()..copyToken = 'account';
  final manga = _MangaApi();
  final comicRepo = _ComicRepo();
  late final novelApi = _NovelApi(user);
  late final novelRepo = _NovelRepo(novelApi);

  Future<void> pump(
    WidgetTester tester, {
    bool dark = false,
    bool withRouter = false,
  }) async {
    final router = withRouter
        ? GoRouter(
            routes: [
              GoRoute(path: '/', builder: (_, _) => const BookshelfPage()),
              GoRoute(
                path: '/detail/:pathWord',
                name: AppRoutes.comicDetail,
                builder: (_, _) => const Scaffold(body: Text('详情目标')),
              ),
            ],
          )
        : null;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      router?.dispose();
      novelRepo.dispose();
      user.dispose();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userManagerProvider.overrideWithValue(user),
          apiClientProvider.overrideWithValue(_Client(manga)),
          comicBookshelfRepoProvider.overrideWithValue(comicRepo),
          novelApiProvider.overrideWithValue(novelApi),
          novelShelfRepoProvider.overrideWithValue(novelRepo),
        ],
        child: wrapWithApp(
          Theme(
            data: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            child: router == null
                ? const BookshelfPage()
                : Router.withConfig(config: router),
          ),
          wrapInScaffold: false,
        ),
      ),
    );
    await settle(tester);
  }
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> refresh(WidgetTester tester) async {
  final pending = tester
      .widget<RefreshIndicator>(find.byType(RefreshIndicator))
      .onRefresh();
  await settle(tester);
  await pending;
}

BookshelfItem _item(
  String name, {
  String latest = 'new',
  String? browse = 'old',
}) => BookshelfItem(
  comic: Comic(name: name, pathWord: name, cover: '', lastChapterId: latest),
  lastBrowseId: browse,
);

Future<void> _readChapter(
  WidgetTester tester,
  String name,
  String chapter, {
  String group = ReadingHistory.defaultGroup,
}) async {
  await tester.runAsync(() async {
    await ReadingHistory.save(
      pathWord: name,
      group: group,
      chapterUuid: chapter,
      chapterName: chapter,
    );
    await ReadingHistory.flush();
  });
  await settle(tester);
}

void main() {
  setUpAll(installSearchImageCache);
  setUp(() async {
    await ReadingHistory.flush();
    SharedPreferences.setMockInitialValues({});
    setupSecureCredentialStoreForTest();
  });
  tearDown(() async {
    await ReadingHistory.flush();
    teardownSecureCredentialStoreForTest();
  });

  testWidgets('缓存书架跨分组按累计已读清除标签，其余使用远端兜底', (tester) async {
    await _readChapter(tester, '已读最新', 'new');
    await _readChapter(tester, '已读最新', 'old', group: 'extra');
    final h = _Harness();
    h.comicRepo.cached = ComicBookshelfData(
      items: [
        _item('已读最新'),
        _item('未读最新'),
        _item('远端已读', browse: 'new'),
        _item('没有浏览记录', browse: null),
      ],
      total: 4,
      cacheTime: DateTime.now(),
    );
    await h.pump(tester);
    expect(find.byType(UpdateBadge), findsOneWidget);
    expect(h.manga.calls, 0);
    expect(h.comicRepo.cached!.items.first.lastBrowseId, 'old');

    await tester.tap(find.byType(FilterChip));
    await settle(tester);
    expect(find.text('未读最新'), findsOneWidget);
    expect(find.text('已读最新'), findsNothing);
    expect(find.text('远端已读'), findsNothing);
    expect(find.text('没有浏览记录'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('读过最新再回看不误标，清除记录恢复远端判定且不联网', (tester) async {
    final h = _Harness();
    h.manga.total = 1;
    h.manga.pages[0] = [_item('漫画')];
    await h.pump(tester);
    expect(find.byType(UpdateBadge), findsOneWidget);

    await _readChapter(tester, '漫画', 'new');
    expect(find.byType(UpdateBadge), findsNothing);
    await _readChapter(tester, '漫画', 'old');
    expect(find.byType(UpdateBadge), findsNothing);
    await tester.tap(find.byType(FilterChip));
    await settle(tester);
    expect(find.text('没有漫画更新'), findsOneWidget);

    await tester.runAsync(() => ReadingHistory.removeProgress('漫画'));
    await settle(tester);
    expect(find.byType(UpdateBadge), findsOneWidget);
    expect(find.text('漫画'), findsOneWidget);
    expect(h.manga.calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('分页也按本地已读纠正，真正新增最新章仍显示更新', (tester) async {
    await _readChapter(tester, '第二页', 'new');
    final h = _Harness();
    h.manga.total = 2;
    h.manga.pages[0] = [_item('第一页')];
    h.manga.pages[1] = [_item('第二页')];
    await h.pump(tester);
    tester.widget<LoadMoreFooter>(find.byType(LoadMoreFooter)).onPressed();
    await settle(tester);
    expect(find.byType(UpdateBadge), findsOneWidget);
    await tester.tap(find.byType(FilterChip));
    await settle(tester);
    expect(find.text('第二页'), findsNothing);

    h.manga.total = 1;
    h.manga.pages[0] = [_item('第二页', latest: 'newer')];
    await refresh(tester);
    expect(find.text('第二页'), findsOneWidget);
    expect(find.byType(UpdateBadge), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('详情返回后不把回看的续读位置或远端缓存改成最新章', (tester) async {
    final h = _Harness();
    h.manga.total = 1;
    h.manga.pages[0] = [_item('漫画', browse: 'server-old')];
    await h.pump(tester, withRouter: true);
    await tester.tap(find.text('漫画'));
    await settle(tester);
    expect(find.text('详情目标'), findsOneWidget);
    await _readChapter(tester, '漫画', 'new');
    await _readChapter(tester, '漫画', 'old');
    GoRouter.of(tester.element(find.text('详情目标'))).pop();
    await settle(tester);
    expect(find.byType(UpdateBadge), findsNothing);
    final record = await tester.runAsync(
      () => ReadingHistory.get('漫画', group: ReadingHistory.defaultGroup),
    );
    expect(record?.chapterUuid, 'old');
    expect(h.comicRepo.cached!.items.single.lastBrowseId, 'server-old');
    expect(tester.takeException(), isNull);
  });

  testWidgets('顶部显示收藏总数而非当前页或筛选后的数量，保留懒加载', (tester) async {
    final h = _Harness();
    await h.pump(tester);
    expect(find.text('漫画 (42)'), findsOneWidget);
    expect(find.text('轻小说'), findsOneWidget);
    expect(h.novelRepo.calls, 0);

    await tester.tap(find.byType(FilterChip));
    await settle(tester);
    expect(find.text('漫画 (42)'), findsOneWidget);

    await tester.tap(find.text('轻小说'));
    await settle(tester);
    expect(find.text('轻小说 (73)'), findsOneWidget);
    expect(find.text('漫画 (42)'), findsOneWidget);
    expect(h.novelRepo.calls, 1);

    await tester.tap(find.text('漫画 (42)'));
    await settle(tester);
    expect(h.manga.calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('空收藏不显示数量，刷新后同步新增及清空', (tester) async {
    final h = _Harness();
    h.manga.total = 0;
    h.novelRepo.total = 0;
    await h.pump(tester);
    expect(find.text('漫画'), findsOneWidget);
    expect(find.text('漫画 (0)'), findsNothing);

    h.manga.total = 9;
    await refresh(tester);
    expect(find.text('漫画 (9)'), findsOneWidget);
    h.manga.total = 0;
    await refresh(tester);
    expect(find.text('漫画'), findsOneWidget);

    await tester.tap(find.text('轻小说'));
    await settle(tester);
    expect(find.text('轻小说 (0)'), findsNothing);
    h.novelRepo.total = 8;
    await refresh(tester);
    expect(find.text('轻小说 (8)'), findsOneWidget);
    h.novelRepo.total = 0;
    await refresh(tester);
    expect(find.text('轻小说'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('小说收藏失效通知更新标签，窄屏深色与横屏保持可用', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final h = _Harness();
    h.manga.total = 12345;
    h.novelRepo.total = 23456;
    await h.pump(tester, dark: true);
    await tester.tap(find.text('轻小说'));
    await settle(tester);
    expect(find.text('漫画 (12345)'), findsOneWidget);
    expect(find.text('轻小说 (23456)'), findsOneWidget);

    tester.view.physicalSize = const Size(812, 375);
    await settle(tester);
    expect(tester.takeException(), isNull);

    h.novelRepo.total = 0;
    final pending = h.novelRepo.invalidateCache();
    await settle(tester);
    await pending;
    expect(find.text('轻小说'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('缓存总数回填标签，分页与退出登录同步更新', (tester) async {
    final h = _Harness();
    h.comicRepo.cached = ComicBookshelfData(
      items: [
        BookshelfItem(
          comic: Comic(name: '缓存漫画', pathWord: 'cached', cover: ''),
        ),
      ],
      total: 64,
      cacheTime: DateTime.now(),
    );
    await h.pump(tester);
    expect(find.text('漫画 (64)'), findsOneWidget);
    expect(h.manga.calls, 0);

    h.manga.total = 65;
    tester.widget<LoadMoreFooter>(find.byType(LoadMoreFooter)).onPressed();
    await settle(tester);
    expect(find.text('漫画 (65)'), findsOneWidget);

    await tester.tap(find.text('轻小说'));
    await settle(tester);
    h.novelRepo.total = 74;
    tester.widget<LoadMoreFooter>(find.byType(LoadMoreFooter)).onPressed();
    await settle(tester);
    expect(find.text('轻小说 (74)'), findsOneWidget);

    h.user.copyToken = null;
    await settle(tester);
    expect(find.text('漫画'), findsOneWidget);
    expect(find.text('轻小说'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
