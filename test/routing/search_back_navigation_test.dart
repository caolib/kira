import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kira/api/novel/novel_api.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/models/novel.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/novel_home_page.dart';
import 'package:kira/providers/novel_providers.dart';
import 'package:kira/utils/app_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/search_page_test_support.dart';
import '../test_helpers.dart';

const _browseBook = NovelBook(pathWord: 'browse', name: '浏览小说');
const _searchBook = NovelBook(pathWord: 'hit', name: '搜索小说');

NovelPage<NovelBook> _novelPage(List<NovelBook> books) =>
    NovelPage(list: books, total: books.length, limit: 18, offset: 0);

class _NovelApi extends Fake implements NovelApi {
  Completer<NovelPage<NovelBook>>? pendingSearch;

  @override
  Future<List<NovelTag>> getThemes() async => const [];

  @override
  Future<NovelPage<NovelBook>> getBooks({
    String theme = '',
    String author = '',
    String ordering = '-popular',
    int limit = 18,
    int offset = 0,
  }) async => _novelPage([_browseBook]);

  @override
  Future<NovelPage<NovelBook>> searchBooks({
    required String keyword,
    int limit = 18,
    int offset = 0,
  }) => pendingSearch?.future ?? Future.value(_novelPage([_searchBook]));
}

Future<GoRouter> _pumpShell(
  WidgetTester tester,
  SearchTestRig rig,
  _NovelApi novelApi, {
  required bool novel,
}) async {
  tester.view.physicalSize = const Size(480, 960);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = searchShellRouter(
    rig,
    initialLocation: novel ? '/novels' : '/search',
    novelPage: const NovelHomePage(),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpSearchFrames(tester);
    router.dispose();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [novelApiProvider.overrideWithValue(novelApi)],
      child: MaterialApp.router(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  // 推完主导航的隐藏分支预热，避免已有延迟任务留在测试结束时。
  await pumpSearchFrames(tester, count: 50);
  return router;
}

String _searchText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await pumpSearchFrames(tester, count: 2);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var exitCalls = 0;

  setUpAll(installSearchImageCache);
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'disclaimer_accepted': true,
      'auto_check_update': false,
      'remote_notice_enabled': false,
      'app_logging_enabled': false,
      'search_tab_index': 0,
    });
    setupSecureCredentialStoreForTest();
    await UserManager().init();
    await AppStorage.cache.remove('novel_themes_v1');
    await AppStorage.cache.remove('novel_popular_list_v1');
    exitCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemNavigator.pop') exitCalls++;
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    teardownSecureCredentialStoreForTest();
  });

  for (final novel in [false, true]) {
    final pageName = novel ? '轻小说' : '漫画搜索';
    for (final confirmExit in [false, true]) {
      for (final submitted in [false, true]) {
        testWidgets(
          '$pageName ${submitted ? '搜索后' : '仅输入'}返回先清空，退出确认=$confirmExit',
          (tester) async {
            await UserManager().theme.setBackExitConfirm(confirmExit);
            final rig = SearchTestRig();
            await _pumpShell(tester, rig, _NovelApi(), novel: novel);
            await tester.enterText(find.byType(TextField), '关键词');
            if (submitted) {
              await tester.testTextInput.receiveAction(
                novel ? TextInputAction.done : TextInputAction.search,
              );
              if (!novel) rig.manga.searches.single.succeed(['搜索漫画']);
            }
            await pumpSearchFrames(tester);
            final l10n = AppLocalizations.of(
              tester.element(find.byType(SearchBar)),
            )!;

            await _back(tester);
            expect(_searchText(tester), isEmpty);
            expect(find.text(novel ? '浏览小说' : '测试热搜'), findsOneWidget);
            expect(find.text(l10n.backAgainToExitToast), findsNothing);
            expect(exitCalls, 0);
            expect(tester.testTextInput.isVisible, isFalse);

            await _back(tester);
            if (confirmExit) {
              expect(find.text(l10n.backAgainToExitToast), findsOneWidget);
              expect(exitCalls, 0);
              await _back(tester);
            }
            expect(exitCalls, 1);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets('$pageName 返回清空后在途请求不能恢复搜索结果', (tester) async {
      final rig = SearchTestRig();
      final novelApi = _NovelApi()
        ..pendingSearch = Completer<NovelPage<NovelBook>>();
      await _pumpShell(tester, rig, novelApi, novel: novel);
      await tester.enterText(find.byType(TextField), '在途关键词');
      await tester.testTextInput.receiveAction(
        novel ? TextInputAction.done : TextInputAction.search,
      );
      await pumpSearchFrames(tester);
      await _back(tester);
      if (novel) {
        novelApi.pendingSearch!.complete(_novelPage([_searchBook]));
      } else {
        rig.manga.searches.single.succeed(['过期漫画']);
      }
      await pumpSearchFrames(tester);
      expect(_searchText(tester), isEmpty);
      expect(find.text(novel ? '搜索小说' : '过期漫画'), findsNothing);
      expect(find.text(novel ? '浏览小说' : '测试热搜'), findsOneWidget);
      expect(exitCalls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$pageName 打开详情后返回只关闭详情，保留搜索', (tester) async {
      final rig = SearchTestRig();
      final router = await _pumpShell(tester, rig, _NovelApi(), novel: novel);
      await tester.enterText(find.byType(TextField), '保留关键词');
      await pumpSearchFrames(tester);
      unawaited(router.push<void>('/test-detail'));
      await pumpSearchFrames(tester);
      expect(find.text('测试详情页'), findsOneWidget);
      await _back(tester);
      await pumpSearchFrames(tester);
      expect(find.text('测试详情页'), findsNothing);
      expect(_searchText(tester), '保留关键词');
      expect(exitCalls, 0);
      await _back(tester);
      expect(_searchText(tester), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$pageName 切走后隐藏分支不消费返回或丢失关键词', (tester) async {
      await UserManager().theme.setBackExitConfirm(true);
      final rig = SearchTestRig();
      final router = await _pumpShell(tester, rig, _NovelApi(), novel: novel);
      await tester.enterText(find.byType(TextField), '隐藏关键词');
      await pumpSearchFrames(tester);
      router.go('/bookshelf');
      await pumpSearchFrames(tester);
      final l10n = AppLocalizations.of(tester.element(find.text('主导航-书架')))!;
      await _back(tester);
      expect(find.text(l10n.backAgainToExitToast), findsOneWidget);
      expect(exitCalls, 0);
      router.go(novel ? '/novels' : '/search');
      await pumpSearchFrames(tester);
      expect(_searchText(tester), '隐藏关键词');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('漫画发现标签不清空隐藏搜索框，保留退出确认', (tester) async {
    await UserManager().theme.setBackExitConfirm(true);
    final rig = SearchTestRig();
    await _pumpShell(tester, rig, _NovelApi(), novel: false);
    await tester.enterText(find.byType(TextField), '隐藏关键词');
    await tapSearchTab(tester, '发现');
    rig.manga.listings.single.succeed([]);
    await pumpSearchFrames(tester);
    final l10n = AppLocalizations.of(tester.element(find.byType(TabBar)))!;
    await _back(tester);
    expect(find.text(l10n.backAgainToExitToast), findsOneWidget);
    expect(exitCalls, 0);
    await tapSearchTab(tester, '搜索');
    expect(_searchText(tester), '隐藏关键词');
    expect(tester.takeException(), isNull);
  });
}
