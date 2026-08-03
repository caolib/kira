import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_spacing.dart';

/// GitHub 风格的阅读活跃度热力图。
///
/// 显示最近 [weeks] 周（默认 53）× 7 天的网格，每格颜色深浅对应当日阅读
/// 章节数。颜色用 [ColorScheme.primary] 的不同透明度分 5 级，跟随主题色。
/// 左侧星期标签（一/三/五），顶部月份标签。单击单元格触发 Tooltip
/// 弹出小气泡显示当日详情（手机无鼠标，tap 模式比悬浮/长按更直观）。
///
/// 打开时默认滚动到最右（最近的日期），让用户立刻看到今天而非一年前。
///
/// 纯 widget 手写，零新依赖。
class HeatmapGrid extends StatefulWidget {
  /// 按 yyyy-MM-dd 索引的每日阅读章节数。
  final Map<String, int> dailyCounts;

  /// 显示的周数。默认 53（约一年）。
  final int weeks;

  /// 终止日期（含）。默认今天。
  final DateTime? end;

  /// 格子圆角。
  final double cellRadius;

  /// 格子大小。
  final double cellSize;

  /// 格子间距。
  final double cellGap;

  /// 空格子的底色。
  final Color? emptyColor;

  const HeatmapGrid({
    super.key,
    required this.dailyCounts,
    this.weeks = 53,
    this.end,
    this.cellRadius = 2,
    this.cellSize = 12,
    this.cellGap = 3,
    this.emptyColor,
  });

  @override
  State<HeatmapGrid> createState() => _HeatmapGridState();
}

class _HeatmapGridState extends State<HeatmapGrid> {
  final _scrollController = ScrollController();
  int _scrollRetries = 0;

  @override
  void initState() {
    super.initState();
    // 默认滚动到最右（最近日期），打开即看到今天而非一年前。
    // 水平 SingleChildScrollView 在 sliver 内，attach 可能在首帧后才完成，
    // 因此轮询等待 hasClients 再跳转（最多重试几帧，防无限循环）。
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
  }

