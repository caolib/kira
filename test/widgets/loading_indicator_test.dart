import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';

void main() {
  group('ExpressiveLoadingIndicator', () {
    testWidgets('renders without error', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ExpressiveLoadingIndicator())),
      );
      expect(find.byType(ExpressiveLoadingIndicator), findsOneWidget);
    });

    testWidgets('renders outlined style without error', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ExpressiveLoadingIndicator(
              style: ExpressiveLoadingIndicatorStyle.outlined,
            ),
          ),
        ),
      );
      expect(find.byType(ExpressiveLoadingIndicator), findsOneWidget);
    });

    testWidgets('animation runs without error', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ExpressiveLoadingIndicator())),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(ExpressiveLoadingIndicator), findsOneWidget);
    });
  });
}
