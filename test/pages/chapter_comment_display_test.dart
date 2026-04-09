import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/chapter_comment.dart';
import 'package:kira/pages/chapter_comment_display.dart';

void main() {
  ChapterComment comment({
    required int id,
    required String userId,
    required String userName,
    required String content,
  }) {
    return ChapterComment(
      id: id,
      createAt: '2026-04-09 12:00:00',
      userId: userId,
      userName: userName,
      userAvatar: 'https://example.com/$userId.png',
      comment: content,
    );
  }

  test('merged comments move to top and are sorted by count descending', () {
    final entries = groupChapterComments([
      comment(id: 1, userId: 'u1', userName: 'A', content: '离谱'),
      comment(id: 2, userId: 'u2', userName: 'B', content: '神作'),
      comment(id: 3, userId: 'u3', userName: 'C', content: '神作'),
      comment(id: 4, userId: 'u4', userName: 'D', content: '哈哈'),
      comment(id: 5, userId: 'u5', userName: 'E', content: '神作'),
      comment(id: 6, userId: 'u6', userName: 'F', content: '哈哈'),
      comment(id: 7, userId: 'u7', userName: 'G', content: '哈哈'),
      comment(id: 8, userId: 'u8', userName: 'H', content: '哈哈'),
    ]);

    expect(entries, hasLength(3));
    expect(entries[0].content, '哈哈');
    expect(entries[0].count, 4);
    expect(entries[0].isMerged, isTrue);
    expect(entries[1].content, '神作');
    expect(entries[1].count, 3);
    expect(entries[1].isMerged, isTrue);
    expect(entries[2].content, '离谱');
    expect(entries[2].count, 1);
    expect(entries[2].isMerged, isFalse);
  });

  test('merged comments with same count keep first appearance order', () {
    final entries = groupChapterComments([
      comment(id: 1, userId: 'u1', userName: 'A', content: '神作'),
      comment(id: 2, userId: 'u2', userName: 'B', content: '离谱'),
      comment(id: 3, userId: 'u3', userName: 'C', content: '神作'),
      comment(id: 4, userId: 'u4', userName: 'D', content: '神作'),
      comment(id: 5, userId: 'u5', userName: 'E', content: '离谱'),
      comment(id: 6, userId: 'u6', userName: 'F', content: '离谱'),
    ]);

    expect(entries, hasLength(2));
    expect(entries.first.content, '神作');
    expect(entries.first.count, 3);
    expect(entries.first.isMerged, isTrue);
    expect(entries.last.content, '离谱');
    expect(entries.last.count, 3);
    expect(entries.last.isMerged, isTrue);
  });

  test('merge avatars are deduplicated by user and capped at five', () {
    final entry = groupChapterComments([
      comment(id: 1, userId: 'u1', userName: 'A', content: '哈哈哈'),
      comment(id: 2, userId: 'u1', userName: 'A', content: '哈哈哈'),
      comment(id: 3, userId: 'u2', userName: 'B', content: '哈哈哈'),
      comment(id: 4, userId: 'u3', userName: 'C', content: '哈哈哈'),
      comment(id: 5, userId: 'u4', userName: 'D', content: '哈哈哈'),
      comment(id: 6, userId: 'u5', userName: 'E', content: '哈哈哈'),
      comment(id: 7, userId: 'u6', userName: 'F', content: '哈哈哈'),
    ]).single;

    expect(entry.count, 7);
    expect(entry.avatarComments(), hasLength(5));
    expect(
      entry.avatarComments().map((comment) => comment.userId).toList(),
      ['u1', 'u2', 'u3', 'u4', 'u5'],
    );
  });

  test('comment content must match exactly to be merged', () {
    final entries = groupChapterComments([
      comment(id: 1, userId: 'u1', userName: 'A', content: '一样'),
      comment(id: 2, userId: 'u2', userName: 'B', content: '一样 '),
    ]);

    expect(entries, hasLength(2));
    expect(entries[0].count, 1);
    expect(entries[1].count, 1);
  });
}
