part of '../filter_chip_row.dart';

/// 按 chip 的自然宽度分行，仅将非末行的余量均分到各 chip。
class _JustifiedTagWrap extends MultiChildRenderObjectWidget {
  const _JustifiedTagWrap({required super.children});

  @override
  _RenderJustifiedTagWrap createRenderObject(BuildContext context) =>
      _RenderJustifiedTagWrap(Directionality.of(context));

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderJustifiedTagWrap renderObject,
  ) {
    renderObject.textDirection = Directionality.of(context);
  }
}

class _TagWrapParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderJustifiedTagWrap extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _TagWrapParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _TagWrapParentData> {
  _RenderJustifiedTagWrap(this._textDirection);

  TextDirection _textDirection;

  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TagWrapParentData) {
      child.parentData = _TagWrapParentData();
    }
  }

  Size _layout(BoxConstraints constraints, {required bool dry}) {
    if (firstChild == null) return constraints.smallest;
    final maxWidth = constraints.maxWidth;
    final row = <({RenderBox child, double width})>[];
    var rowWidth = 0.0;
    var contentWidth = 0.0;
    var height = 0.0;

    void finishRow({required bool justify}) {
      if (row.isEmpty) return;
      if (height > 0) height += AppSpacing.sm;
      final extra = justify && maxWidth.isFinite
          ? math.max(0.0, maxWidth - rowWidth) / row.length
          : 0.0;
      final layoutWidth = maxWidth.isFinite
          ? maxWidth
          : constraints.constrainWidth(rowWidth);
      var x = 0.0;
      var rowHeight = 0.0;
      for (final item in row) {
        final childConstraints = BoxConstraints.tightFor(
          width: item.width + extra,
        );
        final Size childSize;
        if (dry) {
          childSize = item.child.getDryLayout(childConstraints);
        } else {
          item.child.layout(childConstraints, parentUsesSize: true);
          childSize = item.child.size;
          final parentData = item.child.parentData! as _TagWrapParentData;
          parentData.offset = Offset(
            _textDirection == TextDirection.ltr
                ? x
                : layoutWidth - x - childSize.width,
            height,
          );
        }
        rowHeight = math.max(rowHeight, childSize.height);
        x += childSize.width + AppSpacing.sm;
      }
      contentWidth = math.max(contentWidth, x - AppSpacing.sm);
      height += rowHeight;
      row.clear();
      rowWidth = 0.0;
    }

    for (var child = firstChild; child != null; child = childAfter(child)) {
      // 读取 chip 自身的固有宽度，避免手算文字、计数和主题内边距。
      final width = math.min(
        maxWidth,
        child.getMaxIntrinsicWidth(double.infinity),
      );
      if (row.isNotEmpty && rowWidth + AppSpacing.sm + width > maxWidth) {
        finishRow(justify: true);
      }
      if (row.isNotEmpty) rowWidth += AppSpacing.sm;
      row.add((child: child, width: width));
      rowWidth += width;
    }
    finishRow(justify: false);
    return constraints.constrain(
      Size(maxWidth.isFinite ? maxWidth : contentWidth, height),
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _layout(constraints, dry: true);

  @override
  void performLayout() {
    size = _layout(constraints, dry: false);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
