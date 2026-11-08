import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/reading_history.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await ReadingHistory.flush();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() async {
    await ReadingHistory.flush();
    SharedPreferences.setMockInitialValues({});
  });

  test('累计已读跨分组合并，回看旧章不改变已读集合或续读断点', () async {
    await ReadingHistory.save(
      pathWord: 'comic',
      group: ReadingHistory.defaultGroup,
      chapterUuid: 'latest',
      chapterName: '最新章',
    );
    await ReadingHistory.save(
      pathWord: 'comic',
      group: '单行本_group_archive',
      chapterUuid: 'extra',
      chapterName: '番外',
    );
    await ReadingHistory.save(
      pathWord: 'comic',
      group: ReadingHistory.defaultGroup,
      chapterUuid: 'old',
      chapterName: '旧章',
    );

    final chapters = await ReadingHistory.readChapterUuidsForComics([
      'comic',
      'comic',
      'missing',
    ]);

    expect(chapters, {
      'comic': {'latest', 'old', 'extra'},
    });
    final progress = await ReadingHistory.get(
      'comic',
      group: ReadingHistory.defaultGroup,
    );
    expect(progress?.chapterUuid, 'old');
    expect(progress?.readChapterUuids, {'latest', 'old'});
  });

  test('旧记录当前章也算已读，限定作品且跳过损坏记录', () async {
    SharedPreferences.setMockInitialValues({
      'reading_history_a': jsonEncode({
        'chapterUuid': 'legacy',
        'chapterName': '旧记录',
      }),
      'reading_history_a_group_default': jsonEncode({
        'chapterUuid': 'old',
        'readChapterUuids': ['new', 'old'],
      }),
      'reading_history_a_group_broken': '{',
      'reading_history_ab': jsonEncode({'chapterUuid': 'unrelated'}),
      'novel_reading_history_a': 'not-comic-history',
    });

    expect(await ReadingHistory.readChapterUuidsForComics(['a']), {
      'a': {'legacy', 'old', 'new'},
    });
    expect(await ReadingHistory.readChapterUuidsForComics([]), isEmpty);
    expect(
      await ReadingHistory.readChapterUuidsForComics(['missing']),
      isEmpty,
    );
  });

  test('读取重载后的持久化记录，删除全部分组后不保留已读纠正', () async {
    await ReadingHistory.save(
      pathWord: 'comic',
      group: 'extra',
      chapterUuid: 'latest',
      chapterName: '最新章',
    );
    await ReadingHistory.flush();
    final prefs = await SharedPreferences.getInstance();
    final saved = {for (final key in prefs.getKeys()) key: prefs.get(key)!};
    SharedPreferences.setMockInitialValues(saved);

    expect(await ReadingHistory.readChapterUuidsForComics(['comic']), {
      'comic': {'latest'},
    });
    await ReadingHistory.removeProgress('comic');
    expect(await ReadingHistory.readChapterUuidsForComics(['comic']), isEmpty);
  });
}
