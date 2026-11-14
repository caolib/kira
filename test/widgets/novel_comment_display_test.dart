import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/novel.dart';
import 'package:kira/widgets/novel_comment_display.dart';

void main() {
  NovelComment comment(
    String id,
    String userId,
    String text, {
    int replies = 0,
  }) => NovelComment(
    id: id,
    userId: userId,
    userName: userId,
    comment: text,
    count: replies,
  );

  test('沿用漫画规范化、多数原文、排序及同用户同文去重', () {
    final entries = groupNovelComments([
      comment('1', 'a', '普通'),
      comment('2', 'b', ' YES! '),
      comment('3', 'c', 'yes'),
      comment('4', 'd', 'yes'),
      comment('5', 'd', 'yes'),
      comment('6', 'e', '好看'),
      comment('7', 'f', '好看！'),
    ]);
    expect(entries.map((entry) => entry.count), [3, 2, 1]);
    expect(entries.map((entry) => entry.content), ['yes', '好看', '普通']);
    expect(entries.first.userNames(), ['b', 'c', 'd']);
  });

  test('有回复的评论不参与合并或同用户同文去重', () {
    final entries = groupNovelComments([
      comment('1', 'a', '一样', replies: 1),
      comment('2', 'a', '一样', replies: 2),
      comment('3', 'b', '一样'),
      comment('4', 'c', '一样'),
      comment('5', 'a', '一样'),
    ]);
    expect(entries.map((entry) => entry.count), [3, 1, 1]);
    expect(entries.skip(1).map((entry) => entry.primaryComment.id), ['1', '2']);
  });

  test('首次回复后按会话计数独立显示，合并组剩余成员重新计算', () {
    final entries = groupNovelComments([
      comment('1', 'a', '一样'),
      comment('2', 'b', '一样'),
      comment('3', 'c', '一样'),
    ], replyCountOf: (comment) => comment.id == '2' ? 1 : 0);
    expect(entries.map((entry) => entry.count), [2, 1]);
    expect(entries.last.primaryComment.id, '2');
  });

  test('楼中楼关闭合并时同文同用户也逐条保留', () {
    final entries = groupNovelComments([
      comment('1', 'a', '一样'),
      comment('2', 'a', '一样'),
      comment('3', 'b', '一样'),
    ], mergeEnabled: false);
    expect(entries, hasLength(3));
    expect(entries.every((entry) => !entry.isMerged), isTrue);
  });

  test('空内容不合并，同数量组保持出现顺序，头像最多五个', () {
    final entries = groupNovelComments([
      comment('1', 'a', ''),
      for (var i = 2; i <= 7; i++) comment('$i', 'u$i', '好看'),
      for (var i = 8; i <= 13; i++) comment('$i', 'u$i', '精彩'),
    ]);
    expect(entries.map((entry) => entry.content), ['好看', '精彩', '']);
    expect(entries.first.avatarComments(), hasLength(5));
  });
}
