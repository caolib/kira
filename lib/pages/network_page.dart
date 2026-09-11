import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../api/api_transport.dart'
    show
        routes,
        defaultCopyApiHost,
        defaultCopyAppVersion,
        defaultCopyLoginHost,
        copyLoginHostOptions;
import '../l10n/app_localizations.dart';
import '../models/user_manager.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/network_proxy.dart';
import '../utils/screen_layout.dart';
import '../utils/time_format.dart';
import '../utils/toast.dart';
import '../widgets/select_tile.dart';
import '../widgets/setting_tile_group.dart';
import '../widgets/settings_section.dart';

part 'network/network_actions.dart';
part 'network/network_advanced_section.dart';
part 'network/network_nodes_section.dart';
part 'network/network_proxy_section.dart';
part 'network/network_shared_widgets.dart';

/// 网络诊断与配置页 —— 设置页风格（SettingsSection / SettingTileGroup）。
///
///  - 顶部状态卡：呼吸灯 + 当前健康度 + 测速入口。
///  - 代理设置：tile 组内完成模式切换与手动代理配置。
///  - 线路与节点：模式可选「线路 / 节点」，选中项用主色描边 + 填充 +
///    「使用中」徽标表达，一眼可见。
///  - 高级设置（COPY）：默认折叠，点击标题就地展开（无动画）。
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
  final _customLoginHostController = TextEditingController();

  bool _testingLatency = false;
  bool _refreshingSystemProxy = false;
  bool _autoFillingCopySettings = false;
  bool _advancedExpanded = false;
  NetworkProxyType _manualProxyType = NetworkProxyType.http;

  /// 节点延迟结果。key 为线路索引(>=0)或 -1(其他固定 host)。
  Map<int, Map<String, int?>> _latencyResults = {};
  Set<String> _pendingLatencyHosts = {};

  /// 拷贝登录域名连通性：host → 延迟 ms（null = 超时）。
  /// 展开高级设置时测试。
  final Map<String, int?> _loginHostLatency = {};
  final Set<String> _pendingLoginHosts = {};

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
    _customLoginHostController.dispose();
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
          _buildStatusSection(l10n, tt, cs),
          const SizedBox(height: AppSpacing.md),
          _buildProxySection(l10n, tt, cs),
          const SizedBox(height: AppSpacing.md),
          _buildNodesSection(l10n, tt, cs),
          const SizedBox(height: AppSpacing.md),
          _buildAdvancedSection(l10n, tt, cs),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // 状态卡（呼吸灯 + 健康度 + 测速入口）
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildStatusSection(
    AppLocalizations l10n,
    TextTheme tt,
    ColorScheme cs,
  ) {
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
        secondary = l10n.networkHighLatencyProxySuggestion;
      case _HealthLevel.busy:
        primary = l10n.networkStatusBusy;
        secondary = l10n.networkTestingNodes;
      case _HealthLevel.unknown:
        primary = l10n.networkStatusUnknown;
        secondary = l10n.networkStatusUnknownHint;
    }

    return SettingsSection(
      color: Color.alphaBlend(color.withValues(alpha: 0.10), cs.surfaceBright),
      child: Row(
        children: [
          _BreathingDot(color: color, controller: _breathController),
          const SizedBox(width: AppSpacing.md),
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
          const SizedBox(width: AppSpacing.sm),
          _buildTestButton(l10n, tt, cs),
        ],
      ),
    );
  }

  Widget _buildTestButton(AppLocalizations l10n, TextTheme tt, ColorScheme cs) {
    return FilledButton.tonalIcon(
      onPressed: _testingLatency ? null : _testLatency,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        visualDensity: VisualDensity.compact,
      ),
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
    );
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

  /// 当前可用的最低数值延迟（ms），用于状态卡副文案；无数据返回 null。
  int? _bestNumericLatency() {
    int? best;
    for (final route in _latencyResults.values) {
      for (final v in route.values) {
        if (v != null && (best == null || v < best)) best = v;
      }
    }
    return best;
  }
}
