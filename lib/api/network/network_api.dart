import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/app_dio.dart';
import '../../utils/network_error.dart';
import '../../utils/network_proxy.dart';
import '../api_transport.dart';

class NetworkApi {
  final ApiTransport _t;

  NetworkApi(this._t);

  // ── 线路延迟测试 ──

  /// 获取指定线路的所有 host
  List<String> getRouteHosts(int routeIndex) => routes[routeIndex];

  /// 获取线路以外的固定 API / Web host，去重后用于延迟测试展示。
  List<String> getExtraApiHosts() {
    final hosts = <String>[];
    for (final host in <String>[
      _t.user.copyApiHost,
      _t.user.copyLoginHost,
      ...extraApiHosts,
    ]) {
      if (!hosts.contains(host)) hosts.add(host);
    }
    return hosts;
  }

  /// 获取固定 API / Web host 在诊断结果中的展示名称。
  String getExtraApiHostLabel(String host, AppLocalizations l10n) {
    if (host == _t.user.copyApiHost || host == defaultCopyApiHost) {
      return 'COPY API';
    }
    if (host == _t.user.copyLoginHost) {
      return l10n.networkCopyLoginHost;
    }
    return switch (extraApiHostKinds[host] ?? ExtraApiHostKind.fixed) {
      ExtraApiHostKind.copyApi => 'COPY API',
      ExtraApiHostKind.copyLogin => l10n.networkCopyLoginHost,
      ExtraApiHostKind.hotLogin => l10n.networkHotLoginHost,
      ExtraApiHostKind.fixed => l10n.networkFixedApiHost,
    };
  }

  /// 测试指定线路所有 host 的延迟，返回 {host: 毫秒数，超时为 null}
  ///
  /// 遵循应用代理设置：测得的是「按当前网络设置实际到达该节点的延迟」，
  /// 与 API 实际请求路径一致，避免代理用户被直连测速误导。
  Future<Map<String, int?>> testRouteLatency(
    int routeIndex, {
    void Function(String host, int? latency)? onHostResult,
  }) async {
    final results = await testHostsConnectivity(
      getRouteHosts(routeIndex),
      onHostResult: onHostResult,
    );

    for (final entry in results.entries) {
      _t.recordNodeProbe(entry.key, entry.value);
    }

    return results;
  }

  /// 测试固定 API / Web host 的延迟，仅用于诊断展示，不参与线路权重。
  ///
  /// 同样遵循应用代理设置（见 [testHostsConnectivity]）。
  Future<Map<String, int?>> testExtraApiLatency({
    void Function(String host, int? latency)? onHostResult,
  }) {
    return testHostsConnectivity(
      getExtraApiHosts(),
      onHostResult: onHostResult,
    );
  }

  /// 测试给定 host 列表的连通延迟（所有诊断测速共用），不涉及业务请求。
  ///
  /// 通过 [HttpClient] 建立连接，遵循应用代理设置（系统/手动/直连）——
  /// 代理模式下先完成 CONNECT 隧道再做 TLS 握手，测得的是「按当前网络
  /// 设置实际到达该 host 的延迟」，与 API 实际请求路径一致；直连测速
  /// 会误导开了代理的用户（浏览器能打开官网、诊断却显示超时）。
  /// `openUrl` 在连接建立后完成，随即 `abort`，不发送任何请求。
  Future<Map<String, int?>> testHostsConnectivity(
    List<String> hosts, {
    void Function(String host, int? latency)? onHostResult,
  }) async {
    final results = <String, int?>{};
    await Future.wait(
      hosts.map((host) async {
        int? latency;
        final client = NetworkProxy.createHttpClient(
          connectionTimeout: const Duration(seconds: 3),
        );
        try {
          final sw = Stopwatch()..start();
          // openUrl 在连接建立（含代理隧道与 TLS 握手）后完成；
          // 随即 abort，不发送任何请求，测得纯连通耗时。
          final request = await client.openUrl(
            'HEAD',
            Uri.parse('https://$host'),
          );
          sw.stop();
          latency = sw.elapsedMilliseconds;
          request.abort();
        } catch (_) {
          latency = null;
        } finally {
          client.close(force: true);
        }
        results[host] = latency;
        onHostResult?.call(host, latency);
      }),
    );
    return results;
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
}
