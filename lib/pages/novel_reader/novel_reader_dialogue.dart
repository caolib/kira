import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../models/novel.dart';
import '../../models/novel_dialogue_style.dart';
import '../../models/novel_reader_settings.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import 'novel_reader_document.dart';

/// 配对缓存只依附于源章节身份，换卷回收后不会继续持有正文。
final novelDialogueCache = NovelDialogueCache();

class NovelDialogueCache {
  // 同时容纳正在显示和正在预热的选择，避免旧视图重绘时挤掉预热结果。
  final _chapters = Expando<Map<NovelDialogueQuotes, _DialogueChapter>>();

  _DialogueChapter _chapter(
    NovelReaderEntry entry,
    NovelDialogueQuotes quotes,
  ) {
    final cache = _chapters[entry] ??= {};
    final cached = cache.remove(quotes) ?? _DialogueChapter(quotes);
    cache[quotes] = cached;
    if (cache.length > 2) cache.remove(cache.keys.first);
    return cached;
  }

  int _parsedChapters = 0;

  @visibleForTesting
  int get parsedChapters => _parsedChapters;

  Future<void> prepare(
    Iterable<NovelReaderEntry> entries, {
    NovelDialogueQuotes quotes = NovelDialogueQuotes.defaults,
  }) async {
    if (quotes.isEmpty) return;
    final clock = Stopwatch()..start();
    for (final entry in entries) {
      if (entry.isImage) continue;
      final chapter = _chapter(entry, quotes);
      if (chapter.result == null) {
        try {
          await (chapter.pending ??= _prepareEntry(entry, chapter));
        } finally {
          chapter.pending = null;
        }
      }
      if (clock.elapsedMicroseconds >= 4000) {
        await Future<void>.delayed(Duration.zero);
        clock.reset();
      }
    }
  }

  Future<void> _prepareEntry(
    NovelReaderEntry entry,
    _DialogueChapter chapter,
  ) async {
    final parser = _DialogueParser(entry.paragraphs, chapter.quotes);
    final steps = parser.steps().iterator;
    final clock = Stopwatch()..start();
    while (steps.moveNext()) {
      if (clock.elapsedMicroseconds >= 4000) {
        await Future<void>.delayed(Duration.zero);
        clock.reset();
      }
    }
    chapter.result = parser.result;
    _parsedChapters++;
  }

  NovelDialogueParagraph paragraph(
    NovelReaderParagraph paragraph, {
    NovelDialogueQuotes quotes = NovelDialogueQuotes.defaults,
  }) {
    if (quotes.isEmpty) return NovelDialogueParagraph(paragraph.text, const []);
    final chapter = _chapter(paragraph.entry, quotes);
    if (chapter.result == null) {
      // 宿主在提交启用设置、加载卷册时异步预热；独立视图也可直接使用。
      final parser = _DialogueParser(paragraph.entry.paragraphs, quotes);
      for (final _ in parser.steps()) {}
      chapter.result = parser.result;
      _parsedChapters++;
    }
    return chapter.result![paragraph.paragraphIndex];
  }
}

class _DialogueChapter {
  _DialogueChapter(this.quotes);
  final NovelDialogueQuotes quotes;
  List<NovelDialogueParagraph>? result;
  Future<void>? pending;
}

class _QuoteToken {
  _QuoteToken(this.offset, this.quote, this.open);

  final int offset;
  final NovelDialogueQuote quote;
  final bool open;
  bool matched = false;
}

class NovelDialogueRange {
  const NovelDialogueRange(this.start, this.end);

  final int start;
  final int end;
}

/// 区间均使用显示文本的 UTF-16 偏移，与 TextPainter 的行边界一致。
class NovelDialogueParagraph {
  NovelDialogueParagraph(this.text, this.ranges);

  final String text;
  final List<NovelDialogueRange> ranges;

