import 'package:flutter_test/flutter_test.dart';
import 'package:kira/api/automatic_node_selector.dart';

void main() {
  const hosts = ['node1', 'node2', 'node3', 'node4', 'node5', 'node6'];

  test('warmup polls every node before reusing one', () {
    final selector = AutomaticNodeSelector();

    expect(List.generate(hosts.length, (_) => selector.select(hosts)), hosts);
  });

  test('uses the node with the best recent response time', () {
    final selector = AutomaticNodeSelector(explorationInterval: 1000);
    for (var i = 0; i < hosts.length; i++) {
      selector.recordSuccess(hosts[i], Duration(milliseconds: 600 - i * 50));
    }

    expect(selector.select(hosts), 'node6');
    final statuses = selector.statuses(hosts);
    expect(statuses.singleWhere((status) => status.isBest).host, 'node6');
    expect(statuses.singleWhere((status) => status.isCurrent).host, 'node6');
  });

  test('never opens the circuit for every node', () {
    final selector = AutomaticNodeSelector();

    for (final host in hosts) {
      selector.recordFailure(host, hosts);
      selector.recordFailure(host, hosts);
    }

    expect(hosts.where(selector.isCircuitOpen), hasLength(hosts.length - 1));
    expect(selector.isCircuitOpen('node6'), isFalse);
    expect(selector.select(hosts), 'node6');
  });

  test('notifies listeners when live node status changes', () {
    final selector = AutomaticNodeSelector();
    var notifications = 0;
    selector.addListener(() => notifications++);

    selector.select(hosts);
    selector.recordSuccess('node1', const Duration(milliseconds: 120));
    selector.recordFailure('node2', hosts);

    expect(notifications, 3);
  });
}
