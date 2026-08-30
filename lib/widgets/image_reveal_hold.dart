import 'dart:async';

import 'package:flutter/material.dart';

/// 图片加载完成后的过渡尺寸保持层。
///
/// 图片库（如 `CachedNetworkImage` 底层的 octo_image）在占位符 → 真图的
/// 交叉淡出期，会把淡出的占位符与真图叠放在一个**固定居中对齐**的
/// Stack 里。当占位符按估算得出的尺寸大于真图时，真图会悬在占位区域
/// 正中间（两侧留缝）；淡出结束、占位层移除的瞬间，item 尺寸骤然回落
/// 到真图尺寸，引发跳动。
///
/// 本组件在真图旁放一个预估尺寸的透明撑块，把过渡期 item 尺寸稳定在
/// 预估值，调用方用 [alignment] 让真图贴住不应跳动的边缘（如从右到左
/// 横向阅读时右对齐——右缘连着已读内容，估算误差全部落到未读侧）；
/// 撑块计时（应与占位符淡出时长一致）结束后移除，item 尺寸回落到真图，
/// 跳动只发生在可接受的一侧。真图大于预估值时 Stack 以真图为准，
/// 不会裁切、也不会引入额外跳动。
class ImageRevealHold extends StatefulWidget {
  const ImageRevealHold({
    super.key,
    required this.child,
    required this.alignment,
    required this.holdDuration,
    this.holdWidth,
    this.holdHeight,
  });

  final Widget child;

  /// 真图在过渡 Stack 内的对齐方向。
  final AlignmentGeometry alignment;

  /// 撑块保持的宽度（如横向滚动阅读时的预估图宽）。
  final double? holdWidth;

  /// 撑块保持的高度（如竖向滚动阅读时的预估图高）。
  final double? holdHeight;

  /// 撑块保持时长，应与占位符淡出时长一致：撑块移除的瞬间占位符恰好
  /// 淡出完毕，item 尺寸只回落一次。
  final Duration holdDuration;

  @override
  State<ImageRevealHold> createState() => _ImageRevealHoldState();
}

class _ImageRevealHoldState extends State<ImageRevealHold> {
  Timer? _holdTimer;

  bool get _holding => _holdTimer?.isActive ?? false;

  @override
  void initState() {
    super.initState();
    _holdTimer = Timer(widget.holdDuration, () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _holdTimer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      alignment: widget.alignment,
      children: [
        if (_holding) ...[
          if (widget.holdWidth != null) SizedBox(width: widget.holdWidth),
          if (widget.holdHeight != null) SizedBox(height: widget.holdHeight),
        ],
        widget.child,
      ],
    );
  }
}
