import '../../models/chapter.dart';

/// 滚动模式列表里单个 item 的类型。
enum ChainScrollItemKind {
  header,
  prevHead,
  chapterDivider,
  image,
  tail,
  loadMore,
}

/// 滚动模式列表里的单个 item。
class ChainScrollItem {
  final ChainScrollItemKind kind;
  final ChapterDetail? chapter;
  final int? localIndex;
  final int? globalIndex;

  const ChainScrollItem._({
    required this.kind,
    this.chapter,
    this.localIndex,
    this.globalIndex,
  });

  factory ChainScrollItem.header() =>
      const ChainScrollItem._(kind: ChainScrollItemKind.header);
  factory ChainScrollItem.prevHead() =>
      const ChainScrollItem._(kind: ChainScrollItemKind.prevHead);
  factory ChainScrollItem.chapterDivider(ChapterDetail c) =>
      ChainScrollItem._(kind: ChainScrollItemKind.chapterDivider, chapter: c);
  factory ChainScrollItem.image(ChapterDetail c, int local, int global) =>
      ChainScrollItem._(
        kind: ChainScrollItemKind.image,
        chapter: c,
        localIndex: local,
        globalIndex: global,
      );
  factory ChainScrollItem.tail() =>
      const ChainScrollItem._(kind: ChainScrollItemKind.tail);
  factory ChainScrollItem.loadMore() =>
      const ChainScrollItem._(kind: ChainScrollItemKind.loadMore);
}

/// 章节链在滚动列表中的布局结果。
class ChainScrollLayout {
  const ChainScrollLayout({
    required this.items,
    required this.chapterImageStarts,
    required this.chapterScrollStarts,
    required this.imageCount,
  });

  static const empty = ChainScrollLayout(
    items: [],
    chapterImageStarts: [],
    chapterScrollStarts: [],
    imageCount: 0,
  );

  /// 列表 item：头部占位 + 各章[图片 + 分隔条(非末章)] + tail/loadMore。
  final List<ChainScrollItem> items;

  /// 每章第一张图的全局图片索引（跨章连续编号）。
  final List<int> chapterImageStarts;

  /// 每章第一张图对应的 item 索引。
  final List<int> chapterScrollStarts;

  /// 链中所有章节图片的累计数量。
  final int imageCount;
}

/// 按章节链推导滚动列表布局。
///
/// 纯函数，不触碰任何 State：连续阅读的「裁剪链首/链尾后现存 item 索引如何
/// 位移」全靠这里的结构决定，算错一项整屏内容就会跳位，因此单独抽出来便于
/// 单元测试。
///
/// [continuousReading] 为 false 时只渲染 [currentChapter]（缺省取链首）一章，
/// 且不含 prevHead 触发区。
ChainScrollLayout buildChainScrollLayout({
  required List<ChapterDetail> chain,
  required bool continuousReading,
  ChapterDetail? currentChapter,
}) {
  if (chain.isEmpty) return ChainScrollLayout.empty;

  final items = <ChainScrollItem>[];
  final chapterImageStarts = <int>[];
  final chapterScrollStarts = <int>[];

  // 链首没有上一话时是「已经是第一话」提示；连续阅读下否则是拼接上一话的
  // 触发区。两者都恰好占 1 项——裁剪链首后新链首会补上同类占位项，头部项数
  // 不变，这一点对索引位移的计算至关重要。
  if (chain.first.prev == null) {
    items.add(ChainScrollItem.header());
  } else if (continuousReading) {
    items.add(ChainScrollItem.prevHead());
  }

  var imageCursor = 0;
  if (continuousReading) {
    for (var ci = 0; ci < chain.length; ci++) {
      final chapter = chain[ci];
      chapterImageStarts.add(imageCursor);
      chapterScrollStarts.add(items.length);
      for (var i = 0; i < chapter.contents.length; i++) {
        items.add(ChainScrollItem.image(chapter, i, imageCursor + i));
      }
      imageCursor += chapter.contents.length;

      if (ci == chain.length - 1) {
        items.add(
          chapter.next == null
              ? ChainScrollItem.tail()
              : ChainScrollItem.loadMore(),
        );
      } else {
        items.add(ChainScrollItem.chapterDivider(chapter));
      }
    }
  } else {
    final chapter = currentChapter ?? chain.first;
    chapterImageStarts.add(0);
    chapterScrollStarts.add(items.length);
    for (var i = 0; i < chapter.contents.length; i++) {
      items.add(ChainScrollItem.image(chapter, i, i));
    }
    imageCursor = chapter.contents.length;
    items.add(ChainScrollItem.tail());
  }

  return ChainScrollLayout(
    items: items,
    chapterImageStarts: chapterImageStarts,
    chapterScrollStarts: chapterScrollStarts,
    imageCount: imageCursor,
  );
}
