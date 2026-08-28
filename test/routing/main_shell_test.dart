import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/routing/main_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

/// 带计数按钮的占位页：计数存在自己的 State 里，分支子树一旦被重挂载就清零。
class _CounterPage extends StatefulWidget {
  const _CounterPage({required this.marker, this.showCounter = false});

  final String marker;
  final bool showCounter;

  @override
  State<_CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<_CounterPage> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.marker),
            if (widget.showCounter)
              FilledButton(
                onPressed: () => setState(() => _count++),
                child: Text('count:$_count'),
              ),
          ],
        ),
      ),
    );
  }
}

class _MarkerPage extends StatelessWidget {
  const _MarkerPage(this.marker);

  final String marker;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text(marker)));
  }
}

/// 分支布局与 `_navKeyToBranchIndex` 对齐（comic 0 / anime 1 / search 2 /
/// bookshelf 3 / profile 4），保证 goBranch 的分支序号不越界。
/// preload 与 app_router 保持一致：各分支页面启动即挂载。
GoRouter _buildRouter() {
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
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => const _MarkerPage('page-comic'),
              ),
            ],
          ),
          StatefulShellBranch(
            preload: true,
            routes: [
              GoRoute(
                path: '/anime',
                builder: (_, _) => const _MarkerPage('page-anime'),
              ),
            ],
          ),
          StatefulShellBranch(
            preload: true,
            routes: [
              GoRoute(
                path: '/search',
                builder: (_, _) => const _CounterPage(
                  marker: 'page-search',
                  showCounter: true,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            preload: true,
            routes: [
              GoRoute(
                path: '/bookshelf',
                builder: (_, _) => const _MarkerPage('page-bookshelf'),
              ),
            ],
          ),
          StatefulShellBranch(
            preload: true,
            routes: [
              GoRoute(
                path: '/profile',
                builder: (_, _) => const _MarkerPage('page-profile'),
              ),
            ],
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

/// 用户未登录且未开启 anime，默认可见序为 [comic, search, profile]。
Future<void> _pumpShell(WidgetTester tester) async {
  await tester.pumpWidget(_buildApp(_buildRouter()));
  await tester.pumpAndSettle();
}

/// 找到包住指定分支页面的 RepaintBoundary（父级是分支的 FractionalTranslation）。
/// 手动向上遍历祖先，绕开 find.ancestor 对 Offstage 子树的默认过滤。
RenderRepaintBoundary _branchBoundary(WidgetTester tester, String marker) {
  RenderRepaintBoundary? boundary;
  tester.element(find.text(marker, skipOffstage: false)).visitAncestorElements((
    element,
  ) {
    final renderObject = element.renderObject;
    if (renderObject is RenderRepaintBoundary &&
        renderObject.parent is RenderFractionalTranslation) {
      boundary = renderObject;
      return false;
    }
    return true;
  });
  return boundary!;
}

/// 把预热链路的时间推完（启动 1.2s 后逐帧预热各隐藏分支）。
Future<void> _pumpThroughWarmUp(WidgetTester tester) async {
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

  testWidgets('滑动切页保状态，且所有分支 widget 结构稳定', (tester) async {
    await _pumpShell(tester);

    // 结构稳定：隐藏分支也保持同一套包装结构（Offstage>TickerMode>IgnorePointer>
    // FractionalTranslation>RepaintBoundary），5 个分支各有一份。页面内容里
    // 也有零散的 FractionalTranslation，这里只认「直接包 RepaintBoundary」的
    // 分支级包装。
    final translations = find.byWidgetPredicate(
      (widget) =>
          widget is FractionalTranslation && widget.child is RepaintBoundary,
      skipOffstage: false,
    );
    expect(tester.widgetList(translations).length, 5);

    // 预热后：不可见的相邻分支应已被绘制（无待重绘标记），首次滑入不再付
    // 首次光栅化的开销；被设置隐藏的分支（anime、bookshelf）则跳过预热。
    await _pumpThroughWarmUp(tester);
    expect(_branchBoundary(tester, 'page-search').debugNeedsPaint, isFalse);
    expect(_branchBoundary(tester, 'page-profile').debugNeedsPaint, isFalse);
    expect(_branchBoundary(tester, 'page-bookshelf').debugNeedsPaint, isTrue);

    // 向左滑到搜索页。
    await tester.timedDrag(
      find.text('page-comic'),
      const Offset(-400, 0),
      const Duration(milliseconds: 300),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('page-search'), findsOneWidget);
    expect(find.text('page-comic'), findsNothing);

    // 改动搜索页内部状态，滑走再滑回来，状态必须保留。
    await tester.tap(find.text('count:0'));
    await tester.pump();
    expect(find.text('count:1'), findsOneWidget);

    await tester.timedDrag(
      find.text('page-search'),
      const Offset(-400, 0),
      const Duration(milliseconds: 300),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('page-profile'), findsOneWidget);

    await tester.timedDrag(
      find.text('page-profile'),
      const Offset(400, 0),
      const Duration(milliseconds: 300),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('page-search'), findsOneWidget);
    expect(find.text('count:1'), findsOneWidget);

    // 滑动结束后结构依旧稳定。
    expect(tester.widgetList(translations).length, 5);
  });
}
