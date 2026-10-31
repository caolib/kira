import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/pages/app_log_page.dart';
import 'package:kira/utils/app_logger.dart';
import 'package:kira/widgets/app_sheet.dart';
import 'package:kira/widgets/select_tile.dart';
import 'package:kira/widgets/settings_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

/// 只覆盖页面真正用到的几个入口，避免在假时钟下等真实文件 I/O。
class _FakeLogger extends AppLogger {
  _FakeLogger({required this.entries, this.unavailable = false})
    : super(directoryProvider: () async => throw UnimplementedError());

  final List<AppLogEntry> entries;
  bool unavailable;
  bool loggingEnabledState = true;
  AppLogLevel minimumLevelState = AppLogLevel.debug;
  int readCalls = 0;
  int clearCalls = 0;
  int retryCalls = 0;
  String exportedText = 'exported-text';

  @override
  bool get loggingEnabled => loggingEnabledState;

  @override
  AppLogLevel get minimumLevel => minimumLevelState;

  @override
  bool get isUnavailable => unavailable;

  @override
  Future<void> init() async {}

  @override
  Future<void> retryInit() async {
    retryCalls++;
    unavailable = false;
  }

  @override
  Future<List<AppLogEntry>> readEntries({int? limit = 200}) async {
    readCalls++;
    if (unavailable) {
      throw const AppLoggerUnavailableException('unavailable');
    }
    return limit == null ? entries : entries.take(limit).toList();
  }

  @override
  Future<String> exportText({int? limit}) async => exportedText;

  @override
  Future<void> clear() async {
    clearCalls++;
    entries.clear();
  }

  @override
  Future<void> setLoggingEnabled(bool enabled) async {
    loggingEnabledState = enabled;
  }

  @override
  Future<void> setMinimumLevel(AppLogLevel level) async {
    minimumLevelState = level;
  }
}