  int _firstRange(int start) {
    var low = 0;
    var high = ranges.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (ranges[mid].end <= start) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  List<TextSelection> selections(int start, int end) => [
    for (
      var index = _firstRange(start);
      index < ranges.length && ranges[index].start < end;
      index++
    )
      TextSelection(
        baseOffset: math.max(start, ranges[index].start) - start,
        extentOffset: math.min(end, ranges[index].end) - start,
      ),
  ];

  TextSpan span({
    required TextStyle baseStyle,
    required NovelDialoguePresentation dialogue,
    int start = 0,
    int? end,
    bool measurementOnly = false,
  }) {
    final stop = (end ?? text.length).clamp(start, text.length);
    // 页内片段从二分找到的区间开始，不扫描本段前面所有对白。
    final first = _firstRange(start);
    final children = <TextSpan>[];
    var cursor = start;
    final style = measurementOnly
        ? TextStyle(fontWeight: dialogue.fontWeight)
        : dialogue.textStyle;
    for (var index = first; index < ranges.length; index++) {
      final range = ranges[index];
      if (range.start >= stop) break;
      final from = math.max(cursor, range.start);
      final to = math.min(stop, range.end);
      if (cursor < from) {
        children.add(TextSpan(text: text.substring(cursor, from)));
      }
      if (from < to) {
        children.add(TextSpan(text: text.substring(from, to), style: style));
      }
      cursor = to;
    }
    if (cursor < stop) {
      children.add(TextSpan(text: text.substring(cursor, stop)));
    }
    return TextSpan(style: baseStyle, children: children);
  }
}

/// 两次线性扫描：先确定完整配对，再合并嵌套区间。未闭合引号不扩散样式。
/// 每 4096 字符让出一个时间片，避免长章节解析独占 UI 线程。
class _DialogueParser {
  _DialogueParser(this.paragraphs, this.quotes);

  final NovelDialogueQuotes quotes;

  final List<String> paragraphs;
  final result = <NovelDialogueParagraph>[];

  Iterable<void> steps() sync* {
    final delimiters = <int, NovelDialogueQuote>{
      for (final quote in NovelDialogueQuote.values.where(quotes.contains))
        for (final code in quote.pair.codeUnits) code: quote,
    };
    final tokens = <_QuoteToken>[];
    final stack = <_QuoteToken>[];
    var offset = 0;
    var budget = 0;
    for (final text in paragraphs) {
      for (var index = 0; index < text.length; index++) {
        final code = text.codeUnitAt(index);
        final quote = delimiters[code];
        if (quote != null) {
          final closesTop = stack.isNotEmpty && stack.last.quote == quote;
          // 直双引号没有方向：栈顶是同类时闭合，否则开启新的一对。
          final open = quote == NovelDialogueQuote.straightDouble
              ? !closesTop
              : code == quote.pair.codeUnitAt(0);
          final token = _QuoteToken(offset + index, quote, open);
          tokens.add(token);
          if (open) {
            stack.add(token);
          } else if (closesTop) {
            stack.removeLast().matched = true;
            token.matched = true;
          }
        }
        if (++budget >= 4096) {
          budget = 0;
          yield null;
        }
      }
      offset += text.length + 1;
      if (++budget >= 4096) {
        budget = 0;
        yield null;
      }
    }
    final ranges = <NovelDialogueRange>[];
    var depth = 0;
    var start = 0;
    for (final token in tokens) {
      if (token.matched) {
        if (token.open) {
          if (depth++ == 0) start = token.offset;
        } else if (--depth == 0) {
          ranges.add(NovelDialogueRange(start, token.offset + 1));
        }
      }
      if (++budget >= 4096) {
        budget = 0;
        yield null;
      }
    }
    offset = 0;
    var rangeIndex = 0;
    for (final text in paragraphs) {
      final end = offset + text.length;
      while (rangeIndex < ranges.length && ranges[rangeIndex].end <= offset) {
        rangeIndex++;
      }
      final localRanges = <NovelDialogueRange>[];
      for (var index = rangeIndex; index < ranges.length; index++) {
        final range = ranges[index];
        if (range.start >= end) break;
        localRanges.add(
          NovelDialogueRange(
            math.max(0, range.start - offset),
            math.min(text.length, range.end - offset),
          ),
        );
        if (++budget >= 4096) {
          budget = 0;
          yield null;
        }
      }
      result.add(NovelDialogueParagraph(text, localRanges));
      offset = end + 1;
      if (++budget >= 256) {
        budget = 0;
        yield null;
      }
    }
  }
}

@immutable
class NovelDialoguePresentation {
  const NovelDialoguePresentation({
    required this.foreground,
    required this.background,
    required this.fontWeight,
    this.quotes = NovelDialogueQuotes.defaults,
  });

