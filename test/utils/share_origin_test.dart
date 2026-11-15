import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/share_origin.dart';

import '../test_helpers.dart';

void main() {
  setUp(setupSecureCredentialStoreForTest);
  tearDown(teardownSecureCredentialStoreForTest);

  testWidgets('iPad sharing anchor is the visible source button', (
    tester,
  ) async {
    Rect? origin;
    await tester.pumpWidget(
      wrapWithApp(
        Center(
          child: Builder(
            builder: (context) => IconButton(
              key: const ValueKey('share-button'),
              onPressed: () => origin = shareOrigin(context),
              icon: const Icon(Icons.share),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('share-button')));
    expect(origin, tester.getRect(find.byKey(const ValueKey('share-button'))));
    expect(origin!.width, greaterThan(0));
    expect(origin!.height, greaterThan(0));
  });

  testWidgets('zero-size source uses a nonempty screen-centered fallback', (
    tester,
  ) async {
    late BuildContext source;
    await tester.pumpWidget(
      wrapWithApp(
        Center(
          child: Builder(
            builder: (context) {
              source = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    final origin = shareOrigin(source);
    expect(origin.width, 1);
    expect(origin.height, 1);
    final logicalSize = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(
      origin.center,
      Offset(logicalSize.width / 2, logicalSize.height / 2),
    );
  });
}
