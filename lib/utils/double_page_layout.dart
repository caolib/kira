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
class DoublePageLayout {
  DoublePageLayout._(
    this._pageCounts,
    this._spreadStarts,
    this.spreadCount,
    this.coverAlone,
  );

  factory DoublePageLayout.fromPageCounts(
    List<int> pageCounts, {
    bool coverAlone = true,
  }) {
    final starts = <int>[];
    var total = 0;
    for (final pages in pageCounts) {
      starts.add(total);
      total += _spreadsInChapter(pages, coverAlone);
    }
    return DoublePageLayout._(
      List<int>.unmodifiable(pageCounts),
      List<int>.unmodifiable(starts),
      total,
      coverAlone,
    );
  }

  final List<int> _pageCounts;
  final List<int> _spreadStarts;

  /// 整个章节链的跨页总数。
  final int spreadCount;

  /// 每话第一页是否单独成页。
  final bool coverAlone;

  int get chapterCount => _pageCounts.length;

  static int _spreadsInChapter(int pages, bool coverAlone) {
    if (pages <= 0) return 0;
    // 首图单页时它是第 1 个跨页，剩下的 pages - 1 页两两成组。
    return coverAlone ? 1 + pages ~/ 2 : (pages + 1) ~/ 2;
  }

  /// 指定章节占用的跨页数量。
  int spreadsInChapter(int chapterIndex) {
    if (_pageCounts.isEmpty) return 0;
    return _spreadsInChapter(
      _pageCounts[chapterIndex.clamp(0, _pageCounts.length - 1)],
      coverAlone,
    );
  }

  /// 章节内页码对应的跨页（章节内序号）。
  int _localSpread(int imageIndex, int pages) {
    if (!coverAlone) return imageIndex ~/ 2;
    if (imageIndex <= 0) return 0;
    return 1 + (imageIndex - 1) ~/ 2;
  }

  /// 章节内某跨页的第一页页码。
  int _localSpreadStart(int localSpread) {
    if (!coverAlone) return localSpread * 2;
    return localSpread <= 0 ? 0 : 1 + (localSpread - 1) * 2;
  }

  /// 「章节索引 + 章节内页码」所在的全局跨页序号。
  int spreadIndexOf(int chapterIndex, int imageIndex) {
    if (_pageCounts.isEmpty) return 0;
    final ci = chapterIndex.clamp(0, _pageCounts.length - 1);
    final pages = _pageCounts[ci];
    if (pages <= 0) return _spreadStarts[ci];
    final local = _localSpread(imageIndex.clamp(0, pages - 1), pages);
    return _spreadStarts[ci] + local;
  }

  /// 全局跨页序号 -> 该跨页的首页（阅读顺序里的第一页）。
  DoublePageAnchor spreadStart(int spreadIndex) {
    if (_pageCounts.isEmpty || spreadCount <= 0) {
      return (chapterIndex: 0, imageIndex: 0);
    }
    final target = spreadIndex.clamp(0, spreadCount - 1);
    final chapterIndex = _chapterForSpread(target);
    final pages = _pageCounts[chapterIndex];
    final local = target - _spreadStarts[chapterIndex];
    final imageIndex = _localSpreadStart(local).clamp(0, pages - 1);
    return (chapterIndex: chapterIndex, imageIndex: imageIndex);
  }

  /// 全局跨页序号 -> 组成该跨页的页面（1 或 2 页，同一章节内）。
  List<DoublePageAnchor> pagesInSpread(int spreadIndex) {
    if (_pageCounts.isEmpty || spreadCount <= 0) return const [];
    final start = spreadStart(spreadIndex);
    final pages = _pageCounts[start.chapterIndex];
    final anchors = <DoublePageAnchor>[
      (chapterIndex: start.chapterIndex, imageIndex: start.imageIndex),
    ];
    // 首图独占一页，不再并入第二张图。
    if (coverAlone && start.imageIndex == 0) return anchors;
    final second = start.imageIndex + 1;
    if (second < pages) {
      anchors.add((chapterIndex: start.chapterIndex, imageIndex: second));
    }
    return anchors;
  }

  /// 在「各章起始跨页」里找最后一个 `starts[i] <= value` 的下标。
  int _chapterForSpread(int spreadIndex) {
    var lo = 0;
    var hi = _spreadStarts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_spreadStarts[mid] <= spreadIndex) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }
}
