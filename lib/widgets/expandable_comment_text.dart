import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_icon_sizes.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/adaptive_motion.dart';

/// 漫画与小说共用的三行评论正文；长正文点按展开/收起，短正文保留父级操作。
class ExpandableCommentText extends StatefulWidget {
  const ExpandableCommentText({
    super.key,
    required this.text,
    required this.style,
    required this.backgroundColor,
  });

  final String text;
  final TextStyle? style;
  final Color backgroundColor;

  @override
  State<ExpandableCommentText> createState() => _ExpandableCommentTextState();
}

class _ExpandableCommentTextState extends State<ExpandableCommentText> {
  static const _maxLines = 3;
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant ExpandableCommentText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _expanded = false;
  }

  bool _isTextOverflowing(BuildContext context, double maxWidth) {
    if (maxWidth <= 0 || !maxWidth.isFinite) return false;
    final painter = TextPainter(
      text: TextSpan(
        text: widget.text,
        style: DefaultTextStyle.of(context).style.merge(widget.style),
      ),
      textDirection: Directionality.of(context),
      maxLines: _maxLines,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: maxWidth);
    final overflowing = painter.didExceedMaxLines;
    painter.dispose();
    return overflowing;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final baseFontSize = widget.style?.fontSize ?? 14;
    final hintStyle = widget.style?.copyWith(
      color: cs.primary,
      fontWeight: FontWeight.w700,
      fontSize: baseFontSize > 13 ? baseFontSize - 1 : baseFontSize,
      height: 1.2,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!_isTextOverflowing(context, constraints.maxWidth)) {
          return Text(widget.text, style: widget.style);
        }
        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.text,
              maxLines: _expanded ? null : _maxLines,
              overflow: _expanded ? TextOverflow.clip : TextOverflow.ellipsis,
              style: widget.style,
            ),
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_expanded) ...[
                      ExcludeSemantics(
                        child: Text(
                          '…',
                          key: const ValueKey('comment-collapsed-ellipsis'),
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: cs.primary,
                                fontSize: baseFontSize + 4,
                                fontWeight: FontWeight.w800,
                                height: 1,
                              ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                    Text(
                      _expanded
                          ? l10n.chapterCommentsCollapse
                          : l10n.comicCommentExpandFullText,
                      style: hintStyle,
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: AppIconSize.sm,
                      color: cs.primary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: AppRadius.mdR,
            onTap: () => setState(() => _expanded = !_expanded),
            // 减少动画时直接布局，避免零时长 AnimatedSize 在布局中重入。
            child: prefersReducedMotion(context)
                ? content
                : AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: content,
                  ),
          ),
        );
      },
    );
  }
}
