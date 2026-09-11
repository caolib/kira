part of '../network_page.dart';

// ─────────────────────────────────────────────────────────────────────────
// 状态语义类型
// ─────────────────────────────────────────────────────────────────────────

enum _HealthLevel { good, warn, bad, busy, unknown }

extension _HealthLevelX on _HealthLevel {
  Color color(ColorScheme cs) {
    switch (this) {
      case _HealthLevel.good:
        return Colors.green;
      case _HealthLevel.warn:
        return Colors.orange;
      case _HealthLevel.bad:
        return Colors.red;
      case _HealthLevel.busy:
        return cs.primary;
      case _HealthLevel.unknown:
        return cs.onSurfaceVariant;
    }
  }
}

enum _Tone { good, warn, bad, timeout, pending }

extension _ToneX on _Tone {
  Color color(ColorScheme cs) {
    switch (this) {
      case _Tone.good:
        return Colors.green;
      case _Tone.warn:
        return Colors.orange;
      case _Tone.bad:
      case _Tone.timeout:
        return Colors.red;
      case _Tone.pending:
        return cs.onSurfaceVariant;
    }
  }
}

/// 节点延迟 → 颜色语义。
_Tone _nodeTone(bool isPending, int? latency) {
  if (isPending) return _Tone.pending;
  if (latency == null) return _Tone.timeout;
  if (latency <= 800) return _Tone.good;
  if (latency <= 2000) return _Tone.warn;
  return _Tone.bad;
}

// ─────────────────────────────────────────────────────────────────────────
// 小部件
// ─────────────────────────────────────────────────────────────────────────

/// 会呼吸的状态圆点 —— 状态卡的 signature 元素。
class _BreathingDot extends StatelessWidget {
  final Color color;
  final AnimationController controller;

  const _BreathingDot({required this.color, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value;
        final scale = 0.85 + 0.35 * t;
        final glowAlpha = 0.12 + 0.28 * t;
        return SizedBox(
          width: 28,
          height: 28,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: 1 + 0.5 * t,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: glowAlpha),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Transform.scale(
                scale: scale,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.4),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 节点行/胶囊前的延迟状态小圆点。
class _LatencyDot extends StatelessWidget {
  final Color color;

  const _LatencyDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _ConnectedButtonGroupItem {
  final VoidCallback? onPressed;
  final IconData? icon;
  final Widget? loadingWidget;
  final String label;
  final bool isPrimary;

  const _ConnectedButtonGroupItem({
    this.onPressed,
    this.icon,
    this.loadingWidget,
    required this.label,
    this.isPrimary = false,
  });
}

class _ConnectedButtonGroup extends StatelessWidget {
  final List<_ConnectedButtonGroupItem> children;

  const _ConnectedButtonGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final border = BorderSide(color: cs.outline);

    return IntrinsicHeight(
      child: Row(
        children: List.generate(children.length, (i) {
          final item = children[i];
          final isFirst = i == 0;
          final isLast = i == children.length - 1;

          final shape = RoundedRectangleBorder(
            borderRadius: BorderRadius.horizontal(
              left: isFirst ? const Radius.circular(AppRadius.sm) : Radius.zero,
              right: isLast ? const Radius.circular(AppRadius.sm) : Radius.zero,
            ),
          );

          final leftBorder = isFirst ? border : BorderSide.none;
          final rightBorder = isLast ? border : BorderSide.none;

          final effectiveBorder = Border(
            left: leftBorder,
            right: rightBorder,
            top: border,
            bottom: border,
          );

          final buttonWidget = TextButton(
            onPressed: item.onPressed,
            style: ButtonStyle(
              padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              shape: WidgetStateProperty.all(shape),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (item.isPrimary) return cs.primary;
                if (states.contains(WidgetState.disabled)) {
                  return cs.onSurface.withValues(alpha: 0.12);
                }
                return Colors.transparent;
              }),
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (item.isPrimary) return cs.onPrimary;
                if (states.contains(WidgetState.disabled)) {
                  return cs.onSurface.withValues(alpha: 0.38);
                }
                return cs.onSurface;
              }),
              overlayColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.pressed)) {
                  return cs.onSurface.withValues(alpha: 0.12);
                }
                if (states.contains(WidgetState.hovered)) {
                  return cs.onSurface.withValues(alpha: 0.08);
                }
                return null;
              }),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.loadingWidget != null)
                  item.loadingWidget!
                else if (item.icon != null)
                  Icon(item.icon, size: 18),
                const SizedBox(width: 6),
                Text(item.label),
              ],
            ),
          );

          return Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: effectiveBorder,
                borderRadius: shape.borderRadius,
              ),
              child: buttonWidget,
            ),
          );
        }),
      ),
    );
  }
}
