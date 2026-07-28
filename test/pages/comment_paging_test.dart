import 'package:flutter_test/flutter_test.dart';
import 'package:kira/pages/chapter_comments/comment_paging.dart';
import 'package:kira/utils/comment_text.dart';

class _Item {
  const _Item(this.id, this.text);
  final int id;
  final String text;
}

void main() {
  group('appendDedupedById', () {
    test('appends items not already present', () {
      final merged = appendDedupedById(
        const [_Item(1, 'a'), _Item(2, 'b')],
        const [_Item(3, 'c')],
        (item) => item.id,
      );

      expect(merged.map((e) => e.id), [1, 2, 3]);
    });

    test('skips items whose id is already in the list', () {
      final merged = appendDedupedById(
        const [_Item(1, 'a'), _Item(2, 'b')],
        const [_Item(2, 'dupe'), _Item(3, 'c')],
        (item) => item.id,
      );

      expect(merged.map((e) => e.id), [1, 2, 3]);
      // 保留原有条目，不被后来的同 id 覆盖
      expect(merged[1].text, 'b');
    });

    test('drops duplicates inside the incoming page itself', () {
      // 服务端在分页边界重复返回同一条评论时，旧写法会把它放进去。
      final merged = appendDedupedById(
        const [_Item(1, 'a')],
        const [_Item(2, 'b'), _Item(2, 'b again')],
        (item) => item.id,
      );

      expect(merged.map((e) => e.id), [1, 2]);
    });

    test('returns a copy of existing when incoming is empty', () {
      const existing = [_Item(1, 'a')];
      final merged = appendDedupedById(existing, const [], (item) => item.id);

      expect(merged.map((e) => e.id), [1]);
      expect(identical(merged, existing), isFalse);
    });

    test('preserves order of both sides', () {
      final merged = appendDedupedById(
        const [_Item(5, 'e'), _Item(3, 'c')],
        const [_Item(9, 'i'), _Item(1, 'a')],
        (item) => item.id,
      );

      expect(merged.map((e) => e.id), [5, 3, 9, 1]);
    });
  });

  group('CommentText', () {
    test('counts by runes so emoji are one character', () {
      // '😀' 在 UTF-16 里占两个单元，按 String.length 会被算成 2。
      expect(CommentText.lengthOf('😀'), 1);
      expect('😀'.length, 2);
    });

    test('ignores surrounding whitespace', () {
      expect(CommentText.lengthOf('  abc  '), 3);
    });

    test('rejects text shorter than the minimum', () {
      expect(CommentText.isValid('ab'), isFalse);
      expect(CommentText.isValid('abc'), isTrue);
    });

    test('rejects text longer than the maximum', () {
      expect(CommentText.isValid('a' * CommentText.maxLength), isTrue);
      expect(CommentText.isValid('a' * (CommentText.maxLength + 1)), isFalse);
    });

    test('whitespace-only text is invalid', () {
      expect(CommentText.isValid('     '), isFalse);
    });
  });
}
