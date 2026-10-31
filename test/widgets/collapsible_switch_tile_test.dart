import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/widgets/collapsible_switch_tile.dart';

import '../test_helpers.dart';

void main() {
  setUp(setupSecureCredentialStoreForTest);
  tearDown(teardownSecureCredentialStoreForTest);

  for (final adaptive in [false, true]) {
    for (final reduceMotion in [false, true]) {
      testWidgets('row and arrow expand independently from switch '
          '(adaptive: $adaptive, reduced motion: $reduceMotion)', (
        tester,
      ) async {
        var enabled = false;
        var expanded = false;
        var changes = 0;
        await tester.pumpWidget(
          wrapWithApp(
            StatefulBuilder(
              builder: (context, setState) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: reduceMotion),
                child: CollapsibleSwitchTile(
                  title: '专注模式',
                  switchKey: const ValueKey('switch'),
                  expandKey: const ValueKey('expand'),
                  adaptive: adaptive,
                  value: enabled,
                  expanded: expanded,
                  onChanged: (value) => setState(() {
                    enabled = value;
                    changes++;
                  }),
                  onToggleExpanded: () => setState(() => expanded = !expanded),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('专注模式'));
        await tester.pumpAndSettle();
        expect(expanded, isTrue);
        expect(enabled, isFalse);
        expect(changes, 0);

        final header = find.byType(ListTile);
        await tester.tapAt(tester.getBottomLeft(header) + const Offset(12, -6));
        await tester.pumpAndSettle();
        expect(expanded, isFalse);
        expect(changes, 0);

        await tester.tap(find.byKey(const ValueKey('expand')));
        await tester.pumpAndSettle();
        expect(expanded, isTrue);
        expect(enabled, isFalse);

        final toggle = find.byKey(const ValueKey('switch'));
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(enabled, isTrue);
        expect(expanded, isTrue);
        expect(changes, 1);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(enabled, isFalse);
        expect(expanded, isTrue);
        expect(changes, 2);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('large-text narrow layout keeps separate accessible targets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      wrapWithApp(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: CollapsibleSwitchTile(
              title: '专注模式',
              switchKey: const ValueKey('switch'),
              expandKey: const ValueKey('expand'),
              value: false,
              expanded: true,
              onChanged: (_) {},
              onToggleExpanded: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final target in [
      find.byType(ListTile),
      find.byKey(const ValueKey('switch')),
      find.byKey(const ValueKey('expand')),
    ]) {
      expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
    }
    expect(
      tester.getSemantics(find.byKey(const ValueKey('switch'))),
      matchesSemantics(
        label: '专注模式',
        hasToggledState: true,
        isEnabled: true,
        hasEnabledState: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });
}
