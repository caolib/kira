import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/chapter.dart';
import 'package:kira/pages/reader/chain_scroll_layout.dart';

/// 滚动 item 的稳定标识：链首裁剪前后同一标识必须指向同一内容。
String itemId(ChainScrollItem item) => switch (item.kind) {
  ChainScrollItemKind.header => 'header',
  ChainScrollItemKind.prevHead => 'prevHead',
  ChainScrollItemKind.chapterDivider => 'div:${item.chapter!.uuid}',
  ChainScrollItemKind.image => 'img:${item.chapter!.uuid}#${item.localIndex}',
  ChainScrollItemKind.tail => 'tail',
  ChainScrollItemKind.loadMore => 'loadMore',
};

ChapterDetail chapter({
  required String uuid,
  required int pages,
  String? prev,
  String? next,
}) {
  return ChapterDetail(
    uuid: uuid,
    index: 0,
    name: uuid,
    prev: prev,
    next: next,
    contents: List.generate(pages, (i) => '$uuid-$i.jpg', growable: false),
  );
}

/// B/C/D 三话连读，各 [pages] 页，前后都还有别的话。
List<ChapterDetail> midChain({int pages = 3}) => [
  chapter(uuid: 'B', pages: pages, prev: 'A', next: 'C'),
  chapter(uuid: 'C', pages: pages, prev: 'B', next: 'D'),
  chapter(uuid: 'D', pages: pages, prev: 'C', next: 'E'),
];

ChainScrollLayout continuous(List<ChapterDetail> chain) =>
    buildChainScrollLayout(chain: chain, continuousReading: true);

void main() {
  group('buildChainScrollLayout 结构', () {
    test('连续阅读：头部占位 + 各章[图片 + 分隔条] + loadMore', () {
      final layout = continuous(midChain());

      expect(layout.items.map(itemId), [
        'prevHead',
        'img:B#0',
        'img:B#1',
        'img:B#2',
        'div:B',
        'img:C#0',
        'img:C#1',
        'img:C#2',
        'div:C',
        'img:D#0',
        'img:D#1',
        'img:D#2',
        'loadMore',
      ]);
      expect(layout.chapterScrollStarts, [1, 5, 9]);
      expect(layout.chapterImageStarts, [0, 3, 6]);
      expect(layout.imageCount, 9);
    });

    test('链首即漫画首话时用 header，链尾无下一话时用 tail', () {
      final layout = continuous([
        chapter(uuid: 'A', pages: 2, next: 'B'),
        chapter(uuid: 'B', pages: 1, prev: 'A'),
      ]);

      expect(layout.items.map(itemId), [
        'header',
        'img:A#0',
        'img:A#1',
        'div:A',
        'img:B#0',
        'tail',
      ]);
      expect(layout.chapterScrollStarts, [1, 4]);
    });

    test('非连续阅读：只渲染当前章，且不含 prevHead 触发区', () {
      final chain = [chapter(uuid: 'C', pages: 2, prev: 'B', next: 'D')];
      final layout = buildChainScrollLayout(
        chain: chain,
        continuousReading: false,
      );

      expect(layout.items.map(itemId), ['img:C#0', 'img:C#1', 'tail']);
      expect(layout.chapterScrollStarts, [0]);
      expect(layout.imageCount, 2);
    });

    test('空链返回空布局', () {
      final layout = continuous(const []);

      expect(layout.items, isEmpty);
      expect(layout.chapterScrollStarts, isEmpty);
      expect(layout.imageCount, 0);
    });
  });

  group('裁剪链首后的索引位移', () {
    // 阅读器裁掉窗口外的前一话后，只能靠「重建列表 + 视口锚点还原」保持画面
    // 不动。还原用的位移必须让每个幸存 item 精确落回原位，差一项就是整屏跳位。
    test('位移 = 当前章起始 item 索引的新旧差值，幸存 item 全部精确归位', () {
      const pruneCount = 1;
      // 与 midChain 的默认页数不同，确保这里验的是参数化后的位移而非碰巧相等。
      const pages = 4;
      final before = continuous(midChain(pages: pages));
      // 裁掉 B，当前章仍是 D（chainIndex 2 → 1）。
      final after = continuous(midChain(pages: pages).sublist(pruneCount));

      final shift =
          after.chapterScrollStarts[1] - before.chapterScrollStarts[2];
      // 被删掉的只有 B 的 3 张图 + 1 条分隔条。
      expect(shift, -(pages + 1));

      final beforeIds = before.items.map(itemId).toList();
      final afterIds = after.items.map(itemId).toList();
      for (
        var old = before.chapterScrollStarts[pruneCount];
        old < beforeIds.length;
        old++
      ) {
        expect(
          afterIds[old + shift],
          beforeIds[old],
          reason: '旧索引 $old (${beforeIds[old]}) 应落到 ${old + shift}',
        );
      }
    });

    test('头部占位项是被替换而不是被删除，数量恒为 1', () {
      // 按「删掉的 item 数」折算位移会多减这一项：
      // before.chapterScrollStarts[1] == 5，而真实位移是 -4。
      final before = continuous(midChain());
      expect(before.items.first.kind, ChainScrollItemKind.prevHead);
      expect(before.chapterScrollStarts[1], 5);

      // 链首换成漫画首话（header）后裁剪，新链首仍有 1 个头部占位项。
      final headBefore = continuous([
        chapter(uuid: 'A', pages: 3, next: 'B'),
        chapter(uuid: 'B', pages: 3, prev: 'A', next: 'C'),
        chapter(uuid: 'C', pages: 3, prev: 'B', next: 'D'),
      ]);
      expect(headBefore.items.first.kind, ChainScrollItemKind.header);

      final headAfter = continuous([
        chapter(uuid: 'B', pages: 3, prev: 'A', next: 'C'),
        chapter(uuid: 'C', pages: 3, prev: 'B', next: 'D'),
      ]);
      expect(headAfter.items.first.kind, ChainScrollItemKind.prevHead);
      expect(headAfter.chapterScrollStarts[0], 1);
      expect(
        headAfter.chapterScrollStarts[1] - headBefore.chapterScrollStarts[2],
        -4,
      );
    });

    test('各章页数不同也不影响位移精度', () {
      final before = continuous([
        chapter(uuid: 'B', pages: 7, prev: 'A', next: 'C'),
        chapter(uuid: 'C', pages: 2, prev: 'B', next: 'D'),
        chapter(uuid: 'D', pages: 5, prev: 'C', next: 'E'),
      ]);
      final after = continuous([
        chapter(uuid: 'C', pages: 2, prev: 'B', next: 'D'),
        chapter(uuid: 'D', pages: 5, prev: 'C', next: 'E'),
      ]);

      final shift =
          after.chapterScrollStarts[1] - before.chapterScrollStarts[2];
      expect(shift, -8); // B 的 7 张图 + 1 条分隔条

      final beforeIds = before.items.map(itemId).toList();
      final afterIds = after.items.map(itemId).toList();
      for (
        var old = before.chapterScrollStarts[1];
        old < beforeIds.length;
        old++
      ) {
        expect(afterIds[old + shift], beforeIds[old]);
      }
    });
  });
}
