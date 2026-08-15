import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

/// 阅读活跃度条形图。
///
/// 与 [HeatmapGrid] 互补的另一种展示：按天显示，窗口为 [windowDays] 天
/// （默认 14，即两周），每天一根竖向柱子，高度对应当日阅读页数。默认落在
/// 包含"今天"的那两周（窗口末尾对齐本周日，含今天），可通过左右箭头以 7 天
/// 为步长切换到其他周，但不能切到未来。单击柱子弹出当日详情 Tooltip。
///
/// 与 [HeatmapGrid] 一致：纯 widget 手写，零新依赖，颜色跟随 [ColorScheme.primary]。
class BarChartGrid extends StatefulWidget {
  /// 按 yyyy-MM-dd 索引的每日阅读页数（与 [HeatmapGrid] 同源）。
  final Map<String, int> dailyCounts;

  /// 窗口天数。默认 14（两周）。
  final int windowDays;

  /// 切换步长。默认 7（一次切一周）。
  final int stepDays;

  /// 终止日期（含）。默认今天。
  final DateTime? end;

  const BarChartGrid({
    super.key,
    required this.dailyCounts,
    this.windowDays = 14,
    this.stepDays = 7,
    this.end,
  });

  @override
  State<BarChartGrid> createState() => _BarChartGridState();
}

class _BarChartGridState extends State<BarChartGrid> {
  /// 当前窗口相对于默认窗口的偏移天数（负=过去，0=包含今天）。
  late int _offsetDays;

