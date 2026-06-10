import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/user_manager.dart';
import '../utils/network_proxy.dart';

class NetworkPage extends StatefulWidget {
  const NetworkPage({super.key});

  @override
  State<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends State<NetworkPage> {
  final _user = UserManager();
  final _proxyAddressController = TextEditingController();
  bool _testingLatency = false;
  bool _testingGoogleConnectivity = false;
  bool _refreshingSystemProxy = false;
  bool _latencyExpanded = true;
  NetworkProxyType _manualProxyType = NetworkProxyType.http;
  Map<int, Map<String, int?>> _latencyResults = {};
  bool? _googleConnectivityOk;
  int? _googleConnectivityLatencyMs;
  String? _googleConnectivityMessage;

  @override
  void initState() {
    super.initState();
    _proxyAddressController.text = _manualProxyAddress;
    _manualProxyType = _user.networkProxyType;
    _user.addListener(_onChanged);
  }

  @override
  void dispose() {
    _user.removeListener(_onChanged);
    _proxyAddressController.dispose();
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final avgLatency = _averageLatency(_latencyResults[_user.apiRoute]);

    return Scaffold(
      appBar: AppBar(title: const Text('网络')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant, width: 1),
            ),
            color: cs.surfaceContainerLow,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.dns_outlined, color: cs.primary),
                          const SizedBox(width: 12),
                          Text(
                            'API 线路',
                            style: tt.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(value: 0, label: Text('线路 1')),
                            ButtonSegment(value: 1, label: Text('线路 2')),
                          ],
                          selected: {_user.apiRoute},
                          onSelectionChanged: (v) => _user.setApiRoute(v.first),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _testingLatency ? null : _testLatency,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.speed, color: cs.onSurfaceVariant),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('测试线路延迟', style: tt.bodyLarge),
                                if (_testingLatency) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: cs.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text('正在检测各节点...', style: tt.bodySmall),
                                    ],
                                  ),
                                ] else if (_latencyResults.isEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    '尚未进行检测',
                                    style: tt.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (!_testingLatency) _buildLatencyTrailingIcon(cs),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_latencyResults.isNotEmpty && _latencyExpanded) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: _buildLatencyDetail(tt, cs),
                  ),
                ],
              ],
            ),
          ),
          _buildProxyCard(tt, cs),
          _buildGoogleConnectivityCard(tt, cs),
          if (avgLatency != null && avgLatency > 1500)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Material(
                color: cs.errorContainer,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: cs.onErrorContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '当前延迟较大，建议开启代理',
                          style: tt.bodyMedium?.copyWith(
                            color: cs.onErrorContainer,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _latencyGroupLabel(int index) {
    if (index >= 0 && index < ApiClient.routeLabels.length) {
      return ApiClient.routeLabels[index];
    }
    return '其他';
  }

  double? _averageLatency(Map<String, int?>? results) {
    final values = results?.values.whereType<int>().toList() ?? const <int>[];
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  int? _bestLatencyRoute(Map<int, Map<String, int?>> results) {
    int? bestRoute;
    double? bestAverage;

    for (var i = 0; i < ApiClient.routeLabels.length; i++) {
      final average = _averageLatency(results[i]);
      if (average == null) continue;
      if (bestAverage == null || average < bestAverage) {
        bestAverage = average;
        bestRoute = i;
      }
    }

    return bestRoute;
  }

  Widget _buildLatencyTrailingIcon(ColorScheme cs) {
    if (_latencyResults.isEmpty) {
      return Icon(Icons.chevron_right, color: cs.onSurfaceVariant);
    }

    return IconButton(
      tooltip: _latencyExpanded ? '收起测试结果' : '展开测试结果',
      onPressed: () {
        setState(() => _latencyExpanded = !_latencyExpanded);
      },
      icon: Icon(
        _latencyExpanded
            ? Icons.keyboard_arrow_up_rounded
            : Icons.keyboard_arrow_down_rounded,
        color: cs.primary,
      ),
    );
  }

  Widget _buildProxyCard(TextTheme tt, ColorScheme cs) {
    final isManualMode = _user.networkProxyMode == NetworkProxyMode.manual;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cs.outlineVariant, width: 1),
        ),
        color: cs.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.settings_ethernet, color: cs.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '代理设置',
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '重新检测系统代理',
                    onPressed: _refreshingSystemProxy
                        ? null
                        : _refreshSystemProxy,
                    icon: _refreshingSystemProxy
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.primary,
                            ),
                          )
                        : const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<NetworkProxyMode>(
                  segments: const [
                    ButtonSegment(
                      value: NetworkProxyMode.system,
                      label: Text('系统'),
                    ),
                    ButtonSegment(
                      value: NetworkProxyMode.manual,
                      label: Text('手动'),
                    ),
                    ButtonSegment(
                      value: NetworkProxyMode.direct,
                      label: Text('直连'),
                    ),
                  ],
                  selected: {_user.networkProxyMode},
                  onSelectionChanged: (value) => _setProxyMode(value.first),
                ),
              ),
              const SizedBox(height: 12),
              _buildProxyStatusRow(
                icon: Icons.route_outlined,
                label: '当前应用请求',
                value: NetworkProxy.activeProxyDescription,
                tt: tt,
                cs: cs,
              ),
              const SizedBox(height: 8),
              _buildProxyStatusRow(
                icon: Icons.computer_outlined,
                label: '系统代理',
                value: NetworkProxy.systemProxyDescription,
                tt: tt,
                cs: cs,
              ),
              if (isManualMode) ...[
                const SizedBox(height: 16),
                SegmentedButton<NetworkProxyType>(
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
                  onSelectionChanged: (value) {
                    setState(() => _manualProxyType = value.first);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _proxyAddressController,
                  decoration: const InputDecoration(
                    labelText: '代理地址',
                    hintText: '127.0.0.1:7890 或 http://127.0.0.1:7890',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _saveManualProxy(),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saveManualProxy,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('保存并启用手动代理'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProxyStatusRow({
    required IconData icon,
    required String label,
    required String value,
    required TextTheme tt,
    required ColorScheme cs,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Text('$label：', style: tt.bodySmall),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _buildGoogleConnectivityCard(TextTheme tt, ColorScheme cs) {
    final hasResult = _googleConnectivityMessage != null;
    final ok = _googleConnectivityOk == true;
    final statusColor = _testingGoogleConnectivity
        ? cs.primary
        : hasResult
        ? (ok ? Colors.green : cs.error)
        : cs.onSurfaceVariant;
    final subtitle = _testingGoogleConnectivity
        ? '正在通过 ${NetworkProxy.activeProxyDescription} 访问 Google ...'
        : _googleConnectivityMessage ?? '点击测试当前应用能否访问 Google';

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cs.outlineVariant, width: 1),
        ),
        color: cs.surfaceContainerLow,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _testingGoogleConnectivity ? null : _testGoogleConnectivity,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  _testingGoogleConnectivity
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: cs.primary,
                          ),
                        )
                      : Icon(
                          ok ? Icons.check_circle_outline : Icons.public,
                          color: statusColor,
                        ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Google 连通性', style: tt.bodyLarge),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: tt.bodySmall?.copyWith(
                            color: hasResult || _testingGoogleConnectivity
                                ? statusColor
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_googleConnectivityLatencyMs != null &&
                      !_testingGoogleConnectivity)
                    Container(
                      margin: const EdgeInsets.only(left: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$_googleConnectivityLatencyMs ms',
                        style: tt.labelMedium?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  else if (!_testingGoogleConnectivity)
                    Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLatencyDetail(TextTheme tt, ColorScheme cs) {
    if (_latencyResults.isEmpty) return const SizedBox.shrink();

    return Column(
      children: _latencyResults.entries.map((entry) {
        final index = entry.key;
        final hosts = entry.value;
        final hostEntries = hosts.entries.toList();
        final average = index < 0 ? null : _averageLatency(hosts);

        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    index < 0
                        ? Icons.cloud_queue_outlined
                        : index == 0
                        ? Icons.alt_route
                        : Icons.route,
                    size: 18,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _latencyGroupLabel(index),
                    style: tt.titleSmall?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (index >= 0) ...[
                    const Spacer(),
                    Text(
                      average == null ? '平均：超时' : '平均：${average.round()} ms',
                      style: tt.labelMedium?.copyWith(
                        color: average == null
                            ? cs.error
                            : average <= 800
                            ? Colors.green
                            : average <= 2000
                            ? Colors.orange
                            : cs.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 8.0;
                  final itemWidth = (constraints.maxWidth - spacing * 2) / 3;

                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: List.generate(hostEntries.length, (i) {
                      final title = index < 0
                          ? ApiClient().getExtraApiHostLabel(hostEntries[i].key)
                          : '节点 ${i + 1}';
                      final latency = hostEntries[i].value;

                      Color statusColor;
                      if (latency == null) {
                        statusColor = cs.error;
                      } else if (latency <= 800) {
                        statusColor = Colors.green;
                      } else if (latency <= 2000) {
                        statusColor = Colors.orange;
                      } else {
                        statusColor = cs.error;
                      }

                      return SizedBox(
                        width: itemWidth,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest.withValues(
                              alpha: 0.4,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: statusColor.withValues(
                                alpha: latency != null ? 0.3 : 0.1,
                              ),
                              width: 1.2,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tt.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  latency != null ? '$latency ms' : '超时',
                                  style: tt.labelMedium?.copyWith(
                                    color: statusColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  );
                },
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Future<void> _testLatency() async {
    setState(() {
      _testingLatency = true;
      _latencyResults.clear();
    });
    final api = ApiClient();
    try {
      final results = await Future.wait([
        api.testRouteLatency(0).then((r) => MapEntry(0, r)),
        api.testRouteLatency(1).then((r) => MapEntry(1, r)),
        api.testExtraApiLatency().then((r) => MapEntry(-1, r)),
      ]);
      final latencyResults = Map<int, Map<String, int?>>.fromEntries(results);
      final bestRoute = _bestLatencyRoute(latencyResults);
      if (bestRoute != null && bestRoute != _user.apiRoute) {
        await _user.setApiRoute(bestRoute);
      }
      if (!mounted) return;
      setState(() {
        _testingLatency = false;
        _latencyResults = latencyResults;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _testingLatency = false);
    }
  }

  Future<void> _refreshSystemProxy() async {
    setState(() => _refreshingSystemProxy = true);
    final proxy = await NetworkProxy.refreshSystemProxy();
    if (!mounted) return;
    setState(() => _refreshingSystemProxy = false);
    _showSnackBar(proxy == null ? '未检测到系统代理' : '已检测到 ${proxy.label}');
  }

  Future<void> _setProxyMode(NetworkProxyMode mode) async {
    await _user.setNetworkProxyMode(mode);
    if (!mounted) return;
    setState(_clearGoogleConnectivityResult);
  }

  void _clearGoogleConnectivityResult() {
    _googleConnectivityOk = null;
    _googleConnectivityLatencyMs = null;
    _googleConnectivityMessage = null;
  }

  Future<void> _saveManualProxy() async {
    final proxy = NetworkProxy.parseManualProxy(
      host: _proxyAddressController.text,
      port: '',
      type: _manualProxyType,
    );
    if (proxy == null) {
      _showSnackBar('请输入有效的代理地址，例如 127.0.0.1:7890');
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
    setState(_clearGoogleConnectivityResult);
    _showSnackBar('已启用 ${proxy.label}');
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _testGoogleConnectivity() async {
    if (_testingGoogleConnectivity) return;

    setState(() {
      _testingGoogleConnectivity = true;
      _clearGoogleConnectivityResult();
    });

    final uri = Uri.parse('https://www.google.com/generate_204');
    final proxyRule = NetworkProxy.findProxy(uri);
    final stopwatch = Stopwatch()..start();
    final client = NetworkProxy.createHttpClient(
      connectionTimeout: const Duration(seconds: 5),
    );

    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 5));
      request.followRedirects = false;

      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      await response.drain<void>();
      stopwatch.stop();

      final statusCode = response.statusCode;
      final ok = statusCode >= 200 && statusCode < 400;
      if (!mounted) return;
      setState(() {
        _testingGoogleConnectivity = false;
        _googleConnectivityOk = ok;
        _googleConnectivityLatencyMs = stopwatch.elapsedMilliseconds;
        _googleConnectivityMessage = ok
            ? '连接成功，HTTP $statusCode，$proxyRule'
            : '连接失败，HTTP $statusCode，$proxyRule';
      });
    } on TimeoutException {
      stopwatch.stop();
      if (!mounted) return;
      setState(() {
        _testingGoogleConnectivity = false;
        _googleConnectivityOk = false;
        _googleConnectivityLatencyMs = stopwatch.elapsedMilliseconds;
        _googleConnectivityMessage = '连接超时，$proxyRule';
      });
    } on SocketException catch (e) {
      stopwatch.stop();
      if (!mounted) return;
      setState(() {
        _testingGoogleConnectivity = false;
        _googleConnectivityOk = false;
        _googleConnectivityLatencyMs = stopwatch.elapsedMilliseconds;
        _googleConnectivityMessage = '$proxyRule：${e.message}';
      });
    } catch (e) {
      stopwatch.stop();
      if (!mounted) return;
      setState(() {
        _testingGoogleConnectivity = false;
        _googleConnectivityOk = false;
        _googleConnectivityLatencyMs = stopwatch.elapsedMilliseconds;
        _googleConnectivityMessage = '测试失败，$proxyRule：$e';
      });
    } finally {
      client.close(force: true);
    }
  }
}