  final Color foreground;
  final Color? background;
  final FontWeight? fontWeight;
  final NovelDialogueQuotes quotes;

  /// 颜色和底色只改变绘制，不能作废分页缓存。
  (FontWeight, NovelDialogueQuotes)? get layoutKey =>
      fontWeight == null ? null : (fontWeight!, quotes);

  TextStyle get textStyle =>
      TextStyle(color: foreground, fontWeight: fontWeight);

  /// 测量时舍弃绘制属性，把同字重的相邻文本保持为一个 shaping run。
  TextSpan measurementSpan(
    NovelDialogueParagraph paragraph,
    TextStyle baseStyle,
  ) => paragraph.span(
    baseStyle: baseStyle,
    dialogue: this,
    measurementOnly: true,
  );
}

NovelDialoguePresentation? resolveNovelDialoguePresentation(
  NovelReaderSettings settings, {
  required bool dark,
  required Color foreground,
  required Color background,
}) {
  if (!settings.dialogueEnabled || settings.dialogueQuotes.isEmpty) return null;
  final style = settings.dialogueStyleFor(dark: dark);
  final fill = style.backgroundEnabled
      ? Color(style.backgroundColor).withValues(alpha: style.backgroundOpacity)
      : null;
  final surface = fill == null
      ? background
      : Color.alphaBlend(fill, background);
  final color = switch (style.colorMode) {
    NovelDialogueColorMode.body => foreground,
    NovelDialogueColorMode.custom => Color(style.textColor),
    NovelDialogueColorMode.automatic => _automaticColor(
      style.textColor,
      surface,
    ),
  };
  return NovelDialoguePresentation(
    foreground: color,
    background: fill,
    quotes: settings.dialogueQuotes,
    fontWeight: switch (style.weight) {
      NovelDialogueWeight.body => null,
      NovelDialogueWeight.medium => FontWeight.w500,
      NovelDialogueWeight.bold => FontWeight.w700,
    },
  );
}

Color _automaticColor(int seed, Color background) {
  final dark =
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark;
  final initial = HSLColor.fromColor(
    Color(seed),
  ).withSaturation(0.3).withLightness(dark ? 0.72 : 0.36).toColor();
  final luminance = background.computeLuminance();
  final target = luminance > 0.179 ? Colors.black : Colors.white;
  for (var step = 0; step <= 20; step++) {
    final color = Color.lerp(initial, target, step / 20)!;
    final other = color.computeLuminance();
    if ((math.max(luminance, other) + 0.05) /
            (math.min(luminance, other) + 0.05) >=
        4.5) {
      return color;
    }
  }
  return target;
}

NovelDialogueParagraph? novelParagraphDialogue(
  NovelReaderParagraph paragraph,
  NovelDialoguePresentation? dialogue,
) {
  if (dialogue == null || paragraph.text.isEmpty) return null;
  return novelDialogueCache.paragraph(paragraph, quotes: dialogue.quotes);
}

/// 对白底色复用正文 RenderParagraph 的已布局选区，不再单独 TextPainter 测量。
class NovelDialogueText extends StatelessWidget {
  const NovelDialogueText({
    super.key,
    required NovelDialogueParagraph paragraph,
    required this.baseStyle,
    required this.dialogue,
    this.start = 0,
    this.end,
    this.textScaler,
    this.textWidthBasis = TextWidthBasis.parent,
  }) : _paragraph = paragraph,
       _previewText = null,
       paragraphSpacing = 0;

  const NovelDialogueText.preview({
    super.key,
    required String text,
    required this.baseStyle,
    required this.dialogue,
    this.paragraphSpacing = 0,
  }) : _previewText = text,
       _paragraph = null,
       start = 0,
       end = null,
       textScaler = null,
       textWidthBasis = TextWidthBasis.parent;

