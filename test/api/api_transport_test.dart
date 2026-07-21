import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/api/api_transport.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/utils/data_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fixed node mode always uses the selected host', () async {
    SharedPreferences.setMockInitialValues({});
    final user = UserManager();
    await user.init();
    await user.setFixedNodeHost(routes[1][2]);
    await user.setNetworkSelectionMode(NetworkSelectionMode.fixedNode);

    final transport = ApiTransport(
      dio: Dio(),
      commentDio: Dio(),
      user: user,
      cache: DataCache(),
    );

    expect(transport.nextHost(), routes[1][2]);
    expect(transport.nextHost(), routes[1][2]);
  });

  test(
    'route mode uses a host within the selected route and ignores probe weights for other routes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final user = UserManager();
      await user.init();
      await user.setApiRoute(0);
      await user.setNetworkSelectionMode(NetworkSelectionMode.route);

      final transport = ApiTransport(
        dio: Dio(),
        commentDio: Dio(),
        user: user,
        cache: DataCache(),
      );
      final hosts = routes.expand((route) => route).toList();
      // 上报各节点探测结果,仅影响权重,落点仍应在当前路线 route[0] 内。
      for (final host in hosts) {
        transport.recordNodeProbe(host, 1);
      }
      final picked = transport.nextHost();
      expect(routes[0], contains(picked));
    },
  );
}
