import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/user_manager.dart';

class NetworkPage extends StatefulWidget {
  const NetworkPage({super.key});

  @override
  State<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends State<NetworkPage> {
  final _user = UserManager();
  bool _testingLatency = false;
  Map<int, Map<String, int?>> _latencyResults = {};

  @override
  void initState() {
    super.initState();
    _user.addListener(_onChanged);
  }

  @override
  void dispose() {
    _user.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final selectedRouteStats = _latencyResults[_user.apiRoute];
    double? avgLatency;
    if (selectedRouteStats != null) {
      final values = selectedRouteStats.values.whereType<int>().toList();
      if (values.isNotEmpty) {
        avgLatency = values.reduce((a, b) => a + b) / values.length;
      }
    }

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
                                const SizedBox(height: 4),
                                _testingLatency
                                    ? Row(
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
                                          Text(
                                            '正在检测各节点...',
                                            style: tt.bodySmall,
                                          ),
                                        ],
                                      )
                                    : Text(
                                        _latencyResults.isNotEmpty
                                            ? _buildLatencySummary()
                                            : '尚未进行检测',
                                        style: tt.bodySmall?.copyWith(
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                              ],
                            ),
                          ),
                          if (!_testingLatency)
                            Icon(
                              Icons.chevron_right,
                              color: cs.onSurfaceVariant,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_latencyResults.isNotEmpty) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: _buildLatencyDetail(tt, cs),
                  ),
                ],
              ],
            ),
          ),
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

  String _buildLatencySummary() {
    final buffer = StringBuffer();
    for (final entry in _latencyResults.entries) {
      final label = ApiClient.routeLabels[entry.key];
      final values = entry.value.values.whereType<int>().toList();
      if (values.isNotEmpty) {
        final avg = values.reduce((a, b) => a + b) ~/ values.length;
        buffer.write('$label: ${avg}ms  ');
      } else {
        buffer.write('$label: 超时  ');
      }
    }
    return buffer.toString().trim();
  }

  Widget _buildLatencyDetail(TextTheme tt, ColorScheme cs) {
    if (_latencyResults.isEmpty) return const SizedBox.shrink();

    return Column(
      children: _latencyResults.entries.map((entry) {
        final index = entry.key;
        final hosts = entry.value;
        final weights = hosts.values
            .map((v) => (v != null && v > 0) ? 1000.0 / v : 0.0)
            .toList();
        final totalWeight = weights.fold<double>(0.0, (a, b) => a + b);

        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    index == 0 ? Icons.alt_route : Icons.route,
                    size: 20,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    ApiClient.routeLabels[index],
                    style: tt.titleMedium?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...List.generate(hosts.length, (i) {
                final latency = hosts.values.elementAt(i);
                final weight = weights[i];
                final pct = totalWeight > 0 ? (weight / totalWeight) : 0.0;

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

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: statusColor.withValues(
                        alpha: latency != null ? 0.3 : 0.1,
                      ),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '节点 ${i + 1}',
                            style: tt.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
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
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: pct,
                                backgroundColor: cs.outlineVariant.withValues(
                                  alpha: 0.4,
                                ),
                                color: statusColor,
                                minHeight: 8,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 50,
                            child: Text(
                              '${(pct * 100).toStringAsFixed(1)}%',
                              textAlign: TextAlign.end,
                              style: tt.labelMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
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
      ]);
      if (!mounted) return;
      setState(() {
        _testingLatency = false;
        _latencyResults = Map.fromEntries(results);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _testingLatency = false);
    }
  }
}
