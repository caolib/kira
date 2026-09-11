import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/api_transport.dart' show hotLoginHost;
import '../l10n/app_localizations.dart';
import '../models/user_manager.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../theme/app_status_colors.dart';

/// 一批登录节点的探测函数：返回 {host: 延迟毫秒}，超时为 null。
/// 探测遵循应用代理设置（见 NetworkApi.testHostsConnectivity）。
typedef LoginHostProbe =
    Future<Map<String, int?>> Function(
      List<String> hosts, {
      void Function(String host, int? latency)? onHostResult,
    });

/// 登录页顶部的登录节点状态卡。
///
/// 只显示当前所选登录来源对应的节点：热辣来源显示「热辣登录」
/// （[hotLoginHost]，热辣注册也走该域名），拷贝来源显示当前拷贝登录域名。
/// 进入页面即后台探测两个域名（切换来源时结果立即可用），让用户在
/// 登录/注册前就能看出当前网络是否可达。
/// 延迟阈值与配色与网络诊断页保持一致（≤800 绿、≤2000 橙、其余红、超时红）。
///
/// 热辣账号登录实际走线路节点（见网络诊断页），此处展示的是网页登录/注册
/// 域名——网络页也把它标注为「热辣登录」，语义保持一致。
class LoginNodeStatusCard extends StatefulWidget {
  const LoginNodeStatusCard({super.key, required this.useCopyLogin});

  /// 当前是否选中拷贝漫画登录；false 表示热辣漫画。
  final bool useCopyLogin;

  /// 测试注入的探测函数；null 时走 NetworkApi.testHostsConnectivity。
  /// widget 测试必须覆盖它，否则会发起真实网络请求。
  static LoginHostProbe? probeOverride;

  @override
  State<LoginNodeStatusCard> createState() => _LoginNodeStatusCardState();
}

class _LoginNodeStatusCardState extends State<LoginNodeStatusCard> {
  final _api = ApiClient();
  final _user = UserManager();

  /// host → 延迟毫秒；null 表示超时；不在 map 中表示检测中。
  final Map<String, int?> _results = {};
  bool _testing = false;

  /// 后台探测的域名：两个来源都测，切换来源时无需重新等待。
  List<String> get _probeHosts {
    final hosts = <String>[hotLoginHost];
    final copy = _user.copyLoginHost;
    if (copy.isNotEmpty && !hosts.contains(copy)) hosts.add(copy);
    return hosts;
  }

  /// 当前展示的域名：与所选登录来源对应。
  String get _displayHost {
    if (widget.useCopyLogin) {
      final copy = _user.copyLoginHost;
      if (copy.isNotEmpty) return copy;
    }
    return hotLoginHost;
  }

  @override
  void initState() {
    super.initState();
    _testing = true;
    unawaited(_probe());
  }

  Future<void> _probe() async {
    final probe =
        LoginNodeStatusCard.probeOverride ?? _api.network.testHostsConnectivity;
    try {
      await probe(_probeHosts, onHostResult: _onHostResult);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _test() async {
    if (_testing) return;
    setState(() => _testing = true);
    await _probe();
  }

  void _onHostResult(String host, int? latency) {
    if (!mounted) return;
    setState(() => _results[host] = latency);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final host = _displayHost;

    return Container(
      decoration: BoxDecoration(
        // 与网络诊断页节点卡同款底色
        color: Color.alphaBlend(
          cs.surfaceContainerHighest.withValues(alpha: 0.35),
          cs.surface,
        ),
        borderRadius: AppRadius.mdR,
        // 与登录页其余卡片（已保存账号卡）同款阴影。
        boxShadow: AppShadows.md(cs),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lan_outlined, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: AppSpacing.xs),
                Expanded(child: _buildHostRow(host, l10n, tt, cs)),
                // 探测中/空闲占同一 48x48 槽位，行高恒定，卡片不跳动。
                IconButton(
                  tooltip: l10n.networkTestLatencyShort,
                  onPressed: _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHostRow(
    String host,
    AppLocalizations l10n,
    TextTheme tt,
    ColorScheme cs,
  ) {
    final pending = !_results.containsKey(host);
    final latency = _results[host];
    final Color color;
    if (pending) {
      color = AppStatusColors.neutral(cs);
    } else if (latency == null) {
      color = AppStatusColors.danger(cs);
    } else if (latency <= 800) {
      color = AppStatusColors.success(cs);
    } else if (latency <= 2000) {
      color = AppStatusColors.warning(cs);
    } else {
      color = AppStatusColors.danger(cs);
    }

    final label = host == hotLoginHost
        ? l10n.networkHotLoginHost
        : l10n.networkCopyLoginHost;
    final valueText = pending
        ? l10n.networkTesting
        : (latency == null ? l10n.networkTimeout : '$latency ms');

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          label,
          style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        Text(
          valueText,
          style: tt.bodyMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
