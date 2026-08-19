import 'package:flutter/material.dart';

/// 在对话框 / 弹窗子树内托管 [TextEditingController]，由 [State.dispose] 释放。
///
/// `showDialog` 的 Future 在路由 pop 时就完成，但内容子树在退出动画期间仍会重建
/// （例如此时插入 toast 的 OverlayEntry 会让整个 Overlay 重建，进而触发
/// `TextField` 内部 `AnimatedBuilder.didUpdateWidget` 重新订阅 controller）。
/// 因此在 Future 之后立即 dispose，甚至延后一帧 dispose，都可能命中
/// “A TextEditingController was used after being disposed” 断言。
/// 让控制器与子树同寿即可彻底避免。
class TextControllerScope extends StatefulWidget {
  const TextControllerScope({
    super.key,
    this.initialText = '',
    required this.builder,
  });

  final String initialText;
  final Widget Function(BuildContext context, TextEditingController controller)
  builder;

  @override
  State<TextControllerScope> createState() => _TextControllerScopeState();
}

class _TextControllerScopeState extends State<TextControllerScope> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}
