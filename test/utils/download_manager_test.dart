import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/download_manager.dart';

void main() {
  group('DownloadedChapterSummary.failedIndices', () {
    test('round-trips non-empty failed indices', () {
      final original = DownloadedChapterSummary(
        chapterUuid: 'u-1',
        chapterName: '第1话',
        chapterGroup: 'g',
        chapterIndex: 1,
        chapterOrder: 2,
        pageCount: 200,
        savedAt: DateTime(2024, 1, 2, 3, 4, 5),
        failedIndices: const [3, 189, 190],
      );

      final restored = DownloadedChapterSummary.fromJson(original.toJson());

      expect(restored.failedIndices, [3, 189, 190]);
      expect(restored.isPartial, isTrue);
      expect(restored.pageCount, 200);
      expect(restored.chapterUuid, 'u-1');
    });

    test('empty failed indices => not partial', () {
      final original = DownloadedChapterSummary(
        chapterUuid: 'u-2',
        chapterName: '第2话',
        pageCount: 10,
        savedAt: DateTime(2024, 1, 1),
      );
      final restored = DownloadedChapterSummary.fromJson(original.toJson());

      expect(restored.failedIndices, isEmpty);
      expect(restored.isPartial, isFalse);
    });

    test('legacy manifest without failed_indices field defaults to empty', () {
      final legacyJson = <String, dynamic>{
        'chapter_uuid': 'u-3',
        'chapter_name': '第3话',
        'chapter_group': 'default',
        'chapter_index': 0,
        'chapter_order': 0,
        'page_count': 5,
        'saved_at': '2024-01-01T00:00:00.000',
      };
      final restored = DownloadedChapterSummary.fromJson(legacyJson);

      expect(restored.failedIndices, isEmpty);
      expect(restored.isPartial, isFalse);
      expect(restored.pageCount, 5);
    });

    test('sortOrder prefers chapterOrder when non-zero', () {
      final summary = DownloadedChapterSummary(
        chapterUuid: 'u',
        chapterName: 'n',
        pageCount: 1,
        savedAt: DateTime(2024, 1, 1),
        chapterIndex: 5,
        chapterOrder: 9,
      );
      expect(summary.sortOrder, 9);
    });
  });

  group('ChapterDownloadProgress', () {
    test('ratio is completed/total, failed defaults to 0', () {
      const progress = ChapterDownloadProgress(completed: 3, total: 10);
      expect(progress.ratio, closeTo(0.3, 1e-9));
      expect(progress.failed, 0);
    });

    test('zero total guards against division by zero', () {
      const progress = ChapterDownloadProgress(
        completed: 0,
        total: 0,
        failed: 2,
      );
      expect(progress.ratio, 0);
      expect(progress.failed, 2);
    });
  });
}
