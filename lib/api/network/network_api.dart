part of '../api_client.dart';

mixin _NetworkApi on _ApiClientBase {
  // ── 线路延迟测试 ──

  /// 获取指定线路的所有 host
  List<String> getRouteHosts(int routeIndex) => _routes[routeIndex];

  /// 获取线路以外的固定 API / Web host，去重后用于延迟测试展示。
  List<String> getExtraApiHosts() {
    final hosts = <String>[];
    for (final host in <String>[_user.copyApiHost, ..._extraApiHosts]) {
      if (!hosts.contains(host)) hosts.add(host);
    }
    return hosts;
  }

  /// 获取固定 API / Web host 在诊断结果中的展示名称。
  String getExtraApiHostLabel(String host) {
    if (host == _user.copyApiHost || host == defaultCopyApiHost) {
      return 'COPY API';
    }
    return _extraApiHostLabels[host] ?? '固定接口';
  }

  /// 测试指定线路所有 host 的延迟，返回 {host: 毫秒数，超时为 null}
  Future<Map<String, int?>> testRouteLatency(
    int routeIndex, {
    void Function(String host, int? latency)? onHostResult,
  }) async {
    final results = await _testHostsLatency(
      getRouteHosts(routeIndex),
      onHostResult: onHostResult,
    );

    for (final entry in results.entries) {
      if (entry.value == null || entry.value! <= 0) {
        _hostWeights[entry.key] = 0.0;
      } else {
        _hostWeights[entry.key] = 1000.0 / entry.value!;
      }
    }

    return results;
  }

  /// 测试固定 API / Web host 的延迟，仅用于诊断展示，不参与线路权重。
  Future<Map<String, int?>> testExtraApiLatency({
    void Function(String host, int? latency)? onHostResult,
  }) {
    return _testHostsLatency(getExtraApiHosts(), onHostResult: onHostResult);
  }

  Future<Map<String, int?>> _testHostsLatency(
    List<String> hosts, {
    void Function(String host, int? latency)? onHostResult,
  }) async {
    final results = <String, int?>{};
    await Future.wait(
      hosts.map((host) async {
        int? latency;
        try {
          final uri = Uri.tryParse('https://$host');
          final socketHost = uri != null && uri.host.isNotEmpty
              ? uri.host
              : host;
          final port = uri != null && uri.hasPort ? uri.port : 443;
          final sw = Stopwatch()..start();
          await SecureSocket.connect(
            socketHost,
            port,
            timeout: const Duration(seconds: 3),
          );
          sw.stop();
          latency = sw.elapsedMilliseconds;
        } catch (_) {
          latency = null;
        }
        results[host] = latency;
        onHostResult?.call(host, latency);
      }),
    );

    return results;
  }
}
