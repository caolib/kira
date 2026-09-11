import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/widgets/login_node_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _buildTestApp(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    LoginNodeStatusCard.probeOverride = (hosts, {onHostResult}) async {
      final results = <String, int?>{for (final host in hosts) host: 120};
      for (final entry in results.entries) {
        onHostResult?.call(entry.key, entry.value);
      }
      return results;
    };
  });

  tearDown(() {
    LoginNodeStatusCard.probeOverride = null;
  });

  testWidgets('hot source shows only the hot login host', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await UserManager().init();

    await tester.pumpWidget(
      _buildTestApp(const LoginNodeStatusCard(useCopyLogin: false)),
    );
    await tester.pumpAndSettle();

    expect(find.text('热辣登录'), findsOneWidget);
    expect(find.text('拷贝登录'), findsNothing);
    expect(find.text('120 ms'), findsOneWidget);
    expect(find.text('超时'), findsNothing);
    expect(find.text('当前延迟较大，建议开启代理'), findsNothing);
  });

  testWidgets('copy source shows only the copy login host', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await UserManager().init();

    await tester.pumpWidget(
      _buildTestApp(const LoginNodeStatusCard(useCopyLogin: true)),
    );
    await tester.pumpAndSettle();

    expect(find.text('拷贝登录'), findsOneWidget);
    expect(find.text('热辣登录'), findsNothing);
    expect(find.text('120 ms'), findsOneWidget);
  });

  testWidgets('shows timeout state and proxy hint when host is unreachable', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await UserManager().init();
    LoginNodeStatusCard.probeOverride = (hosts, {onHostResult}) async {
      final results = <String, int?>{for (final host in hosts) host: null};
      for (final entry in results.entries) {
        onHostResult?.call(entry.key, entry.value);
      }
      return results;
    };

    await tester.pumpWidget(
      _buildTestApp(const LoginNodeStatusCard(useCopyLogin: false)),
    );
    await tester.pumpAndSettle();

    expect(find.text('超时'), findsOneWidget);
    expect(find.text('超时，无法连接'), findsOneWidget);
  });

  testWidgets('refresh button re-runs the probe', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await UserManager().init();
    var calls = 0;
    LoginNodeStatusCard.probeOverride = (hosts, {onHostResult}) async {
      calls++;
      final results = <String, int?>{for (final host in hosts) host: 100};
      for (final entry in results.entries) {
        onHostResult?.call(entry.key, entry.value);
      }
      return results;
    };

    await tester.pumpWidget(
      _buildTestApp(const LoginNodeStatusCard(useCopyLogin: false)),
    );
    await tester.pumpAndSettle();
    expect(calls, 1);

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('100 ms'), findsOneWidget);
  });
}