  final NovelDialogueParagraph? _paragraph;
  final String? _previewText;
  final TextStyle baseStyle;
  final NovelDialoguePresentation? dialogue;
  final int start;
  final int? end;
  final TextScaler? textScaler;
  final TextWidthBasis textWidthBasis;
  final double paragraphSpacing;

  @override
  Widget build(BuildContext context) {
    if (_previewText case final text?) {
      final lines = text.split('\n');
      final presentation = dialogue;
      final List<NovelDialogueParagraph> paragraphs;
      if (presentation == null) {
        paragraphs = [
          for (final line in lines) NovelDialogueParagraph(line, const []),
        ];
      } else {
        final parser = _DialogueParser(lines, presentation.quotes);
        for (final _ in parser.steps()) {}
        paragraphs = parser.result;
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < paragraphs.length; index++)
            Padding(
              padding: EdgeInsets.only(
                bottom: index == paragraphs.length - 1 ? 0 : paragraphSpacing,
              ),
              child: _buildText(paragraphs[index]),
            ),
        ],
      );
    }
    return _buildText(_paragraph!);
  }

  Widget _buildText(NovelDialogueParagraph paragraph) {
    final stop = end ?? paragraph.text.length;
    final presentation = dialogue;
    if (presentation == null || paragraph.ranges.isEmpty) {
      return Text(
        paragraph.text.substring(start, stop),
        style: baseStyle,
        textScaler: textScaler,
        textWidthBasis: textWidthBasis,
      );
    }
    final text = Text.rich(
      paragraph.span(
        baseStyle: baseStyle,
        dialogue: presentation,
        start: start,
        end: stop,
      ),
      style: baseStyle,
      textScaler: textScaler,
      textWidthBasis: textWidthBasis,
    );
    final fill = presentation.background;
    if (fill == null || fill.a == 0) return text;
    return _DialogueBackground(
      color: fill,
      selections: paragraph.selections(start, stop),
      child: text,
    );
  }
}

class _DialogueBackground extends SingleChildRenderObjectWidget {
  const _DialogueBackground({
    required this.color,
    required this.selections,
    required super.child,
  });

  final Color color;
  final List<TextSelection> selections;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderDialogueBackground(color, selections);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderDialogueBackground renderObject,
  ) {
    renderObject.update(color, selections);
  }
}

@visibleForTesting
Rect novelDialogueBackgroundRect(
  Rect glyphBounds, {
  Iterable<Rect> narrationBounds = const [],
}) {
  final padding = (glyphBounds.height * 0.12).clamp(
    AppSpacing.xs / 2,
    AppSpacing.xs,
  );
  var left = glyphBounds.left - padding;
  var right = glyphBounds.right + padding;
  // 同行正文与底色之间保留 2dp；空间不足时只内收底色，不移动文字。
  // 换行和页片段边缘仍向外留白，按视觉位置兼容双向文本。
  final gap = math.min(AppSpacing.xs / 2, glyphBounds.width / 4);
  const tolerance = 0.01;
  for (final narration in narrationBounds) {
    if ((narration.top - glyphBounds.top).abs() > tolerance ||
        (narration.bottom - glyphBounds.bottom).abs() > tolerance) {
      continue;
    }
    if (narration.right <= glyphBounds.left + tolerance) {
      left = math.max(left, narration.right + gap);
    }
    if (narration.left >= glyphBounds.right - tolerance) {
      right = math.min(right, narration.left - gap);
    }
  }
  return Rect.fromLTRB(
    left,
    glyphBounds.top - padding,
    right,
    glyphBounds.bottom + padding,
  );
}

