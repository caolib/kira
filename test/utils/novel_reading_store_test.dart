import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/novel_reading_progress.dart';
import 'package:kira/utils/novel_reading_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

NovelReadingProgress _progress(String volumeId, int minute) =>
    NovelReadingProgress(
      pathWord: 'book',
      name: '小说',
      cover: '',
      volumeId: volumeId,
      volumeName: volumeId,
      chapterName: '',
      updatedAt: DateTime(2026, 11, 8, 0, minute),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => SharedPreferences.setMockInitialValues({}));

  test('回看旧卷仍保留最新卷已读，重建实例不改变续读位置', () async {
    final store = NovelReadingStore();
    await store.saveProgress(_progress('new', 1));
    await store.saveProgress(_progress('old', 2));

    final rebuilt = NovelReadingStore();
    expect(await rebuilt.readVolumeIdsForBooks(['book', 'book', 'missing']), {
      'book': {'new', 'old'},
    });
    expect((await rebuilt.readProgress('book'))?.volumeId, 'old');
    expect(await rebuilt.readVolumeIdsForBooks([]), isEmpty);
  });

  test('旧记录缺少累计集合时，以当前卷为已读，损坏记录不参与', () async {
    final legacy = _progress('new', 1).toJson()..remove('readVolumeIds');
    SharedPreferences.setMockInitialValues({
      'novel_reading_history_book': jsonEncode(legacy),
      'novel_reading_history_broken': '{',
      'reading_history_book': 'not-novel-history',
    });

    expect(
      await NovelReadingStore().readVolumeIdsForBooks([
        'book',
        'broken',
        'missing',
      ]),
      {
        'book': {'new'},
      },
    );
  });

  test('删除本地记录后重建实例不保留已读纠正', () async {
    final store = NovelReadingStore();
    await store.saveProgress(_progress('new', 1));
    await store.removeProgress('book');
    expect(await NovelReadingStore().readVolumeIdsForBooks(['book']), isEmpty);
  });
}
