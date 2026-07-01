import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/widgets/shimmer_skeleton.dart';

void main() {
  // ── ShimmerBox ────────────────────────────────────────────────────────

  group('ShimmerBox', () {
    testWidgets('renders with specified width and height', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ShimmerBox(width: 100, height: 20),
          ),
        ),
      );

      // Verify the ShimmerBox renders and its Container has the right size
      final shimmerBox = tester.widget<ShimmerBox>(find.byType(ShimmerBox));
      expect(shimmerBox.width, 100);
      expect(shimmerBox.height, 20);
    });

    testWidgets('renders with default height when width is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ShimmerBox(),
          ),
        ),
      );

      expect(find.byType(ShimmerBox), findsOneWidget);
    });
  });

  // ── ShimmerShell ─────────────────────────────────────────────────────

  group('ShimmerShell', () {
    testWidgets('builds with a child without error', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ShimmerShell(
              child: Text('Loading'),
            ),
          ),
        ),
      );

      expect(find.text('Loading'), findsOneWidget);
      expect(find.byType(ShimmerShell), findsOneWidget);
    });
  });

  // ── ComicCoverSkeletonGrid ────────────────────────────────────────────

  group('ComicCoverSkeletonGrid', () {
    testWidgets('renders specified count of items', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                ComicCoverSkeletonGrid(),
              ],
            ),
          ),
        ),
      );

      // Each skeleton item contains a Card widget
      expect(find.byType(Card), findsNWidgets(6));
    });

    testWidgets('renders with custom count', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                ComicCoverSkeletonGrid(count: 3),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(Card), findsNWidgets(3));
    });
  });

  // ── ComicRowSkeletonList ──────────────────────────────────────────────

  group('ComicRowSkeletonList', () {
    testWidgets('builds without error inside CustomScrollView', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                ComicRowSkeletonList(),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(ComicRowSkeletonList), findsOneWidget);
    });

    testWidgets('renders specified count of skeleton cards', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                ComicRowSkeletonList(count: 3),
              ],
            ),
          ),
        ),
      );

      // Each row item contains a Card
      expect(find.byType(Card), findsNWidgets(3));
    });
  });
}
