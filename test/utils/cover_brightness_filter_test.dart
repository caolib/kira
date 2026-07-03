import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/utils/cover_brightness_filter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('applies color filter in dark mode when brightness is reduced', (
    tester,
  ) async {
    await UserManager().init();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        darkTheme: ThemeData(brightness: Brightness.dark),
        themeMode: ThemeMode.dark,
        home: const Scaffold(
          body: CoverBrightnessFilter(child: SizedBox(width: 10, height: 10)),
        ),
      ),
    );

    expect(find.byType(ColorFiltered), findsOneWidget);
  });

  testWidgets('skips color filter in light mode', (tester) async {
    await UserManager().init();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        darkTheme: ThemeData(brightness: Brightness.dark),
        themeMode: ThemeMode.light,
        home: const Scaffold(
          body: CoverBrightnessFilter(child: SizedBox(width: 10, height: 10)),
        ),
      ),
    );

    expect(find.byType(ColorFiltered), findsNothing);
  });

  testWidgets('applies color filter in system dark mode', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await UserManager().init();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        darkTheme: ThemeData(brightness: Brightness.dark),
        home: const Scaffold(
          body: CoverBrightnessFilter(child: SizedBox(width: 10, height: 10)),
        ),
      ),
    );

    expect(find.byType(ColorFiltered), findsOneWidget);
  });

  testWidgets('updates color filter when brightness setting changes', (
    tester,
  ) async {
    final user = UserManager();
    await user.init();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        darkTheme: ThemeData(brightness: Brightness.dark),
        themeMode: ThemeMode.dark,
        home: const Scaffold(
          body: CoverBrightnessFilter(child: SizedBox(width: 10, height: 10)),
        ),
      ),
    );

    expect(find.byType(ColorFiltered), findsOneWidget);

    await user.setDarkModeCoverBrightness(1.0);
    await tester.pump();

    expect(find.byType(ColorFiltered), findsNothing);

    await user.setDarkModeCoverBrightness(0.1);
    await tester.pump();

    expect(find.byType(ColorFiltered), findsOneWidget);
  });
}
