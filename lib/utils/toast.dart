import 'dart:async';
import 'package:flutter/material.dart';

import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import 'adaptive_motion.dart';

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

  Duration get _displayDuration =>
      widget.isError ? const Duration(seconds: 4) : const Duration(seconds: 1);

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final reduced = prefersReducedMotion(context);
      if (reduced) {
        _anim.value = 1;
      } else {
        _anim.forward();
      }
      _timer = Timer(_displayDuration, _dismiss);
    });
    widget.controller.dismiss = _dismiss;
  }

  void _dismiss() {
    if (_removed) return;
    _removed = true;
    _timer?.cancel();
    if (!mounted) {
      widget.onDismiss();
      return;
    }
    if (prefersReducedMotion(context)) {
      widget.onDismiss();
      return;
    }
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
    final icon = widget.isError
        ? Icons.error_outline
        : Icons.check_circle_outline;
    final media = MediaQuery.of(context);
    final textScale = media.textScaler.scale(14).clamp(14.0, 20.0);

    return Positioned(
      top: media.padding.top + 16,
      left: media.padding.left,
      right: media.padding.right,
      child: Center(
        child: SlideTransition(
          position: _slide,
          child: FadeTransition(
            opacity: _fade,
            child: GestureDetector(
              onTap: _dismiss,
              child: Semantics(
                liveRegion: true,
                label: widget.message,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: media.size.width - 48,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: AppRadius.mdR,
                      boxShadow: AppShadows.md(cs),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, color: fg, size: 20),
                        const SizedBox(width: AppSpacing.sm),
                        Flexible(
                          child: Text(
                            widget.message,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: fg, fontSize: textScale),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
