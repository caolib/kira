import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_icon_sizes.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/adaptive_motion.dart';
import '../utils/app_logger.dart';
import '../utils/toast.dart';

/// 左滑只展开操作，不论滑多远都不直接删除整组。
class BookmarkGroupHeader extends StatefulWidget {
  const BookmarkGroupHeader({
    super.key,
    required this.detailsKey,
    required this.resumeKey,
    required this.cover,
    required this.name,
    required this.count,
    required this.pinned,
    required this.onDetails,
    required this.onPin,
    required this.onDelete,
    this.enabled = true,
    this.onResume,
    this.chapter = '',
    this.progress = '',
  });

  final Key detailsKey;
  final Key resumeKey;
  final Widget cover;
  final String name;
  final int count;
  final bool pinned;
  final bool enabled;
  final VoidCallback onDetails;
  final Future<void> Function() onPin;
  final Future<void> Function() onDelete;
  final VoidCallback? onResume;
  final String chapter;
  final String progress;

  @override
  State<BookmarkGroupHeader> createState() => _BookmarkGroupHeaderState();
}

class _BookmarkGroupHeaderState extends State<BookmarkGroupHeader>
    with SingleTickerProviderStateMixin {
  late final _slide = AnimationController(vsync: this);
  bool _busy = false;

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  void _settle(bool open) {
    final target = open ? 1.0 : 0.0;
    if (prefersReducedMotion(context)) {
      _slide.value = target;
    } else {
      _slide.animateTo(
        target,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || !widget.enabled) return;
    setState(() => _busy = true);
    _settle(false);
    try {
      await action();
    } catch (error, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          error,
          stackTrace: stack,
          source: 'bookmark_group_header',
        ),
      );
      if (mounted) {
        showToast(
          context,
          AppLocalizations.of(
            context,
          )!.bookmarksUpdateFailedDetail(error.toString()),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final pinLabel = widget.pinned
        ? l10n.bookmarkGroupUnpin
        : l10n.bookmarkGroupPin;
    final enabled = widget.enabled && !_busy;
    return LayoutBuilder(
      builder: (context, constraints) {
        final buttonWidth = math.min(
          constraints.maxWidth / 2,
          math.max(
            72.0,
            MediaQuery.textScalerOf(context).scale(14) * 4 + AppSpacing.lg,
          ),
        );
        final paneWidth = 2 * buttonWidth;
        return GestureDetector(
          onHorizontalDragStart: enabled ? (_) => _slide.stop() : null,
          onHorizontalDragUpdate: enabled
              ? (d) => _slide.value -= d.delta.dx / paneWidth
              : null,
          onHorizontalDragEnd: enabled
              ? (d) {
                  final velocity = d.primaryVelocity ?? 0;
                  _settle(
                    velocity.abs() > 350 ? velocity < 0 : _slide.value >= .5,
                  );
                }
              : null,
          onHorizontalDragCancel: enabled
              ? () => _settle(_slide.value >= .5)
              : null,
          child: AnimatedBuilder(
            animation: _slide,
            child: _buildFace(context, constraints.maxWidth),
            builder: (context, face) {
              final revealed = _slide.value > 0;
              return TapRegion(
                enabled: revealed,
                onTapOutside: (_) => _settle(false),
                child: ClipRect(
                  child: Stack(
                    children: [
                      if (revealed)
                        Positioned(
                          top: 0,
                          bottom: 0,
                          right: 0,
                          width: paneWidth,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _action(
                                pinLabel,
                                cs.secondaryContainer,
                                cs.onSecondaryContainer,
                                widget.onPin,
                              ),
                              _action(
                                l10n.deleteButton,
                                cs.errorContainer,
                                cs.onErrorContainer,
                                widget.onDelete,
                              ),
                            ],
                          ),
                        ),
                      Transform.translate(
                        offset: Offset(-paneWidth * _slide.value, 0),
                        child: Material(
                          color: cs.surfaceBright,
                          child: Semantics(
                            customSemanticsActions: enabled && !revealed
                                ? {
                                    CustomSemanticsAction(
                                      label: pinLabel,
                                    ): () =>
                                        _run(widget.onPin),
                                    CustomSemanticsAction(
                                      label: l10n.deleteButton,
                                    ): () =>
                                        _run(widget.onDelete),
                                  }
                                : null,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: revealed ? () => _settle(false) : null,
                              child: ExcludeFocus(
                                excluding: revealed,
                                child: ExcludeSemantics(
                                  excluding: revealed,
                                  child: IgnorePointer(
                                    ignoring: revealed,
                                    child: face,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _action(
    String label,
    Color background,
    Color foreground,
    Future<void> Function() action,
  ) => Expanded(
    child: Material(
      color: background,
      child: InkWell(
        onTap: widget.enabled && !_busy ? () => _run(action) : null,
        child: Center(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: foreground),
          ),
        ),
      ),
    ),
  );

  Widget _buildFace(BuildContext context, double width) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return InkWell(
      key: widget.detailsKey,
      onTap: widget.onDetails,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: AspectRatio(aspectRatio: .72, child: widget.cover),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      if (widget.pinned) ...[
                        Icon(
                          Icons.push_pin,
                          size: AppIconSize.xs,
                          color: cs.primary,
                          semanticLabel: l10n.bookmarkGroupPinned,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                      ],
                      Flexible(
                        child: Text(
                          l10n.bookmarksCount(widget.count),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (widget.onResume != null) ...[
              const SizedBox(width: AppSpacing.sm),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.min(192, width * .48),
                ),
                child: _ResumeButton(
                  key: widget.resumeKey,
                  chapter: widget.chapter,
                  progress: widget.progress,
                  onPressed: widget.onResume!,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResumeButton extends StatelessWidget {
  const _ResumeButton({
    super.key,
    required this.chapter,
    required this.progress,
    required this.onPressed,
  });

  final String chapter;
  final String progress;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = AppLocalizations.of(context)!.novelContinueReading;
    final label = chapter.isEmpty && progress.isEmpty ? hint : chapter;
    return Tooltip(
      message: [hint, chapter, progress].where((s) => s.isNotEmpty).join(' · '),
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 42),
          visualDensity: theme.visualDensity.copyWith(vertical: 0),
          tapTargetSize: MaterialTapTargetSize.padded,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.smR),
          textStyle: theme.textTheme.bodySmall,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 数字优先于章节名；即使大字体下数字本身也超宽，仍完整显示。
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (label.isNotEmpty)
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (progress.isNotEmpty)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: math.max(
                        0,
                        constraints.maxWidth - AppIconSize.sm,
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${label.isEmpty ? '' : ' · '}$progress',
                        maxLines: 1,
                      ),
                    ),
                  ),
                const Icon(Icons.chevron_right, size: AppIconSize.sm),
              ],
            );
          },
        ),
      ),
    );
  }
}
