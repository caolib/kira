import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/app_dio.dart';
import '../../utils/network_error.dart';
import '../api_transport.dart';
import '../automatic_node_selector.dart';

class NetworkApi {
  final ApiTransport _t;

  NetworkApi(this._t);

  List<AutomaticNodeStatus> get automaticNodeStatuses =>
      _t.automaticNodeStatuses;

  void addAutomaticNodeListener(void Function() listener) =>
      _t.addAutomaticNodeListener(listener);

  void removeAutomaticNodeListener(void Function() listener) =>
      _t.removeAutomaticNodeListener(listener);

  // ── 线路延迟测试 ──

  /// 获取指定线路的所有 host
  List<String> getRouteHosts(int routeIndex) => routes[routeIndex];

  /// 获取线路以外的固定 API / Web host，去重后用于延迟测试展示。
  List<String> getExtraApiHosts() {
    final hosts = <String>[];
    for (final host in <String>[_t.user.copyApiHost, ...extraApiHosts]) {
      if (!hosts.contains(host)) hosts.add(host);
    }
    return hosts;
  }

  /// 获取固定 API / Web host 在诊断结果中的展示名称。
  String getExtraApiHostLabel(String host, AppLocalizations l10n) {
    if (host == _t.user.copyApiHost || host == defaultCopyApiHost) {
      return 'COPY API';
    }
    return switch (extraApiHostKinds[host] ?? ExtraApiHostKind.fixed) {
      ExtraApiHostKind.copyApi => 'COPY API',
      ExtraApiHostKind.copyLogin => l10n.networkCopyLoginHost,
      ExtraApiHostKind.hotLogin => l10n.networkHotLoginHost,
      ExtraApiHostKind.fixed => l10n.networkFixedApiHost,
    };
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
      _t.recordNodeProbe(entry.key, entry.value);
      if (entry.value == null || entry.value! <= 0) {
        _t.setHostWeight(entry.key, 0.0);
      } else {
        _t.setHostWeight(entry.key, 1000.0 / entry.value!);
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

  /// 从 network2 接口获取当前 COPY API 地址（取路由 0 的第一个 host）。
  Future<String> fetchCopyApiHost() async {
    final version = _t.user.copyAppVersion;
    final dio = AppDio.create(
      source: 'copy_api',
      options: BaseOptions(
        validateStatus: (_) => true,
        headers: {
          'User-Agent': 'COPY/$version',
          'Accept': 'application/json',
          'source': 'copyApp',
          'platform': '3',
          'version': version,
        },
      ),
    );
    try {
      final resp = await dio.get(
        'https://${_t.user.copyApiHost}/api/v3/system/network2',
        queryParameters: {'platform': 3},
      );
      final data = resp.data is String && (resp.data as String).isNotEmpty
          ? (jsonDecode(resp.data as String) as Map<String, dynamic>)
          : resp.data;
      if (data is Map && data['code'] == 200) {
        final results = data['results'];
        if (results is Map) {
          final api = results['api'];
          if (api is List && api.isNotEmpty) {
            final firstRoute = api[0];
            if (firstRoute is List && firstRoute.isNotEmpty) {
              final host = firstRoute[0]?.toString().trim() ?? '';
              if (host.isNotEmpty) return host;
            }
          }
        }
      }
      final message = data is Map
          ? (data['message']?.toString() ?? 'Failed to fetch COPY API host')
          : 'Failed to fetch COPY API host';
      NetworkError.throwBadResponse(
        response: resp,
        message: message,
        source: 'copy_api',
      );
    } finally {
      dio.close();
    }
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
          final socket = await SecureSocket.connect(
            socketHost,
            port,
            timeout: const Duration(seconds: 3),
          );
          sw.stop();
          latency = sw.elapsedMilliseconds;
          await socket.close();
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
