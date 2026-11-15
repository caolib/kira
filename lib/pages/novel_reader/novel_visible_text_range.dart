import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'novel_reader_document.dart';

/// 原始段落的 UTF-16 半开区间；不复制正文，也不使用随排版变化的页码。
class NovelVisibleTextRange {
  const NovelVisibleTextRange({
    required this.paragraph,
    required this.itemIndex,
    required this.start,
    required this.end,
  });

  final NovelReaderParagraph paragraph;
  final int itemIndex;
  final int start;
  final int end;
}

/// 仅统计启用时包住正文（不含标题/段距）。复用 Text/Text.rich 的布局，
/// 注册随懒列表挂载/回收，不遍历列表或全文，不引入第二次文字测量。
class NovelTextRangeProbe extends SingleChildRenderObjectWidget {
  const NovelTextRangeProbe({
    super.key,
    required this.paragraph,
    required this.itemIndex,
    required this.onAttach,
    required this.onDetach,
    required super.child,
  });

  final NovelReaderParagraph paragraph;
  final int itemIndex;
  final ValueChanged<RenderNovelTextRangeProbe> onAttach;
  final ValueChanged<RenderNovelTextRangeProbe> onDetach;

  @override
  RenderNovelTextRangeProbe createRenderObject(BuildContext context) =>
      RenderNovelTextRangeProbe(paragraph, itemIndex, onAttach, onDetach);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderNovelTextRangeProbe renderObject,
  ) => renderObject.update(paragraph, itemIndex);
}

class RenderNovelTextRangeProbe extends RenderProxyBox {
  RenderNovelTextRangeProbe(
    this.paragraph,
    this.itemIndex,
    this._onAttach,
    this._onDetach,
  );

  NovelReaderParagraph paragraph;
  int itemIndex;
  final ValueChanged<RenderNovelTextRangeProbe> _onAttach;
  final ValueChanged<RenderNovelTextRangeProbe> _onDetach;
  RenderParagraph? _text;

  void update(NovelReaderParagraph value, int index) {
    if (attached && index != itemIndex) _onDetach(this);
    final moved = index != itemIndex;
    paragraph = value;
    itemIndex = index;
    if (attached && moved) _onAttach(this);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _onAttach(this);
  }

  @override
  void detach() {
    _onDetach(this);
    _text = null;
    super.detach();
  }

  @override
  void performLayout() {
    super.performLayout();
    _text = null;
  }

  RenderParagraph? _resolveText() {
    if (_text case final cached? when cached.attached) return cached;
    RenderBox? current = child;
    // 正文只有 Text 的语义包装与对白背景等少量 proxy，不递归全树。
    for (var depth = 0; current != null && depth < 8; depth++) {
      if (current is RenderParagraph) return _text = current;
      current = current is RenderProxyBox ? current.child : null;
    }
    return null;
  }

  NovelVisibleTextRange? visibleRange(RenderBox viewport) {
    if (!attached || !hasSize || paragraph.text.isEmpty) return null;
    final text = _resolveText();
    if (text == null || !text.hasSize || text.size.isEmpty) return null;
    final origin = text.localToGlobal(Offset.zero, ancestor: viewport);
    final top = math.max(0.0, -origin.dy);
    final bottom = math.min(text.size.height, viewport.size.height - origin.dy);
    if (bottom <= top ||
        origin.dx >= viewport.size.width ||
        origin.dx + text.size.width <= 0) {
      return null;
    }
    final length = paragraph.text.length;
    // 完整可见直接给原始范围；仅裁切段落查询已布局的首末可见行。
    TextSelection lineAt(double y) {
      final left = text.getPositionForOffset(Offset(-1, y)).offset;
      final right = text
          .getPositionForOffset(Offset(text.size.width + 1, y))
          .offset;
      return TextSelection(
        baseOffset: math.min(left, right),
        extentOffset: math.max(left, right),
      );
    }

    var start = 0;
    var end = length;
    if (top > 0) {
      final first = lineAt(top);
      // y 可能落在行距空隙中：候选行字形全在屏外时不能多计一行。
      final visible = text
          .getBoxesForSelection(first)
          .any((box) => box.bottom > top && box.top < bottom);
      start = visible ? first.start : first.end;
    }
    if (bottom < text.size.height) {
      final last = lineAt(bottom - 0.001);
      final visible = text
          .getBoxesForSelection(last)
          .any((box) => box.top < bottom && box.bottom > top);
      end = visible ? last.end : last.start;
    }
    if (end <= start) return null;
    return NovelVisibleTextRange(
      paragraph: paragraph,
      itemIndex: itemIndex,
      start: start.clamp(0, length),
      end: end.clamp(0, length),
    );
  }
}
