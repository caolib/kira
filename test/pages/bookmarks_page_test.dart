import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/pages/bookmarks_page.dart';
import 'package:kira/routing/app_router.dart';
import 'package:kira/utils/bookmark_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    BookmarkStore().debugReset();
    await BookmarkStore().toggle(
      pathWord: 'comic-a',
      comicName: '漫画 A',
      group: 'default',
      chapterUuid: 'chapter-1',
      chapterName: '第 1 话',
      page: 7,
    );
  });

  tearDown(() => BookmarkStore().debugReset());

  testWidgets('single bookmark still renders as a list and card opens detail', (
    tester,
  ) async {
    final router = _createRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(_buildTestApp(router));
    await tester.pumpAndSettle();

    expect(find.text('1 条书签'), findsOneWidget);
    expect(find.text('第 1 话'), findsOneWidget);
    expect(find.byType(Dismissible), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('bookmark_comic_comic-a')),
        matching: find.byType(IconButton),
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('bookmark_comic_comic-a')));
    await tester.pumpAndSettle();

    expect(find.text('detail:comic-a'), findsOneWidget);
  });

  testWidgets('bookmark list item opens its saved reader position', (
    tester,
  ) async {
    final router = _createRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(_buildTestApp(router));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('bookmark_open_chapter-1:7')));
    await tester.pumpAndSettle();

    expect(find.text('reader:comic-a:chapter-1:7'), findsOneWidget);
  });

  testWidgets('swiping comic header removes all bookmarks for that comic', (
    tester,
  ) async {
    final router = _createRouter();
    addTearDown(router.dispose);

    await BookmarkStore().toggle(
      pathWord: 'comic-a',
      comicName: '漫画 A',
      group: 'default',
      chapterUuid: 'chapter-2',
      chapterName: '第 2 话',
      page: 3,
    );
    await tester.pumpWidget(_buildTestApp(router));
    await tester.pumpAndSettle();

    expect(BookmarkStore().bookmarks, hasLength(2));
    await tester.drag(
      find.byKey(const ValueKey('bookmark_group_comic-a')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();

    expect(BookmarkStore().bookmarks, isEmpty);
    expect(find.text('还没有书签'), findsOneWidget);
  });
}

Widget _buildTestApp(GoRouter router) {
  return MaterialApp.router(
    routerConfig: router,
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
  );
}

GoRouter _createRouter() {
  return GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const BookmarksPage()),
      GoRoute(
        path: '/comic/:pathWord',
        name: AppRoutes.comicDetail,
        builder: (_, state) =>
            Scaffold(body: Text('detail:${state.pathParameters['pathWord']}')),
      ),
      GoRoute(
        path: '/reader/:pathWord/:chapterUuid',
        name: AppRoutes.reader,
        builder: (_, state) {
          final extra = state.extra as ReaderExtra;
          return Scaffold(
            body: Text(
              'reader:${state.pathParameters['pathWord']}:'
              '${state.pathParameters['chapterUuid']}:${extra.initialPage}',
            ),
          );
        },
      ),
    ],
  );
}
