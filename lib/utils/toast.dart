import 'dart:async';
import 'package:flutter/material.dart';

/// 顶部气泡式通知
void showToast(BuildContext context, String message, {bool isError = false}) {
  final overlay = Overlay.of(context);
  final cs = Theme.of(context).colorScheme;

  late final OverlayEntry entry;
  final controller = _ToastController();

  entry = OverlayEntry(
    builder: (_) => _ToastWidget(
      message: message,
      isError: isError,
      colorScheme: cs,
      controller: controller,
      onDismiss: () => entry.remove(),
    ),
  );

  overlay.insert(entry);
}

class _ToastController {
  VoidCallback? dismiss;
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final bool isError;
  final ColorScheme colorScheme;
  final _ToastController controller;
  final VoidCallback onDismiss;

  const _ToastWidget({
    required this.message,
    required this.isError,
    required this.colorScheme,
    required this.controller,
    required this.onDismiss,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  Timer? _timer;
  bool _removed = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeIn);

    _anim.forward();
    _timer = Timer(const Duration(seconds: 2), _dismiss);
    widget.controller.dismiss = _dismiss;
  }

  void _dismiss() {
    if (_removed) return;
    _removed = true;
    _timer?.cancel();
    _anim.reverse().then((_) {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.colorScheme;
    final bg = widget.isError ? cs.errorContainer : cs.primaryContainer;
    final fg = widget.isError ? cs.onErrorContainer : cs.onPrimaryContainer;
    final icon = widget.isError ? Icons.error_outline : Icons.check_circle_outline;

    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      left: 24,
      right: 24,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: GestureDetector(
            onTap: _dismiss,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: fg, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        widget.message,
                        style: TextStyle(color: fg, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
