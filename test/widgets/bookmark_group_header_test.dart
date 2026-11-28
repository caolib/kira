import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/widgets/bookmark_group_header.dart';

import '../test_helpers.dart';

void main() {
  setUp(setupSecureCredentialStoreForTest);
  tearDown(teardownSecureCredentialStoreForTest);

  for (final brightness in Brightness.values) {
    testWidgets('长卷名、大字与减少动画：$brightness', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 700);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var pins = 0;
      var deletes = 0;
      var opens = 0;
      var resumes = 0;
      await tester.pumpWidget(
        wrapWithApp(
          Center(
            child: SizedBox(
              width: 288,
              child: BookmarkGroupHeader(
                detailsKey: const ValueKey('details'),
                resumeKey: const ValueKey('resume'),
                cover: const SizedBox(),
                name: '很长的书名' * 8,
                count: 500,
                pinned: true,
                onDetails: () => opens++,
                onPin: () async => pins++,
                onDelete: () async => deletes++,
                onResume: () => resumes++,
                chapter: '很长的卷名' * 8,
                progress: '100.00%',
              ),
            ),
          ),
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final button = find.byType(OutlinedButton);
      final outline = tester.getRect(
        find.descendant(of: button, matching: find.byType(Material)),
      );
      expect(outline.height, 42);
      final hitArea = tester.getRect(button);
      expect(hitArea.height, greaterThanOrEqualTo(48));
      // 描边外的上下留白也应续读，而非进入作品详情。
      await tester.tapAt(hitArea.topCenter + const Offset(0, 1));
      await tester.tapAt(hitArea.bottomCenter - const Offset(0, 1));
      expect(resumes, 2);
      expect(opens, 0);
      await tester.drag(
        find.byKey(const ValueKey('details')),
        const Offset(-180, 0),
      );
      await tester.pump();
      expect(find.text('取消置顶').hitTestable(), findsOneWidget);
      expect(find.text('删除').hitTestable(), findsOneWidget);
      expect(deletes, 0);
      await tester.tap(find.text('取消置顶'));
      await tester.pump();
      expect(pins, 1);
      expect(find.text('删除'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
