import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/routing/branch_activation.dart';
import 'package:kira/routing/main_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

/// 记录「首次加载」发生的分支页：onBranchFirstActivated 触发时把 marker
/// 追加进共享的 loads 列表，用列表内容断言门控时序。
class _RecorderPage extends StatefulWidget {
  const _RecorderPage(this.marker, this.loads);

  final String marker;
  final List<String> loads;

  @override
  State<_RecorderPage> createState() => _RecorderPageState();
}

class _RecorderPageState extends State<_RecorderPage> with BranchDeferredInit {
  @override
  void initState() {
    super.initState();
    deferInitialLoadToBranchActivation();
  }

  @override
  void onBranchFirstActivated() => widget.loads.add(widget.marker);

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(widget.marker)));
}

/// 分支布局与 `_navKeyToBranchIndex` 对齐（comic 0 / search 1 / bookshelf 2 /
/// profile 3 / novel 4），全部 preload，与 app_router 的挂载策略一致。
GoRouter _buildRouter(List<String> loads) {
  GoRoute branch(String path, String marker) =>
      GoRoute(path: path, builder: (_, _) => _RecorderPage(marker, loads));

  return GoRouter(
    initialLocation: '/',
    routes: [
      StatefulShellRoute(
        navigatorContainerBuilder: buildMainShellNavigatorContainer,
        builder: (context, state, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            preload: true,
            routes: [branch('/', 'page-comic')],
          ),
          StatefulShellBranch(
            preload: true,
            routes: [branch('/search', 'page-search')],
          ),
          StatefulShellBranch(
            preload: true,
            routes: [branch('/bookshelf', 'page-bookshelf')],
          ),
          StatefulShellBranch(
            preload: true,
            routes: [branch('/profile', 'page-profile')],
          ),
          StatefulShellBranch(
            preload: true,
            routes: [branch('/novels', 'page-novel')],
          ),
        ],
      ),
    ],
  );
}

Widget _buildApp(GoRouter router) {
  return MaterialApp.router(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: router,
  );
}

/// 默认视口（800x600）走左侧 NavigationRail，按目的地标签切换，
/// 不依赖图标样式或选中态。
Future<void> _tapDestination(WidgetTester tester, String label) async {
  final destination = find.descendant(
    of: find.byType(NavigationRail),
    matching: find.text(label),
  );
  expect(destination, findsOneWidget);
  await tester.tap(destination);
  await tester.pump();
}

/// 推过去稳态：切页动画（300ms）+ 停稳去抖（400ms）+ 预热链路（1.2s 起，
/// 逐分支 60ms）都要耗完，测试结束时也不能残留待触发定时器。
Future<void> _pumpSettled(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'disclaimer_accepted': true,
      'auto_check_update': false,
      'remote_notice_enabled': false,
    });
    setupSecureCredentialStoreForTest();
    await UserManager().init();
  });

  tearDown(teardownSecureCredentialStoreForTest);

  testWidgets('启动只加载初始分支，其他分支保持未加载', (tester) async {
    final loads = <String>[];
    await tester.pumpWidget(_buildApp(_buildRouter(loads)));
    await _pumpSettled(tester);

    expect(loads, ['page-comic']);
  });

  testWidgets('切到新分支停稳后加载一次，切回不重复加载', (tester) async {
    final loads = <String>[];
    await tester.pumpWidget(_buildApp(_buildRouter(loads)));
    await _pumpSettled(tester);

    // 漫画 → 我的。
    await _tapDestination(tester, '我的');
    await _pumpSettled(tester);
    expect(loads, ['page-comic', 'page-profile']);

    // 切回漫画分支：状态保留，首次加载不重放。
    await _tapDestination(tester, '漫画');
    await _pumpSettled(tester);
    expect(loads, ['page-comic', 'page-profile']);
  });

  testWidgets('停稳去抖窗口内切走的目标分支不加载', (tester) async {
    final loads = <String>[];
    await tester.pumpWidget(_buildApp(_buildRouter(loads)));
    await _pumpSettled(tester);

    // 点书架后 50ms 内切回漫画：书架从未成为「停稳激活」分支。
    await _tapDestination(tester, '书架');
    await tester.pump(const Duration(milliseconds: 50));
    await _tapDestination(tester, '漫画');
    await _pumpSettled(tester);

    expect(loads, ['page-comic']);
  });

  testWidgets('拖动切页与点按一样触发停稳加载', (tester) async {
    final loads = <String>[];
    await tester.pumpWidget(_buildApp(_buildRouter(loads)));
    await _pumpSettled(tester);

    // 默认可见序 [comic, novel, search, bookshelf, profile]：向左滑 = 下一页。
    await tester.timedDrag(
      find.text('page-comic'),
      const Offset(-400, 0),
      const Duration(milliseconds: 300),
    );
    await _pumpSettled(tester);

    expect(loads, ['page-comic', 'page-novel']);
  });

  testWidgets('不在分支容器内的页面保持挂载即加载的旧行为', (tester) async {
    final loads = <String>[];
    await tester.pumpWidget(
      MaterialApp(home: _RecorderPage('page-solo', loads)),
    );
    await tester.pump();

    expect(loads, ['page-solo']);
  });
}
