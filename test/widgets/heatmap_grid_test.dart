import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/widgets/heatmap_grid.dart';

Color _cellColor(WidgetTester tester, String tooltipMessage) {
  final tooltip = find.byWidgetPredicate(
    (widget) => widget is Tooltip && widget.message == tooltipMessage,
  );
  expect(tooltip, findsOneWidget);

  final decoratedBox = find.descendant(
    of: tooltip,
    matching: find.byType(DecoratedBox),
  );
  expect(decoratedBox, findsOneWidget);

  final decoration = tester.widget<DecoratedBox>(decoratedBox).decoration;
  if (decoration is! BoxDecoration || decoration.color == null) {
    fail('Heatmap cell must have a BoxDecoration with a color.');
  }
  return decoration.color!;
}

void main() {
  testWidgets('uses fixed page-count thresholds for cell colors', (
    tester,
  ) async {
    const primary = Color(0xFF336699);
    const empty = Color(0xFFE0E0E0);
    final dailyCounts = <String, int>{
      '2020-01-06': 1,
      '2020-01-07': 50,
      '2020-01-08': 51,
      '2020-01-09': 150,
      '2020-01-10': 151,
      '2020-01-11': 300,
      '2020-01-12': 301,
    };

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          colorScheme: const ColorScheme.light(primary: primary),
        ),
        home: Scaffold(
          body: HeatmapGrid(
            dailyCounts: dailyCounts,
            weeks: 2,
            end: DateTime(2020, 1, 12),
            emptyColor: empty,
          ),
        ),
      ),
    );

    expect(_cellColor(tester, '2020-01-05'), empty);
    expect(_cellColor(tester, '1 页'), primary.withValues(alpha: 0.35));
    expect(_cellColor(tester, '50 页'), primary.withValues(alpha: 0.35));
    expect(_cellColor(tester, '51 页'), primary.withValues(alpha: 0.55));
    expect(_cellColor(tester, '150 页'), primary.withValues(alpha: 0.55));
    expect(_cellColor(tester, '151 页'), primary.withValues(alpha: 0.75));
    expect(_cellColor(tester, '300 页'), primary.withValues(alpha: 0.75));
    expect(_cellColor(tester, '301 页'), primary);
  });
}