/// Merge visual runs within one selection, never across lines or real gaps.
/// Callers use BoxHeightStyle.max so fallback fonts share each line's bounds.
@visibleForTesting
List<Rect> novelDialogueBackgroundRuns(Iterable<ui.TextBox> boxes) {
  final sorted =
      [
        for (final box in boxes)
          if (!box.toRect().isEmpty) box.toRect(),
      ]..sort((a, b) {
        final row = a.top.compareTo(b.top);
        return row != 0 ? row : a.left.compareTo(b.left);
      });
  final runs = <Rect>[];
  // Only absorb subpixel rounding, not unselected text between bidi runs.
  const tolerance = 0.01;
  for (final bounds in sorted) {
    if (runs.isNotEmpty) {
      final previous = runs.last;
      if ((previous.top - bounds.top).abs() <= tolerance &&
          (previous.bottom - bounds.bottom).abs() <= tolerance &&
          bounds.left <= previous.right + tolerance) {
        runs[runs.length - 1] = previous.expandToInclude(bounds);
        continue;
      }
    }
    runs.add(bounds);
  }
  return runs;
}

class _RenderDialogueBackground extends RenderProxyBox {
  _RenderDialogueBackground(this._color, this._selections);

  Color _color;
  List<TextSelection> _selections;
  Path? _backgroundPath;
  InlineSpan? _text;
  RenderParagraph? _paragraph;
  TextScaler? _scaler;
  TextDirection? _direction;
  TextAlign? _align;

  void update(Color color, List<TextSelection> selections) {
    if (_color == color && listEquals(_selections, selections)) return;
    _color = color;
    if (!listEquals(_selections, selections)) _backgroundPath = null;
    _selections = selections;
    markNeedsPaint();
  }

  @override
  void performLayout() {
    super.performLayout();
    _backgroundPath = null;
  }

  RenderParagraph? _findParagraph(RenderObject object) {
    if (object is RenderParagraph) return object;
    RenderParagraph? result;
    object.visitChildren((child) {
      result ??= _findParagraph(child);
    });
    return result;
  }

  Path _createBackgroundPath(RenderParagraph paragraph) {
    final path = Path();
    final narrationBounds = <Rect>[];
    void addNarration(int start, int end) {
      if (start >= end) return;
      narrationBounds.addAll(
        paragraph
            .getBoxesForSelection(
              TextSelection(baseOffset: start, extentOffset: end),
              boxHeightStyle: ui.BoxHeightStyle.max,
            )
            .map((box) => box.toRect())
            .where((bounds) => !bounds.isEmpty),
      );
    }

    // 一次收集当前片段的非对白选区，并随背景路径缓存，无额外文本测量。
    var cursor = 0;
    for (final selection in _selections) {
      addNarration(cursor, selection.start);
      cursor = selection.end;
    }
    addNarration(cursor, paragraph.text.toPlainText().length);
    for (final selection in _selections) {
      final boxes = paragraph.getBoxesForSelection(
        selection,
        boxHeightStyle: ui.BoxHeightStyle.max,
      );
      for (final bounds in novelDialogueBackgroundRuns(boxes)) {
        path.addRRect(
          RRect.fromRectAndRadius(
            novelDialogueBackgroundRect(
              bounds,
              narrationBounds: narrationBounds,
            ),
            const Radius.circular(AppRadius.xs),
          ),
        );
      }
    }
    return path;
  }

  @override
  Rect get paintBounds => super.paintBounds.inflate(AppSpacing.xs);

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    final paragraph = child == null ? null : _findParagraph(child);
    if (paragraph != null) {
      if (!identical(_paragraph, paragraph) ||
          !identical(_text, paragraph.text) ||
          _scaler != paragraph.textScaler ||
          _direction != paragraph.textDirection ||
          _align != paragraph.textAlign) {
        _backgroundPath = null;
        _paragraph = paragraph;
        _text = paragraph.text;
        _scaler = paragraph.textScaler;
        _direction = paragraph.textDirection;
        _align = paragraph.textAlign;
      }
      final path = _backgroundPath ??= _createBackgroundPath(paragraph);
      final paragraphOffset = paragraph.localToGlobal(
        Offset.zero,
        ancestor: this,
      );
      final origin = offset + paragraphOffset;
      final canvas = context.canvas;
      canvas.save();
      canvas.translate(origin.dx, origin.dy);
      // 同段自动换行可以相连；合成路径只填充一次，交叠处不会加深底色。
      canvas.drawPath(path, Paint()..color = _color);
      canvas.restore();
    }
    super.paint(context, offset);
  }
}
