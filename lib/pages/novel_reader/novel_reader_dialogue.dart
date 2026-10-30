import 'dart:async';
import 'dart:math' as math;

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
  final _chapters = Expando<List<NovelDialogueParagraph>>();
  final _pending = Expando<Future<void>>();
  int _parsedChapters = 0;

  @visibleForTesting
  int get parsedChapters => _parsedChapters;

  Future<void> prepare(Iterable<NovelReaderEntry> entries) async {
    final clock = Stopwatch()..start();
    for (final entry in entries) {
      if (entry.isImage) continue;
      if (_chapters[entry] == null) {
        final pending = _pending[entry];
        if (pending != null) {
          await pending;
        } else {
          final future = _prepareEntry(entry);
          _pending[entry] = future;
          try {
            await future;
          } finally {
            _pending[entry] = null;
          }
        }
      }
      if (clock.elapsedMicroseconds >= 4000) {
        await Future<void>.delayed(Duration.zero);
        clock.reset();
      }
    }
  }

  Future<void> _prepareEntry(NovelReaderEntry entry) async {
    final parser = _DialogueParser(entry.paragraphs);
    final steps = parser.steps().iterator;
    final clock = Stopwatch()..start();
    while (steps.moveNext()) {
      if (clock.elapsedMicroseconds >= 4000) {
        await Future<void>.delayed(Duration.zero);
        clock.reset();
      }
    }
    _chapters[entry] = parser.result;
    _parsedChapters++;
  }

  NovelDialogueParagraph paragraph(NovelReaderParagraph paragraph) {
    var chapter = _chapters[paragraph.entry];
    if (chapter == null) {
      // 宿主在提交启用设置、加载卷册时异步预热；独立视图也可直接使用。
      final parser = _DialogueParser(paragraph.entry.paragraphs);
      for (final _ in parser.steps()) {}
      chapter = parser.result;
      _chapters[paragraph.entry] = chapter;
      _parsedChapters++;
    }
    return chapter[paragraph.paragraphIndex];
  }
}

class _QuoteToken {
  _QuoteToken(this.offset, this.code, this.open);

  final int offset;
  final int code;
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
  _DialogueParser(this.paragraphs);

  final List<String> paragraphs;
  final result = <NovelDialogueParagraph>[];

  Iterable<void> steps() sync* {
    final tokens = <_QuoteToken>[];
    final stack = <_QuoteToken>[];
    var offset = 0;
    var budget = 0;
    for (final text in paragraphs) {
      for (var index = 0; index < text.length; index++) {
        final code = text.codeUnitAt(index);
        final open = code == 0x300C || code == 0x300E;
        if (open || code == 0x300D || code == 0x300F) {
          final token = _QuoteToken(offset + index, code, open);
          tokens.add(token);
          if (open) {
            stack.add(token);
          } else if (stack.isNotEmpty && stack.last.code + 1 == code) {
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
  });

  final Color foreground;
  final Color? background;
  final FontWeight? fontWeight;

  /// 颜色和底色只改变绘制，不能作废分页缓存。
  FontWeight? get layoutKey => fontWeight;

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
  if (!settings.dialogueEnabled) return null;
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
  return novelDialogueCache.paragraph(paragraph);
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
      final parser = _DialogueParser(text.split('\n'));
      for (final _ in parser.steps()) {}
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < parser.result.length; index++)
            Padding(
              padding: EdgeInsets.only(
                bottom: index == parser.result.length - 1
                    ? 0
                    : paragraphSpacing,
              ),
              child: _buildText(parser.result[index]),
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
Rect novelDialogueBackgroundRect(Rect glyphBounds) {
  final padding = (glyphBounds.height * 0.12).clamp(
    AppSpacing.xs / 2,
    AppSpacing.xs,
  );
  return Rect.fromLTRB(
    glyphBounds.left,
    glyphBounds.top - padding,
    glyphBounds.right,
    glyphBounds.bottom + padding,
  );
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
    for (final selection in _selections) {
      for (final box in paragraph.getBoxesForSelection(selection)) {
        final bounds = box.toRect();
        if (bounds.isEmpty) continue;
        path.addRRect(
          RRect.fromRectAndRadius(
            novelDialogueBackgroundRect(bounds),
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
