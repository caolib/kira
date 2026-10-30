import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/novel_reader_settings.dart';
import '../../theme/app_spacing.dart';
import 'novel_reader_dialogue.dart';
import 'novel_reader_document.dart';

/// 段落显示文本：空行渲染为单个空格，空章节显示占位文案（与滚动模式一致）。
/// 分页测量与页面渲染共用，保证两处排版输入一致。
String novelParagraphDisplayText(
  NovelReaderParagraph paragraph,
  String emptyChapterText, {
  NovelDialoguePresentation? dialogue,
}) {
  if (paragraph.entry.paragraphs.isEmpty) return emptyChapterText;
  final display = novelParagraphDialogue(paragraph, dialogue)?.text;
  return display ?? (paragraph.text.isEmpty ? ' ' : paragraph.text);
}

/// 一个页面片段：某段落在本页显示的行区间 [startLine, endLine)，
/// 以及对应的字符区间 [startOffset, endOffset)，渲染时按字符区间取子串。
@immutable
class NovelPageSlice {
  const NovelPageSlice({
    required this.itemIndex,
    required this.startLine,
    required this.endLine,
    required this.startOffset,
    required this.endOffset,
    this.hasTitle = false,
  });

  final int itemIndex;
  final int startLine;
  final int endLine;
  final int startOffset;
  final int endOffset;

  /// 本片段是章节首段且带章节标题（渲染在片段上方）。
  final bool hasTitle;
}

/// 一页：若干按顺序排列的片段。
class NovelPaginatedPage {
  NovelPaginatedPage(this.slices);

  final List<NovelPageSlice> slices;
}

/// 分页的全部排版输入。任何一项变化都需要重新分页。
@immutable
class NovelPaginationSpec {
  const NovelPaginationSpec({
    required this.textStyle,
    required this.titleStyle,
    required this.textScaler,
    required this.textDirection,
    required this.size,
    required this.viewportHeight,
    required this.contentTopInset,
    required this.paragraphSpacing,
    required this.titleSpacing,
    required this.emptyChapterText,
    this.dialogue,
  });

  /// 正文样式（含 fontSize / height / color）。
  final TextStyle textStyle;

  /// 章节标题样式（headlineSmall）。
  final TextStyle titleStyle;
  final TextScaler textScaler;
  final TextDirection textDirection;

  /// 正文可用区域（已扣除系统栏 inset 与横向留白）。
  final Size size;

  /// 整屏高度（含系统栏 inset）。锚点的 alignment 与滚动模式同义：
  /// 段落 widget 顶相对整屏顶的比例（负值表示顶部在屏幕上方外）。
  final double viewportHeight;

  /// 内容区顶部 inset（contentPadding.top）。页首段落 widget 顶的
  /// 屏幕位置 = contentTopInset + 页内深度。
  final double contentTopInset;

  final double paragraphSpacing;

  /// 章节标题上下的固定留白（与滚动模式的 AppSpacing.xxl 一致）。
  final double titleSpacing;
  final String emptyChapterText;
  final NovelDialoguePresentation? dialogue;
}

/// 单个段落的测量结果：只保留行高、行边界与累计高度，
/// 不保留 TextPainter（避免整卷布局缓存占用内存）。
class NovelTextMetrics {
  const NovelTextMetrics({
    required this.lineHeights,
    required this.lineOffsets,
    required this.lineTops,
  });

  final List<double> lineHeights;

  /// 每行起始字符偏移（长度 = 行数 + 1，末项为文本长度）。
  final List<int> lineOffsets;

  /// 每行顶部相对段落顶部的偏移（长度 = 行数）。
  final List<double> lineTops;

  double get height => lineTops.isEmpty ? 0 : lineTops.last + lineHeights.last;

  int get lineCount => lineHeights.length;
}

class _Checkpoint {
  const _Checkpoint({
    required this.pageIndex,
    required this.slices,
    required this.usedHeight,
  });

  final int pageIndex;
  final int slices;
  final double usedHeight;
}

