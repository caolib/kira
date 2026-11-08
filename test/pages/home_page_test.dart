import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kira/models/comic.dart' hide Theme;
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/home_page.dart';
import 'package:kira/providers/repository_providers.dart';
import 'package:kira/repositories/manga_home_repository.dart';
import 'package:kira/routing/app_router.dart';
import 'package:kira/widgets/section_header.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

class _HomeRepository extends MangaHomeRepository {
  final data = CopyMangaHomeData(
    home: CopyMangaHome(
      recComics: [Comic(name: '测试作品', pathWord: 'test', cover: '')],
    ),
  );

  @override
  Future<CopyMangaHomeData?> loadBFromCache() async => data;

  @override
  Future<CopyMangaHomeData> loadB() async => data;
}

class _ControlledHomeRepository extends MangaHomeRepository {
  CopyMangaHomeData? cached;
  CopyMangaHomeData data = const CopyMangaHomeData(home: CopyMangaHome());
  Object? error;
  int calls = 0;

  @override
  Future<CopyMangaHomeData?> loadBFromCache() async => cached;

  @override
  Future<CopyMangaHomeData> loadB() async {
    calls++;
    if (error != null) throw error!;
    return data;
  }
}

void main() {
  setUp(() async {
    setupSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({
      'manga_home_source': 'copy',
      'banner_visible': false,
    });
    await UserManager().init();
  });

  tearDown(teardownSecureCredentialStoreForTest);

  Future<void> mount(
    WidgetTester tester, {
    double textScale = 1,
    MangaHomeRepository? repository,
  }) async {
    tester.view.physicalSize = const Size(375, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mangaHomeRepositoryProvider.overrideWithValue(
            repository ?? _HomeRepository(),
          ),
        ],
        child: wrapWithApp(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: true,
                textScaler: TextScaler.linear(textScale),
              ),
              child: const HomePage(),
            ),
          ),
          wrapInScaffold: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('empty copy home shows a message and can retry', (tester) async {
    final repository = _ControlledHomeRepository();
    await mount(tester, repository: repository);

    expect(find.text('暂无可显示内容'), findsOneWidget);
    expect(find.text('专题'), findsNothing);
    repository.data = _HomeRepository().data;
    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump();

    expect(find.text('测试作品'), findsOneWidget);
    expect(find.text('暂无可显示内容'), findsNothing);
    expect(repository.calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty copy cache does not hide the network failure', (
    tester,
  ) async {
    final repository = _ControlledHomeRepository()
      ..cached = const CopyMangaHomeData(home: CopyMangaHome())
      ..error = DioException(
        requestOptions: RequestOptions(path: '/home'),
        message: '连接超时',
        type: DioExceptionType.connectionTimeout,
      );
    await mount(tester, repository: repository);

    expect(find.text('连接超时'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('专题'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('copy refresh failure keeps content and retry clears the error', (
    tester,
  ) async {
    final repository = _ControlledHomeRepository()
      ..data = _HomeRepository().data;
    await mount(tester, repository: repository);
    repository.error = DioException(
      requestOptions: RequestOptions(path: '/home'),
      response: Response(
        requestOptions: RequestOptions(path: '/home'),
        statusCode: 503,
        data: {'code': 503, 'message': '服务器暂时不可用'},
      ),
      type: DioExceptionType.badResponse,
    );
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pump();

    expect(find.text('测试作品'), findsOneWidget);
    expect(find.text('刷新失败：服务器暂时不可用'), findsOneWidget);
    expect(find.byType(MaterialBanner), findsOneWidget);
    repository.error = null;
    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump();

    expect(find.text('测试作品'), findsOneWidget);
    expect(find.byType(MaterialBanner), findsNothing);
    expect(repository.calls, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cached copy content also reports an empty response', (
    tester,
  ) async {
    final repository = _ControlledHomeRepository()
      ..cached = _HomeRepository().data
      ..error = const EmptyCopyMangaHomeException();
    await mount(tester, repository: repository);

    expect(find.text('测试作品'), findsOneWidget);
    expect(find.text('刷新失败：暂无可显示内容'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'copy section is unframed and collapses without changing titles',
    (tester) async {
      await mount(tester);
      expect(find.byType(SectionHeader), findsOneWidget);
      final label = tester.widget<Text>(find.text('测试作品'));
      expect(label.maxLines, 1);
      final section = find
          .ancestor(
            of: find.byType(SectionHeader),
            matching: find.byType(Material),
          )
          .first;
      expect(tester.widget<Material>(section).color, Colors.transparent);

      await tester.tap(find.text('推荐'));
      await tester.pump();
      expect(UserManager().isCopyHomeSectionCollapsed('copy-rec'), isTrue);
      expect(find.text('测试作品').hitTestable(), findsNothing);

      await tester.tap(find.text('推荐'));
      await tester.pump();
      expect(UserManager().isCopyHomeSectionCollapsed('copy-rec'), isFalse);
      expect(find.text('测试作品').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('copy section header fits a narrow screen with large text', (
    tester,
  ) async {
    await mount(tester, textScale: 2);
    expect(find.text('推荐'), findsOneWidget);
    await tester.tap(find.text('推荐'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('more opens the list without toggling the section', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const HomePage()),
        GoRoute(
          path: '/copy/:kind',
          name: AppRoutes.copyMangaList,
          builder: (_, state) =>
              Scaffold(body: Text('list:${state.pathParameters['kind']}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mangaHomeRepositoryProvider.overrideWithValue(_HomeRepository()),
        ],
        child: wrapWithApp(
          Router.withConfig(config: router),
          wrapInScaffold: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();
    expect(find.text('list:recommendations'), findsOneWidget);
    expect(UserManager().isCopyHomeSectionCollapsed('copy-rec'), isFalse);
    expect(tester.takeException(), isNull);
  });
}
