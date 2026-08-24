import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/comic_comment.dart';
import 'package:kira/pages/comic_comment_display.dart';

void main() {
  ComicComment comment({
    required int id,
    required String userId,
    required String userName,
    required String content,
  }) {
    return ComicComment(
      id: id,
      createAt: '2026-04-09 12:00:00',
      userId: userId,
      userName: userName,
      userAvatar: 'https://example.com/$userId.png',
      comment: content,
      replyCount: 0,
    );
  }

  test('merged comments move to top and are sorted by count descending', () {
    final entries = groupComicComments([
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
    final entries = groupComicComments([
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

  test('exact duplicate comments from the same user are kept once', () {
    final entries = groupComicComments([
      comment(id: 1, userId: 'u1', userName: 'A', content: '哈哈哈'),
      comment(id: 2, userId: 'u1', userName: 'A', content: '哈哈哈'),
      comment(id: 3, userId: 'u2', userName: 'B', content: '哈哈哈'),
      comment(id: 4, userId: 'u3', userName: 'C', content: '哈哈哈'),
      comment(id: 5, userId: 'u4', userName: 'D', content: '哈哈哈'),
      comment(id: 6, userId: 'u5', userName: 'E', content: '哈哈哈'),
      comment(id: 7, userId: 'u6', userName: 'F', content: '哈哈哈'),
    ]);

    expect(entries, hasLength(1));
    expect(entries.single.count, 6);
    expect(entries.single.isMerged, isTrue);
  });

  test('merge avatars are deduplicated by user and capped at five', () {
    final entries = groupComicComments([
      comment(id: 1, userId: 'u1', userName: 'A', content: '哈哈哈'),
      comment(id: 2, userId: 'u2', userName: 'B', content: '哈哈哈'),
      comment(id: 3, userId: 'u3', userName: 'C', content: '哈哈哈'),
      comment(id: 4, userId: 'u4', userName: 'D', content: '哈哈哈'),
      comment(id: 5, userId: 'u5', userName: 'E', content: '哈哈哈'),
      comment(id: 6, userId: 'u6', userName: 'F', content: '哈哈哈'),
    ]);
    final entry = entries.singleWhere((item) => item.isMerged);

    expect(entries, hasLength(1));
    expect(entry.count, 6);
    expect(entry.avatarComments(), hasLength(5));
    expect(entry.avatarComments().map((comment) => comment.userId).toList(), [
      'u1',
      'u2',
      'u3',
      'u4',
      'u5',
    ]);
  });

  test('comments with trailing spaces are merged', () {
    final entries = groupComicComments([
      comment(id: 1, userId: 'u1', userName: 'A', content: '一样'),
      comment(id: 2, userId: 'u2', userName: 'B', content: '一样 '),
    ]);

    expect(entries, hasLength(1));
    expect(entries[0].count, 2);
    expect(entries[0].isMerged, isTrue);
  });

  test(
    'comments with punctuation differences are merged with majority text',
    () {
      final entries = groupComicComments([
        comment(id: 1, userId: 'u1', userName: 'A', content: '我操'),
        comment(id: 2, userId: 'u2', userName: 'B', content: '我操！'),
        comment(id: 3, userId: 'u3', userName: 'C', content: '我操'),
        comment(id: 4, userId: 'u4', userName: 'D', content: '我操！'),
        comment(id: 5, userId: 'u5', userName: 'E', content: '我操'),
      ]);

      expect(entries, hasLength(1));
      expect(entries[0].count, 5);
      expect(entries[0].content, '我操'); // 多数优先
    },
  );

  test('userNames are deduplicated and in first-appearance order', () {
    final entries = groupComicComments([
      comment(id: 1, userId: 'u1', userName: 'Alice', content: '好评'),
      comment(id: 2, userId: 'u2', userName: 'Bob', content: '好评'),
      comment(id: 3, userId: 'u1', userName: 'Alice', content: '好评'),
      comment(id: 4, userId: 'u3', userName: 'Charlie', content: '好评'),
    ]);
    final entry = entries.singleWhere((item) => item.isMerged);

    expect(entry.userNames(), ['Alice', 'Bob', 'Charlie']);
  });

  test('empty comments are treated as unmergeable single entries', () {
    final entries = groupComicComments([
      comment(id: 1, userId: 'u1', userName: 'A', content: ''),
      comment(id: 2, userId: 'u2', userName: 'B', content: '神作'),
      comment(id: 3, userId: 'u3', userName: 'C', content: '神作'),
    ]);

    // '神作' is merged (count 2), empty comment stays single.
    expect(entries, hasLength(2));
    expect(entries[0].isMerged, isTrue); // merged '神作' goes first
    expect(entries[0].count, 2);
    expect(entries[1].isMerged, isFalse); // empty stays single
    expect(entries[1].content, '');
  });
}
