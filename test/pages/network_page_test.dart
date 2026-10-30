import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/api/api_client.dart';
import 'package:kira/api/network/network_api.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/network_page.dart';
import 'package:kira/widgets/select_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

/// 只覆盖测速入口；线路卡片布局不依赖网络结果。
class _FakeNetworkApi implements NetworkApi {
  @override
  List<String> getRouteHosts(int routeIndex) => const ['route-host.test'];

  @override
  List<String> getExtraApiHosts() => const ['copy-host.test'];

  @override
  String getExtraApiHostLabel(String host, AppLocalizations l10n) =>
      l10n.networkCopyApiHost;

  @override
  Future<Map<String, int?>> testRouteLatency(
    int routeIndex, {
    void Function(String host, int? latency)? onHostResult,
  }) async {
    final latency = routeIndex == 0 ? 500 : 100;
    onHostResult?.call('route-host.test', latency);
    return {'route-host.test': latency};
  }

  @override
  Future<Map<String, int?>> testExtraApiLatency({
    void Function(String host, int? latency)? onHostResult,
  }) async {
    onHostResult?.call('copy-host.test', 200);
    return {'copy-host.test': 200};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClient implements ApiClient {
  @override
  final NetworkApi network = _FakeNetworkApi();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late ApiClient originalApi;

  setUp(() async {
    setupSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({});
    await UserManager().init();
    originalApi = ApiClient();
    ApiClient.setTestInstance(_FakeClient());
  });

  tearDown(() {
    ApiClient.setTestInstance(originalApi);
    teardownSecureCredentialStoreForTest();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: wrapWithApp(const NetworkPage(), wrapInScaffold: false),
      ),
    );
    // 呼吸灯是无限循环动画，不能用 pumpAndSettle；固定 pump 两帧让
    // post-frame 自动测速完成，「其他」块随之出现。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  void setScreen(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('speed tests switch routes without a success toast', (
    tester,
  ) async {
    await pumpPage(tester);
    expect(UserManager().apiRoute, 1);
    expect(find.textContaining('测速后已'), findsNothing);
    expect(find.textContaining('建议开启代理'), findsNothing);
    await tester.tap(find.text('测速'));
    await tester.pump();
    expect(find.textContaining('测速后已'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide screen puts route cards and the extra group on one row', (
    tester,
  ) async {
    setScreen(tester, const Size(900, 700));
    await pumpPage(tester);

    final route1 = tester.getTopLeft(find.text('线路 1'));
    final route2 = tester.getTopLeft(find.text('线路 2'));
    final other = tester.getTopLeft(find.text('其他'));

    // 标题字号不同会带来 1px 基线差，同一行按「垂直位置接近」判断。
    expect(route2.dy, closeTo(route1.dy, 2));
    expect(other.dy, closeTo(route1.dy, 2));
    expect(route1.dx, lessThan(route2.dx));
    expect(route2.dx, lessThan(other.dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('auto-test switch reveals all four intervals below the cards', (
    tester,
  ) async {
    setScreen(tester, const Size(900, 900));
    await pumpPage(tester);
    expect(UserManager().network.autoTestEnabled, isFalse);
    expect(find.text('测速间隔'), findsNothing);
    await tester.tap(find.text('定时测速并切换线路'));
    await tester.pump();
    expect(UserManager().network.autoTestEnabled, isTrue);
    expect(find.text('测速间隔'), findsOneWidget);
    expect(find.text('1h'), findsOneWidget);
    await tester.tap(find.byType(SelectTile<int>));
    await tester.pump();
    for (final hours in [1, 3, 6, 24]) {
      expect(find.text('${hours}h'), findsWidgets);
    }
    await tester.tap(find.text('6h'));
    await tester.pump();
    expect(UserManager().network.autoTestIntervalHours, 6);
    expect(find.text('6h'), findsOneWidget);
    await tester.tap(find.text('定时测速并切换线路'));
    await tester.pump();
    expect(find.text('测速间隔'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow screen keeps the cards stacked vertically', (
    tester,
  ) async {
    setScreen(tester, const Size(400, 900));
    await pumpPage(tester);

    final route1 = tester.getTopLeft(find.text('线路 1'));
    final route2 = tester.getTopLeft(find.text('线路 2'));
    final other = tester.getTopLeft(find.text('其他'));

    expect(route2.dy, greaterThan(route1.dy));
    expect(other.dy, greaterThan(route2.dy));
    expect(tester.getTopLeft(find.text('定时测速并切换线路')).dy, greaterThan(other.dy));
    expect(tester.takeException(), isNull);
  });
}
