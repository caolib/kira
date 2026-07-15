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

  test('automatic mode uses recent node performance', () async {
    SharedPreferences.setMockInitialValues({});
    final user = UserManager();
    await user.init();
    await user.setNetworkSelectionMode(NetworkSelectionMode.automatic);

    final transport = ApiTransport(
      dio: Dio(),
      commentDio: Dio(),
      user: user,
      cache: DataCache(),
    );
    final hosts = routes.expand((route) => route).toList();
    for (var i = 0; i < hosts.length; i++) {
      transport.recordNodeProbe(hosts[i], 600 - i * 50);
    }

    expect(transport.nextHost(), hosts.last);
  });
}
