import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/routing/main_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GoRouter router;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'disclaimer_accepted': true,
      'auto_check_update': false,
      'remote_notice_enabled': false,
      'anime_feature_enabled': true,
    });
    await UserManager().init();

    StatefulShellBranch branch(String path, String label) {
      return StatefulShellBranch(
        routes: [
          GoRoute(
            path: path,
            builder: (_, _) => ColoredBox(
              color: Colors.white,
              child: Center(child: Text('$label page')),
            ),
          ),
        ],
      );
    }

    router = GoRouter(
      routes: [
        StatefulShellRoute(
          navigatorContainerBuilder: buildMainShellNavigatorContainer,
          builder: (_, _, navigationShell) =>
              MainShell(navigationShell: navigationShell),
          branches: [
            branch('/', 'comic'),
            branch('/anime', 'anime'),
            branch('/search', 'search'),
            branch('/bookshelf', 'bookshelf'),
            branch('/profile', 'profile'),
          ],
        ),
      ],
    );
  });

  tearDown(() async {
    router.dispose();
    await UserManager().setBottomNavLabelMode(BottomNavLabelMode.selectedOnly);
  });

  testWidgets('dual-slides without intermediate pages and uses capsule nav', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(GNav), findsOneWidget);
    expect(find.byType(PageView), findsNothing);
    expect(find.text('comic page'), findsOneWidget);

    // Visible tabs without login: comic, anime, search, profile (index 3).
    await tester.tap(find.byType(GButton).at(3));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    // Direct dual-page slide: no intermediate anime/search pages on stage.
    expect(router.routeInformationProvider.value.uri.path, '/profile');
    expect(find.text('comic page'), findsOneWidget);
    expect(find.text('profile page'), findsOneWidget);
    expect(find.text('anime page'), findsNothing);
    expect(find.text('search page'), findsNothing);

    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(
      tester.getCenter(find.text('profile page')).dx,
      greaterThan(0.5 * screenWidth),
    );

    await tester.pumpAndSettle();
    expect(find.text('profile page'), findsOneWidget);
    expect(find.text('comic page'), findsNothing);

    await tester.drag(find.text('profile page'), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/search');
    expect(find.text('search page'), findsOneWidget);
  });

  testWidgets('classic always-label mode uses NavigationBar', (tester) async {
    await UserManager().setBottomNavLabelMode(BottomNavLabelMode.always);

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(GNav), findsNothing);
  });
}
