import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/novel.dart';
import 'package:kira/pages/novel_bookmarks_page.dart';
import 'package:kira/pages/novel_reader/novel_reader_contents_sheet.dart';
import 'package:kira/pages/novel_reader/novel_reader_illustrations.dart';
import 'package:kira/providers/novel_providers.dart';
import 'package:kira/repositories/novel_repository.dart';
import 'package:kira/utils/novel_bookmark_store.dart';
import 'package:kira/widgets/error_retry_view.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

const _image = NovelContentEntry(
  name: '插图',
  contentType: 2,
  content: 'https://images.invalid/test.png',
);

class _Repository implements NovelRepository {
  final pendingDetail = Completer<NovelVolumeDetail>();
  final detail = const NovelVolumeDetail(
    book: NovelBook(pathWord: 'book', name: '小说'),
    volume: NovelVolume(
      id: 'v1',
      name: '第一卷',
      contents: [NovelContentEntry(name: '第一章', contentType: 1)],
    ),
  );

  @override
  Future<List<NovelVolume>> loadVolumes(
    String pathWord, {
    bool refresh = false,
  }) async => [detail.volume];

  @override
  Future<NovelVolumeDetail> loadVolumeDetail(
    String pathWord,
    String volumeId, {
    bool refresh = false,
  }) => pendingDetail.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected repository access: ${invocation.memberName}',
  );
}

void _expectPatternedLoading() {
  expect(find.byType(ExpressiveLoadingIndicator), findsOneWidget);
  expect(find.byType(CircularProgressIndicator), findsNothing);
}

void main() {
  setUp(() {
    setupSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    teardownSecureCredentialStoreForTest();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets(
    'novel bookmarks use patterned loading until the store is ready',
    (tester) async {
      final pending = Completer<SharedPreferences>();
      final store = NovelBookmarkStore.forTesting(prefs: pending.future);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [novelBookmarkStoreProvider.overrideWithValue(store)],
          child: wrapWithApp(NovelBookmarksPage(onChanged: () {})),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      _expectPatternedLoading();

      pending.complete(await SharedPreferences.getInstance());
      await tester.pumpAndSettle();
      expect(find.byType(ExpressiveLoadingIndicator), findsNothing);
      expect(find.text('还没有书签'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await store.flush();
      store.dispose();
    },
  );

  testWidgets('novel contents use patterned loading until chapters arrive', (
    tester,
  ) async {
    final repository = _Repository();
    await tester.pumpWidget(
      wrapWithApp(
        NovelReaderContentsSheet(
          repository: repository,
          pathWord: 'book',
          volumeId: 'v1',
          entryIndex: 0,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    _expectPatternedLoading();

    repository.pendingDetail.complete(repository.detail);
    await tester.pumpAndSettle();
    expect(find.byType(ExpressiveLoadingIndicator), findsNothing);
    expect(find.text('第一章'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('illustration loading and retry keep the theme primary color', (
    tester,
  ) async {
    var pending = Completer<List<int>>();
    await tester.pumpWidget(
      wrapWithApp(
        NovelReaderIllustrations(
          volumeName: '第一卷',
          illustrations: const [_image],
          loadBytes: (_) => pending.future,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    _expectPatternedLoading();
    expect(
      tester
          .widget<ExpressiveLoadingIndicator>(
            find.byType(ExpressiveLoadingIndicator),
          )
          .color,
      Theme.of(
        tester.element(find.byType(ExpressiveLoadingIndicator)),
      ).colorScheme.primary,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('novel-illustration-0'))).height,
      greaterThan(0),
    );

    pending.completeError(const FormatException('test failure'));
    await tester.pumpAndSettle();
    expect(find.byType(ExpressiveLoadingIndicator), findsNothing);
    expect(find.byType(ErrorRetryView), findsOneWidget);

    pending = Completer<List<int>>();
    tester.widget<ErrorRetryView>(find.byType(ErrorRetryView)).onRetry();
    await tester.pump();
    _expectPatternedLoading();
    expect(
      tester
          .widget<ExpressiveLoadingIndicator>(
            find.byType(ExpressiveLoadingIndicator),
          )
          .color,
      Theme.of(
        tester.element(find.byType(ExpressiveLoadingIndicator)),
      ).colorScheme.primary,
    );
    pending.complete(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=',
      ),
    );
    for (var frame = 0; frame < 8; frame++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      if (find.byType(Image).evaluate().isNotEmpty) break;
    }
    final image = tester.widget<Image>(find.byType(Image));
    await tester.runAsync(
      () => precacheImage(image.image, tester.element(find.byType(Image))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ExpressiveLoadingIndicator), findsNothing);
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
