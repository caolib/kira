import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/pages/app_log_page.dart';
import 'package:kira/utils/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('kira_app_log_page_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('shows logging controls with warning as default threshold', (
    tester,
  ) async {
    final logger = AppLogger(directoryProvider: () async => tempDir);

    await tester.pumpWidget(MaterialApp(home: AppLogPage(logger: logger)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('日志记录'), findsOneWidget);
    expect(find.text('记录级别'), findsOneWidget);
    expect(find.text('警告及以上'), findsWidgets);
    expect(tester.widget<Switch>(find.byType(Switch)).value, true);
  });

  testWidgets('can disable logging from the log page', (tester) async {
    final logger = AppLogger(directoryProvider: () async => tempDir);

    await tester.pumpWidget(MaterialApp(home: AppLogPage(logger: logger)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('日志记录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(logger.loggingEnabled, false);
    expect(tester.widget<Switch>(find.byType(Switch)).value, false);
  });

  testWidgets('level filter bar shows all levels and filters entries', (
    tester,
  ) async {
    final logger = AppLogger(directoryProvider: () async => tempDir);
    await logger.setMinimumLevel(AppLogLevel.debug);

    await logger.init();
    await logger.recordError('error one', source: 'test');
    await logger.recordInfo('info one', source: 'test');
    await logger.recordWarning('warning one', source: 'test');

    await tester.pumpWidget(MaterialApp(home: AppLogPage(logger: logger)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('刷新'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('error one'), findsOneWidget);
    expect(find.text('info one'), findsOneWidget);
    expect(find.text('warning one'), findsOneWidget);

    Finder filterChip(String label) =>
        find.descendant(of: find.byType(FilterChip), matching: find.text(label));

    await tester.tap(filterChip('错误'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('error one'), findsOneWidget);
    expect(find.text('info one'), findsNothing);
    expect(find.text('warning one'), findsNothing);

    await tester.tap(filterChip('全部'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('error one'), findsOneWidget);
    expect(find.text('info one'), findsOneWidget);
    expect(find.text('warning one'), findsOneWidget);
  });

  testWidgets('renders recorded entries', (tester) async {
    final logger = AppLogger(directoryProvider: () async => tempDir);

    await logger.init();
    await logger.recordError('error one', source: 'test');

    await tester.pumpWidget(MaterialApp(home: AppLogPage(logger: logger)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('error one'), findsOneWidget);
  });

  testWidgets('expanded entry shows a copy button', (tester) async {
    final logger = AppLogger(directoryProvider: () async => tempDir);

    await logger.init();
    await logger.recordError('error one', source: 'test');

    await tester.pumpWidget(MaterialApp(home: AppLogPage(logger: logger)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('error one'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byTooltip('复制此日志'), findsOneWidget);
  });
}
