import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/widgets/error_retry_view.dart';

import '../test_helpers.dart';

void main() {
  // ── ErrorRetryView ────────────────────────────────────────────────────

  group('ErrorRetryView', () {
    Widget buildSubject({
      VoidCallback? onRetry,
      IconData? icon,
      String? message,
      String? retryLabel,
    }) {
      return wrapWithApp(
        ErrorRetryView(
          icon: icon ?? Icons.cloud_off,
          message: message ?? '加载失败',
          retryLabel: retryLabel ?? '重试',
          onRetry: onRetry ?? () {},
        ),
      );
    }

    testWidgets('renders icon, message, and retry button', (tester) async {
      await tester.pumpWidget(buildSubject());

      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
      expect(find.text('加载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });

    testWidgets('tapping retry button calls callback', (tester) async {
      var pressed = false;
      await tester.pumpWidget(buildSubject(onRetry: () => pressed = true));

      await tester.tap(find.text('重试'));
      expect(pressed, true);
    });

    testWidgets('renders custom icon', (tester) async {
      await tester.pumpWidget(buildSubject(icon: Icons.error_outline));

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsNothing);
    });

    testWidgets('renders custom message', (tester) async {
      await tester.pumpWidget(buildSubject(message: '网络错误'));

      expect(find.text('网络错误'), findsOneWidget);
      expect(find.text('加载失败'), findsNothing);
    });

    testWidgets('renders custom retry label', (tester) async {
      await tester.pumpWidget(buildSubject(retryLabel: 'Retry'));

      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('重试'), findsNothing);
    });
  });

  // ── SliverErrorRetryView ─────────────────────────────────────────────

  group('SliverErrorRetryView', () {
    Widget buildSliverSubject({VoidCallback? onRetry}) {
      return wrapWithApp(
        CustomScrollView(
          slivers: [SliverErrorRetryView(onRetry: onRetry ?? () {})],
        ),
      );
    }

    testWidgets('renders inside CustomScrollView', (tester) async {
      await tester.pumpWidget(buildSliverSubject());

      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
      expect(find.text('加载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });

    testWidgets('tapping retry button calls callback', (tester) async {
      var pressed = false;
      await tester.pumpWidget(
        buildSliverSubject(onRetry: () => pressed = true),
      );

      await tester.tap(find.text('重试'));
      expect(pressed, true);
    });
  });
}
