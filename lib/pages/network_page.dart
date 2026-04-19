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

    return Scaffold(
      appBar: AppBar(title: const Text('网络')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          Card(
            color: cs.surfaceContainerLow,
            child: Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.dns_outlined, color: cs.onSurfaceVariant),
                          const SizedBox(width: 16),
                          const Text('API 线路'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(value: 0, label: Text('线路 1')),
                            ButtonSegment(value: 1, label: Text('线路 2')),
                          ],
                          selected: {_user.apiRoute},
                          onSelectionChanged: (v) =>
                              _user.setApiRoute(v.first),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.speed),
                  title: const Text('测试线路延迟'),
                  subtitle: _testingLatency
                      ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text('测试中...'),
                          ],
                        )
                      : _latencyResults.isNotEmpty
                          ? Text(
                              _buildLatencySummary(),
                              style: tt.bodySmall,
                            )
                          : const Text('检测各线路的响应延迟'),
                  trailing:
                      _testingLatency ? null : const Icon(Icons.play_arrow),
                  onTap: _testingLatency ? null : _testLatency,
                ),
                if (_latencyResults.isNotEmpty) ...[
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: _buildLatencyDetail(tt, cs),
                  ),
                ],
              ],
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
    Widget buildRoute(int index) {
      final hosts = _latencyResults[index];
      if (hosts == null) return const SizedBox.shrink();
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ApiClient.routeLabels[index],
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            for (var i = 0; i < hosts.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Expanded(child: Text('节点 ${i + 1}', style: tt.bodySmall)),
                    Text(
                      hosts.values.elementAt(i) != null
                          ? '${hosts.values.elementAt(i)} ms'
                          : '超时',
                      style: tt.bodySmall?.copyWith(
                        color: hosts.values.elementAt(i) != null
                            ? cs.primary
                            : cs.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildRoute(0),
        const SizedBox(width: 16),
        buildRoute(1),
      ],
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
