/// UTF-16 字符区间，与 Flutter 排版偏移一致；持久化时只保存偏移，不存正文。
class NovelReadingRange {
  const NovelReadingRange(this.start, this.end);

  final int start;
  final int end;
}

/// 一段正文当天已展示的区间。顺序阅读通常只有一段；跳读保留空隙。
/// 仅遍历新覆盖部分，反复上报相同视口不会重新扫描文字。
class NovelReadingRanges {
  NovelReadingRanges([Iterable<NovelReadingRange> ranges = const []]) {
    for (final range in ranges) {
      if (range.start >= 0 && range.end > range.start) {
        _merge(range.start, range.end);
      }
    }
  }

  final _ranges = <NovelReadingRange>[];

  List<List<int>> toJson() => [
    for (final range in _ranges) [range.start, range.end],
  ];

  factory NovelReadingRanges.fromJson(Object? value) {
    final ranges = <NovelReadingRange>[];
    if (value is List) {
      for (final pair in value) {
        if (pair is! List || pair.length != 2) continue;
        final start = pair[0];
        final end = pair[1];
        if (start is int && end is int) {
          ranges.add(NovelReadingRange(start, end));
        }
      }
    }
    return NovelReadingRanges(ranges);
  }

  /// 字数按 Unicode 码点计，排除空白；含标点，英文按字母而非单词。
  int add(String text, int start, int end) {
    start = start.clamp(0, text.length);
    end = end.clamp(start, text.length);
    // 排版通常不会拆代理对；仍防御性对齐，避免生僻汉字算两次。
    if (start > 0 &&
        start < text.length &&
        _lowSurrogate(text.codeUnitAt(start))) {
      --start;
    }
    if (end > 0 && end < text.length && _lowSurrogate(text.codeUnitAt(end))) {
      ++end;
    }
    if (end <= start) return 0;
    if (_ranges.length == 1 &&
        _ranges.first.start <= start &&
        _ranges.first.end >= end) {
      return 0;
    }
    var cursor = start;
    var count = 0;
    for (final range in _ranges) {
      if (range.end <= cursor) continue;
      if (range.start >= end) break;
      if (range.start > cursor) count += _count(text, cursor, range.start);
      if (range.end > cursor) cursor = range.end;
      if (cursor >= end) break;
    }
    if (cursor < end) count += _count(text, cursor, end);
    _merge(start, end);
    return count;
  }

  void _merge(int start, int end) {
    var first = 0;
    while (first < _ranges.length && _ranges[first].end < start) {
      ++first;
    }
    var last = first;
    while (last < _ranges.length && _ranges[last].start <= end) {
      final range = _ranges[last];
      if (range.start < start) start = range.start;
      if (range.end > end) end = range.end;
      ++last;
    }
    _ranges.replaceRange(first, last, [NovelReadingRange(start, end)]);
  }

  static bool _lowSurrogate(int code) => code >= 0xdc00 && code <= 0xdfff;

  static int _count(String text, int start, int end) {
    var count = 0;
    for (var i = start; i < end; ++i) {
      final code = text.codeUnitAt(i);
      if (_whitespace(code)) continue;
      if (code >= 0xd800 &&
          code <= 0xdbff &&
          i + 1 < end &&
          _lowSurrogate(text.codeUnitAt(i + 1))) {
        ++i;
      }
      ++count;
    }
    return count;
  }

  static bool _whitespace(int code) =>
      (code >= 0x09 && code <= 0x0d) ||
      code == 0x20 ||
      code == 0x85 ||
      code == 0xa0 ||
      code == 0x1680 ||
      (code >= 0x2000 && code <= 0x200a) ||
      code == 0x2028 ||
      code == 0x2029 ||
      code == 0x202f ||
      code == 0x205f ||
      code == 0x3000 ||
      code == 0xfeff;
}
