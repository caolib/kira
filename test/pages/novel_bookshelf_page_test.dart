import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kira/api/novel/novel_api.dart';
import 'package:kira/models/api_ordering.dart';
import 'package:kira/models/novel.dart';
import 'package:kira/models/novel_reading_progress.dart';
import 'package:kira/pages/novel_bookshelf_page.dart';
import 'package:kira/providers/app_providers.dart';
import 'package:kira/providers/novel_providers.dart';
import 'package:kira/repositories/novel_bookshelf_repository.dart';
import 'package:kira/routing/app_router.dart';
import 'package:kira/utils/app_storage.dart';
import 'package:kira/utils/novel_reading_store.dart';
import 'package:kira/widgets/app_sheet.dart';
import 'package:kira/widgets/comic_card_skeleton.dart';
import 'package:kira/widgets/filter_chip_row.dart';
import 'package:kira/widgets/load_more_footer.dart';
import 'package:kira/widgets/novel_widgets.dart';
import 'package:kira/widgets/ordering_tile.dart';
import 'package:kira/widgets/update_badge.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../novel_api_test.dart' show NovelTestUser;
import '../test_helpers.dart';

NovelShelfEntry _entry(String id, {bool updated = false}) => NovelShelfEntry(
  uuid: id.hashCode,
  book: NovelBook(uuid: id, pathWord: id, name: id, lastChapterId: 'new'),
  lastBrowseId: updated ? 'old' : 'new',
);

NovelPage<NovelShelfEntry> _page(
  List<NovelShelfEntry> list, {
  int? total,
  int offset = 0,
}) => NovelPage(
  list: list,
  total: total ?? list.length,
  offset: offset,
  limit: 18,
);

class _User extends NovelTestUser {
  @override
  bool get isCopyLoggedIn => copyToken?.isNotEmpty == true;

  @override
  bool get isLoggedIn => token?.isNotEmpty == true || isCopyLoggedIn;
}

class _Api implements NovelApi {
  _Api(this.user);
  final _User user;
  final calls = <(String, String, int)>[];
  final collections = <(String, bool)>[];
  Future<NovelPage<NovelShelfEntry>> Function(String, String, int)? respond;
  Future<void> Function()? mutate;

  @override
  String get cacheScope => '${user.copyApiHost}-${user.copyToken ?? 'guest'}';

  @override
  Future<NovelPage<NovelShelfEntry>> getBookshelf({
    int limit = 18,
    int offset = 0,
    int freeType = 1,
    String ordering = ApiOrdering.datetimeModifier,
  }) {
    calls.add((cacheScope, ordering, offset));
    return respond?.call(cacheScope, ordering, offset) ??
        Future.value(_page([_entry('书籍')]));
  }

  @override
  Future<void> setCollected({
    required String bookUuid,
    required bool collected,
  }) async {
    collections.add((bookUuid, collected));
    await mutate?.call();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('$invocation');
}

class _Harness {
  _Harness();
  final user = _User()..copyToken = 'account-a';
  late final api = _Api(user);
  late final repo = NovelBookshelfRepository(api: api);
  final active = ValueNotifier(false);
  late GoRouter router;
  String? loginCopyOnly;

  Future<void> pump(
    WidgetTester tester, {
    double textScale = 1,
    bool dark = false,
  }) async {
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => ValueListenableBuilder(
            valueListenable: active,
            builder: (_, value, _) => NovelBookshelfPage(active: value),
          ),
        ),
        GoRoute(
          path: '/detail/:pathWord',
          name: AppRoutes.novelDetail,
          builder: (_, _) => const Scaffold(body: Text('详情目标')),
        ),
        GoRoute(
          path: '/login',
          name: AppRoutes.login,
          builder: (_, state) {
            loginCopyOnly = state.uri.queryParameters['copyOnly'];
            return const Scaffold(body: Text('COPY 登录目标'));
          },
        ),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      repo.dispose();
      user.dispose();
      active.dispose();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userManagerProvider.overrideWithValue(user),
          novelApiProvider.overrideWithValue(api),
          novelShelfRepoProvider.overrideWithValue(repo),
        ],
        child: wrapWithApp(
          Builder(
            builder: (context) => Theme(
              data: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light,
              ),
              child: MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: Router.withConfig(config: router),
              ),
            ),
          ),
          wrapInScaffold: false,
        ),
      ),
    );
    await tester.pump();
  }
}

