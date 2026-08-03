import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/reader_settings.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/reading_stats.dart';
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
    final tt = Theme.of(context).textTheme;
    showModalBottomSheet<void>(
      context: context,
      // 抽屉弹出后值可能变化（关闭统计），用 StatefulBuilder 重建
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
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
    );
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
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // 概览三数字
                _OverviewCard(
                  comics: comicsCount,
                  chapters: chaptersCount,
                  pages: pagesCount,
                ),
                const SizedBox(height: AppSpacing.md),
                // 常看类型
                _TagsCard(tags: tags),
                const SizedBox(height: AppSpacing.md),
                // 热力图
                _HeatmapCard(daily: daily, since: snap?.since),
                const SizedBox(height: AppSpacing.xxl),
              ]),
            ),
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

class _HeatmapCard extends StatelessWidget {
  final Map<String, int> daily;
  final DateTime? since;
  const _HeatmapCard({required this.daily, this.since});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
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
                  Icons.calendar_month_outlined,
                  size: 20,
                  color: cs.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(l10n.statsActivityHeatmap, style: tt.titleMedium),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            HeatmapGrid(dailyCounts: daily),
            const SizedBox(height: AppSpacing.sm),
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

String _formatDate(DateTime t) =>
    '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
