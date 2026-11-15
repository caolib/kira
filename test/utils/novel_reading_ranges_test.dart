import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/novel_reading_ranges.dart';

void main() {
  test(
    'overlap merges, gaps stay unread, duplicate ranges do no extra counting',
    () {
      final ranges = NovelReadingRanges();
      const text = '0123456789';
      expect(ranges.add(text, 0, 3), 3);
      expect(ranges.add(text, 7, 10), 3);
      expect(ranges.toJson(), [
        [0, 3],
        [7, 10],
      ]);
      expect(ranges.add(text, 2, 8), 4);
      expect(ranges.toJson(), [
        [0, 10],
      ]);
      expect(ranges.add(text, 0, 10), 0);
      expect(ranges.add(text, 4, 7), 0);
    },
  );

  test('counts unicode codepoints and punctuation, excludes whitespace', () {
    const text = '中 文\tA。\n𠮷　 ';
    final ranges = NovelReadingRanges();
    expect(ranges.add(text, 0, text.length), 5);
    expect(ranges.add(text, 0, text.length), 0);
    final restored = NovelReadingRanges.fromJson(ranges.toJson());
    expect(restored.add(text, 0, text.length), 0);
  });

  test('split surrogate pairs are aligned and counted only once', () {
    final ranges = NovelReadingRanges();
    expect(ranges.add('𠮷文', 0, 1), 1);
    expect(ranges.add('𠮷文', 1, 2), 0);
    expect(ranges.add('𠮷文', 2, 3), 1);
    expect(ranges.toJson(), [
      [0, 3],
    ]);
  });

  test('invalid persisted ranges are ignored and valid ranges normalized', () {
    final ranges = NovelReadingRanges.fromJson([
      [7, 10],
      [-1, 5],
      [3, 1],
      ['0', 9],
      null,
      [1],
      [0, 4],
      [3, 7],
    ]);
    expect(ranges.toJson(), [
      [0, 10],
    ]);
    expect(ranges.add('0123456789', -10, 99), 0);
  });

  test('random ranges match a per-character reference set', () {
    final random = Random(7);
    const text = '零一二三四五六七八九';
    for (var run = 0; run < 100; ++run) {
      final reference = <int>{};
      final ranges = NovelReadingRanges();
      for (var i = 0; i < 100; ++i) {
        final start = random.nextInt(text.length + 1);
        final end = start + random.nextInt(text.length - start + 1);
        var expected = 0;
        for (var j = start; j < end; ++j) {
          if (reference.add(j)) ++expected;
        }
        expect(ranges.add(text, start, end), expected);
      }
    }
  });
}
