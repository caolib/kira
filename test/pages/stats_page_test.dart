import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/models/reader_settings.dart';
import 'package:kira/pages/stats_page.dart';
import 'package:kira/utils/reading_stats.dart';
import 'package:kira/widgets/app_sheet.dart';
import 'package:kira/widgets/settings_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

Widget _buildTestApp(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(teardownSecureCredentialStoreForTest);

  setUp(() async {
    setupSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({});
    ReadingStats.reloadFromPrefs();
    ReaderSettings().resetPrefsCache();
    await ReaderSettings().initFromPrefs(await SharedPreferences.getInstance());
  });

  testWidgets('disabled state shows enable button and privacy note', (
    tester,
  ) async {
    await tester.pumpWidget(_buildTestApp(const StatsPage()));
    await tester.pumpAndSettle();

    // 开关默认关闭 → 显示开启按钮与隐私说明
    expect(find.byIcon(Icons.insights_rounded), findsOneWidget);
    expect(find.text('开启'), findsOneWidget);
    expect(find.textContaining('数据仅保存在本地'), findsOneWidget);
  });

  testWidgets('enabled state shows overview card when data exists', (
    tester,
  ) async {
    // 预置：开启统计 + 写入一条统计数据
    SharedPreferences.setMockInitialValues({
      'reader_reading_stats_enabled': true,
      'reading_stats_v1':
          '{"comicMeta":{"comic-a":{"name":"漫画A","tags":["恋爱"],"chapterImages":{"ch-1":12}}},"daily":{},"since":"2026-08-03"}',
    });
    ReaderSettings().resetPrefsCache();
    await ReaderSettings().initFromPrefs(await SharedPreferences.getInstance());
    ReadingStats.reloadFromPrefs();

    await tester.pumpWidget(_buildTestApp(const StatsPage()));
    await tester.pumpAndSettle();

    // 已开启态：显示概览卡（漫画/章节/页数）与常看类型标题
    expect(find.text('漫画'), findsWidgets);
    expect(find.text('章节'), findsWidgets);
    expect(find.text('页数'), findsWidgets);
    expect(find.text('常看类型'), findsOneWidget);
    expect(find.text('恋爱'), findsOneWidget);
    expect(find.text('开始于 2026-08-03'), findsOneWidget);
  });

  testWidgets('enabled empty state shows zeros instead of empty hint', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'reader_reading_stats_enabled': true,
      // reading_stats_v1 缺失 → 空快照，按 0 渲染
    });
    ReaderSettings().resetPrefsCache();
    await ReaderSettings().initFromPrefs(await SharedPreferences.getInstance());
    ReadingStats.reloadFromPrefs();

    await tester.pumpWidget(_buildTestApp(const StatsPage()));
    await tester.pumpAndSettle();

    // 无空态提示；概览三数字均显示 0
    expect(find.text('还没有阅读数据'), findsNothing);
    expect(find.text('漫画'), findsWidgets);
    expect(find.text('章节'), findsWidgets);
    expect(find.text('页数'), findsWidgets);
    expect(find.text('0'), findsNWidgets(3));
  });

  testWidgets('settings cards remain scrollable at narrow large-text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await ReaderSettings().setReadingStatsEnabled(true);
    await tester.pumpWidget(
      wrapWithApp(const StatsPage(), wrapInScaffold: false),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsSection), findsNWidgets(4));
    await tester.ensureVisible(find.text('清除'));
    await tester.pumpAndSettle();
    expect(find.text('清除').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'enabled state shows FAB; tapping opens settings sheet with 关闭/清除',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'reader_reading_stats_enabled': true,
        'reading_stats_v1':
            '{"comicMeta":{"comic-a":{"name":"漫画A","tags":[],"chapterImages":{"ch-1":1}}},"daily":{}}',
      });
      ReaderSettings().resetPrefsCache();
      await ReaderSettings().initFromPrefs(
        await SharedPreferences.getInstance(),
      );
      ReadingStats.reloadFromPrefs();

      await tester.pumpWidget(_buildTestApp(const StatsPage()));
      await tester.pumpAndSettle();

      // 右下角设置 FAB 存在；未开启态不应有 FAB
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);

      // 内联的关闭/清除按钮已移除，不应在主页直接可见
      expect(find.text('关闭'), findsNothing);
      expect(find.text('清除'), findsNothing);

      // 点击 FAB 弹出底部抽屉，里面有开关与清除操作
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();
      expect(find.text('阅读统计设置'), findsOneWidget);
      expect(find.text('统计功能'), findsOneWidget);
      expect(find.text('清除'), findsOneWidget);
      expect(find.byType(AppSheet), findsOneWidget);
      expect(find.byType(SettingsSection), findsNWidgets(4));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('stats-chart-settings-card')),
          matching: find.byType(RadioGroup<int>),
        ),
        findsOneWidget,
      );
      final clear = find.text('清除');
      await tester.ensureVisible(clear);
      await tester.pumpAndSettle();
      expect(clear.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
