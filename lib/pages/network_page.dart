import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../api/api_transport.dart'
    show
        routes,
        defaultCopyApiHost,
        defaultCopyAppVersion,
        copyLoginHostOptions;
import '../l10n/app_localizations.dart';
import '../models/user_manager.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/network_proxy.dart';
import '../utils/screen_layout.dart';
import '../utils/time_format.dart';
import '../utils/toast.dart';

part 'network/network_actions.dart';
part 'network/network_extra_hosts.dart';
part 'network/network_proxy_card.dart';
part 'network/network_shared_widgets.dart';

/// 网络诊断与配置页 —— 仪表盘卡片流。
///
/// 设计理念：把整页当作一块「网络仪表盘」。
///  - 顶部是一条会呼吸的状态条，绿/橙/红三色实时反映连通性，一眼判断当前健康度。
///  - 下方是可点选的节点卡片网格：每张卡是一颗节点，单击切换。卡片自带状态条，
///    超时/低延迟/高延迟用颜色与高度区分，不再用文字副标题挤占空间。
///  - 代理设置采用「行内展开」——选「手动」时输入框就地铺开，不再单独成卡。
///  - COPY 高级设置默认折叠为一条入口，点开就地展开。
/// 全程只在主 ListView 内交互，不弹 sheet，所有控制随时可见。
class NetworkPage extends StatefulWidget {
  const NetworkPage({super.key});

