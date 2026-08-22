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
import '../utils/time_format.dart';
import '../utils/toast.dart';

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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _buildStatusBar(l10n, tt, cs),
          const SizedBox(height: AppSpacing.lg),
          _buildModeSelector(l10n, tt, cs),
          const SizedBox(height: AppSpacing.lg),
          _buildNodeGrid(l10n, tt, cs),
          const SizedBox(height: AppSpacing.lg),
          _buildProxyCard(l10n, tt, cs),
          const SizedBox(height: AppSpacing.lg),
          _buildAdvancedCard(l10n, tt, cs),
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
        else
          ..._buildRouteGroups(routeEntries, isFixed, l10n, tt, cs),
        if (extraEntries.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _buildExtraGroup(extraEntries, l10n, tt, cs),
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

  List<Widget> _buildRouteGroups(
    Iterable<MapEntry<int, Map<String, int?>>> entries,
    bool isFixed,
    AppLocalizations l10n,
    TextTheme tt,
    ColorScheme cs,
  ) {
    final widgets = <Widget>[];
    for (final entry in entries) {
      final routeIndex = entry.key;
      final routeHosts = routes[routeIndex];
      final hosts = entry.value;
      // route 模式下可能尚无延迟结果,需用 routes 的完整 host 列表补齐,
      // 以便整条线路都能点选/展示为「未测」。
      final orderedHosts = isFixed
          ? hosts.entries.toList()
          : routeHosts.map((h) => MapEntry(h, hosts[h])).toList();
      final average = _averageLatency(hosts);
      final hasPending = orderedHosts.any(
        (e) => _isLatencyPending(routeIndex, e.key),
      );

      widgets.add(
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
      );
      widgets.add(
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
      );
      widgets.add(const SizedBox(height: AppSpacing.sm));
    }
    return widgets;
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
          child: Column(
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

  Widget _buildExtraGroup(
    Map<String, int?> extra,
    AppLocalizations l10n,
    TextTheme tt,
    ColorScheme cs,
  ) {
    final entries = extra.entries.toList();
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
                  color: cs.secondaryContainer,
                  borderRadius: AppRadius.xsR,
                ),
                child: Text(
                  l10n.networkOtherRouteGroup,
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSecondaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 10.0;
            const columns = 3;
            final width =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: List.generate(entries.length, (i) {
                return SizedBox(
                  width: width,
                  child: _buildExtraCard(
                    host: entries[i].key,
                    latency: entries[i].value,
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

  Widget _buildExtraCard({
    required String host,
    required int? latency,
    required AppLocalizations l10n,
    required TextTheme tt,
    required ColorScheme cs,
  }) {
    final isPending = _isLatencyPending(-1, host);
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
    final title = _networkApi.getExtraApiHostLabel(host, l10n);
    final valueText = isPending
        ? l10n.networkTesting
        : (latency == null ? l10n.networkTimeout : '$latency ms');

    return Card(
      color: Color.alphaBlend(
        cs.surfaceContainerHighest.withValues(alpha: 0.35),
        cs.surface,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.labelSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.xs),
            if (_testingLatency && isPending)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            else
              Text(
                valueText,
                style: tt.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // 代理卡（行内展开）
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildProxyCard(AppLocalizations l10n, TextTheme tt, ColorScheme cs) {
    final mode = _user.networkProxyMode;
    final isManual = mode == NetworkProxyMode.manual;

    return Card(
      color: cs.surfaceContainerLow,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 6),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, color: cs.tertiary, size: 22),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    l10n.networkProxySettings,
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _ProxyPill(
                  active: _hasActiveProxy,
                  label: NetworkProxy.activeProxyDescription(l10n),
                  tt: tt,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<NetworkProxyMode>(
                segments: [
                  ButtonSegment(
                    value: NetworkProxyMode.system,
                    icon: const Icon(Icons.desktop_windows_rounded, size: 18),
                    label: Text(l10n.networkProxySystem),
                  ),
                  ButtonSegment(
                    value: NetworkProxyMode.manual,
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: Text(l10n.networkProxyManual),
                  ),
                  ButtonSegment(
                    value: NetworkProxyMode.direct,
                    icon: const Icon(Icons.link_off_rounded, size: 18),
                    label: Text(l10n.networkProxyDirect),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (v) => _setProxyMode(v.first),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: isManual
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<NetworkProxyType>(
                            segments: const [
                              ButtonSegment(
                                value: NetworkProxyType.http,
                                label: Text('HTTP'),
                              ),
                              ButtonSegment(
                                value: NetworkProxyType.socks,
                                label: Text('SOCKS5'),
                              ),
                            ],
                            selected: {_manualProxyType},
                            onSelectionChanged: (v) {
                              setState(() => _manualProxyType = v.first);
                            },
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextField(
                          controller: _proxyAddressController,
                          decoration: InputDecoration(
                            labelText: l10n.networkProxyAddress,
                            hintText: l10n.networkProxyAddressHint,
                            prefixIcon: const Icon(Icons.link_rounded),
                            border: const OutlineInputBorder(),
                          ),
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _saveManualProxy(),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _saveManualProxy,
                            icon: const Icon(Icons.save_outlined),
                            label: Text(l10n.networkSaveAndEnableManualProxy),
                          ),
                        ),
                      ],
                    ),
                  )
                : mode == NetworkProxyMode.direct
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            l10n.networkProxyDirectHint,
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  bool get _hasActiveProxy {
    switch (_user.networkProxyMode) {
      case NetworkProxyMode.manual:
        return _user.hasManualProxy;
      case NetworkProxyMode.system:
        return NetworkProxy.systemProxy != null;
      case NetworkProxyMode.direct:
        return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // 高级设置卡片（默认折叠，点击标题展开）
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildAdvancedCard(
    AppLocalizations l10n,
    TextTheme tt,
    ColorScheme cs,
  ) {
    return Card(
      color: cs.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () =>
                  setState(() => _advancedExpanded = !_advancedExpanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                child: Row(
                  children: [
                    Icon(Icons.tune_rounded, color: cs.secondary, size: 22),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        l10n.networkAdvancedSettings,
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      'COPY',
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    AnimatedRotation(
                      turns: _advancedExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.expand_more_rounded,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _advancedExpanded
                ? _buildAdvancedContent(l10n, tt, cs)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  /// 高级设置(COPY API 配置)的本体内容。
  Widget _buildAdvancedContent(
    AppLocalizations l10n,
    TextTheme tt,
    ColorScheme cs,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(height: 1, color: cs.outlineVariant),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.networkCopyAutoUpdate, style: tt.bodyMedium),
                    const SizedBox(height: 2),
                    Text(
                      _user.copySettingsUpdatedAt == null
                          ? l10n.networkCopyAutoUpdateNever
                          : l10n.networkCopyAutoUpdateLast(
                              TimeFormat.relative(
                                DateTime.fromMillisecondsSinceEpoch(
                                  _user.copySettingsUpdatedAt!,
                                ),
                                l10n,
                              ),
                            ),
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _user.copyAutoUpdate,
                onChanged: (v) => _user.setCopyAutoUpdate(v),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            initialValue: _user.copyLoginHost,
            decoration: InputDecoration(
              labelText: l10n.networkCopyLoginDomain,
              helperText: l10n.networkCopyLoginDomainHint,
              prefixIcon: const Icon(Icons.login_rounded),
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final host in copyLoginHostOptions)
                DropdownMenuItem<String>(value: host, child: Text(host)),
            ],
            onChanged: (value) {
              if (value != null) _setCopyLoginHost(value);
            },
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _copyApiHostController,
            decoration: const InputDecoration(
              labelText: 'COPY API URL',
              hintText: defaultCopyApiHost,
              prefixIcon: Icon(Icons.dns_rounded),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _copyAppVersionController,
            decoration: InputDecoration(
              labelText: l10n.networkCopyAppVersion,
              hintText: defaultCopyAppVersion,
              prefixIcon: const Icon(Icons.numbers_rounded),
              border: const OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _saveCopyAdvancedSettings(),
          ),
          const SizedBox(height: AppSpacing.md),
          _buildAdvancedActions(cs),
        ],
      ),
    );
  }

  Widget _buildAdvancedActions(ColorScheme cs) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      width: double.infinity,
      child: _ConnectedButtonGroup(
        children: [
          _ConnectedButtonGroupItem(
            onPressed: _autoFillingCopySettings ? null : _autoFillCopySettings,
            loadingWidget: _autoFillingCopySettings
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  )
                : null,
            icon: _autoFillingCopySettings ? null : Icons.auto_fix_high,
            label: l10n.networkFill,
          ),
          _ConnectedButtonGroupItem(
            onPressed: _autoFillingCopySettings
                ? null
                : _resetCopyAdvancedSettings,
            icon: Icons.restart_alt,
            label: l10n.commentSettingsResetButton,
          ),
          _ConnectedButtonGroupItem(
            onPressed: _saveCopyAdvancedSettings,
            icon: Icons.save_outlined,
            label: l10n.commentSettingsSaveButton,
            isPrimary: true,
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // 延迟计算辅助
  // ─────────────────────────────────────────────────────────────────────

  double? _averageLatency(Map<String, int?>? results) {
    final values = results?.values.whereType<int>().toList() ?? const <int>[];
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  int _nodeNumber(int routeIndex, int localIndex) =>
      routes.take(routeIndex).fold(0, (sum, route) => sum + route.length) +
      localIndex +
      1;

  String? _bestLatencyHost(Map<int, Map<String, int?>> results) {
    String? bestHost;
    int? bestLatency;
    for (var route = 0; route < ApiClient.routeCount; route++) {
      final entries = results[route]?.entries;
      if (entries == null) continue;
      for (final entry in entries) {
        final latency = entry.value;
        if (latency != null && (bestLatency == null || latency < bestLatency)) {
          bestHost = entry.key;
          bestLatency = latency;
        }
      }
    }
    return bestHost;
  }

  Color _latencyTone(double avg, ColorScheme cs) {
    if (avg <= 800) return Colors.green;
    if (avg <= 2000) return Colors.orange;
    return cs.error;
  }

  String _latencyHostKey(int index, String host) => '$index|$host';

  bool _isLatencyPending(int index, String host) {
    return _pendingLatencyHosts.contains(_latencyHostKey(index, host));
  }

  // ─────────────────────────────────────────────────────────────────────
  // 操作逻辑
  // ─────────────────────────────────────────────────────────────────────

  Future<void> _setSelectionMode(NetworkSelectionMode mode) async {
    if (mode == NetworkSelectionMode.fixedNode && _user.fixedNodeHost == null) {
      await _user.setFixedNodeHost(ApiClient().network.getRouteHosts(0).first);
    }
    await _user.setNetworkSelectionMode(mode);
  }

  Future<void> _testLatency() async {
    final api = ApiClient();
    final pendingResults = <int, Map<String, int?>>{};
    final pendingHosts = <String>{};
    for (var i = 0; i < ApiClient.routeCount; i++) {
      pendingResults[i] = {
        for (final host in api.network.getRouteHosts(i)) host: null,
      };
      pendingHosts.addAll(
        api.network.getRouteHosts(i).map((host) => _latencyHostKey(i, host)),
      );
    }
    pendingResults[-1] = {
      for (final host in api.network.getExtraApiHosts()) host: null,
    };
    pendingHosts.addAll(
      api.network.getExtraApiHosts().map((host) => _latencyHostKey(-1, host)),
    );

    void updateHostLatency(int index, String host, int? latency) {
      if (!mounted) return;
      setState(() {
        _latencyResults[index]?[host] = latency;
        _pendingLatencyHosts.remove(_latencyHostKey(index, host));
      });
    }

    setState(() {
      _testingLatency = true;
      _latencyResults = pendingResults;
      _pendingLatencyHosts = pendingHosts;
    });
    try {
      final tests = <Future<MapEntry<int, Map<String, int?>>>>[
        api.network
            .testExtraApiLatency(
              onHostResult: (host, latency) =>
                  updateHostLatency(-1, host, latency),
            )
            .then((r) => MapEntry(-1, r)),
      ];
      for (var route = 0; route < ApiClient.routeCount; route++) {
        tests.add(
          api.network
              .testRouteLatency(
                route,
                onHostResult: (host, latency) =>
                    updateHostLatency(route, host, latency),
              )
              .then((result) => MapEntry(route, result)),
        );
      }
      final results = await Future.wait(tests);
      final latencyResults = Map<int, Map<String, int?>>.fromEntries(results);
      // 仅 fixedNode 模式测速后自动选最低延迟节点;route 模式留给用户手动点选线路。
      if (_user.networkSelectionMode == NetworkSelectionMode.fixedNode) {
        final bestHost = _bestLatencyHost(latencyResults);
        if (bestHost != null && bestHost != _user.fixedNodeHost) {
          await _user.setFixedNodeHost(bestHost);
          if (mounted) {
            _showToast(
              AppLocalizations.of(context)!.networkFixedNodeAutoSelected,
            );
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _testingLatency = false;
        _latencyResults = latencyResults;
        _pendingLatencyHosts = {};
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _testingLatency = false;
        _pendingLatencyHosts = {};
      });
    }
  }

  Future<void> _refreshSystemProxy() async {
    setState(() => _refreshingSystemProxy = true);
    final proxy = await NetworkProxy.refreshSystemProxy();
    if (!mounted) return;
    setState(() => _refreshingSystemProxy = false);
    final l10n = AppLocalizations.of(context)!;
    _showToast(
      proxy == null
          ? l10n.networkNoSystemProxyDetected
          : l10n.networkSystemProxyDetected(proxy.label),
    );
  }

  Future<void> _setProxyMode(NetworkProxyMode mode) async {
    await _user.setNetworkProxyMode(mode);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _setCopyLoginHost(String host) async {
    if (host == _user.copyLoginHost) return;
    await _user.setCopyLoginHost(host);
    if (!mounted) return;
    // 延迟结果按 host 记录，切换后清空以反映新的测试目标。
    setState(() {
      _latencyResults = {};
      _pendingLatencyHosts = {};
    });
  }

  Future<void> _saveCopyAdvancedSettings() async {
    final host = UserManager.normalizeCopyApiHost(_copyApiHostController.text);
    final version = UserManager.normalizeCopyAppVersion(
      _copyAppVersionController.text,
    );
    final hostChanged = host != _user.copyApiHost;

    _copyApiHostController.text = host;
    _copyAppVersionController.text = version;

    await _user.setCopyApiHost(host);
    await _user.setCopyAppVersion(version);
    if (!mounted) return;

    if (hostChanged) {
      setState(() {
        _latencyResults = {};
        _pendingLatencyHosts = {};
      });
    }
    _showToast(AppLocalizations.of(context)!.networkCopyAdvancedSaved);
  }

  Future<void> _resetCopyAdvancedSettings() async {
    final hostChanged = _user.copyApiHost != defaultCopyApiHost;
    _copyApiHostController.text = defaultCopyApiHost;
    _copyAppVersionController.text = defaultCopyAppVersion;

    await _user.setCopyApiHost(defaultCopyApiHost);
    await _user.setCopyAppVersion(defaultCopyAppVersion);
    if (!mounted) return;

    if (hostChanged) {
      setState(() {
        _latencyResults = {};
        _pendingLatencyHosts = {};
      });
    }
    _showToast(AppLocalizations.of(context)!.networkCopyAdvancedReset);
  }

  Future<void> _autoFillCopySettings() async {
    if (_autoFillingCopySettings) return;

    setState(() => _autoFillingCopySettings = true);

    try {
      final apiHost = await ApiClient().network.fetchCopyApiHost();
      final version = await ApiClient().manga.fetchCopyLatestAppVersion();
      if (!mounted) return;
      _copyApiHostController.text = apiHost;
      _copyAppVersionController.text = version;
      _showToast(
        AppLocalizations.of(context)!.networkCopyAutoFilled(apiHost, version),
      );
    } catch (e) {
      if (!mounted) return;
      _showToast(
        AppLocalizations.of(context)!.networkAutoFillFailed(_errorMessage(e)),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _autoFillingCopySettings = false);
      }
    }
  }

  String _errorMessage(Object error) {
    if (error is DioException) {
      final message = error.message;
      if (message != null && message.isNotEmpty) return message;

      final statusCode = error.response?.statusCode;
      if (statusCode != null) return 'HTTP $statusCode';

      final rawError = error.error?.toString();
      if (rawError != null && rawError.isNotEmpty) return rawError;
    }
    return error.toString();
  }

  Future<void> _saveManualProxy() async {
    final proxy = NetworkProxy.parseManualProxy(
      host: _proxyAddressController.text,
      port: '',
      type: _manualProxyType,
    );
    if (proxy == null) {
      _showToast(
        AppLocalizations.of(context)!.networkInvalidProxyAddress,
        isError: true,
      );
      return;
    }

    _proxyAddressController.text = proxy.host.contains(':')
        ? '[${proxy.host}]:${proxy.port}'
        : '${proxy.host}:${proxy.port}';
    _manualProxyType = proxy.type;

    await _user.setManualProxy(
      host: proxy.host,
      port: proxy.port,
      type: proxy.type,
    );
    if (!mounted) return;
    setState(() {});
    _showToast(AppLocalizations.of(context)!.networkProxyEnabled(proxy.label));
  }

  void _showToast(String message, {bool isError = false}) {
    if (!mounted) return;
    showToast(context, message, isError: isError);
  }
}

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

/// 会呼吸的状态圆点 —— 仪表盘的 signature 元素。
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

/// 代理状态胶囊：激活时显眼，未激活时灰。
class _ProxyPill extends StatelessWidget {
  final bool active;
  final String label;
  final TextTheme tt;

  const _ProxyPill({
    required this.active,
    required this.label,
    required this.tt,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = active ? Colors.green : cs.onSurfaceVariant;
    return Container(
      constraints: const BoxConstraints(maxWidth: 160),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: active ? 0.14 : 0.06),
        borderRadius: AppRadius.smR,
        border: Border.all(color: color.withValues(alpha: active ? 0.4 : 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? Icons.shield_rounded : Icons.shield_moon_outlined,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
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