/// 增量分页器：按目录顺序逐段测量并切页，可在任意段落边界检查点续算。
///
/// 页面是「前缀稳定」的：一旦某段落被分页覆盖，它所在页与页内位置不再变化，
/// 除非从更早的检查点重建。段落变化可从受影响段落重建（[rebuildFrom]），
/// 字体/尺寸变化则整体重建（[reset]）。
class NovelReaderPaginator {
  NovelReaderPaginator({required this.document, required this.spec}) {
    _resetPages();
  }

  final NovelTextDocument document;
  final NovelPaginationSpec spec;

  /// 已构建的页（`pages.last` 是正在填充的当前页）。
  final List<NovelPaginatedPage> pages = [];

  final Map<int, NovelTextMetrics> _metrics = {};
  final Map<int, int> _itemStartPage = {};
  final Map<int, _Checkpoint> _checkpoints = {};
  final Map<int, double> _titleHeights = {};

  double _usedHeight = 0;
  int _nextItem = 0;

  /// 已完整分页（所有段落都已覆盖）。
  bool get complete => _nextItem >= document.itemCount;

  /// 已经分页覆盖到的段落数（含正在填充的当前页）。
  int get builtItems => _nextItem;

  void _resetPages() {
    pages
      ..clear()
      ..add(NovelPaginatedPage(<NovelPageSlice>[]));
    _usedHeight = 0;
    _nextItem = 0;
    _itemStartPage.clear();
    _checkpoints.clear();
  }

  /// 整体重建（字体/行距/尺寸变化）。
  void reset() {
    _metrics.clear();
    _titleHeights.clear();
    _resetPages();
  }

  /// 从 [itemIndex] 的检查点重建，仅重新分页该段落及其后续内容。
  ///
  /// [invalidate] 里列出的其他变化段落会一并丢弃测量缓存，
  /// 避免同批变化沿用旧排版、与渲染不一致。
  void rebuildFrom(int itemIndex, {Iterable<int>? invalidate}) {
    final checkpoint = _checkpoints[itemIndex];
    if (checkpoint == null) {
      reset();
      return;
    }
    _metrics.remove(itemIndex);
    if (invalidate != null) {
      for (final item in invalidate) {
        if (item != itemIndex) _metrics.remove(item);
      }
    }
    _itemStartPage.removeWhere((item, _) => item >= itemIndex);
    _checkpoints.removeWhere((item, _) => item >= itemIndex);
    _titleHeights.remove(itemIndex);
    pages.removeRange(checkpoint.pageIndex + 1, pages.length);
    pages.last.slices.removeRange(checkpoint.slices, pages.last.slices.length);
    _usedHeight = checkpoint.usedHeight;
    _nextItem = itemIndex;
  }

  /// 继续分页至多 [maxItems] 个段落。返回是否仍有剩余段落。
  bool buildMore({int maxItems = 8}) {
    var processed = 0;
    while (_nextItem < document.itemCount && processed < maxItems) {
      _placeItem(_nextItem);
      _nextItem++;
      processed++;
    }
    if (complete) _pruneEmptyTail();
    return !complete;
  }

  void _pruneEmptyTail() {
    while (pages.length > 1 && pages.last.slices.isEmpty) {
      pages.removeLast();
    }
  }

  double _titleHeightFor(NovelReaderParagraph paragraph) {
    if (paragraph.paragraphIndex != 0 || paragraph.entry.name.isEmpty) {
      return 0;
    }
    return _titleHeights.putIfAbsent(
      paragraph.entry.entryIndex,
      () => _measureText(paragraph.entry.name, spec.titleStyle).height,
    );
  }

  /// 段落的标题块高度（无标题/非首段为 0）：标题高 + 上下留白。
  double _titleBlockFor(NovelReaderParagraph paragraph) {
    final height = _titleHeightFor(paragraph);
    return height == 0 ? 0 : height + spec.titleSpacing * 2;
  }