  void _scrollToEnd() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      return;
    }
    if (_scrollRetries++ < 10) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    final weeks = widget.weeks;
    final cellSize = widget.cellSize;
    final cellGap = widget.cellGap;
    final cellRadius = widget.cellRadius;

    // 计算网格起止：end 当周的周日为最后一列。
    final today = widget.end ?? DateTime.now();
    final endSunday = _floorToSunday(today);
    final startSunday = endSunday.subtract(Duration(days: 7 * (weeks - 1)));
    final maxCount = widget.dailyCounts.values.fold<int>(0, _maxInt);

    // 月份标签：每周检查列首日期是否跨月，跨月则标月号。
    final monthLabels = <_MonthLabel>[];
    for (var w = 0; w < weeks; w++) {
      final colDate = startSunday.add(Duration(days: 7 * w));
      if (colDate.month != (colDate.subtract(const Duration(days: 7)).month)) {
        monthLabels.add(_MonthLabel(weekIndex: w, month: colDate.month));
      }
    }

    // 星期标签行（一/三/五 对应 row 1/3/5，row 0=周日）。
    final weekdayLabels = <String>[
      l10n.statsHeatmapWeekdayMon,
      l10n.statsHeatmapWeekdayWed,
      l10n.statsHeatmapWeekdayFri,
    ];

    final cellEmpty = widget.emptyColor ?? cs.surfaceContainerHighest;

    // 固定格子尺寸，清晰可读；窄屏横向滚动（与 GitHub 移动端一致）。
    const labelWidth = 20.0;
    final gridWidth = (cellSize + cellGap) * weeks - cellGap;
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: gridWidth + labelWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 月份标签行
            SizedBox(
              height: 16,
              child: Padding(
                padding: const EdgeInsets.only(left: labelWidth),
                child: Stack(
                  children: [
                    for (final m in monthLabels)
                      Positioned(
                        left: m.weekIndex * (cellSize + cellGap),
                        child: Text(
                          '${m.month}',
                          style: tt.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 星期标签列
                SizedBox(
                  width: labelWidth,
                  height: (cellSize + cellGap) * 7 - cellGap,
                  child: Stack(
                    children: [
                      for (var i = 0; i < weekdayLabels.length; i++)
                        Positioned(
                          top: (i * 2 + 1) * (cellSize + cellGap) - 2,
                          left: 0,
                          child: Text(
                            weekdayLabels[i],
                            style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // 网格：weeks 列 × 7 行
                SizedBox(
                  width: gridWidth,
                  height: (cellSize + cellGap) * 7 - cellGap,
                  child: Stack(
                    children: [
                      for (var w = 0; w < weeks; w++)
                        for (var r = 0; r < 7; r++)
                          _buildCell(
                            context,
                            startSunday,
                            w,
                            r,
                            maxCount,
                            cellEmpty,
                            cellSize,
                            cellGap,
                            cellRadius,
                            l10n,
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Positioned _buildCell(
    BuildContext context,
    DateTime startSunday,
    int week,
    int row,
    int maxCount,
    Color cellEmpty,
    double cellSize,
    double cellGap,
    double cellRadius,
    AppLocalizations l10n,
  ) {
    final date = startSunday.add(Duration(days: week * 7 + row));
    // 未来日期不渲染格子
    final isFuture = date.isAfter(DateTime.now());
    if (isFuture) {
      return Positioned(
        left: week * (cellSize + cellGap),
        top: row * (cellSize + cellGap),
        child: SizedBox(
          width: cellSize,
          height: cellSize,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(cellRadius),
            ),
          ),
        ),
      );
    }
    final key = _dayKey(date);
    final count = widget.dailyCounts[key] ?? 0;
    final cs = Theme.of(context).colorScheme;
    final color = count == 0
        ? cellEmpty
        : _levelColor(cs.primary, count, maxCount);
    // 单击触发 Tooltip（贴在格子上方的小气泡），而非悬浮/长按——
    // 手机无鼠标，悬浮不可用；长按体验差。tap 模式单击即弹。
    final message = count == 0
        ? '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'
        : l10n.statsPagesOnDate(count);
    return Positioned(
      left: week * (cellSize + cellGap),
      top: row * (cellSize + cellGap),
      child: Tooltip(
        message: message,
        triggerMode: TooltipTriggerMode.tap,
        child: SizedBox(
          width: cellSize,
          height: cellSize,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(cellRadius),
            ),
          ),
        ),
      ),
    );
  }

  /// 按"当天阅读页数"固定阈值选 4 级透明度（GitHub 风格）。
  ///
  /// 含义固定、用户间可比，不受章节页数差异影响：
  /// - 1-20 页（浅色）：翻几页浏览
  /// - 21-50 页：日常阅读
  /// - 51-100 页：深度阅读
  /// - 101+ 页（最深）：重度阅读
  Color _levelColor(Color base, int count, int maxCount) {
    double alpha;
    if (count <= 0) {
      // 由调用方处理空格底色，此处不预期为 0
      alpha = 0.0;
    } else if (count <= 20) {
      alpha = 0.35;
    } else if (count <= 50) {
      alpha = 0.55;
    } else if (count <= 100) {
      alpha = 0.75;
    } else {
      alpha = 1.0;
    }
    return base.withValues(alpha: alpha);
  }

  static DateTime _floorToSunday(DateTime t) {
    final d = DateTime(t.year, t.month, t.day);
    return d.subtract(Duration(days: d.weekday % 7));
  }

  static String _dayKey(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}'
      '-${t.month.toString().padLeft(2, '0')}'
      '-${t.day.toString().padLeft(2, '0')}';
}

int _maxInt(int a, int b) => a > b ? a : b;

class _MonthLabel {
  final int weekIndex;
  final int month;
  const _MonthLabel({required this.weekIndex, required this.month});
}

/// 热力图图例（少 → 多），与 [HeatmapGrid] 配套使用。
class HeatmapLegend extends StatelessWidget {
  final Color? emptyColor;
  final Color? baseColor;
  const HeatmapLegend({super.key, this.emptyColor, this.baseColor});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    final empty = emptyColor ?? cs.surfaceContainerHighest;
    final base = baseColor ?? cs.primary;
    final levels = [
      empty,
      base.withValues(alpha: 0.35),
      base.withValues(alpha: 0.55),
      base.withValues(alpha: 0.75),
      base.withValues(alpha: 1.0),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.statsHeatmapLess,
          style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(width: AppSpacing.xs),
        for (final c in levels)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(2),
              ),
              child: const SizedBox(width: 12, height: 12),
            ),
          ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          l10n.statsHeatmapMore,
          style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}
