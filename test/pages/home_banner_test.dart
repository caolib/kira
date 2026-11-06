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
import 'package:kira/widgets/comic_hero_tags.dart';
import 'package:kira/widgets/crossfade_carousel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';
import 'search_page_test_support.dart' show installSearchImageCache;

class _Repository extends MangaHomeRepository {
  final banners = [
    for (var i = 0; i < 2; i++)
      MangaBanner(
        cover: 'https://images.invalid/banner-$i.png',
        brief: '简介$i',
        outUuid: '$i',
        comic: Comic(name: '轮播作品$i', pathWord: 'banner-$i', cover: ''),
      ),
  ];

  @override
  Future<MangaHomeData?> loadAFromCache() => loadA();

  @override
  Future<MangaHomeData> loadA() async => MangaHomeData(
    home: MangaHome(banners: banners),
    ranking: const [],
  );

  @override
  Future<CopyMangaHomeData?> loadBFromCache() => loadB();

  @override
  Future<CopyMangaHomeData> loadB() async =>
      CopyMangaHomeData(home: CopyMangaHome(banners: banners));
}

void main() {
  setUpAll(installSearchImageCache);
  setUp(setupSecureCredentialStoreForTest);
  tearDown(teardownSecureCredentialStoreForTest);

  for (final source in ['hot', 'copy']) {
    testWidgets('$source 首页轮播保留布局、标题与点击跳转，图片单独微缩放', (tester) async {
      SharedPreferences.setMockInitialValues({
        'manga_home_source': source,
        'banner_visible': true,
      });
      await UserManager().init();
      ComicDetailExtra? extra;
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const HomePage()),
          GoRoute(
            path: '/comic/:pathWord',
            name: AppRoutes.comicDetail,
            builder: (_, state) {
              if (state.extra case final ComicDetailExtra value) extra = value;
              return Scaffold(
                body: Text('详情:${state.pathParameters['pathWord']}'),
              );
            },
          ),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        router.dispose();
      });
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mangaHomeRepositoryProvider.overrideWithValue(_Repository()),
          ],
          child: wrapWithApp(
            Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(source == 'copy' ? 2 : 1),
                ),
                child: Theme(
                  data: ThemeData(
                    brightness: source == 'copy'
                        ? Brightness.dark
                        : Brightness.light,
                  ),
                  child: Router.withConfig(config: router),
                ),
              ),
            ),
            wrapInScaffold: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final carousel = find.byType(CrossfadeCarousel);
      expect(carousel, findsOneWidget);
      expect(find.text('轮播作品0'), findsOneWidget);
      expect(find.text('简介0'), findsOneWidget);
      final bounds = tester.getRect(carousel);
      expect(bounds.width, 343);
      expect(bounds.height, closeTo(343 / (16 / 9) + 8, 0.01));

      tester.view.physicalSize = const Size(812, 375);
      await tester.pumpAndSettle();
      final dragBounds = tester.getRect(carousel);
      expect(dragBounds.width, greaterThan(0));
      expect(dragBounds.width, lessThanOrEqualTo(780));
      expect(
        dragBounds.height,
        closeTo((dragBounds.width / (16 / 9)).clamp(140.0, 240.0) + 8, 0.01),
      );
      expect(tester.takeException(), isNull);

      final gesture = await tester.startGesture(tester.getCenter(carousel));
      await gesture.moveBy(const Offset(-30, 0));
      await gesture.moveBy(const Offset(-160, 0));
      await tester.pump();
      expect(tester.getRect(carousel), dragBounds);
      final transforms = find.descendant(
        of: carousel,
        matching: find.byType(Transform),
      );
      expect(
        find.ancestor(of: find.text('轮播作品1'), matching: transforms),
        findsNothing,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('轮播作品1'), findsOneWidget);
      expect(find.text('简介1'), findsOneWidget);
      await tester.tap(find.text('轮播作品1'));
      await tester.pumpAndSettle();
      expect(find.text('详情:banner-1'), findsOneWidget);
      expect(extra?.initialComic?.pathWord, 'banner-1');
      expect(
        extra?.heroTagBase,
        ComicHeroTags.base(
          scope: source == 'copy' ? 'copy-banner' : 'home-banner',
          pathWord: 'banner-1',
          index: 0,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
