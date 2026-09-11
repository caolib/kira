import 'package:flutter/material.dart';

import '../theme/app_radius.dart';

/// RikkaHub `Select` 的 Flutter 版：胶囊形触发器（tonal 叠色）+ 箭头随
/// 展开/收起上下翻转，点击弹出与触发器等宽的下拉菜单（Overlay 跟随
/// 锚点，点外部自动收起）。
///
/// 用法（放 ListTile 的 trailing）：
/// ```dart
/// trailing: SelectTile<String>(
///   value: _locale,
///   items: [
///     SelectItem('', l10n.languageSystem),
///     SelectItem('zh', l10n.languageSimplified),
///   ],
///   onChanged: _user.setLocale,
/// ),
/// ```
final class SelectTile<T> extends StatefulWidget {
  final T value;
  final List<SelectItem<T>> items;
  final ValueChanged<T> onChanged;

  const SelectTile({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  State<SelectTile<T>> createState() => _SelectTileState<T>();
}

final class SelectItem<T> {
  final T value;
  final String label;

  /// 胶囊里显示的短文本；缺省用 [label]（菜单项始终显示 [label]）。
  final String? compactLabel;

  const SelectItem(this.value, this.label, {this.compactLabel});

  String get pillLabel => compactLabel ?? label;
}

class _SelectTileState<T> extends State<SelectTile<T>> {
  final _layerLink = LayerLink();
  OverlayEntry? _menuEntry;
  bool _expanded = false;

  void _dismissMenu() {
    _menuEntry?.remove();
    _menuEntry = null;
    if (_expanded) setState(() => _expanded = false);
  }

  void _toggle() {
    if (_expanded) {
      _dismissMenu();
      return;
    }
    setState(() => _expanded = true);
    final overlay = Overlay.of(context);
    final width = context.size?.width;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    _menuEntry = OverlayEntry(
      builder: (context) => Stack(children: [
        // 全屏透明捕获层：点外部收起（带方向性返回手势穿透）。
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _dismissMenu,
            onPanStart: (_) => _dismissMenu(),
          ),
        ),
        CompositedTransformFollower(
          link: _layerLink,
          targetAnchor: Alignment.bottomLeft,
          child: SizedBox(
            width: width,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              color: cs.surfaceContainerHigh,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final item in widget.items)
                    InkWell(
                      onTap: () {
                        widget.onChanged(item.value);
                        _dismissMenu();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodyMedium?.copyWith(
                              color: item.value == widget.value
                                  ? cs.primary
                                  : cs.onSurface,
                              fontWeight: item.value == widget.value
                                  ? FontWeight.w600
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ]),
    );
    overlay.insert(_menuEntry!);
  }

  @override
  void dispose() {
    _menuEntry?.remove();
    _menuEntry = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final label = widget.items
        .where((i) => i.value == widget.value)
        .map((i) => i.pillLabel)
        .firstOrNull ?? '';

    return CompositedTransformTarget(
      link: _layerLink,
      child: Material(
        // tonalElevation 4 的近似：容器色上叠一层低透明度 primary。
        color: Color.alphaBlend(
          cs.primary.withValues(alpha: 0.08),
          cs.surfaceContainerHighest,
        ),
        borderRadius: AppRadius.fullR,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _toggle,
          borderRadius: AppRadius.fullR,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 168),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodyMedium,
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
