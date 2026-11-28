import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/reader_settings.dart';
import 'package:kira/utils/reading_stats.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../account_storage_test_support.dart';

Future<void> record({
  String book = 'book',
  String volume = 'v1',
  int entry = 0,
  int paragraph = 0,
  String text = '零一二三四五六七八九',
  int start = 0,
  int end = 10,
  DateTime? at,
  List<String>? tags,
}) => ReadingStats.recordNovelReading(
  pathWord: book,
  volumeId: volume,
  entryIndex: entry,
  paragraphIndex: paragraph,
  text: text,
  start: start,
  end: end,
  readAt: at,
  novelName: '小说',
  tags: tags,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AccountPreferencesPlatform platform;

  setUp(() {
    platform = AccountPreferencesPlatform()..install();
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

  Future<void> coldStart() async {
    await ReadingStats.flush();
    SharedPreferences.resetStatic();
    ReadingStats.reloadFromPrefs();
  }

  test('disabled and invalid records never write stats', () async {
    ReadingStats.setEnabledGate(() => false);
    await record();
    ReadingStats.setEnabledGate(() => true);
    await record(book: '');
    await record(volume: '');
    await record(entry: -1);
    await record(paragraph: -1);
    await record(end: 0);
    await record(text: ' \n\t　', end: 4);
    expect((await ReadingStats.load()).isEmpty, isTrue);
    expect(platform.values, isEmpty);
  });

  test(
    'counts visible ranges, skips gaps and deduplicates after cold starts',
    () async {
      await record(end: 3);
      await record(start: 7);
      await coldStart();
      await record(end: 3);
      var snap = await ReadingStats.load();
      expect(novelWordsReadCount(snap), 6);
      expect(novelsReadCount(snap), 1);
      expect(novelVolumesReadCount(snap), 1);
      expect(novelChaptersReadCount(snap), 1);
      expect(snap.novelDaily.values.single, 6);
      expect(snap.daily, isEmpty);
      await record(start: 2, end: 8);
      await coldStart();
      snap = await ReadingStats.load();
      expect(novelWordsReadCount(snap), 10);
      await record();
      expect(novelWordsReadCount(await ReadingStats.load()), 10);
      expect(
        () => snap.novelMeta['book']!.chapters['v1']!['0'] = '',
        throwsUnsupportedError,
      );
    },
  );

  test(
    'daily rereading counts again while book volume and chapter counts stay unique',
    () async {
      final today = DateTime.now();
      final tomorrow = DateTime(today.year, today.month, today.day + 1);
      await record(at: today, tags: ['奇幻', '奇幻']);
      await record(at: today);
      await coldStart();
      await record(at: tomorrow);
      await record(at: tomorrow);
      final snap = await ReadingStats.load();
      expect(novelWordsReadCount(snap), 20);
      expect(snap.novelDaily.values, everyElement(10));
      expect(snap.novelDaily.length, 2);
      expect(novelChaptersReadCount(snap), 1);
      expect(topNovelTags(snap).single.count, 1);
    },
  );

  test('当天只重读同一段也能补标签，冷启动不增加阅读量', () async {
    await record(entry: 1);
    await record();
    await coldStart();
    await record(tags: ['奇幻']);
    await coldStart();
    final snap = await ReadingStats.load();
    expect(topNovelTags(snap).single.name, '奇幻');
    expect(topNovelTags(snap).single.count, 2);
    expect(novelWordsReadCount(snap), 20);
    expect(snap.novelDaily.values.single, 20);
  });

  test('chapter and paragraph identity includes book and volume', () async {
    await Future.wait([
      record(tags: ['奇幻']),
      record(paragraph: 1),
      record(entry: 1),
      record(volume: 'v2'),
      record(book: 'other', tags: ['日常']),
      ReadingStats.recordImageLoad(pathWord: 'book', chapterUuid: '0'),
    ]);
    final snap = await ReadingStats.load();
    expect(novelWordsReadCount(snap), 50);
    expect(novelsReadCount(snap), 2);
    expect(novelVolumesReadCount(snap), 3);
    expect(novelChaptersReadCount(snap), 4);
    expect(pagesReadCount(snap), 1);
    expect(topNovelTags(snap).first.name, '奇幻');
    expect(topNovelTags(snap).first.count, 3);
  });

  test(
    'old comic JSON survives new novel records and both selective clears',
    () async {
      const old =
          '{"comicMeta":{"c":{"name":"旧漫画","tags":["校园"],"chapterImages":{"ch":12}}},"daily":{"2026-01-01":12},"since":"2026-01-01"}';
      platform.values['flutter.reading_stats_v1'] = old;
      await record();
      await coldStart();
      var snap = await ReadingStats.load();
      expect(pagesReadCount(snap), 12);
      expect(novelWordsReadCount(snap), 10);
      expect(snap.since, DateTime(2026));
      await ReadingStats.clear(novel: true);
      await coldStart();
      snap = await ReadingStats.load();
      expect(pagesReadCount(snap), 12);
      expect(snap.novelMeta, isEmpty);
      expect(snap.novelDaily, isEmpty);
      expect(snap.novelSince, isNull);
      await record();
      await ReadingStats.clear(novel: false);
      await coldStart();
      snap = await ReadingStats.load();
      expect(snap.comicMeta, isEmpty);
      expect(snap.daily, isEmpty);
      expect(snap.since, isNull);
      expect(novelWordsReadCount(snap), 10);
      await ReadingStats.clear();
      expect(
        jsonDecode(platform.values['flutter.reading_stats_v1']! as String),
        isNot(contains('novelHistoryInitialized')),
      );
      expect((await ReadingStats.load()).novelHistoryInitialized, isFalse);
      expect((await ReadingStats.load()).isEmpty, isTrue);
    },
  );

  for (final throws in [false, true]) {
    test(
      'failed ${throws ? 'throwing' : 'false'} write remains retryable across cold start',
      () async {
        await record();
        platform.beforeWrite = (key, value) async {
          if (key != 'flutter.reading_stats_v1') return;
          platform.failKey = 'reading_stats_v1';
          platform.failValue = value;
          platform.throwOnFailure = throws;
        };
        await expectLater(
          ReadingStats.flush(),
          throws ? throwsA(isA<PlatformException>()) : throwsStateError,
        );
        expect(platform.values['flutter.reading_stats_v1'], isNull);
        platform.beforeWrite = null;
        await coldStart();
        expect(novelWordsReadCount(await ReadingStats.load()), 10);
        await record();
        expect(novelWordsReadCount(await ReadingStats.load()), 10);
      },
    );
  }

  test('restore pause and generation invalidate pending records', () async {
    final pending = record();
    ReadingStats.reloadFromPrefs();
    await pending;
    expect((await ReadingStats.load()).isEmpty, isTrue);
    await ReadingStats.pauseForRestore();
    await record();
    expect((await ReadingStats.load()).isEmpty, isTrue);
    ReadingStats.resumeAfterRestore();
    await record();
    expect(novelWordsReadCount(await ReadingStats.load()), 10);
  });

  test(
    'continuous reports coalesce writes and persist no novel text',
    () async {
      for (var i = 0; i < 100; ++i) {
        await record(paragraph: i);
      }
      expect(
        platform.operations.where((op) => op.method.startsWith('set')),
        isEmpty,
      );
      await ReadingStats.flush();
      expect(
        platform.operations.where((op) => op.method.startsWith('set')).length,
        1,
      );
      final raw = platform.values['flutter.reading_stats_v1']! as String;
      expect(raw, isNot(contains('零一二三四五六七八九')));
      expect(jsonDecode(raw)['novelMeta']['book']['totalWords'], 1000);
    },
  );
}
