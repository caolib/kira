import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/reading_history.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
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
}
