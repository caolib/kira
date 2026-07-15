import 'package:flutter/foundation.dart';

class AutomaticNodeStatus {
  final String host;
  final int? averageLatencyMs;
  final int samples;
  final int selections;
  final int consecutiveFailures;
  final bool circuitOpen;
  final bool isBest;
  final bool isCurrent;

  const AutomaticNodeStatus({
    required this.host,
    required this.averageLatencyMs,
    required this.samples,
    required this.selections,
    required this.consecutiveFailures,
    required this.circuitOpen,
    required this.isBest,
    required this.isCurrent,
  });
}

class AutomaticNodeSelector extends ChangeNotifier {
  static const _initialLatencyMs = 1000.0;
  static const _failureLatencyMs = 5000.0;

  final Duration circuitDuration;
  final int failureThreshold;
  final int explorationInterval;
  final DateTime Function() _now;
  final Map<String, _NodePerformance> _nodes = {};
  int _selectionCount = 0;
  String? _currentHost;

  AutomaticNodeSelector({
    this.circuitDuration = const Duration(seconds: 30),
    this.failureThreshold = 2,
    this.explorationInterval = 10,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  String select(List<String> hosts) {
    final now = _now();
    final candidates = hosts
        .map((host) => _nodes.putIfAbsent(host, () => _NodePerformance(host)))
        .where((node) => !node.isCircuitOpen(now))
        .toList();
    final usable = candidates.isEmpty
        ? hosts.map((host) => _nodes[host]!).toList()
        : candidates;

    final warmup = usable
        .where((node) => node.selections == 0 && node.samples == 0)
        .toList();
    final selected = warmup.isNotEmpty
        ? warmup.first
        : (++_selectionCount % explorationInterval == 0
              ? usable.reduce(
                  (a, b) => a.lastSelected.isBefore(b.lastSelected) ? a : b,
                )
              : usable.reduce((a, b) => a.score <= b.score ? a : b));
    selected.lastSelected = now;
    selected.selections++;
    _currentHost = selected.host;
    notifyListeners();
    return selected.host;
  }

  void recordSuccess(String host, Duration elapsed) {
    final node = _nodes.putIfAbsent(host, () => _NodePerformance(host));
    node.recordLatency(elapsed.inMilliseconds.toDouble());
    node.consecutiveFailures = 0;
    node.circuitOpenUntil = null;
    notifyListeners();
  }

  void recordFailure(String host, Iterable<String> allHosts) {
    final node = _nodes.putIfAbsent(host, () => _NodePerformance(host));
    node.recordLatency(_failureLatencyMs);
    node.consecutiveFailures++;
    if (node.consecutiveFailures < failureThreshold) {
      notifyListeners();
      return;
    }

    final now = _now();
    final hasOtherUsableNode = allHosts.any((otherHost) {
      if (otherHost == host) return false;
      return !_nodes
          .putIfAbsent(otherHost, () => _NodePerformance(otherHost))
          .isCircuitOpen(now);
    });
    if (hasOtherUsableNode) {
      node.circuitOpenUntil = now.add(circuitDuration);
      if (_currentHost == host) _currentHost = null;
    }
    notifyListeners();
  }

  bool isCircuitOpen(String host) =>
      _nodes[host]?.isCircuitOpen(_now()) ?? false;

  List<AutomaticNodeStatus> statuses(List<String> hosts) {
    final now = _now();
    final nodes = hosts
        .map((host) => _nodes.putIfAbsent(host, () => _NodePerformance(host)))
        .toList();
    final measured = nodes
        .where((node) => node.samples > 0 && !node.isCircuitOpen(now))
        .toList();
    final best = measured.isEmpty
        ? null
        : measured.reduce((a, b) => a.score <= b.score ? a : b).host;
    return nodes
        .map(
          (node) => AutomaticNodeStatus(
            host: node.host,
            averageLatencyMs: node.averageLatencyMs?.round(),
            samples: node.samples,
            selections: node.selections,
            consecutiveFailures: node.consecutiveFailures,
            circuitOpen: node.isCircuitOpen(now),
            isBest: node.host == best,
            isCurrent: node.host == _currentHost,
          ),
        )
        .toList(growable: false);
  }
}

class _NodePerformance {
  final String host;
  double? averageLatencyMs;
  int samples = 0;
  int selections = 0;
  int consecutiveFailures = 0;
  DateTime? circuitOpenUntil;
  DateTime lastSelected = DateTime.fromMillisecondsSinceEpoch(0);

  _NodePerformance(this.host);

  double get score =>
      (averageLatencyMs ?? AutomaticNodeSelector._initialLatencyMs) +
      consecutiveFailures * 1000;

  bool isCircuitOpen(DateTime now) => circuitOpenUntil?.isAfter(now) ?? false;

  void recordLatency(double latencyMs) {
    averageLatencyMs = averageLatencyMs == null
        ? latencyMs
        : averageLatencyMs! * 0.8 + latencyMs * 0.2;
    samples++;
  }
}
