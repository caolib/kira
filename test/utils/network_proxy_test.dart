import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/utils/network_proxy.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('proxy endpoint rule does not fall back to direct connection', () {
    const httpProxy = NetworkProxyEndpoint(
      host: '127.0.0.1',
      port: 7890,
      type: NetworkProxyType.http,
    );
    const socksProxy = NetworkProxyEndpoint(
      host: '127.0.0.1',
      port: 7891,
      type: NetworkProxyType.socks,
    );

    expect(httpProxy.findProxyRule, 'PROXY 127.0.0.1:7890');
    expect(socksProxy.findProxyRule, 'SOCKS 127.0.0.1:7891');
  });

  test('manual proxy mode uses the configured proxy only', () async {
    final user = UserManager();
    await user.init();
    await user.setManualProxy(
      host: '127.0.0.1',
      port: 7890,
      type: NetworkProxyType.http,
    );

    expect(
      NetworkProxy.findProxy(Uri.parse('https://www.google.com/')),
      'PROXY 127.0.0.1:7890',
    );
  });
}
