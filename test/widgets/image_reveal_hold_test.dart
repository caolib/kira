import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/widgets/image_reveal_hold.dart';

import '../test_helpers.dart';

void main() {
  const childKey = ValueKey('child');
  const holdDuration = Duration(milliseconds: 100);

  Widget buildHold({
    required Alignment alignment,
    double? holdWidth,
    double? holdHeight,
    required Size childSize,
    Duration duration = holdDuration,
  }) {
    return Center(
      child: ImageRevealHold(
        alignment: alignment,
        holdWidth: holdWidth,
        holdHeight: holdHeight,
        holdDuration: duration,
        child: Container(
          key: childKey,
          width: childSize.width,
          height: childSize.height,
          color: Colors.red,
        ),
      ),
    );
  }

  group('ImageRevealHold', () {
    testWidgets('hold period pins extent to the estimate and right-aligns '
        'the child', (tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          buildHold(
            alignment: Alignment.centerRight,
            holdWidth: 300,
            childSize: const Size(100, 50),
          ),
        ),
      );

      // 撑块（300 宽）在淡出期内把 item 宽度稳定在预估值，真图（100 宽）
      // 右对齐贴住已读侧边缘，垂直方向保持居中。
      expect(tester.getSize(find.byType(ImageRevealHold)), const Size(300, 50));
      expect(
        tester.getTopRight(find.byKey(childKey)).dx,
        tester.getTopRight(find.byType(ImageRevealHold)).dx,
      );
      expect(
        tester.getCenter(find.byKey(childKey)).dy,
        tester.getCenter(find.byType(ImageRevealHold)).dy,
      );
    });

    testWidgets('releases the extent once the hold duration elapses', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapWithApp(
          buildHold(
            alignment: Alignment.centerRight,
            holdWidth: 300,
            childSize: const Size(100, 50),
          ),
        ),
      );

      await tester.pump(holdDuration + const Duration(milliseconds: 50));

      // 撑块移除后 item 回落到真图尺寸，右缘仍然贴住原位置。
      expect(tester.getSize(find.byType(ImageRevealHold)), const Size(100, 50));
      expect(
        tester.getTopRight(find.byKey(childKey)).dx,
        tester.getTopRight(find.byType(ImageRevealHold)).dx,
      );
    });

    testWidgets('holdHeight pins the vertical extent and top-aligns the '
        'child', (tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          buildHold(
            alignment: Alignment.topCenter,
            holdHeight: 200,
            childSize: const Size(80, 60),
          ),
        ),
      );

      expect(tester.getSize(find.byType(ImageRevealHold)), const Size(80, 200));
      expect(
        tester.getTopLeft(find.byKey(childKey)).dy,
        tester.getTopLeft(find.byType(ImageRevealHold)).dy,
      );

      await tester.pump(holdDuration + const Duration(milliseconds: 50));
      expect(tester.getSize(find.byType(ImageRevealHold)), const Size(80, 60));
    });

    testWidgets('a child larger than the estimate is never clipped', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapWithApp(
          buildHold(
            alignment: Alignment.centerRight,
            holdWidth: 100,
            childSize: const Size(400, 60),
          ),
        ),
      );

      // 估算偏小时 Stack 以真图为准，不会把真图裁进预估尺寸里。
      expect(tester.getSize(find.byType(ImageRevealHold)), const Size(400, 60));
      expect(
        tester.getTopRight(find.byKey(childKey)).dx,
        tester.getTopRight(find.byType(ImageRevealHold)).dx,
      );
    });

    testWidgets('unmounting before the hold elapses does not throw', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapWithApp(
          buildHold(
            alignment: Alignment.centerRight,
            holdWidth: 300,
            childSize: const Size(100, 50),
            duration: const Duration(seconds: 10),
          ),
        ),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 11));

      expect(tester.takeException(), isNull);
    });
  });
}