AppLogEntry _entry(AppLogLevel level, String message) {
  return AppLogEntry(
    timestamp: DateTime(2026, 1, 2, 3, 4, 5),
    level: level,
    source: 'seed',
    message: message,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'app_logging_enabled': true});
  });

  Future<_FakeLogger> pumpPage(
    WidgetTester tester, {
    List<AppLogEntry>? entries,
    bool unavailable = false,
    bool loggingEnabled = true,
  }) async {
    final logger = _FakeLogger(
      entries: entries ?? [_entry(AppLogLevel.error, 'boom')],
      unavailable: unavailable,
    )..loggingEnabledState = loggingEnabled;
    await tester.pumpWidget(
      wrapWithApp(AppLogPage(logger: logger), wrapInScaffold: false),
    );
    await tester.pumpAndSettle();
    return logger;
  }

  testWidgets('lists stored entries with level and source', (tester) async {
    await pumpPage(
      tester,
      entries: [
        _entry(AppLogLevel.warning, 'warn-entry'),
        _entry(AppLogLevel.error, 'error-entry'),
      ],
    );

    expect(find.textContaining('error-entry'), findsOneWidget);
    expect(find.textContaining('warn-entry'), findsOneWidget);
  });

  testWidgets('shows a retry view instead of an empty state on read failure', (
    tester,
  ) async {
    await pumpPage(tester, unavailable: true);

    expect(
      find.textContaining('AppLoggerUnavailableException'),
      findsOneWidget,
    );
    expect(find.text('暂无错误日志'), findsNothing);
  });

  testWidgets('recovers after a successful retry', (tester) async {
    final logger = await pumpPage(tester, unavailable: true);
    expect(
      find.textContaining('AppLoggerUnavailableException'),
      findsOneWidget,
    );

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(logger.retryCalls, 1);
    expect(find.textContaining('AppLoggerUnavailableException'), findsNothing);
    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('filters by level through the SelectTile dropdown', (
    tester,
  ) async {
    await pumpPage(
      tester,
      entries: [
        _entry(AppLogLevel.warning, 'warn-entry'),
        _entry(AppLogLevel.error, 'error-entry'),
      ],
    );

    // 面板上的 SelectTile 是等级筛选；设置面板里的那个在底部弹层中。
    await tester.tap(find.byType(SelectTile<AppLogLevel?>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('警告').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('warn-entry'), findsOneWidget);
    expect(find.textContaining('error-entry'), findsNothing);
  });

  testWidgets('search narrows the visible entries', (tester) async {
    await pumpPage(
      tester,
      entries: [
        _entry(AppLogLevel.error, 'alpha-failure'),
        _entry(AppLogLevel.error, 'beta-failure'),
      ],
    );

    await tester.enterText(find.byType(TextField), 'alpha');
    await tester.pumpAndSettle();

    expect(find.textContaining('alpha-failure'), findsOneWidget);
    expect(find.textContaining('beta-failure'), findsNothing);
  });

  testWidgets('expanding an entry drops the title line clamp', (tester) async {
    final longMessage = 'long-message-${'x' * 400}';
    await pumpPage(tester, entries: [_entry(AppLogLevel.error, longMessage)]);

    Text titleWidget() =>
        tester.widget<Text>(find.textContaining('long-message').first);
    expect(titleWidget().maxLines, 2);

    await tester.tap(find.textContaining('long-message').first);
    await tester.pumpAndSettle();

    expect(titleWidget().maxLines, isNull);
  });

  testWidgets('single entry copy writes the entry text to the clipboard', (
    tester,
  ) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          final arguments = call.arguments;
          if (arguments is Map && arguments['text'] is String) {
            copied.add(arguments['text'].toString());
          }
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await pumpPage(
      tester,
      entries: [_entry(AppLogLevel.error, 'copy-me-entry')],
    );
    await tester.tap(find.textContaining('copy-me-entry').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.copy_rounded));
    await tester.pumpAndSettle();

    expect(copied, hasLength(1));
    expect(copied.single, contains('copy-me-entry'));
    expect(copied.single, contains('source: seed'));
  });

  testWidgets('the toolbar offers export and clear but no bulk copy', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.byTooltip('导出日志文件'), findsOneWidget);
    expect(find.byTooltip('清空日志'), findsOneWidget);
    expect(find.byTooltip('复制日志'), findsNothing);
  });

  testWidgets('clearing asks for confirmation and empties the list', (
    tester,
  ) async {
    final logger = await pumpPage(
      tester,
      entries: [_entry(AppLogLevel.error, 'to-be-cleared')],
    );

    await tester.tap(find.byTooltip('清空日志'));
    await tester.pumpAndSettle();
    expect(find.text('确定要删除本地保存的错误日志吗？'), findsOneWidget);

    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();

    expect(logger.clearCalls, 1);
    expect(find.text('暂无错误日志'), findsOneWidget);
  });

  testWidgets('cancelling the clear dialog keeps the entries', (tester) async {
    final logger = await pumpPage(
      tester,
      entries: [_entry(AppLogLevel.error, 'kept-entry')],
    );

    await tester.tap(find.byTooltip('清空日志'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(logger.clearCalls, 0);
    expect(find.textContaining('kept-entry'), findsOneWidget);
  });

  testWidgets('settings sheet switches the minimum level', (tester) async {
    final logger = await pumpPage(tester);

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.byType(AppSheet), findsOneWidget);
    expect(find.byType(SettingsSection), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('log-recording-settings-card')),
        matching: find.byType(SwitchListTile),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byType(SelectTile<AppLogLevel>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('错误').last);
    await tester.pumpAndSettle();

    expect(logger.minimumLevelState, AppLogLevel.error);
  });

  testWidgets('settings sheet toggles logging', (tester) async {
    final logger = await pumpPage(tester);

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(logger.loggingEnabledState, isFalse);
  });

  testWidgets('disabled logging with no entries shows a distinct empty state', (
    tester,
  ) async {
    final logger = await pumpPage(tester, entries: [], loggingEnabled: false);

    expect(find.text('日志记录已关闭'), findsOneWidget);
    expect(find.text('暂无错误日志'), findsNothing);

    // 空态里的按钮直接把记录打开，不用再进设置。
    await tester.tap(find.text('记录日志'));
    await tester.pumpAndSettle();

    expect(logger.loggingEnabledState, isTrue);
    expect(find.text('日志记录已关闭'), findsNothing);
    expect(find.text('暂无错误日志'), findsOneWidget);
  });

  testWidgets('disabled logging keeps existing entries visible with a banner', (
    tester,
  ) async {
    await pumpPage(
      tester,
      entries: [_entry(AppLogLevel.error, 'kept-entry')],
      loggingEnabled: false,
    );

    expect(find.text('日志记录已关闭'), findsOneWidget);
    expect(find.textContaining('kept-entry'), findsOneWidget);
  });
}
