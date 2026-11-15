import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/novel_reading_progress.dart';
import 'package:kira/models/reader_settings.dart';
import 'package:kira/utils/novel_reading_store.dart';
import 'package:kira/utils/reading_stats.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../account_storage_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AccountPreferencesPlatform platform;
  late NovelReadingStore history;

  setUp(() {
    platform = AccountPreferencesPlatform()..install();
    history = NovelReadingStore();
    ReadingStats.reloadFromPrefs();
    ReadingStats.resumeAfterRestore();
    ReadingStats.setEnabledGate(() => true);
  });

  tearDown(() {
    ReadingStats.reloadFromPrefs();
    ReadingStats.resumeAfterRestore();
    ReadingStats.setEnabledGate(() => ReaderSettings().readingStatsEnabled);
    platform.dispose();
  });

  Future<void> saveHistory(String book, {String volume = 'v2'}) =>
      history.saveProgress(
        NovelReadingProgress(
          pathWord: book,
          name: '旧小说 $book',
          cover: '',
          volumeId: volume,
          volumeName: volume,
          entryIndex: 7,
          chapterName: '读到的章节',
          paragraphIndex: 20,
          progress: 0.7,
          updatedAt: DateTime(2026, 8, 3),
          readVolumeIds: const {'v1'},
        ),
      );

  Future<void> readLive({String book = 'live'}) =>
      ReadingStats.recordNovelReading(
        pathWord: book,
        volumeId: 'v2',
        entryIndex: 7,
        paragraphIndex: 20,
        text: '甲乙丙丁',
        start: 0,
        end: 4,
      );

  Future<void> coldStart() async {
    await ReadingStats.flush();
    SharedPreferences.resetStatic();
    ReadingStats.reloadFromPrefs();
  }

  test('disabled initialization does not read or write statistics', () async {
    await saveHistory('old');
    ReadingStats.setEnabledGate(() => false);
    await ReadingStats.initializeNovelsFromHistory();
    expect(platform.values.containsKey('flutter.reading_stats_v1'), isFalse);
    expect((await ReadingStats.load()).novelHistoryInitialized, isFalse);
  });

  test(
    'imports all local books and known volumes without fabricated words',
    () async {
      for (var i = 0; i < 36; i++) {
        await saveHistory('book-$i');
      }
      await ReadingStats.recordImageLoad(pathWord: 'comic', chapterUuid: 'c1');
      await ReadingStats.initializeNovelsFromHistory();
      await coldStart();
      final snapshot = await ReadingStats.load();
      expect(novelsReadCount(snapshot), 36);
      expect(novelVolumesReadCount(snapshot), 72);
      expect(novelChaptersReadCount(snapshot), 36);
      expect(snapshot.novelMeta['book-0']!.chapters['v1'], isEmpty);
      expect(snapshot.novelMeta['book-0']!.chapters['v2']!.keys, ['7']);
      expect(snapshot.novelMeta['book-0']!.name, '旧小说 book-0');
      expect(novelWordsReadCount(snapshot), 0);
      expect(snapshot.novelDaily, isEmpty);
      expect(snapshot.novelSince, isNull);
      expect(topNovelTags(snapshot), isEmpty);
      expect(pagesReadCount(snapshot), 1);
      expect(snapshot.novelHistoryInitialized, isTrue);
    },
  );

  test('initialization and marker persist once across cold starts', () async {
    await saveHistory('old');
    await ReadingStats.initializeNovelsFromHistory();
    await coldStart();
    await saveHistory('later', volume: 'v3');
    await ReadingStats.initializeNovelsFromHistory();
    final snapshot = await ReadingStats.load();
    expect(snapshot.novelMeta.keys, ['old']);
    expect(novelVolumesReadCount(snapshot), 2);
    expect(novelChaptersReadCount(snapshot), 1);
  });

  test(
    'existing novel statistics are not replaced or mixed with history',
    () async {
      await saveHistory('old');
      await readLive();
      await ReadingStats.initializeNovelsFromHistory();
      final snapshot = await ReadingStats.load();
      expect(snapshot.novelMeta.keys, ['live']);
      expect(novelWordsReadCount(snapshot), 4);
      expect(snapshot.novelDaily.values.single, 4);
      expect(snapshot.novelHistoryInitialized, isTrue);
    },
  );

  test(
    'parallel initialization finishes before a new visible reading record',
    () async {
      await saveHistory('old');
      await Future.wait([
        ReadingStats.initializeNovelsFromHistory(),
        ReadingStats.initializeNovelsFromHistory(),
        readLive(),
      ]);
      final snapshot = await ReadingStats.load();
      expect(snapshot.novelMeta.keys, unorderedEquals(['old', 'live']));
      expect(novelWordsReadCount(snapshot), 4);
      expect(novelVolumesReadCount(snapshot), 3);
      expect(novelChaptersReadCount(snapshot), 2);
      expect(snapshot.novelDaily.values.single, 4);
    },
  );

  test(
    'historical chapter does not suppress actual visible character counting',
    () async {
      await saveHistory('old');
      await ReadingStats.initializeNovelsFromHistory();
      await readLive(book: 'old');
      await readLive(book: 'old');
      final snapshot = await ReadingStats.load();
      expect(novelWordsReadCount(snapshot), 4);
      expect(novelChaptersReadCount(snapshot), 1);
      expect(novelVolumesReadCount(snapshot), 2);
    },
  );

  test(
    'snapshot loading waits for an in-flight history initialization',
    () async {
      await saveHistory('old');
      final initialization = ReadingStats.initializeNovelsFromHistory();
      final snapshot = await ReadingStats.load();
      await initialization;
      expect(snapshot.novelMeta.keys, ['old']);
      expect(snapshot.novelHistoryInitialized, isTrue);
    },
  );

  test(
    'clear waits for initialization before allowing a fresh history import',
    () async {
      await saveHistory('old');
      final started = Completer<void>();
      final release = Completer<void>();
      platform.beforeWrite = (key, _) async {
        if (key != 'flutter.reading_stats_v1') return;
        platform.beforeWrite = null;
        started.complete();
        await release.future;
      };
      final initialization = ReadingStats.initializeNovelsFromHistory();
      await started.future;
      final clearing = ReadingStats.clear(novel: true);
      release.complete();
      await Future.wait([initialization, clearing]);
      await coldStart();
      final cleared = await ReadingStats.load();
      expect(cleared.isEmpty, isTrue);
      expect(cleared.novelHistoryInitialized, isFalse);
      await ReadingStats.initializeNovelsFromHistory();
      expect((await ReadingStats.load()).novelMeta.keys, ['old']);
    },
  );

  for (final novel in <bool?>[true, null]) {
    test(
      'clear novel=$novel resets initialization and allows history import after cold start',
      () async {
        await saveHistory('old');
        await ReadingStats.initializeNovelsFromHistory();
        await ReadingStats.clear(novel: novel);
        await coldStart();
        final cleared = await ReadingStats.load();
        expect(cleared.isEmpty, isTrue);
        expect(cleared.novelHistoryInitialized, isFalse);
        await ReadingStats.initializeNovelsFromHistory();
        final snapshot = await ReadingStats.load();
        expect(snapshot.novelMeta.keys, ['old']);
        expect(novelVolumesReadCount(snapshot), 2);
        expect(novelChaptersReadCount(snapshot), 1);
        expect(novelWordsReadCount(snapshot), 0);
        expect(snapshot.novelDaily, isEmpty);
        expect(snapshot.novelHistoryInitialized, isTrue);
        expect(await history.readProgress('old'), isNotNull);
      },
    );
  }

  test(
    'clearing only comics leaves novel history initialization available',
    () async {
      await saveHistory('old');
      await ReadingStats.clear(novel: false);
      await ReadingStats.initializeNovelsFromHistory();
      expect(novelsReadCount(await ReadingStats.load()), 1);
    },
  );

  test(
    'zero statistics retry with later history without redundant empty writes',
    () async {
      await ReadingStats.initializeNovelsFromHistory();
      final writes = platform.operations.length;
      await ReadingStats.initializeNovelsFromHistory();
      expect(platform.operations.length, writes);
      await coldStart();
      await saveHistory('later');
      await ReadingStats.initializeNovelsFromHistory();
      expect((await ReadingStats.load()).novelMeta.keys, ['later']);
    },
  );

  test(
    'legacy initialization marker does not block all-zero statistics',
    () async {
      await saveHistory('old');
      platform.values['flutter.reading_stats_v1'] = jsonEncode({
        'comicMeta': {
          'comic': {
            'name': '漫画',
            'tags': <String>[],
            'chapterImages': {'c1': 12},
          },
        },
        'daily': {'2026-08-03': 12},
        'novelMeta': <String, Object>{},
        'novelDaily': {'2026-08-03': 0},
        'novelHistoryInitialized': true,
      });
      await (await SharedPreferences.getInstance()).reload();
      ReadingStats.reloadFromPrefs();
      await ReadingStats.initializeNovelsFromHistory();
      await coldStart();
      final snapshot = await ReadingStats.load();
      expect(snapshot.novelMeta.keys, ['old']);
      expect(novelVolumesReadCount(snapshot), 2);
      expect(novelWordsReadCount(snapshot), 0);
      expect(snapshot.novelDaily.values, everyElement(0));
      expect(pagesReadCount(snapshot), 12);
    },
  );

  test('nonzero daily words alone prevent reinitialization', () async {
    await saveHistory('old');
    platform.values['flutter.reading_stats_v1'] = jsonEncode({
      'novelMeta': <String, Object>{},
      'novelDaily': {'2026-08-03': 4},
      'novelHistoryInitialized': true,
    });
    await (await SharedPreferences.getInstance()).reload();
    ReadingStats.reloadFromPrefs();
    await ReadingStats.initializeNovelsFromHistory();
    final snapshot = await ReadingStats.load();
    expect(snapshot.novelMeta, isEmpty);
    expect(snapshot.novelDaily, {'2026-08-03': 4});
  });

  test(
    'invalid local records are skipped without losing valid records',
    () async {
      await saveHistory('valid');
      platform.values['flutter.novel_reading_history_broken'] = '{broken';
      platform.values['flutter.novel_reading_history_wrong-key'] =
          platform.values['flutter.novel_reading_history_valid']!;
      await (await SharedPreferences.getInstance()).reload();
      await ReadingStats.initializeNovelsFromHistory();
      expect((await ReadingStats.load()).novelMeta.keys, ['valid']);
    },
  );

  for (final throws in [false, true]) {
    test(
      'initialization write failure (throws=$throws) preserves a retryable snapshot',
      () async {
        await saveHistory('old');
        platform.throwOnFailure = throws;
        platform.beforeWrite = (key, value) async {
          if (key != 'flutter.reading_stats_v1') return;
          platform
            ..failKey = 'reading_stats_v1'
            ..failValue = value;
        };
        await expectLater(
          ReadingStats.initializeNovelsFromHistory(),
          throws ? throwsA(isA<PlatformException>()) : throwsStateError,
        );
        expect(
          platform.values.containsKey('flutter.reading_stats_v1'),
          isFalse,
        );
        platform.beforeWrite = null;
        await ReadingStats.initializeNovelsFromHistory();
        await coldStart();
        final snapshot = await ReadingStats.load();
        expect(novelsReadCount(snapshot), 1);
        expect(novelVolumesReadCount(snapshot), 2);
        expect(snapshot.novelHistoryInitialized, isTrue);
      },
    );
  }
}
