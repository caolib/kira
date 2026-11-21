import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/double_page_layout.dart';

void main() {
  group('DoublePageLayout 首图单页', () {
    final layout = DoublePageLayout.fromPageCounts([5, 4]);

    test('跨页数量按「首图单独 + 其余两页一组」计算', () {
      // 5 页：1 + 5 ~/ 2 = 3；4 页：1 + 4 ~/ 2 = 3。
      expect(layout.spreadsInChapter(0), 3);
      expect(layout.spreadsInChapter(1), 3);
      expect(layout.spreadCount, 6);
    });

    test('首图独占第一个跨页', () {
      expect(layout.pagesInSpread(0), [(chapterIndex: 0, imageIndex: 0)]);
      expect(layout.pagesInSpread(1), [
        (chapterIndex: 0, imageIndex: 1),
        (chapterIndex: 0, imageIndex: 2),
      ]);
      expect(layout.pagesInSpread(2), [
        (chapterIndex: 0, imageIndex: 3),
        (chapterIndex: 0, imageIndex: 4),
      ]);
    });

    test('章节末页独占一个跨页，不跨章拼合', () {
      // 第二章 4 页 = [0] [1,2] [3]，最后一页单独。
      expect(layout.pagesInSpread(3), [(chapterIndex: 1, imageIndex: 0)]);
      expect(layout.pagesInSpread(5), [(chapterIndex: 1, imageIndex: 3)]);
    });

    test('页码到跨页的映射可往返', () {
      for (var chapter = 0; chapter < layout.chapterCount; chapter++) {
        final pages = chapter == 0 ? 5 : 4;
        for (var image = 0; image < pages; image++) {
          final spread = layout.spreadIndexOf(chapter, image);
          final anchors = layout.pagesInSpread(spread);
          expect(
            anchors,
            contains((chapterIndex: chapter, imageIndex: image)),
            reason: '第 $chapter 话第 ${image + 1} 页应出现在跨页 $spread',
          );
          expect(layout.spreadStart(spread).chapterIndex, chapter);
        }
      }
    });

    test('单页章节只占一个跨页', () {
      final single = DoublePageLayout.fromPageCounts([1]);
      expect(single.spreadCount, 1);
      expect(single.pagesInSpread(0), [(chapterIndex: 0, imageIndex: 0)]);
    });
  });

  group('DoublePageLayout 无首图单页', () {
    final layout = DoublePageLayout.fromPageCounts([4, 3], coverAlone: false);

    test('从第一页起两页一组', () {
      expect(layout.spreadCount, 2 + 2);
      expect(layout.pagesInSpread(0), [
        (chapterIndex: 0, imageIndex: 0),
        (chapterIndex: 0, imageIndex: 1),
      ]);
      expect(layout.pagesInSpread(1), [
        (chapterIndex: 0, imageIndex: 2),
        (chapterIndex: 0, imageIndex: 3),
      ]);
      // 3 页的章节：[0,1] [2]
      expect(layout.pagesInSpread(2), [
        (chapterIndex: 1, imageIndex: 0),
        (chapterIndex: 1, imageIndex: 1),
      ]);
      expect(layout.pagesInSpread(3), [(chapterIndex: 1, imageIndex: 2)]);
    });
  });

  test('空链不产生跨页', () {
    final empty = DoublePageLayout.fromPageCounts(const []);
    expect(empty.spreadCount, 0);
    expect(empty.pagesInSpread(0), isEmpty);
    expect(empty.spreadStart(0), (chapterIndex: 0, imageIndex: 0));
  });
}