  void _placeItem(int itemIndex) {
    final paragraph = document.paragraphAt(itemIndex);
    final checkpoint = _Checkpoint(
      pageIndex: pages.length - 1,
      slices: pages.last.slices.length,
      usedHeight: _usedHeight,
    );
    _checkpoints[itemIndex] = checkpoint;
    final metrics = _metrics.putIfAbsent(itemIndex, () => _measure(paragraph));

    // 章节标题：标题与其后至少一行正文同页，放不下则另起一页。
    final titleBlock = _titleBlockFor(paragraph);
    if (titleBlock > 0) {
      final firstLine = metrics.lineHeights.isEmpty
          ? 0.0
          : metrics.lineHeights.first;
      if (_usedHeight > 0 &&
          _usedHeight + titleBlock + firstLine >
              spec.size.height - _pageHeightSafety) {
        _newPage();
      }
      _usedHeight += titleBlock;
    }

    var line = 0;
    while (line < metrics.lineCount) {
      var fit = 0;
      var height = 0.0;
      final available = spec.size.height - _usedHeight - _pageHeightSafety;
      while (line + fit < metrics.lineCount &&
          height + metrics.lineHeights[line + fit] <= available + _epsilon) {
        height += metrics.lineHeights[line + fit];
        fit++;
      }
      if (fit == 0) {
        // 单行都放不下：空页仍放不下说明该行高于整页，强制放一行避免死循环。
        if (_usedHeight <= 0) {
          fit = 1;
          height = metrics.lineHeights[line];
        } else {
          _newPage();
          continue;
        }
      }
      final last = line + fit >= metrics.lineCount;
      pages.last.slices.add(
        NovelPageSlice(
          itemIndex: itemIndex,
          startLine: line,
          endLine: line + fit,
          startOffset: metrics.lineOffsets[line],
          endOffset: metrics.lineOffsets[line + fit],
          hasTitle: titleBlock > 0 && line == 0,
        ),
      );
      if (line == 0) _itemStartPage[itemIndex] = pages.length - 1;
      _usedHeight += height;
      line += fit;
      if (!last) _newPage();
    }
    // 段距只在段落末尾计一次（跨页段落的中断片段不加段距）。
    _usedHeight += spec.paragraphSpacing;
  }

  void _newPage() {
    _usedHeight = 0;
    pages.add(NovelPaginatedPage(<NovelPageSlice>[]));
  }

  NovelTextMetrics _measure(NovelReaderParagraph paragraph) {
    final display = novelParagraphDialogue(paragraph, spec.dialogue);
    return _measureText(
      display?.text ??
          novelParagraphDisplayText(paragraph, spec.emptyChapterText),
      spec.textStyle,
      // 单纯配色不影响行度量，保留单 span 测量的成本。
      span:
          display != null &&
              display.ranges.isNotEmpty &&
              spec.dialogue!.fontWeight != null
          ? spec.dialogue!.measurementSpan(display, spec.textStyle)
          : null,
    );
  }

  NovelTextMetrics _measureText(
    String text,
    TextStyle style, {
    TextSpan? span,
  }) {
    // TextPainter 没有 style 参数：样式必须挂在根 span 上，否则会按默认
    // 字号测量，与渲染结果不一致（页面溢出）。
    final painter = TextPainter(
      text: span ?? TextSpan(text: text, style: style),
      textDirection: spec.textDirection,
      textScaler: spec.textScaler,
    )..layout(maxWidth: spec.size.width);
    final metrics = painter.computeLineMetrics();
    final lineHeights = <double>[];
    final lineTops = <double>[];
    final lineOffsets = <int>[0];
    var top = 0.0;
    for (final line in metrics) {
      lineHeights.add(line.height);
      lineTops.add(top);
      top += line.height;
      // 取该行垂直中点处的文本位置，再用 getLineBoundary 精确取行尾字符。
      final probe = painter.getPositionForOffset(
        Offset(0, lineTops.last + line.height / 2),
      );
      lineOffsets.add(painter.getLineBoundary(probe).end);
    }
    if (lineHeights.isEmpty) {
      // 空文本（理论上不会出现：空行已渲染为空格）按一行处理。
      lineHeights.add(style.fontSize ?? 14);
      lineTops.add(0);
      lineOffsets.add(text.length);
    } else {
      lineOffsets[lineOffsets.length - 1] = text.length;
    }
    painter.dispose();
    return NovelTextMetrics(
      lineHeights: lineHeights,
      lineOffsets: lineOffsets,
      lineTops: lineTops,
    );
  }