  @override
  void initState() {
    super.initState();
    _offsetDays = 0;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;

    final today = widget.end ?? DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    // 默认窗口末尾 = 含"今天"的那一周的周日（周一=1..周日=7）。
    // 今天周日时 weekday=7 → 7-7=0，窗口末尾即今天，含今天，正确；
    // 其余日子窗口末尾在本周日（>= 今天），窗口自然包含今天。
    final thisSunday = todayDate.add(Duration(days: 7 - todayDate.weekday));
    final windowEnd = thisSunday.add(Duration(days: _offsetDays));
    // 不能切到未来周：offset=0 时窗口已含今天所在周，再前进就进未来，禁掉。
    // 只有往回退过（offset<0）才能再前进回到当前周。
    final allowForward = _offsetDays < 0;
    // 不能回退超过有数据的范围（~730 天）
    final allowBackward = _offsetDays - widget.stepDays >= -_maxPastOffset;

    final windowStart = windowEnd.subtract(
      Duration(days: widget.windowDays - 1),
    );

    final bars = <_DayBar>[];
    var maxCount = 0;
    for (var i = 0; i < widget.windowDays; i++) {
      final d = windowStart.add(Duration(days: i));
      final isFuture = d.isAfter(todayDate);
      final count = isFuture ? 0 : (widget.dailyCounts[_dayKey(d)] ?? 0);
      if (count > maxCount) maxCount = count;
      bars.add(
        _DayBar(
          date: d,
          count: count,
          isFuture: isFuture,
          isToday: _sameDay(d, todayDate),
        ),
      );
    }

    const chartHeight = 120.0;
    const axisHeight = 20.0;
    const barGap = 4.0;
    const yAxisWidth = 28.0;

    // Y 轴刻度：顶部=max，中部=max/2，底部=0。maxCount=0 时不画数字。
    final hasScale = maxCount > 0;
    final midCount = (maxCount / 2).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 窗口范围 + 切换控件
        Row(
          children: [
            _NavButton(
              icon: Icons.chevron_left_rounded,
              onTap: allowBackward
                  ? () => setState(() => _offsetDays -= widget.stepDays)
                  : null,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '${_formatDate(windowStart)} ~ ${_formatDate(windowEnd)}',
                textAlign: TextAlign.center,
                style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _NavButton(
              icon: Icons.chevron_right_rounded,
              onTap: allowForward
                  ? () => setState(() => _offsetDays += widget.stepDays)
                  : null,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        // 柱子区（左 Y 轴 + 右柱列）+ 横轴
        LayoutBuilder(
          builder: (context, constraints) {
            // 柱列可用宽度 = 总宽 - Y 轴列宽
            final barsWidth = (constraints.maxWidth - yAxisWidth).clamp(
              0.0,
              constraints.maxWidth,
            );
            final totalGap = barGap * (bars.length - 1);
            final barWidth = (barsWidth - totalGap) / bars.length;
            final safeBarWidth = barWidth.isFinite && barWidth > 0
                ? barWidth
                : 8.0;
            final yLabelStyle = tt.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: chartHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Y 轴刻度列
                      SizedBox(
                        width: yAxisWidth,
                        child: Stack(
                          children: [
                            if (hasScale)
                              Positioned(
                                top: 0,
                                right: 2,
                                child: Text('$maxCount', style: yLabelStyle),
                              ),
                            if (hasScale)
                              Positioned(
                                top: (chartHeight / 2 - 6).clamp(
                                  0.0,
                                  chartHeight,
                                ),
                                right: 2,
                                child: Text('$midCount', style: yLabelStyle),
                              ),
                            Positioned(
                              bottom: 0,
                              right: 2,
                              child: Text('0', style: yLabelStyle),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      // 柱列
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (var i = 0; i < bars.length; i++)
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    right: i == bars.length - 1 ? 0 : barGap,
                                  ),
                                  child: _Bar(
                                    bar: bars[i],
                                    maxCount: maxCount,
                                    chartHeight: chartHeight,
                                    baseColor: cs.primary,
                                    trackColor: cs.surfaceContainerHighest,
                                    mutedColor: cs.surfaceContainerLow,
                                    barWidth: safeBarWidth,
                                    l10n: l10n,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                // 横轴星期标签：左侧留 Y 轴等宽占位，使标签与柱子对齐
                SizedBox(
                  height: axisHeight,
                  child: Row(
                    children: [
                      const SizedBox(width: yAxisWidth),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Row(
                          children: [
                            for (var i = 0; i < bars.length; i++)
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    right: i == bars.length - 1 ? 0 : barGap,
                                  ),
                                  child: Text(
                                    bars[i].isFuture
                                        ? ''
                                        : _weekdayLabel(bars[i].date, l10n),
                                    textAlign: TextAlign.center,
                                    style: tt.labelSmall?.copyWith(
                                      color: bars[i].isToday
                                          ? cs.primary
                                          : cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  /// 最大可回退偏移（天）。历史数据最多保留 ~730 天，给同样上限即可，
  /// 超出后窗口起始日早于有数据的日子，柱子自然全空，不报错。
  static const int _maxPastOffset = 730;

  static String _weekdayLabel(DateTime d, AppLocalizations l10n) {
    // 每天都显示星期（一~日），便于一周内横向定位；今天用主题色高亮。
    switch (d.weekday) {
      case 1:
        return l10n.statsBarChartWeekdayMon;
      case 2:
        return l10n.statsBarChartWeekdayTue;
      case 3:
        return l10n.statsBarChartWeekdayWed;
      case 4:
        return l10n.statsBarChartWeekdayThu;
      case 5:
        return l10n.statsBarChartWeekdayFri;
      case 6:
        return l10n.statsBarChartWeekdaySat;
      case 7:
        return l10n.statsBarChartWeekdaySun;
      default:
        return '';
    }
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _dayKey(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}'
      '-${t.month.toString().padLeft(2, '0')}'
      '-${t.day.toString().padLeft(2, '0')}';

  static String _formatDate(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}

class _DayBar {
  final DateTime date;
  final int count;
  final bool isFuture;
  final bool isToday;
  const _DayBar({
    required this.date,
    required this.count,
    required this.isFuture,
    required this.isToday,
  });
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _NavButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final disabled = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.fullR,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Icon(
          icon,
          size: 24,
          color: disabled ? cs.surfaceContainerHighest : cs.primary,
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final _DayBar bar;
  final int maxCount;
  final double chartHeight;
  final Color baseColor;
  final Color trackColor;
  final Color mutedColor;
  final double barWidth;
  final AppLocalizations l10n;

  const _Bar({
    required this.bar,
    required this.maxCount,
    required this.chartHeight,
    required this.baseColor,
    required this.trackColor,
    required this.mutedColor,
    required this.barWidth,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = maxCount <= 0 ? 0.0 : bar.count / maxCount;
    final filledHeight = (chartHeight * ratio).clamp(2.0, chartHeight);
    final message = bar.isFuture
        ? _fmt(bar.date)
        : bar.count == 0
        ? _fmt(bar.date)
        : l10n.statsPagesOnDate(bar.count);
    final color = bar.isFuture
        ? mutedColor
        : bar.isToday
        ? baseColor
        : baseColor.withValues(alpha: 0.65);
    return Tooltip(
      message: message,
      triggerMode: TooltipTriggerMode.tap,
      child: SizedBox(
        height: chartHeight,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            // 轨道底色
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: trackColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            // 实际柱子（0 值时不画填充，只留轨道）
            if (bar.count > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: filledHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _fmt(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}