  @override
  State<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends State<NetworkPage>
    with TickerProviderStateMixin {
  /// extension part 文件里的成员不是 State 子类成员，不能直接调用受保护的
  /// [setState]，统一经由这个转发方法。
  void _setState(VoidCallback fn) => setState(fn);
  final _user = UserManager();
  final _networkApi = ApiClient().network;
  final _proxyAddressController = TextEditingController();
  final _copyApiHostController = TextEditingController();
  final _copyAppVersionController = TextEditingController();

  bool _testingLatency = false;
  bool _refreshingSystemProxy = false;
  bool _autoFillingCopySettings = false;
  bool _advancedExpanded = false;
  NetworkProxyType _manualProxyType = NetworkProxyType.http;

  /// 节点延迟结果。key 为线路索引(>=0)或 -1(其他固定 host)。
  Map<int, Map<String, int?>> _latencyResults = {};
  Set<String> _pendingLatencyHosts = {};

  late final AnimationController _breathController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _proxyAddressController.text = _manualProxyAddress;
    _copyApiHostController.text = _user.copyApiHost;
    _copyAppVersionController.text = _user.copyAppVersion;
    _manualProxyType = _user.networkProxyType;
    _user.addListener(_onChanged);
    // 进入页面即自动测速一次,让用户第一时间看到各线路/节点延迟。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_testingLatency && _latencyResults.isEmpty) {
        _testLatency();
      }
    });
  }

  @override
  void dispose() {
    _breathController.dispose();
    _user.removeListener(_onChanged);
    _proxyAddressController.dispose();
    _copyApiHostController.dispose();
    _copyAppVersionController.dispose();
    super.dispose();
  }

  String get _manualProxyAddress {
    if (!_user.hasManualProxy) return '';
    final host = _user.networkProxyHost;
    final needsBrackets =
        host.contains(':') && !host.startsWith('[') && !host.endsWith(']');
    final displayHost = needsBrackets ? '[$host]' : host;
    return '$displayHost:${_user.networkProxyPort}';
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  // ─────────────────────────────────────────────────────────────────────
  /// 健康度推导：根据当前线路的节点延迟均值判断。
  _HealthLevel _deriveHealth() {
    if (_testingLatency) return _HealthLevel.busy;
    final avg = _averageLatency(_latencyResults[_user.apiRoute]);
    if (avg == null) return _HealthLevel.unknown;
    if (avg <= 800) return _HealthLevel.good;
    if (avg <= 2000) return _HealthLevel.warn;
    return _HealthLevel.bad;
  }

  // ─────────────────────────────────────────────────────────────────────
  // 页面骨架
  // ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final screenWidth = MediaQuery.of(context).size.width;
    final hp = ScreenLayout.horizontalPadding(screenWidth);
    final isWide =
        ScreenLayout.contentWidth(screenWidth) >= ScreenLayout.wideBreakpoint;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.networkTitle),
        actions: [
          IconButton(
            tooltip: l10n.networkRefreshSystemProxy,
            onPressed: _refreshingSystemProxy ? null : _refreshSystemProxy,
            icon: _refreshingSystemProxy
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(hp, 8, hp, 32),
        children: [
          _buildStatusBar(l10n, tt, cs),
          const SizedBox(height: AppSpacing.lg),
          _buildModeSelector(l10n, tt, cs),
          const SizedBox(height: AppSpacing.lg),
          _buildNodeGrid(l10n, tt, cs),
          const SizedBox(height: AppSpacing.lg),
          // 宽屏：代理设置与高级设置双列并排；窄屏纵向堆叠。
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildProxyCard(l10n, tt, cs)),
                const SizedBox(width: AppSpacing.lg),
                Expanded(child: _buildAdvancedCard(l10n, tt, cs)),
              ],
            )
          else ...[
            _buildProxyCard(l10n, tt, cs),
            const SizedBox(height: AppSpacing.lg),
            _buildAdvancedCard(l10n, tt, cs),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // 顶部状态条（呼吸灯）
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildStatusBar(AppLocalizations l10n, TextTheme tt, ColorScheme cs) {
    final health = _deriveHealth();
    final color = health.color(cs);

    String primary;
    String secondary;
    switch (health) {
      case _HealthLevel.good:
        primary = l10n.networkStatusGood;
        secondary = _statusSecondaryGood(l10n);
      case _HealthLevel.warn:
        primary = l10n.networkStatusWarn;
        secondary = _statusSecondaryWarn(l10n);
      case _HealthLevel.bad:
        primary = l10n.networkStatusBad;
        secondary = _statusSecondaryBad(l10n);
      case _HealthLevel.busy:
        primary = l10n.networkStatusBusy;
        secondary = l10n.networkTestingNodes;
      case _HealthLevel.unknown:
        primary = l10n.networkStatusUnknown;
        secondary = l10n.networkStatusUnknownHint;
    }

    return Card(
      color: Color.alphaBlend(color.withValues(alpha: 0.12), cs.surface),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            _BreathingDot(color: color, controller: _breathController),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    primary,
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    secondary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            _buildStatusMetric(l10n, tt, cs),
          ],
        ),
      ),
    );
  }

  /// 状态条右侧的关键指标胶囊：两种模式下分别显示「线路/节点」+ 延迟。
  Widget _buildStatusMetric(
    AppLocalizations l10n,
    TextTheme tt,
    ColorScheme cs,
  ) {
    final isFixed =
        _user.networkSelectionMode == NetworkSelectionMode.fixedNode;
    final label = isFixed
        ? l10n.networkModeFixedNodeShort
        : l10n.networkModeRoute;
    final value = isFixed
        ? (l10n.networkNodeLabel(_fixedNodeNumber()))
        : l10n.networkRouteLabel(_user.apiRoute + 1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: AppRadius.mdR,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: tt.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  int _fixedNodeNumber() {
    final host = _user.fixedNodeHost;
    if (host == null) return 1;
    for (var r = 0; r < routes.length; r++) {
      final idx = routes[r].indexOf(host);
      if (idx >= 0) return _nodeNumber(r, idx);
    }
    return 1;
  }

  String _statusSecondaryGood(AppLocalizations l10n) {
    final ms = _bestNumericLatency();
    return ms != null
        ? l10n.networkStatusGoodHint(ms)
        : l10n.networkStatusGoodFallback;
  }

  String _statusSecondaryWarn(AppLocalizations l10n) {
    final ms = _bestNumericLatency();
    return ms != null
        ? l10n.networkStatusWarnHint(ms)
        : l10n.networkHighLatencyProxySuggestion;
  }

  String _statusSecondaryBad(AppLocalizations l10n) =>
      l10n.networkHighLatencyProxySuggestion;

  /// 当前可用的最低数值延迟（ms），用于状态条副文案；无数据返回 null。
  int? _bestNumericLatency() {
    int? best;
    for (final route in _latencyResults.values) {
      for (final v in route.values) {
        if (v != null && (best == null || v < best)) best = v;
      }
    }
    return best;
  }

  // ─────────────────────────────────────────────────────────────────────
  // 模式选择
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildModeSelector(
    AppLocalizations l10n,
    TextTheme tt,
    ColorScheme cs,
  ) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<NetworkSelectionMode>(
        segments: [
          ButtonSegment(
            value: NetworkSelectionMode.route,
            icon: const Icon(Icons.alt_route_rounded, size: 18),
            label: Text(l10n.networkModeRoute),
          ),
          ButtonSegment(
            value: NetworkSelectionMode.fixedNode,
            icon: const Icon(Icons.push_pin_rounded, size: 18),
            label: Text(l10n.networkModeFixedNodeShort),
          ),
        ],
        selected: {_user.networkSelectionMode},
        onSelectionChanged: (v) => _setSelectionMode(v.first),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // 节点网格（route / fixedNode 模式）
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildNodeGrid(AppLocalizations l10n, TextTheme tt, ColorScheme cs) {
    final isFixed =
        _user.networkSelectionMode == NetworkSelectionMode.fixedNode;
    // route 模式始终展示两条线路(哪怕尚未测速),让用户可直接点选线路;
    // fixedNode 与「其他」分组按已有延迟结果展示。
    final List<MapEntry<int, Map<String, int?>>> routeEntries;
    final extraEntries = _latencyResults[-1] ?? const <String, int?>{};
    if (isFixed) {
      routeEntries = _latencyResults.entries.where((e) => e.key >= 0).toList();
    } else {
      final indexed = <MapEntry<int, Map<String, int?>>>[];
      for (var r = 0; r < routes.length; r++) {
        indexed.add(MapEntry(r, _latencyResults[r] ?? const {}));
      }
      routeEntries = indexed;
    }

    final showHint = _latencyResults.isEmpty && !_testingLatency;
    final isWide =
        ScreenLayout.contentWidth(MediaQuery.sizeOf(context).width) >=
        ScreenLayout.wideBreakpoint;

    // 各线路分组（线路 1/2/… + 其他）：窄屏纵向堆叠、宽屏横向并排成列。
    final groups = <Widget>[
      for (final entry in routeEntries)
        _buildRouteGroup(
          routeIndex: entry.key,
          hosts: entry.value,
          isFixed: isFixed,
          wide: isWide,
          l10n: l10n,
          tt: tt,
          cs: cs,
        ),
      if (extraEntries.isNotEmpty)
        _buildExtraGroup(
          extraEntries,
          wide: isWide,
          l10n: l10n,
          tt: tt,
          cs: cs,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                isFixed
                    ? l10n.networkNodeGridFixedHint
                    : l10n.networkNodeGridRouteHint,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            _buildTestButton(l10n, tt, cs),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (showHint)
          _buildEmptyHint(l10n, tt, cs)
        else if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < groups.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.md),
                Expanded(child: groups[i]),
              ],
            ],
          )
        else
          for (var i = 0; i < groups.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            groups[i],
          ],
      ],
    );
  }

  Widget _buildTestButton(AppLocalizations l10n, TextTheme tt, ColorScheme cs) {
    return FilledButton.tonalIcon(
      onPressed: _testingLatency ? null : _testLatency,
      icon: _testingLatency
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: cs.primary,
              ),
            )
          : const Icon(Icons.bolt_rounded, size: 18),
      label: Text(l10n.networkTestLatencyShort),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildEmptyHint(AppLocalizations l10n, TextTheme tt, ColorScheme cs) {
    return Card(
      color: Color.alphaBlend(
        cs.surfaceContainerHighest.withValues(alpha: 0.3),
        cs.surface,
      ),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
          child: Column(
            children: [
              Icon(
                Icons.network_check_rounded,
                size: 30,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.networkNotTested,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 单条线路分组：标签行（线路名 + 平均延迟）+ 节点卡片。
  /// 窄屏节点横排 3 列；宽屏（作为并排列时）纵向堆叠为横向卡片。
  Widget _buildRouteGroup({
    required int routeIndex,
    required Map<String, int?> hosts,
    required bool isFixed,
    required bool wide,
    required AppLocalizations l10n,
    required TextTheme tt,
    required ColorScheme cs,
  }) {
    final routeHosts = routes[routeIndex];
    // route 模式下可能尚无延迟结果,需用 routes 的完整 host 列表补齐,
    // 以便整条线路都能点选/展示为「未测」。
    final orderedHosts = isFixed
        ? hosts.entries.toList()
        : routeHosts.map((h) => MapEntry(h, hosts[h])).toList();
    final average = _averageLatency(hosts);
    final hasPending = orderedHosts.any(
      (e) => _isLatencyPending(routeIndex, e.key),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: AppRadius.xsR,
                ),
                child: Text(
                  l10n.networkRouteLabel(routeIndex + 1),
                  style: tt.labelSmall?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (average != null || hasPending)
                Text(
                  average == null
                      ? (hasPending
                            ? l10n.networkAverageTesting
                            : l10n.networkAverageTimeout)
                      : l10n.networkAverageLatency(average.round()),
                  style: tt.labelSmall?.copyWith(
                    color: average == null
                        ? cs.onSurfaceVariant
                        : _latencyTone(average, cs),
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
        if (wide)
          Column(
            children: [
              for (var i = 0; i < orderedHosts.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: i == orderedHosts.length - 1 ? 0 : 10,
                  ),
                  child: _buildNodeCard(
                    routeIndex: routeIndex,
                    localIndex: i,
                    host: orderedHosts[i].key,
                    latency: orderedHosts[i].value,
                    isFixedMode: isFixed,
                    horizontal: true,
                    l10n: l10n,
                    tt: tt,
                    cs: cs,
                  ),
                ),
            ],
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 10.0;
              final width = (constraints.maxWidth - spacing * 2) / 3;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: List.generate(orderedHosts.length, (i) {
                  return SizedBox(
                    width: width,
                    child: _buildNodeCard(
                      routeIndex: routeIndex,
                      localIndex: i,
                      host: orderedHosts[i].key,
                      latency: orderedHosts[i].value,
                      isFixedMode: isFixed,
                      l10n: l10n,
                      tt: tt,
                      cs: cs,
                    ),
                  );
                }),
              );
            },
          ),
      ],
    );
  }

  Widget _buildNodeCard({
    required int routeIndex,
    required int localIndex,
    required String host,
    required int? latency,
    required bool isFixedMode,
    required AppLocalizations l10n,
    required TextTheme tt,
    required ColorScheme cs,
    bool horizontal = false,
  }) {
    final isPending = _isLatencyPending(routeIndex, host);
    // route 模式下,选中状态对齐当前 apiRoute(整条线路高亮);
    // fixedNode 模式下,仅当前固定节点高亮。
    final isSelected = isFixedMode
        ? _user.fixedNodeHost == host
        : _user.apiRoute == routeIndex;
    final tone = isPending
        ? _Tone.pending
        : (latency == null
              ? _Tone.timeout
              : (latency <= 800
                    ? _Tone.good
                    : latency <= 2000
                    ? _Tone.warn
                    : _Tone.bad));
    final color = tone.color(cs);

    final title = l10n.networkNodeLabel(_nodeNumber(routeIndex, localIndex));
    final valueText = isPending
        ? l10n.networkTesting
        : (latency == null ? l10n.networkTimeout : '$latency ms');

    // route 模式点击节点 → 切到该节点所在的线路;
    // fixedNode 模式点击节点 → 固定到该节点。
    final canTap = !isPending;
    final onTap = canTap
        ? () {
            if (isFixedMode) {
              _user.setFixedNodeHost(host);
            } else {
              _user.setApiRoute(routeIndex);
            }
          }
        : null;

    return Card(
      color: cs.surface,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            // 选中态用更淡的填充,避免过于抢眼;无描边,靠填充+文字色区分。
            color: isSelected
                ? Color.alphaBlend(
                    cs.primary.withValues(alpha: 0.08),
                    cs.surface,
                  )
                : cs.surface,
            borderRadius: AppRadius.lgR,
          ),
          child: horizontal
              ? Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.labelMedium?.copyWith(
                          fontWeight: isSelected
                              ? FontWeight.w800
                              : FontWeight.w700,
                          color: isSelected ? cs.primary : cs.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      valueText,
                      style: tt.labelLarge?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        height: 1,
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.labelMedium?.copyWith(
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w700,
                              color: isSelected ? cs.primary : cs.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        valueText,
                        style: tt.labelLarge?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          height: 1,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