Future<void> _pumpFrames(WidgetTester tester) async {
  // AppStorage's cached prefs future belongs to setUp's real async zone.
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<T> _complete<T>(WidgetTester tester, Future<T> pending) async {
  await _pumpFrames(tester);
  return pending;
}

Future<void> _settle(WidgetTester tester) async {
  await _pumpFrames(tester);
  await tester.pumpAndSettle();
}

Future<void> _sort(WidgetTester tester, String label) async {
  await tester.tap(find.byType(ActionChip));
  // Loading skeletons may still be animating while changing ordering.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  expect(find.byType(AppSheet), findsOneWidget);
  expect(find.byType(OrderingTile), findsNWidgets(3));
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _more(WidgetTester tester) async {
  tester.widget<LoadMoreFooter>(find.byType(LoadMoreFooter)).onPressed();
  await tester.pump();
}

Future<void> _refresh(WidgetTester tester) =>
    tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh();

Future<void> _refreshAndSettle(WidgetTester tester) async {
  final pending = _refresh(tester);
  await _settle(tester);
  await pending;
}

Future<void> _readVolume(
  WidgetTester tester,
  String pathWord,
  String volumeId,
) async {
  await tester.runAsync(
    () => NovelReadingStore().saveProgress(
      NovelReadingProgress(
        pathWord: pathWord,
        name: pathWord,
        cover: '',
        volumeId: volumeId,
        volumeName: volumeId,
        chapterName: '',
        updatedAt: DateTime.now(),
      ),
    ),
  );
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => SharedPreferences.setMockInitialValues({}));
  setUp(() async {
    setupSecureCredentialStoreForTest();
    await (await AppStorage.sharedPreferences()).clear();
  });
  tearDown(teardownSecureCredentialStoreForTest);

  testWidgets('本地已读最新卷后回看，缓存书架与筛选都不误标', (tester) async {
    await _readVolume(tester, '读过最新', 'new');
    await _readVolume(tester, '读过最新', 'old');
    final h = _Harness();
    h.api.respond = (_, _, _) async => _page([
      _entry('读过最新', updated: true),
      _entry('未读最新', updated: true),
      _entry('远端已读'),
    ]);
    await _complete(tester, h.repo.load());
    await h.pump(tester);
    await _settle(tester);
    expect(find.byType(UpdateBadge), findsOneWidget);
    expect(h.api.calls.length, 1);

    await tester.tap(find.text('有更新'));
    await _settle(tester);
    expect(find.text('未读最新'), findsOneWidget);
    expect(find.text('读过最新'), findsNothing);
    expect(find.text('远端已读'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('本地进度变更和清除直接刷新徽标，不额外请求书架', (tester) async {
    final h = _Harness();
    h.api.respond = (_, _, _) async => _page([_entry('小说', updated: true)]);
    await h.pump(tester);
    await _settle(tester);
    expect(find.byType(UpdateBadge), findsOneWidget);
    await _readVolume(tester, '小说', 'old');
    expect(find.byType(UpdateBadge), findsOneWidget);
    await _readVolume(tester, '小说', 'new');
    expect(find.byType(UpdateBadge), findsNothing);
    await _readVolume(tester, '小说', 'old');
    expect(find.byType(UpdateBadge), findsNothing);
    await tester.tap(find.text('有更新'));
    await _settle(tester);
    expect(find.text('没有轻小说更新'), findsOneWidget);

    await tester.runAsync(() => NovelReadingStore().removeProgress('小说'));
    await _settle(tester);
    expect(find.byType(UpdateBadge), findsOneWidget);
    expect(h.api.calls.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('详情返回仍保留旧卷续读断点，本地已读在账号间共用', (tester) async {
    final h = _Harness();
    h.api.respond = (_, _, _) async => _page([_entry('小说', updated: true)]);
    await h.pump(tester);
    await _settle(tester);
    await tester.tap(find.text('小说'));
    await _settle(tester);
    await _readVolume(tester, '小说', 'new');
    await _readVolume(tester, '小说', 'old');
    h.router.pop();
    await _settle(tester);
    expect(find.byType(UpdateBadge), findsNothing);
    final record = await tester.runAsync(
      () => NovelReadingStore().readProgress('小说'),
    );
    expect(record?.volumeId, 'old');
    expect(
      (await _complete(tester, h.repo.load())).items.single.lastBrowseId,
      'old',
    );

    h.user.copyToken = 'account-b';
    await _settle(tester);
    expect(find.text('小说'), findsOneWidget);
    expect(find.byType(UpdateBadge), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('分页使用本地已读，新最新卷仍由远端标记更新', (tester) async {
    await _readVolume(tester, '第二页', 'new');
    final h = _Harness();
    h.api.respond = (_, _, offset) async => _page(
      [_entry(offset == 0 ? '第一页' : '第二页', updated: true)],
      total: 2,
      offset: offset,
    );
    await h.pump(tester);
    await _settle(tester);
    await _more(tester);
    await _settle(tester);
    expect(find.byType(UpdateBadge), findsOneWidget);
    await tester.tap(find.text('有更新'));
    await _settle(tester);
    expect(find.text('第二页'), findsNothing);

    h.api.respond = (_, _, _) async => _page([
      const NovelShelfEntry(
        uuid: 1,
        book: NovelBook(
          uuid: '第二页',
          pathWord: '第二页',
          name: '第二页',
          lastChapterId: 'newer',
        ),
        lastBrowseId: 'old',
      ),
    ]);
    await _refreshAndSettle(tester);
    expect(find.text('第二页'), findsOneWidget);
    expect(find.byType(UpdateBadge), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('排序与漫画一致，补齐浏览时间并复用独立缓存', (tester) async {
    final h = _Harness();
    h.api.respond = (_, ordering, _) async => _page([_entry(ordering)]);
    await h.pump(tester);
    await tester.runAsync(() async => Future<void>.delayed(Duration.zero));
    await _settle(tester);
    expect(h.api.calls.single.$2, ApiOrdering.datetimeModifier);
    await _sort(tester, '浏览时间');
    await _settle(tester);
    expect(find.text(ApiOrdering.datetimeBrowse), findsOneWidget);
    expect(h.api.calls.last.$2, ApiOrdering.datetimeBrowse);
    await _sort(tester, '作品更新时间');
    await _settle(tester);
    expect(h.api.calls.last.$2, ApiOrdering.datetimeUpdated);
    await _sort(tester, '收藏时间');
    await _settle(tester);
    expect(h.api.calls.length, 3);
    expect(find.text(ApiOrdering.datetimeModifier), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('账号和 host 切换立即清空旧卡片，跨账号新鲜缓存不会一直 loading', (tester) async {
    final h = _Harness();
    h.api.respond = (scope, _, _) async => _page([_entry(scope)]);
    h.user.copyToken = 'account-b';
    await _complete(tester, h.repo.load());
    h.user.copyToken = 'account-a';
    await h.pump(tester);
    await _settle(tester);
    expect(find.text('copy.invalid-account-a'), findsOneWidget);
    h.user.copyToken = 'account-b';
    await _settle(tester);
    expect(find.text('copy.invalid-account-a'), findsNothing);
    expect(find.text('copy.invalid-account-b'), findsOneWidget);
    expect(find.byType(ComicCardSkeleton), findsNothing);
    expect(h.api.calls.length, 2);

    final pending = Completer<NovelPage<NovelShelfEntry>>();
    h.api.respond = (_, _, _) => pending.future;
    h.user.copyApiHost = 'new.invalid';
    await tester.pump();
    expect(find.byType(NovelBookCard), findsNothing);
    expect(find.byType(ComicCardSkeleton), findsWidgets);
    pending.complete(_page([_entry('新线路')]));
    await _settle(tester);
    expect(find.text('新线路'), findsOneWidget);
    h.user.token = 'HOT-stays-logged-in';
    h.user.copyToken = null;
    await _settle(tester);
    expect(find.byType(NovelBookCard), findsNothing);
    expect(find.text('登录拷贝账户'), findsOneWidget);
    expect(h.user.isLoggedIn, isTrue);
  });

  testWidgets('旧首屏迟到不能覆盖新身份缓存', (tester) async {
    final h = _Harness();
    h.user.copyToken = 'account-b';
    h.api.respond = (_, _, _) async => _page([_entry('乙账号')]);
    await _complete(tester, h.repo.load());
    h.user.copyToken = 'account-a';
    final old = Completer<NovelPage<NovelShelfEntry>>();
    h.api.respond = (_, _, _) => old.future;
    await h.pump(tester);
    h.user.copyToken = 'account-b';
    await _settle(tester);
    expect(find.text('乙账号'), findsOneWidget);
    old.complete(_page([_entry('甲账号旧首屏')]));
    await _settle(tester);
    expect(find.text('甲账号旧首屏'), findsNothing);
    expect(find.text('乙账号'), findsOneWidget);
  });

  testWidgets('旧第二页不得追加到新排序，重复条目不改变服务端 offset', (tester) async {
    final h = _Harness();
    final old = Completer<NovelPage<NovelShelfEntry>>();
    h.api.respond = (_, ordering, offset) async {
      if (ordering == ApiOrdering.datetimeModifier && offset > 0) {
        return old.future;
      }
      if (ordering == ApiOrdering.datetimeModifier) {
        return _page([_entry('旧首屏')], total: 3);
      }
      return _page([_entry('新排序'), _entry('新排序')], total: 3);
    };
    await h.pump(tester);
    await _settle(tester);
    await _more(tester);
    await _sort(tester, '浏览时间');
    await _settle(tester);
    old.complete(_page([_entry('旧第二页')], offset: 1, total: 3));
    await _settle(tester);
    expect(find.text('新排序'), findsOneWidget);
    expect(find.text('旧第二页'), findsNothing);
    expect(
      tester.widget<LoadMoreFooter>(find.byType(LoadMoreFooter)).label,
      '加载更多（2/3）',
    );
  });

  testWidgets('刷新后分页不复用旧代次的在途请求，并发刷新只发一次', (tester) async {
    final h = _Harness();
    final old = Completer<NovelPage<NovelShelfEntry>>();
    var pageCalls = 0;
    h.api.respond = (_, _, offset) async {
      if (offset == 0) return _page([_entry('首屏')], total: 3);
      pageCalls++;
      return pageCalls == 1
          ? old.future
          : _page([_entry('新第二页'), _entry('首屏')], offset: 1, total: 3);
    };
    await h.pump(tester);
    await _settle(tester);
    await _more(tester);
    final refreshes = Future.wait([_refresh(tester), _refresh(tester)]);
    await _settle(tester);
    await refreshes;
    expect(h.api.calls.where((call) => call.$3 == 0).length, 2);
    await _more(tester);
    await _settle(tester);
    expect(pageCalls, 2);
    expect(find.text('新第二页'), findsOneWidget);
    expect(find.text('首屏'), findsOneWidget);
    old.complete(_page([_entry('旧第二页')], offset: 1, total: 3));
    await _settle(tester);
    expect(find.text('旧第二页'), findsNothing);
    expect(find.byType(LoadMoreFooter), findsNothing);
  });

  testWidgets('分页失败可点重试；首屏刷新失败保留内容并显示内联重试', (tester) async {
    final h = _Harness();
    var failPage = true;
    var failRefresh = false;
    h.api.respond = (_, _, offset) async {
      if (offset > 0) {
        if (failPage) throw const NovelApiException('离线');
        return _page([_entry('第二页')], offset: 1, total: 2);
      }
      if (failRefresh) throw const NovelApiException('离线');
      return _page([_entry('首屏')], total: 2);
    };
    await h.pump(tester);
    await _settle(tester);
    await _more(tester);
    await _settle(tester);
    expect(
      tester.widget<LoadMoreFooter>(find.byType(LoadMoreFooter)).label,
      '重试',
    );
    failPage = false;
    await tester.tap(find.text('重试'));
    await _settle(tester);
    expect(find.text('第二页'), findsOneWidget);
    failRefresh = true;
    await _refreshAndSettle(tester);
    await _settle(tester);
    expect(find.text('首屏'), findsOneWidget);
    expect(find.byType(InlineRetryNotice), findsOneWidget);
    failRefresh = false;
    tester.widget<InlineRetryNotice>(find.byType(InlineRetryNotice)).onRetry();
    await _settle(tester);
    expect(find.byType(InlineRetryNotice), findsNothing);
  });

  testWidgets('空书架按钮及下拉均能刷新，外部收藏通知更新常驻页', (tester) async {
    final h = _Harness();
    var collected = false;
    h.api.respond = (_, _, _) async => _page(collected ? [_entry('已收藏')] : []);
    h.api.mutate = () async => collected = !collected;
    await h.pump(tester);
    await _settle(tester);
    expect(find.text('书架还是空的，去发现喜欢的小说吧'), findsOneWidget);
    await tester.tap(find.text('刷新'));
    await _settle(tester);
    expect(h.api.calls.length, 2);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 350));
    await _settle(tester);
    expect(h.api.calls.length, 3);
    await _complete(
      tester,
      h.repo.setCollected(bookUuid: '已收藏', collected: true),
    );
    await _settle(tester);
    expect(find.text('已收藏'), findsOneWidget);
    await _complete(
      tester,
      h.repo.setCollected(bookUuid: '已收藏', collected: false),
    );
    await _settle(tester);
    expect(find.byType(NovelBookCard), findsNothing);
    expect((await _complete(tester, h.repo.load())).items, isEmpty);
  });

  testWidgets('取消收藏使用共享弹层，取消后重建页面不复活', (tester) async {
    final h = _Harness();
    var removed = false;
    h.api.respond = (_, _, _) async => _page(removed ? [] : [_entry('待移除')]);
    h.api.mutate = () async => removed = true;
    await h.pump(tester);
    await _settle(tester);
    await tester.longPress(find.text('待移除'));
    await _settle(tester);
    expect(find.byType(AppSheet), findsOneWidget);
    await tester.tap(find.text('取消收藏'));
    await _settle(tester);
    expect(h.api.collections, [('待移除', false)]);
    expect(find.byType(NovelBookCard), findsNothing);
    final rebuilt = NovelBookshelfRepository(api: h.api);
    addTearDown(rebuilt.dispose);
    expect((await _complete(tester, rebuilt.load())).items, isEmpty);
  });

  for (final phase in ['首屏', '刷新', '分页', '取消收藏']) {
    testWidgets('$phase 401 清空列表并只进入 COPY 登录，HOT 不退出', (tester) async {
      final h = _Harness();
      h.user.token = 'HOT-account';
      var expired = phase == '首屏';
      final error = phase == '分页'
          ? DioException(
              requestOptions: RequestOptions(),
              response: Response(
                requestOptions: RequestOptions(),
                statusCode: 401,
              ),
            )
          : const NovelApiException('登录过期', code: 401);
      h.api.respond = (_, _, _) async {
        if (expired) throw error;
        return _page([_entry('旧书')], total: 2);
      };
      h.api.mutate = () async => throw error;
      await h.pump(tester);
      await _settle(tester);
      if (phase != '首屏') {
        expired = true;
        if (phase == '刷新') {
          unawaited(_refresh(tester));
        } else if (phase == '分页') {
          await _more(tester);
        } else {
          await tester.longPress(find.text('旧书'));
          await _settle(tester);
          await tester.tap(find.text('取消收藏'));
        }
        await _settle(tester);
      }
      expect(find.text('登录已过期'), findsOneWidget);
      expect(find.byType(NovelBookCard), findsNothing);
      expect(await _complete(tester, h.repo.loadFromCache()), isNull);
      expect(h.user.token, 'HOT-account');
      await tester.tap(find.text('去登录'));
      await _settle(tester);
      expect(h.loginCopyOnly, 'true');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('一个账号过期弹窗打开时，新账号再次 401 仍进入不可操作状态', (tester) async {
    final h = _Harness();
    h.api.respond = (_, _, _) async =>
        throw const NovelApiException('过期', code: 401);
    await h.pump(tester);
    await _settle(tester);
    h.user.copyToken = 'account-b';
    await _settle(tester);
    await tester.tap(find.text('稍后再说'));
    await _settle(tester);
    expect(find.text('登录拷贝账户'), findsOneWidget);
    expect(find.text('书架还是空的，去发现喜欢的小说吧'), findsNothing);
  });

  testWidgets('激活与回前台遵循 TTL；刷新反馈保留原列表', (tester) async {
    final h = _Harness();
    await h.pump(tester);
    await _settle(tester);
    h.active.value = true;
    await _settle(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle(tester);
    expect(h.api.calls.length, 1);
    final pending = Completer<NovelPage<NovelShelfEntry>>();
    h.api.respond = (_, _, _) => pending.future;
    final refresh = _refresh(tester);
    await tester.pump();
    expect(find.text('书籍'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    pending.complete(_page([_entry('刷新结果')]));
    await _settle(tester);
    await refresh;
    expect(find.text('刷新结果'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('更新徽标、无更新空态、窄屏深色及大字体不溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final h = _Harness();
    h.api.respond = (_, _, _) async => _page([_entry('已更新', updated: true)]);
    await h.pump(tester, textScale: 1.5, dark: true);
    await _settle(tester);
    expect(find.byType(UpdateBadge), findsOneWidget);
    await tester.tap(find.text('有更新'));
    await _settle(tester);
    h.api.respond = (_, _, _) async => _page([_entry('无更新')]);
    await _refreshAndSettle(tester);
    await _settle(tester);
    expect(find.text('没有轻小说更新'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