  /// 片段在页面中的高度（含标题块）。
  double sliceHeight(NovelPageSlice slice) {
    final metrics = _metrics[slice.itemIndex];
    if (metrics == null) return 0;
    var height = 0.0;
    for (var line = slice.startLine; line < slice.endLine; line++) {
      height += metrics.lineHeights[line];
    }
    if (slice.hasTitle) {
      final paragraph = document.paragraphAt(slice.itemIndex);
      final titleHeight = _titleHeights[paragraph.entry.entryIndex] ?? 0;
      height += titleHeight + spec.titleSpacing * 2;
    }
    return height;
  }

  /// 段落某行所在的页（从该段落起始页向后扫描）。
  int? _pageForItemLine(int itemIndex, int line) {
    final start = _itemStartPage[itemIndex];
    if (start == null) return null;
    for (var page = start; page < pages.length; page++) {
      for (final slice in pages[page].slices) {
        if (slice.itemIndex != itemIndex) continue;
        if (line >= slice.startLine && line < slice.endLine) return page;
      }
      // 已越过该段落的片段（后续页面不会再出现）。
      if (pages[page].slices.isNotEmpty &&
          pages[page].slices.first.itemIndex > itemIndex) {
        break;
      }
    }
    return start;
  }

  /// 页首片段相对「段落 widget 顶（含标题块）」的像素深度。
  double _depthOf(NovelPageSlice slice) {
    final paragraph = document.paragraphAt(slice.itemIndex);
    final titleBlock = _titleBlockFor(paragraph);
    if (slice.hasTitle) return 0;
    final metrics = _metrics[slice.itemIndex];
    if (metrics == null || slice.startLine >= metrics.lineCount) {
      return titleBlock;
    }
    return titleBlock + metrics.lineTops[slice.startLine];
  }

  /// 段落 widget 的总高度（标题块 + 正文 + 段距），与滚动模式 item 同构。
  double _itemHeightFor(int itemIndex) {
    final metrics = _metrics[itemIndex];
    if (metrics == null) return 0;
    return _titleBlockFor(document.paragraphAt(itemIndex)) +
        metrics.height +
        spec.paragraphSpacing;
  }

  /// 锚点所在页；分页尚未覆盖该段落时返回 null。
  ///
  /// alignment 与滚动模式同义（段落 widget 顶相对整屏顶的比例）：
  /// 负值按像素换算为段内行号，落到该行所在页，保证滚动↔翻页切换精确。
  int? pageForAnchor(NovelReaderAnchor anchor) {
    final itemIndex = document.itemFor(anchor);
    if (itemIndex >= _nextItem) return null;
    final start = _itemStartPage[itemIndex];
    if (start == null) return null;
    final alignment = anchor.alignment.isFinite ? anchor.alignment : 0.0;
    if (alignment >= 0) return start;
    final metrics = _metrics[itemIndex];
    if (metrics == null || metrics.lineCount == 0) return start;
    final viewport = spec.viewportHeight;
    if (viewport <= 0) return start;
    final titleBlock = _titleBlockFor(document.paragraphAt(itemIndex));
    final depthWanted = spec.contentTopInset - alignment * viewport;
    if (depthWanted <= titleBlock) return start;
    // 容差不可省：alignment 由 _depthOf 除以整屏高得到，回代时除法/乘法的
    // 舍入会让恰好落在行顶的深度差出 1ulp（如 972 变 971.999…），
    // 于锚点往返（本页→锚点→本页）上偏一行、进而偏一页。
    var line = 0;
    while (line + 1 < metrics.lineCount &&
        titleBlock + metrics.lineTops[line + 1] <= depthWanted + _epsilon) {
      line++;
    }
    return _pageForItemLine(itemIndex, line) ?? start;
  }

