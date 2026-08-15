import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/reader_settings.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/reading_stats.dart';
import '../utils/toast.dart';
import '../widgets/bar_chart_grid.dart';
import '../widgets/error_retry_view.dart';
import '../widgets/heatmap_grid.dart';
import '../widgets/shimmer_skeleton.dart';

/// 阅读统计页。
///
/// 两态：
/// - 未开启（`reader.readingStatsEnabled == false`）：显示开启引导——说明
///   记录什么、可随时关闭/清除、数据仅本地，加一个开启按钮。点击开启后转为
///   已开启态，数据从空开始，之后随阅读增量累积。
/// - 已开启：`CustomScrollView` 展示概览三数字、常看类型 top10、阅读活跃度
///   热力图。所有数据只读 1 个 prefs 键（`reading_stats_v1`），零网络。
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  final _reader = ReaderSettings();

  bool _loading = false;
  bool _initializing = false;
  String? _error;
  ReadingStatsSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    if (_reader.readingStatsEnabled) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snap = await ReadingStats.load();
      if (!mounted) return;
      setState(() {
        _snapshot = snap;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// 开启统计：设开关为 true。数据从空开始，之后随阅读增量累积。
  Future<void> _enableStats() async {
    setState(() => _initializing = true);
    try {
      await _reader.setReadingStatsEnabled(true);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      setState(() => _initializing = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _initializing = false;
      });
    }
  }

  Future<void> _clearData() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.statsClearConfirmTitle),
        content: Text(l10n.statsClearConfirmContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancelButton),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.statsClearButton),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ReadingStats.clear();
    if (_reader.readingStatsEnabled) {
      // 开启态：清除后显示空态，之后随阅读增量累积。
      await _load();
    } else {
      if (!mounted) return;
      setState(() {});
    }
  }

  /// 从底部弹出设置抽屉：统计功能开关 / 清除数据。
  ///
  /// 沿用项目常见底部抽屉模式（如 general_page 的设置项）：SafeArea +
  /// Column + SwitchListTile/ListTile，无第三方依赖。
  void _showSettingsSheet() {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    showModalBottomSheet<void>(
      context: context,
      // 内容较高（拖拽列表 + 图表样式 + 清除按钮），允许占满更多屏幕高度并滚动。
      isScrollControlled: true,
      // 抽屉弹出后值可能变化（关闭统计），用 StatefulBuilder 重建。
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          // 内容可能超出可视高（拖拽列表 + 图表样式 + 清除按钮），
          // 用可滚动容器而非固定 Column，避免底部按钮被裁。
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.xs,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(l10n.statsSettings, style: tt.titleMedium),
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.insights_rounded),
                  title: Text(l10n.statsDisableButton),
                  value: _reader.readingStatsEnabled,
                  onChanged: (value) async {
                    if (!value) {
                      await _reader.setReadingStatsEnabled(false);
                      if (!ctx.mounted) return;
                      setSheetState(() {}); // 抽屉内开关状态更新
                      if (!mounted) return;
                      setState(() {
                        _snapshot = null;
                        _loading = false;
                        _error = null;
                      });
                      Navigator.pop(ctx); // 关闭后回到未开启态，抽屉收起
                    }
                    // 开启在未开启态的 body 内处理，此抽屉仅在已开启态可见
                  },
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                // 显示组件：概览 / 常看类型 / 阅读活跃度，至少保留一个。
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    0,
                  ),
                  child: Row(
                    children: [
                      Text(
                        l10n.statsShowSections,
                        style: tt.labelMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        l10n.statsDragToReorder,
                        style: tt.labelSmall?.copyWith(color: cs.outline),
                      ),
                    ],
                  ),
                ),
                // 可拖拽排序 + 显示开关。拖拽把手在行首，长按拖动。
                _SectionReorderList(
                  ctx: ctx,
                  setSheetState: setSheetState,
                  onToggle: _toggleSection,
                  onReorder: (newOrder) async {
                    await _reader.setReadingStatsSectionOrder(newOrder);
                    if (!ctx.mounted) return;
                    setSheetState(() {});
                    if (!mounted) return;
                    setState(() {}); // 页面卡片列表按新顺序重建
                  },
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                // 图表样式：热力图 / 条形图
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    0,
                  ),
                  child: Text(
                    l10n.statsChartStyle,
                    style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                RadioGroup<int>(
                  groupValue: _reader.readingStatsChartStyle,
                  onChanged: (value) async {
                    if (value == null) return;
                    await _reader.setReadingStatsChartStyle(value);
                    if (!ctx.mounted) return;
                    setSheetState(() {});
                    if (!mounted) return;
                    setState(() {}); // 图表区重建
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<int>(
                        value: 0,
                        title: Text(l10n.statsChartStyleHeatmap),
                        subtitle: Text(
                          l10n.statsChartStyleHeatmapDesc,
                          style: tt.bodySmall,
                        ),
                        dense: true,
                      ),
                      RadioListTile<int>(
                        value: 1,
                        title: Text(l10n.statsChartStyleBar),
                        subtitle: Text(
                          l10n.statsChartStyleBarDesc,
                          style: tt.bodySmall,
                        ),
                        dense: true,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: Text(l10n.statsClearButton),
                  onTap: () {
                    Navigator.pop(ctx);
                    _clearData();
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 切换某个统计组件的显示开关。
  ///
  /// 关闭时若其余可见组件为 0，则拒绝并提示"至少保留一个"，保持开关回弹到开。
  ///
  /// [sectionId] 为 `overview` / `tags` / `activity`，借此解析当前值、其余可见
  /// 数与对应 setter，避免调用方手算。
  Future<void> _toggleSection(
    BuildContext sheetCtx,
    void Function(void Function()) setSheetState, {
    required String sectionId,
    required bool next,
  }) async {
    final show = <String, bool>{
      'overview': _reader.readingStatsShowOverview,
      'tags': _reader.readingStatsShowTags,
      'activity': _reader.readingStatsShowActivityChart,
    };
    final current = show[sectionId]!;
    final othersVisible = show.entries
        .where((e) => e.key != sectionId)
        .fold(0, (s, e) => s + (e.value ? 1 : 0));
    Future<void> apply() {
      switch (sectionId) {
        case 'overview':
          return _reader.setReadingStatsShowOverview(next);
        case 'tags':
          return _reader.setReadingStatsShowTags(next);
        case 'activity':
          return _reader.setReadingStatsShowActivityChart(next);
      }
      return Future.value();
    }

    if (current && !next && othersVisible == 0) {
      final l10n = AppLocalizations.of(context)!;
      if (mounted) {
        // 顶部 toast 提示；用 sheet 的 ctx 让 Overlay 正确锚定在可见层级。
        showToast(sheetCtx, l10n.statsKeepAtLeastOne, isError: true);
        setSheetState(() {}); // 让开关回弹
      }
      return;
    }
    await apply();
    if (!sheetCtx.mounted) return;
    setSheetState(() {});
    if (!mounted) return;
    setState(() {}); // 页面卡片列表重建
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final enabled = _reader.readingStatsEnabled;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.statsTitle)),
      body: enabled ? _buildEnabledBody() : _buildDisabledBody(),
      // 已开启态才显示设置入口；未开启态的开启按钮已在 body 内。
      floatingActionButton: enabled
          ? FloatingActionButton(
              onPressed: _showSettingsSheet,
              tooltip: l10n.statsSettings,
              child: const Icon(Icons.tune_rounded),
            )
          : null,
    );
  }

  // ── 未开启态 ──────────────────────────────────────────────────────

  Widget _buildDisabledBody() {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insights_rounded,
              size: 72,
              color: cs.primary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(l10n.statsEnableTitle, style: tt.titleLarge),
            const SizedBox(height: AppSpacing.xl),
            // 记录内容说明卡
            Card(
              color: cs.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoRow(
                      icon: Icons.book_outlined,
                      text: l10n.statsRecordComics,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _InfoRow(
                      icon: Icons.list_alt_rounded,
                      text: l10n.statsRecordChapters,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _InfoRow(
                      icon: Icons.image_outlined,
                      text: l10n.statsRecordPages,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _InfoRow(
                      icon: Icons.style_outlined,
                      text: l10n.statsRecordTags,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _InfoRow(
                      icon: Icons.calendar_month_outlined,
                      text: l10n.statsRecordHeatmap,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.statsPrivacyNote,
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (_initializing)
              const CircularProgressIndicator()
            else
              FilledButton.icon(
                onPressed: _enableStats,
                icon: const Icon(Icons.power_settings_new_rounded),
                label: Text(l10n.statsEnableButton),
              ),
          ],
        ),
      ),
    );
  }

  // ── 已开启态 ──────────────────────────────────────────────────────

  Widget _buildEnabledBody() {
    final l10n = AppLocalizations.of(context)!;
    if (_loading && _snapshot == null) {
      return _buildLoadingBody();
    }
    if (_error != null && _snapshot == null) {
      return ErrorRetryView(message: l10n.loadingFailed, onRetry: _load);
    }
    final snap = _snapshot;
    // 无数据时不显示空态，直接按 0 渲染（热力图、tag 列表自然为空）。
    final comicsCount = snap == null ? 0 : comicsReadCount(snap);
    final chaptersCount = snap == null ? 0 : chaptersReadCount(snap);
    final pagesCount = snap == null ? 0 : pagesReadCount(snap);
    final tags = snap == null ? const <TagCount>[] : topTags(snap);
    final daily = snap?.daily ?? const <String, int>{};
    // 按显示开关收集可见卡片，卡片之间留 md 间距。
    // 按持久化顺序 + 显示开关收集可见卡片，卡片之间留 md 间距。
    final cards = <Widget>[];
    for (final id in _reader.readingStatsSectionOrder) {
      final visible = switch (id) {
        'overview' => _reader.readingStatsShowOverview,
        'tags' => _reader.readingStatsShowTags,
        'activity' => _reader.readingStatsShowActivityChart,
        _ => false,
      };
      if (!visible) continue;
      final card = switch (id) {
        'overview' => _OverviewCard(
          comics: comicsCount,
          chapters: chaptersCount,
          pages: pagesCount,
        ),
        'tags' => _TagsCard(tags: tags),
        'activity' => _ActivityChartCard(daily: daily, since: snap?.since),
        _ => null,
      };
      if (card == null) continue;
      if (cards.isNotEmpty) cards.add(const SizedBox(height: AppSpacing.md));
      cards.add(card);
    }
    // 至少保留一个由设置抽屉层强制；此处防御性兜底。
    if (cards.isEmpty) {
      cards.add(
        _OverviewCard(
          comics: comicsCount,
          chapters: chaptersCount,
          pages: pagesCount,
        ),
      );
    }
    cards.add(const SizedBox(height: AppSpacing.xxl));
    // 刷新时顶部进度条
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          if (_loading)
            const SliverToBoxAdapter(
              child: LinearProgressIndicator(minHeight: 2),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            sliver: SliverList(delegate: SliverChildListDelegate(cards)),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingBody() {
    return const Padding(
      padding: EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          ShimmerShell(
            child: ShimmerBox(
              width: double.infinity,
              height: 100,
              radius: AppRadius.lg,
            ),
          ),
          SizedBox(height: AppSpacing.md),
          ShimmerShell(
            child: ShimmerBox(
              width: double.infinity,
              height: 160,
              radius: AppRadius.lg,
            ),
          ),
          SizedBox(height: AppSpacing.md),
          ShimmerShell(
            child: ShimmerBox(
              width: double.infinity,
              height: 140,
              radius: AppRadius.lg,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 子组件 ──────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: cs.primary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(text, style: tt.bodyMedium)),
      ],
    );
  }
}

class _OverviewCard extends StatelessWidget {
  final int comics;
  final int chapters;
  final int pages;
  const _OverviewCard({
    required this.comics,
    required this.chapters,
    required this.pages,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                child: _StatCell(
                  icon: Icons.book_outlined,
                  value: _format(comics),
                  label: l10n.statsComicsRead,
                ),
              ),
              const VerticalDivider(width: 1, indent: 8, endIndent: 8),
              Expanded(
                child: _StatCell(
                  icon: Icons.list_alt_rounded,
                  value: _format(chapters),
                  label: l10n.statsChaptersRead,
                ),
              ),
              const VerticalDivider(width: 1, indent: 8, endIndent: 8),
              Expanded(
                child: _StatCell(
                  icon: Icons.image_outlined,
                  value: _format(pages),
                  label: l10n.statsPagesRead,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 千位逗号：1234 → '1,234'。统计值可能很大，逗号便于快速读取。
  static String _format(int n) {
    final s = n.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }
}

class _StatCell extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _StatCell({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: cs.primary),
        const SizedBox(height: AppSpacing.xs),
        FittedBox(
          child: Text(
            value,
            style: tt.headlineMedium?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _TagsCard extends StatelessWidget {
  final List<TagCount> tags;
  const _TagsCard({required this.tags});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final maxCount = tags.isEmpty ? 1 : tags.first.count;
    return Card(
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.style_outlined, size: 20, color: cs.primary),
                const SizedBox(width: AppSpacing.sm),
                Text(l10n.statsTopTags, style: tt.titleMedium),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (tags.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Center(
                  child: Text(
                    l10n.statsNoTags,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              )
            else
              for (final t in tags)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _TagBar(name: t.name, count: t.count, max: maxCount),
                ),
          ],
        ),
      ),
    );
  }
}

class _TagBar extends StatelessWidget {
  final String name;
  final int count;
  final int max;
  const _TagBar({required this.name, required this.count, required this.max});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final ratio = max <= 0 ? 0.0 : count / max;
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            name,
            style: tt.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: ClipRRect(
            borderRadius: AppRadius.xsR,
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 10,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(cs.primary),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 32,
          child: Text(
            '$count',
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

/// 阅读活跃度图表卡片。
///
/// 根据 [ReaderSettings.readingStatsChartStyle] 渲染热力图或条形图；
/// 图例同步切换。卡片标题保持"阅读活跃度"。
class _ActivityChartCard extends StatelessWidget {
  final Map<String, int> daily;
  final DateTime? since;
  const _ActivityChartCard({required this.daily, this.since});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final style = ReaderSettings().readingStatsChartStyle;
    final useBar = style == 1;
    return Card(
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  useBar
                      ? Icons.bar_chart_rounded
                      : Icons.calendar_month_outlined,
                  size: 20,
                  color: cs.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(l10n.statsActivityHeatmap, style: tt.titleMedium),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            useBar
                ? BarChartGrid(dailyCounts: daily)
                : HeatmapGrid(dailyCounts: daily),
            const SizedBox(height: AppSpacing.sm),
            if (!useBar)
              const Align(
                alignment: Alignment.centerRight,
                child: HeatmapLegend(),
              ),
            if (since != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  l10n.statsRecordingSince(_formatDate(since!)),
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 设置抽屉里"显示组件"节的可拖拽列表。
///
/// 三行顺序由 [ReaderSettings.readingStatsSectionOrder] 决定；长按行首把手拖动
/// 重排，松手后调 [onReorder] 写回。每行右侧的显示开关走 [onToggle]，关闭
/// 最后一个时会由父级弹出"至少保留一个"提示。
class _SectionReorderList extends StatelessWidget {
  final BuildContext ctx;
  final void Function(void Function()) setSheetState;
  final Future<void> Function(
    BuildContext sheetCtx,
    void Function(void Function()) setSheetState, {
    required String sectionId,
    required bool next,
  })
  onToggle;
  final Future<void> Function(List<String> newOrder) onReorder;

  const _SectionReorderList({
    required this.ctx,
    required this.setSheetState,
    required this.onToggle,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final reader = ReaderSettings();
    final order = reader.readingStatsSectionOrder;
    final meta = <String, ({IconData icon, String label, bool value})>{
      'overview': (
        icon: Icons.book_outlined,
        label: l10n.statsSectionOverview,
        value: reader.readingStatsShowOverview,
      ),
      'tags': (
        icon: Icons.style_outlined,
        label: l10n.statsSectionTags,
        value: reader.readingStatsShowTags,
      ),
      'activity': (
        icon: Icons.calendar_month_outlined,
        label: l10n.statsSectionActivity,
        value: reader.readingStatsShowActivityChart,
      ),
    };

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: order.length,
      onReorderItem: (oldIndex, newIndex) {
        // onReorderItem 已对 newIndex 做过校正（移除 oldIndex 处的项后），
        // 直接 remove+insert 即可。
        final next = List<String>.of(order);
        final item = next.removeAt(oldIndex);
        next.insert(newIndex, item);
        onReorder(next);
      },
      proxyDecorator: (child, _, _) => Material(
        color: Colors.transparent,
        elevation: 2,
        borderRadius: BorderRadius.circular(8),
        child: child,
      ),
      itemBuilder: (context, i) {
        final id = order[i];
        final m = meta[id]!;
        return Padding(
          key: ValueKey(id),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            children: [
              // 拖拽把手：长按启动拖动
              ReorderableDragStartListener(
                index: i,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Icon(
                    Icons.drag_handle_rounded,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              Icon(m.icon, color: cs.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  m.label,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              Switch(
                value: m.value,
                onChanged: (v) =>
                    onToggle(ctx, setSheetState, sectionId: id, next: v),
              ),
            ],
          ),
        );
      },
    );
  }
}

String _formatDate(DateTime t) =>
    '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
