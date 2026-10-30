import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/network/network_api.dart';
import '../models/network_settings.dart';
import 'app_logger.dart';

class NetworkLatencyTestResult {
  final Map<int, Map<String, int?>> latencies;
  final NetworkSelectionMode? autoSelectedMode;

  const NetworkLatencyTestResult(this.latencies, this.autoSelectedMode);
}

/// 网络页与定时任务共用一轮线路测速，避免重复探测与旧结果覆盖手动选择。
class NetworkLatencyTester extends ChangeNotifier {
  final NetworkApi api;
  final NetworkSettings settings;
  Future<NetworkLatencyTestResult>? _inFlight;
  Map<int, Map<String, int?>> _latencies = {};
  final Set<(int, String)> _pendingHosts = {};
  bool _disposed = false;
  bool _suspended = false;

  NetworkLatencyTester({required this.api, required this.settings});

  bool get busy => _inFlight != null;
  Map<int, Map<String, int?>> get latencies => _latencies;
  Set<(int, String)> get pendingHosts => _pendingHosts;

  Future<NetworkLatencyTestResult> testAndSelect({
    bool Function()? shouldApply,
  }) {
    return _inFlight ??= Future.microtask(() => _testAndSelect(shouldApply))
        .whenComplete(() {
          _inFlight = null;
          _notify();
        });
  }

  Future<NetworkLatencyTestResult> _testAndSelect(
    bool Function()? shouldApply,
  ) async {
    final selectionRevision = settings.selectionRevision;
    _latencies = {
      for (var route = 0; route < ApiClient.routeCount; route++)
        route: {for (final host in api.getRouteHosts(route)) host: null},
    };
    _pendingHosts
      ..clear()
      ..addAll([
        for (final route in _latencies.entries)
          for (final host in route.value.keys) (route.key, host),
      ]);
    _notify();
    try {
      final results = await Future.wait([
        for (var route = 0; route < ApiClient.routeCount; route++)
          api
              .testRouteLatency(
                route,
                onHostResult: (host, latency) {
                  _latencies[route]?[host] = latency;
                  _pendingHosts.remove((route, host));
                  _notify();
                },
              )
              .then((result) => MapEntry(route, result)),
      ]);
      _latencies = Map.fromEntries(results);
      NetworkSelectionMode? selected;
      if (!_disposed &&
          !_suspended &&
          selectionRevision == settings.selectionRevision &&
          (shouldApply?.call() ?? true)) {
        switch (settings.selectionMode) {
          case NetworkSelectionMode.route:
            final best = bestAverageRoute(
              _latencies,
              current: settings.apiRoute,
            );
            if (best != null && best != settings.apiRoute) {
              await settings.setApiRoute(best);
              selected = NetworkSelectionMode.route;
            }
          case NetworkSelectionMode.fixedNode:
            final best = bestLatencyHost(
              _latencies,
              current: settings.fixedNodeHost,
            );
            if (best != null && best != settings.fixedNodeHost) {
              await settings.setFixedNodeHost(best);
              selected = NetworkSelectionMode.fixedNode;
            }
        }
      }
      return NetworkLatencyTestResult(_latencies, selected);
    } catch (error, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          error,
          stackTrace: stack,
          source: 'network.latency',
        ),
      );
      rethrow;
    } finally {
      _pendingHosts.clear();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> pauseForRestore() async {
    _suspended = true;
    await _inFlight;
  }

  void resumeAfterRestore() => _suspended = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  static double? averageLatency(Map<String, int?>? results) {
    final values = results?.values.whereType<int>().toList() ?? const <int>[];
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  /// 同延迟时保留当前线路，所有线路不可达时不切换。
  static int? bestAverageRoute(
    Map<int, Map<String, int?>> results, {
    required int current,
  }) {
    int? best = averageLatency(results[current]) == null ? null : current;
    double? bestLatency = averageLatency(results[current]);
    for (var route = 0; route < ApiClient.routeCount; route++) {
      final latency = averageLatency(results[route]);
      if (latency != null && (bestLatency == null || latency < bestLatency)) {
        best = route;
        bestLatency = latency;
      }
    }
    return best;
  }

  static String? bestLatencyHost(
    Map<int, Map<String, int?>> results, {
    String? current,
  }) {
    String? best;
    int? bestLatency;
    for (var route = 0; route < ApiClient.routeCount; route++) {
      for (final entry
          in results[route]?.entries ?? <MapEntry<String, int?>>[]) {
        final latency = entry.value;
        if (latency != null &&
            (bestLatency == null ||
                latency < bestLatency ||
                (latency == bestLatency && entry.key == current))) {
          best = entry.key;
          bestLatency = latency;
        }
      }
    }
    return best;
  }
}
