/// 双页阅读的排版模型：把「章节 + 章节内页码」映射成「第几个跨页」。
///
/// 纯计算、不依赖 Flutter，便于单测。跨页只在同一章节内部成对，
/// 不做跨章拼合：章节末页不足两页时独占一个跨页，回翻/前进的边界
/// 因此与「一章一页」的单页模式完全一致。
typedef DoublePageAnchor = ({int chapterIndex, int imageIndex});

/// 双页阅读的分组规则。
///
/// [coverAlone] 为 true 时，每话第一页（漫画里通常是跨页彩图/封面）
/// 单独占一个跨页，其后从第 2 页起两页一组：`[0]`、`[1,2]`、`[3,4]`…
/// 为 false 时从第一页起两页一组：`[0,1]`、`[2,3]`…
///
/// [widePages] 登记「本身已经是横向跨页的大图」（宽高比不小于
/// [wideAspectThreshold] 的页面）。这类图片与相邻单页并排时会被压到
/// 半屏高，看起来明显偏小，因此一律独占一个跨页、铺满整屏；它前后的
/// 单页按剩余顺序继续两两配对，不会因为它的插入而错位。
class DoublePageLayout {
  DoublePageLayout._(
    this._groups,
    this._spreadStarts,
    this.spreadCount,
    this.coverAlone,
  );

  factory DoublePageLayout.fromPageCounts(
    List<int> pageCounts, {
    bool coverAlone = true,
    Set<(int, int)> widePages = const {},
  }) {
    final groups = <List<DoublePageAnchor>>[];
    final starts = <int>[];
    var total = 0;
    for (var ci = 0; ci < pageCounts.length; ci++) {
      starts.add(total);
      final chapterGroups = _groupsForChapter(
        chapterIndex: ci,
        pages: pageCounts[ci],
        coverAlone: coverAlone,
        widePages: widePages,
      );
      groups.addAll(chapterGroups);
      total += chapterGroups.length;
    }
    return DoublePageLayout._(
      List<List<DoublePageAnchor>>.unmodifiable([
        for (final group in groups) List<DoublePageAnchor>.unmodifiable(group),
      ]),
      List<int>.unmodifiable(starts),
      total,
      coverAlone,
    );
  }

  /// 视为「横向跨页大图」的宽高比下限（宽 / 高 ≥ 1.2 即明显横向）。
  /// 取略大于 1 的阈值：正方形或近方形的单页不会被误判成跨页大图。
  static const double wideAspectThreshold = 1.2;

  /// 每个跨页由哪些页面组成（1 或 2 页，同一章节内）。
  final List<List<DoublePageAnchor>> _groups;
  final List<int> _spreadStarts;

  /// 整个章节链的跨页总数。
  final int spreadCount;

  /// 每话第一页是否单独成页。
  final bool coverAlone;

  int get chapterCount => _spreadStarts.length;

  static List<List<DoublePageAnchor>> _groupsForChapter({
    required int chapterIndex,
    required int pages,
    required bool coverAlone,
    required Set<(int, int)> widePages,
  }) {
    final groups = <List<DoublePageAnchor>>[];
    if (pages <= 0) return groups;
    var index = 0;
    // 首图单页：它独占第一个跨页，其余页面从第 2 页起继续分组。
    if (coverAlone) {
      groups.add([(chapterIndex: chapterIndex, imageIndex: 0)]);
      index = 1;
    }
    while (index < pages) {
      final anchor = (chapterIndex: chapterIndex, imageIndex: index);
      final next = index + 1;
      // 横向大图（自身已是跨页）独占一屏；下一张单页紧接其后重新配对。
      if (widePages.contains((chapterIndex, index))) {
        groups.add([anchor]);
        index++;
        continue;
      }
      if (next < pages && !widePages.contains((chapterIndex, next))) {
        groups.add([anchor, (chapterIndex: chapterIndex, imageIndex: next)]);
        index += 2;
      } else {
        groups.add([anchor]);
        index++;
      }
    }
    return groups;
  }

  /// 指定章节占用的跨页数量。
  int spreadsInChapter(int chapterIndex) {
    if (chapterCount == 0) return 0;
    final ci = chapterIndex.clamp(0, chapterCount - 1);
    final start = _spreadStarts[ci];
    final end = ci + 1 < chapterCount ? _spreadStarts[ci + 1] : spreadCount;
    return end - start;
  }

  /// 「章节索引 + 章节内页码」所在的全局跨页序号。
  int spreadIndexOf(int chapterIndex, int imageIndex) {
    if (chapterCount == 0 || spreadCount <= 0) return 0;
    final ci = chapterIndex.clamp(0, chapterCount - 1);
    final search = (chapterIndex: ci, imageIndex: imageIndex);
    final chapterStart = _spreadStarts[ci];
    final chapterEnd = ci + 1 < chapterCount
        ? _spreadStarts[ci + 1]
        : spreadCount;
    for (var spread = chapterStart; spread < chapterEnd; spread++) {
      for (final anchor in _groups[spread]) {
        if (anchor.imageIndex == search.imageIndex) return spread;
      }
    }
    return chapterStart;
  }

  /// 全局跨页序号 -> 该跨页的首页（阅读顺序里的第一页）。
  DoublePageAnchor spreadStart(int spreadIndex) {
    if (chapterCount == 0 || spreadCount <= 0) {
      return (chapterIndex: 0, imageIndex: 0);
    }
    final target = spreadIndex.clamp(0, spreadCount - 1);
    return _groups[target].first;
  }

  /// 全局跨页序号 -> 组成该跨页的页面（1 或 2 页，同一章节内）。
  List<DoublePageAnchor> pagesInSpread(int spreadIndex) {
    if (chapterCount == 0 || spreadCount <= 0) return const [];
    return _groups[spreadIndex.clamp(0, spreadCount - 1)];
  }
}
