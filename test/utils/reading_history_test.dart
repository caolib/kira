import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/reading_history.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // 待写队列是静态的：先冲刷掉上一个测试的残留，再换上干净的 prefs。
    await ReadingHistory.flush();
    SharedPreferences.setMockInitialValues({});
  });

  test('saves reading records separately by group', () async {
    await ReadingHistory.save(
      pathWord: 'comic-a',
      group: ReadingHistory.defaultGroup,
      chapterUuid: 'chapter-10',
      chapterName: '第10话',
      page: 3,
      totalPage: 12,
    );
    await ReadingHistory.save(
      pathWord: 'comic-a',
      group: 'tankobon',
      chapterUuid: 'volume-1',
      chapterName: '第1卷',
      page: 7,
      totalPage: 180,
    );

    final defaultRecord = await ReadingHistory.get(
      'comic-a',
      group: ReadingHistory.defaultGroup,
    );
    final tankobonRecord = await ReadingHistory.get(
      'comic-a',
      group: 'tankobon',
    );

    expect(defaultRecord?.chapterUuid, 'chapter-10');
    expect(defaultRecord?.page, 3);
    expect(tankobonRecord?.chapterUuid, 'volume-1');
    expect(tankobonRecord?.page, 7);
  });

  test('does not use legacy fallback for non-default groups', () async {
    await ReadingHistory.save(
      pathWord: 'comic-b',
      chapterUuid: 'chapter-2',
      chapterName: '第2话',
      page: 2,
      totalPage: 8,
    );

    final defaultRecord = await ReadingHistory.get(
      'comic-b',
      group: ReadingHistory.defaultGroup,
    );
    final otherRecord = await ReadingHistory.get('comic-b', group: 'other');

    expect(defaultRecord?.chapterUuid, 'chapter-2');
    expect(otherRecord, isNull);
  });

  test('latestForComic returns the most recently saved group record', () async {
    await ReadingHistory.save(
      pathWord: 'comic-c',
      group: ReadingHistory.defaultGroup,
      chapterUuid: 'chapter-1',
      chapterName: '第1话',
    );
    await Future<void>.delayed(const Duration(milliseconds: 1));
    await ReadingHistory.save(
      pathWord: 'comic-c',
      group: 'tankobon',
      chapterUuid: 'volume-1',
      chapterName: '第1卷',
    );

    final latest = await ReadingHistory.latestForComic('comic-c');

    expect(latest?.chapterUuid, 'volume-1');
    expect(latest?.group, 'tankobon');
    expect(latest?.updatedAt, isNotNull);
  });

  test('merged saves keep every chapter in the read set', () async {
    // 连续翻章会在一个防抖窗口内触发多次保存；中间章节不能被丢掉。
    for (final uuid in ['ch-1', 'ch-2', 'ch-3']) {
      await ReadingHistory.save(
        pathWord: 'comic-d',
        group: ReadingHistory.defaultGroup,
        chapterUuid: uuid,
        chapterName: uuid,
      );
    }

    final record = await ReadingHistory.get(
      'comic-d',
      group: ReadingHistory.defaultGroup,
    );

    expect(record?.chapterUuid, 'ch-3');
    expect(record?.readChapterUuids, containsAll(['ch-1', 'ch-2', 'ch-3']));
  });

  test(
    'get flushes pending writes so readers never see stale progress',
    () async {
      await ReadingHistory.save(
        pathWord: 'comic-e',
        group: ReadingHistory.defaultGroup,
        chapterUuid: 'ch-9',
        chapterName: '第9话',
        page: 4,
      );

      final prefs = await SharedPreferences.getInstance();
      // 防抖未到期，进度仍只在内存队列里。
      expect(prefs.getString('reading_history_comic-e'), isNull);

      final record = await ReadingHistory.get(
        'comic-e',
        group: ReadingHistory.defaultGroup,
      );

      expect(record?.chapterUuid, 'ch-9');
      expect(record?.page, 4);
      // 读取顺带把它落了盘。
      expect(prefs.getString('reading_history_comic-e'), isNotNull);
    },
  );

  test('flush persists pending progress immediately', () async {
    await ReadingHistory.save(
      pathWord: 'comic-f',
      group: ReadingHistory.defaultGroup,
      chapterUuid: 'ch-5',
      chapterName: '第5话',
      page: 2,
    );

    await ReadingHistory.flush();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('reading_history_comic-f'), isNotNull);
  });

  test('merged saves across different comics stay separate', () async {
    await ReadingHistory.save(
      pathWord: 'comic-g',
      group: ReadingHistory.defaultGroup,
      chapterUuid: 'g-1',
      chapterName: 'G1',
    );
    await ReadingHistory.save(
      pathWord: 'comic-h',
      group: ReadingHistory.defaultGroup,
      chapterUuid: 'h-1',
      chapterName: 'H1',
    );

    await ReadingHistory.flush();

    expect(
      (await ReadingHistory.get(
        'comic-g',
        group: ReadingHistory.defaultGroup,
      ))?.chapterUuid,
      'g-1',
    );
    expect(
      (await ReadingHistory.get(
        'comic-h',
        group: ReadingHistory.defaultGroup,
      ))?.chapterUuid,
      'h-1',
    );
  });
}