  /// 页面起始锚点；页内从段落中间开始时用负 alignment 还原段内位置。
  NovelReaderAnchor anchorForPage(int pageIndex) {
    final page = pages[pageIndex];
    if (page.slices.isEmpty) {
      final fallback = pageIndex > 0 ? pages[pageIndex - 1].slices : const [];
      if (fallback.isEmpty) {
        return const NovelReaderAnchor(entryIndex: 0);
      }
      final last = fallback.last;
      return document.anchorFor(last.itemIndex);
    }
    final slice = page.slices.first;
    final viewport = spec.viewportHeight;
    final alignment = viewport <= 0
        ? 0.0
        : (spec.contentTopInset - _depthOf(slice)) / viewport;
    return document.anchorFor(slice.itemIndex, alignment: alignment);
  }

  /// 页面阅读位置（itemIndex + 段内像素比例），进度与滚动模式同一算法，
  /// 保证两种模式切换时百分比连续。
  NovelReaderLocation locationForPage(int pageIndex) {
    final page = pages[pageIndex];
    if (page.slices.isEmpty) {
      return NovelReaderLocation(
        anchor: anchorForPage(pageIndex),
        itemIndex: 0,
        progress: 0,
      );
    }
    final slice = page.slices.first;
    final metrics = _metrics[slice.itemIndex];
    final itemHeight = _itemHeightFor(slice.itemIndex);
    final fraction = itemHeight <= 0
        ? 0.0
        : ((_depthOf(slice) - spec.contentTopInset) / itemHeight).clamp(
            0.0,
            1.0,
          );
    final atDocumentEnd =
        complete &&
        pageIndex == pages.length - 1 &&
        page.slices.last.itemIndex == document.itemCount - 1 &&
        metrics != null &&
        page.slices.last.endLine >= metrics.lineCount;
    final progress = atDocumentEnd
        ? 1.0
        : ((slice.itemIndex + fraction) / document.itemCount).clamp(0.0, 1.0);
    return NovelReaderLocation(
      anchor: anchorForPage(pageIndex),
      itemIndex: slice.itemIndex,
      progress: progress,
    );
  }

  /// 页面上最接近垂直中点的有正文段落（工具栏书签以此为参照）。
  NovelReaderParagraph? centerParagraph(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= pages.length) return null;
    final page = pages[pageIndex];
    if (page.slices.isEmpty) return null;
    final target = spec.size.height / 2;
    NovelPageSlice? best;
    var bestDistance = double.infinity;
    NovelPageSlice? bestText;
    var bestTextDistance = double.infinity;
    var top = 0.0;
    for (final slice in page.slices) {
      final height = sliceHeight(slice);
      final center = top + height / 2;
      final distance = (center - target).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = slice;
      }
      final paragraph = document.paragraphAt(slice.itemIndex);
      if (paragraph.text.trim().isNotEmpty && distance < bestTextDistance) {
        bestTextDistance = distance;
        bestText = slice;
      }
      top += height;
    }
    final chosen = bestText ?? best;
    return chosen == null ? null : document.paragraphAt(chosen.itemIndex);
  }
}

/// 浮点容差：避免恰好等高的行因舍入被推到下一页。
const double _epsilon = 0.001;

/// 分页与渲染之间的安全余量。渲染时可用宽度由布局引擎重新计算，与测量
/// 理论上一致，但亚像素舍入仍可能让实际内容高出一点点；预留半像素可避免
/// 触发 RenderFlex 溢出提示，代价是每页少放半像素内容。
const double _pageHeightSafety = 0.5;

/// 滚动与分页共用的正文宽度：先扣系统栏 inset，再按设定的最大宽度居中。
({double width, double horizontalPadding}) novelPageMetricsFor(
  Size size,
  EdgeInsets contentPadding, {
  double maxContentWidth = NovelReaderSettings.defaultContentWidth,
}) {
  final contentWidth = math.max(0.0, size.width - contentPadding.horizontal);
  final side = math.max(AppSpacing.xxl, (contentWidth - maxContentWidth) / 2);
  return (
    width: math.max(0.0, contentWidth - side * 2),
    horizontalPadding: side,
  );
}
