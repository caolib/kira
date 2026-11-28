import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/reader_settings.dart';
import '../providers/novel_providers.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/app_logger.dart';
import '../utils/reading_stats.dart';
import '../utils/screen_layout.dart';
import '../utils/toast.dart';
import '../widgets/app_sheet.dart';
import '../widgets/bar_chart_grid.dart';
import '../widgets/error_retry_view.dart';
import '../widgets/heatmap_grid.dart';
import '../widgets/section_header.dart';
import '../widgets/settings_section.dart';
import '../widgets/shimmer_skeleton.dart';

/// 阅读统计页。
///
/// 两态：
/// - 未开启（`reader.readingStatsEnabled == false`）：显示开启引导——说明
///   记录什么、可随时关闭/清除、数据仅本地，加一个开启按钮。点击开启后转为
///   已开启态，小说统计全零时可从本地断点初始化，之后随实际阅读增量累积。
/// - 已开启：同一滚动页展示漫画与小说分区；各自配置概览、常看类型及
///   阅读活跃度。所有数据只读本地统计快照，零网络。
class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key});

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends ConsumerState<StatsPage> {
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
      await ReadingStats.initializeNovelsFromHistory();
      if (!mounted) return;
      await ReadingStats.fillMissingNovelTags(ref.read(localNovelTagsProvider));
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

  /// 开启统计，小说统计全零时导入本地断点，之后随实际阅读增量累积。
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

  Future<void> _clearData({required bool isNovel}) async {
    final l10n = AppLocalizations.of(context)!;
    final type = isNovel ? l10n.novelTitle : l10n.comicTabLabel;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.statsClearTypeConfirmTitle(type)),
        content: Text(l10n.statsClearTypeConfirmContent(type)),
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
    try {
      await ReadingStats.clear(novel: isNovel);
      if (!mounted) return;
      await _load();
    } catch (error, stack) {
      await AppLogger.instance.recordWarning(
        error,
        stackTrace: stack,
        source: 'stats_page.clear',
      );
      if (!mounted) return;
      showToast(context, error.toString(), isError: true);
    }
  }

  /// 沿用阅读设置的 AppSheet / 分段切换；主统计页仍同时展示两类数据。
  void _showSettingsSheet() {
    final l10n = AppLocalizations.of(context)!;
    final tt = Theme.of(context).textTheme;
    var isNovel = false;
    showAppSheet<void>(
      context,
      maxHeightFactor: 0.7,
      child: StatefulBuilder(
        builder: (ctx, setSheetState) => SingleChildScrollView(
          key: PageStorageKey('stats-${isNovel ? 'novel' : 'comic'}-settings'),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.statsSettings, style: tt.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              SettingsSection(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.insights_rounded),
                  title: Text(l10n.statsDisableButton),
                  value: _reader.readingStatsEnabled,
                  onChanged: (value) async {
                    if (!value) {
                      await _reader.setReadingStatsEnabled(false);
                      if (!ctx.mounted) return;
                      setSheetState(() {});
                      if (!mounted) return;
                      setState(() {
                        _snapshot = null;
                        _loading = false;
                        _error = null;
                      });
                      Navigator.pop(ctx);
                    }
                    // 开启在未开启态的 body 内处理，此抽屉仅在已开启态可见。
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SegmentedButton<bool>(
                key: const ValueKey('stats-settings-tabs'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text(
                      l10n.comicTabLabel,
                      key: const ValueKey('stats-settings-comic-tab'),
                    ),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text(
                      l10n.novelTitle,
                      key: const ValueKey('stats-settings-novel-tab'),
                    ),
                  ),
                ],
                selected: {isNovel},
                onSelectionChanged: (selection) =>
                    setSheetState(() => isNovel = selection.single),
              ),
              const SizedBox(height: AppSpacing.sm),
              ..._buildDomainSettings(ctx, setSheetState, isNovel: isNovel),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDomainSettings(
    BuildContext ctx,
    StateSetter setSheetState, {
    required bool isNovel,
  }) {
    final l10n = AppLocalizations.of(ctx)!;
    final cs = Theme.of(ctx).colorScheme;
    final tt = Theme.of(ctx).textTheme;
    final domain = isNovel ? 'novel' : 'comic';
    return [
      SwitchListTile(
        key: ValueKey('stats-$domain-visible'),
        contentPadding: EdgeInsets.zero,
        title: Text(isNovel ? l10n.novelTitle : l10n.comicTabLabel),
        subtitle: Text(l10n.statsVisibilityHint, style: tt.bodySmall),
        value: isNovel
            ? _reader.readingStatsShowNovels
            : _reader.readingStatsShowComics,
        onChanged: (value) async {
          final otherVisible = isNovel
              ? _reader.readingStatsShowComics
              : _reader.readingStatsShowNovels;
          if (!value && !otherVisible) {
            showToast(ctx, l10n.statsKeepAtLeastOneType, isError: true);
            return;
          }
          await _saveStatsSetting(
            ctx,
            setSheetState,
            () => isNovel
                ? _reader.setReadingStatsShowNovels(value)
                : _reader.setReadingStatsShowComics(value),
          );
        },
      ),
      SettingsSection(
        key: ValueKey(
          isNovel
              ? 'stats-novel-section-settings-card'
              : 'stats-section-settings-card',
        ),
        child: Column(
          children: [
            // 显示组件：概览 / 常看类型 / 阅读活跃度，至少保留一个。
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    l10n.statsShowSections,
                    style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
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
              order: _sectionOrder(isNovel),
              visibility: _sectionVisibility(isNovel),
              onToggle:
                  (sheetCtx, update, {required sectionId, required next}) =>
                      _toggleSection(
                        sheetCtx,
                        update,
                        isNovel: isNovel,
                        sectionId: sectionId,
                        next: next,
                      ),
              onReorder: (newOrder) => _saveStatsSetting(
                ctx,
                setSheetState,
                () => isNovel
                    ? _reader.setNovelReadingStatsSectionOrder(newOrder)
                    : _reader.setReadingStatsSectionOrder(newOrder),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      SettingsSection(
        key: ValueKey(
          isNovel
              ? 'stats-novel-chart-settings-card'
              : 'stats-chart-settings-card',
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 图表样式：热力图 / 条形图
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                l10n.statsChartStyle,
                style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            RadioGroup<int>(
              groupValue: isNovel
                  ? _reader.novelReadingStatsChartStyle
                  : _reader.readingStatsChartStyle,
              onChanged: (value) async {
                if (value == null) return;
                await _saveStatsSetting(
                  ctx,
                  setSheetState,
                  () => isNovel
                      ? _reader.setNovelReadingStatsChartStyle(value)
                      : _reader.setReadingStatsChartStyle(value),
                );
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
                      isNovel
                          ? l10n.statsNovelChartStyleBarDesc
                          : l10n.statsChartStyleBarDesc,
                      style: tt.bodySmall,
                    ),
                    dense: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      SettingsSection(
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.delete_sweep_outlined),
          key: ValueKey('stats-$domain-clear'),
          title: Text(l10n.statsClearButton),
          onTap: () {
            Navigator.pop(ctx);
            _clearData(isNovel: isNovel);
          },
        ),
      ),
    ];
  }

  List<String> _sectionOrder(bool isNovel) => isNovel
      ? _reader.novelReadingStatsSectionOrder
      : _reader.readingStatsSectionOrder;

  Map<String, bool> _sectionVisibility(bool isNovel) => {
    'overview': isNovel
        ? _reader.novelReadingStatsShowOverview
        : _reader.readingStatsShowOverview,
    'tags': isNovel
        ? _reader.novelReadingStatsShowTags
        : _reader.readingStatsShowTags,
    'activity': isNovel
        ? _reader.novelReadingStatsShowActivityChart
        : _reader.readingStatsShowActivityChart,
  };

  /// 切换某个统计组件的显示开关。
  ///
  /// 关闭时若其余可见组件为 0，则拒绝并提示"至少保留一个"，保持开关回弹到开。
  ///
  /// [sectionId] 为 `overview` / `tags` / `activity`，借此解析当前值、其余可见
  /// 数与对应 setter，避免调用方手算。
  Future<void> _toggleSection(
    BuildContext sheetCtx,
    void Function(void Function()) setSheetState, {
    required bool isNovel,
    required String sectionId,
    required bool next,
  }) async {
    final show = _sectionVisibility(isNovel);
    final current = show[sectionId]!;
    final othersVisible = show.entries
        .where((e) => e.key != sectionId)
        .fold(0, (s, e) => s + (e.value ? 1 : 0));
    Future<void> apply() {
      switch (sectionId) {
        case 'overview':
          return isNovel
              ? _reader.setNovelReadingStatsShowOverview(next)
              : _reader.setReadingStatsShowOverview(next);
        case 'tags':
          return isNovel
              ? _reader.setNovelReadingStatsShowTags(next)
              : _reader.setReadingStatsShowTags(next);
        case 'activity':
          return isNovel
              ? _reader.setNovelReadingStatsShowActivityChart(next)
              : _reader.setReadingStatsShowActivityChart(next);
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
    await _saveStatsSetting(sheetCtx, setSheetState, apply);
  }

  Future<void> _saveStatsSetting(
    BuildContext sheetCtx,
    StateSetter setSheetState,
    Future<void> Function() save,
  ) async {
    try {
      await save();
    } catch (error, stack) {
      await AppLogger.instance.recordWarning(
        error,
        stackTrace: stack,
        source: 'stats_page.settings',
      );
      if (sheetCtx.mounted) {
        showToast(sheetCtx, error.toString(), isError: true);
      }
      return;
    }
    if (sheetCtx.mounted) setSheetState(() {});
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final enabled = _reader.readingStatsEnabled;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.statsTitle)),
      body: enabled ? _buildEnabledBody() : _buildDisabledBody(),
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
              color: cs.surfaceBright,
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
    if (_loading && _snapshot == null) return _buildLoadingBody();
    if (_error != null && _snapshot == null) {
      return ErrorRetryView(message: _error, onRetry: _load);
    }
    final screenWidth = MediaQuery.sizeOf(context).width;
    final hp = ScreenLayout.horizontalPadding(screenWidth);
    final sections = [
      if (_reader.readingStatsShowComics) _buildDomain(isNovel: false),
      if (_reader.readingStatsShowNovels) _buildDomain(isNovel: true),
    ];
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final useColumns =
        sections.length == 2 &&
        screenWidth - hp * 2 >= 840 * textScale.clamp(1.0, 2.0);
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        key: const PageStorageKey('reading-stats'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (_loading)
            const SliverToBoxAdapter(
              child: LinearProgressIndicator(minHeight: 2),
            ),
          SliverPadding(
            // 预留悬浮设置按钮与系统安全区，页底提示不被遮挡。
            padding: EdgeInsets.fromLTRB(
              hp,
              AppSpacing.lg,
              hp,
              AppSpacing.xxl + 56 + MediaQuery.paddingOf(context).bottom,
            ),
            sliver: SliverList.list(
              children: [
                if (useColumns)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: sections[0]),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: sections[1]),
                    ],
                  )
                else
                  for (final (index, section) in sections.indexed) ...[
                    if (index > 0) const SizedBox(height: AppSpacing.xl),
                    section,
                  ],
                const SizedBox(height: AppSpacing.lg),
                Text(
                  AppLocalizations.of(context)!.statsAccuracyHint,
                  key: const ValueKey('stats-accuracy-hint'),
                  textAlign: TextAlign.center,
                  style: AppTypography.meta(Theme.of(context).textTheme)
                      ?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDomain({required bool isNovel}) {
    final l10n = AppLocalizations.of(context)!;
    final snap = _snapshot;
    // 无数据时不显示空态，直接按 0 渲染（热力图、tag 列表自然为空）。
    final booksCount = snap == null
        ? 0
        : isNovel
        ? novelsReadCount(snap)
        : comicsReadCount(snap);
    final middleCount = snap == null
        ? 0
        : isNovel
        ? novelVolumesReadCount(snap)
        : chaptersReadCount(snap);
    final lastCount = snap == null
        ? 0
        : isNovel
        ? novelChaptersReadCount(snap)
        : pagesReadCount(snap);
    final tags = snap == null
        ? const <TagCount>[]
        : isNovel
        ? topNovelTags(snap)
        : topTags(snap);
    final daily =
        (isNovel ? snap?.novelDaily : snap?.daily) ?? const <String, int>{};
    final since = isNovel ? snap?.novelSince : snap?.since;
    final overview = _OverviewCard(
      books: booksCount,
      middleCount: middleCount,
      lastCount: lastCount,
      words: isNovel && snap != null ? novelWordsReadCount(snap) : 0,
      isNovel: isNovel,
    );
    final entries = <(String, Widget)>[];
    for (final id in _sectionOrder(isNovel)) {
      final visible = _sectionVisibility(isNovel)[id] ?? false;
      if (!visible) continue;
      final card = switch (id) {
        'overview' => overview,
        'tags' => _TagsCard(tags: tags),
        'activity' => _ActivityChartCard(
          daily: daily,
          since: since,
          isNovel: isNovel,
        ),
        _ => null,
      };
      if (card == null) continue;
      entries.add((id, card));
    }
    // 至少保留一个由设置抽屉层强制；此处防御性兜底。
    if (entries.isEmpty) {
      entries.add(('overview', overview));
    }

    final domain = isNovel ? 'novel' : 'comic';
    return Column(
      key: ValueKey('stats-$domain'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: isNovel ? l10n.novelTitle : l10n.comicTabLabel,
          icon: isNovel ? Icons.menu_book_outlined : Icons.book_outlined,
        ),
        for (final entry in entries) ...[
          const SizedBox(height: AppSpacing.md),
          KeyedSubtree(
            key: ValueKey('stats-$domain-${entry.$1}'),
            child: entry.$2,
          ),
        ],
      ],
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
  final int books;
  final int middleCount;
  final int lastCount;
  final int words;
  final bool isNovel;
  const _OverviewCard({
    required this.books,
    required this.middleCount,
    required this.lastCount,
    required this.words,
    required this.isNovel,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final cells = [
      _StatCell(
        icon: Icons.book_outlined,
        value: _format(books),
        label: isNovel ? l10n.statsNovelsRead : l10n.statsComicsRead,
      ),
      _StatCell(
        icon: isNovel ? Icons.library_books_outlined : Icons.list_alt_rounded,
        value: _format(middleCount),
        label: isNovel ? l10n.statsNovelVolumesRead : l10n.statsChaptersRead,
      ),
      _StatCell(
        icon: isNovel ? Icons.list_alt_rounded : Icons.image_outlined,
        value: _format(lastCount),
        label: isNovel ? l10n.statsChaptersRead : l10n.statsPagesRead,
      ),
      if (isNovel)
        _StatCell(
          icon: Icons.text_fields_rounded,
          value: _format(words),
          label: l10n.statsNovelWordsRead,
        ),
    ];
    return Card(
      color: cs.surfaceBright,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            if (constraints.maxWidth >=
                cells.length * 80 * scale.clamp(1.0, 1.5)) {
              return IntrinsicHeight(
                child: Row(
                  children: [
                    for (final (index, cell) in cells.indexed) ...[
                      if (index > 0)
                        const VerticalDivider(
                          width: 1,
                          indent: 8,
                          endIndent: 8,
                        ),
                      Expanded(child: cell),
                    ],
                  ],
                ),
              );
            }
            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.lg,
              children: [
                for (final cell in cells)
                  SizedBox(
                    width: (constraints.maxWidth - AppSpacing.sm) / 2,
                    child: cell,
                  ),
              ],
            );
          },
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
              color: cs.onSurface,
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
      color: cs.surfaceBright,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.style_outlined, size: 20, color: cs.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(l10n.statsTopTags, style: tt.titleMedium)),
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
        Text(
          '$count',
          style: tt.labelSmall?.copyWith(color: cs.onSurface),
          textAlign: TextAlign.end,
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
  final bool isNovel;
  const _ActivityChartCard({
    required this.daily,
    required this.isNovel,
    this.since,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final reader = ReaderSettings();
    final style = isNovel
        ? reader.novelReadingStatsChartStyle
        : reader.readingStatsChartStyle;
    final useBar = style == 1;
    final countLabel = isNovel
        ? l10n.statsNovelWordsOnDate
        : l10n.statsPagesOnDate;
    return Card(
      color: cs.surfaceBright,
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
                Expanded(
                  child: Text(l10n.statsActivityHeatmap, style: tt.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            useBar
                ? BarChartGrid(dailyCounts: daily, countLabel: countLabel)
                : HeatmapGrid(
                    dailyCounts: daily,
                    countLabel: countLabel,
                    thresholds: isNovel
                        ? const [1000, 5000, 10000]
                        : const [50, 150, 300],
                  ),
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
  final List<String> order;
  final Map<String, bool> visibility;

  const _SectionReorderList({
    required this.ctx,
    required this.setSheetState,
    required this.onToggle,
    required this.onReorder,
    required this.order,
    required this.visibility,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final meta = <String, ({IconData icon, String label, bool value})>{
      'overview': (
        icon: Icons.book_outlined,
        label: l10n.statsSectionOverview,
        value: visibility['overview']!,
      ),
      'tags': (
        icon: Icons.style_outlined,
        label: l10n.statsSectionTags,
        value: visibility['tags']!,
      ),
      'activity': (
        icon: Icons.calendar_month_outlined,
        label: l10n.statsSectionActivity,
        value: visibility['activity']!,
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
