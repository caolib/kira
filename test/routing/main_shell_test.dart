import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/routing/main_shell.dart';
import 'package:kira/utils/app_update.dart';
import 'package:kira/utils/remote_notice_service.dart';
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

/// 分支布局与 `_navKeyToBranchIndex` 对齐（comic 0 / search 1 / bookshelf 2 /
/// profile 3 / novel 4），保证 goBranch 的分支序号不越界。
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
          // 轻小说分支与 app_router 一致：preload 挂载页面框架，首次数据
          // 加载由 BranchDeferredInit 推迟到分支激活（测试页不发起加载）。
          // 它仍占可见序的第 5 位。
          StatefulShellBranch(
            preload: true,
            routes: [
              GoRoute(
                path: '/novels',
                builder: (_, _) => const _MarkerPage('page-novel'),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

Widget _buildApp(GoRouter router, {double textScale = 1}) {
  return MaterialApp.router(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: router,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
  );
}

/// 未登录时默认可见序为 [comic, novel, search, bookshelf, profile]。
Future<void> _pumpShell(WidgetTester tester, {double textScale = 1}) async {
  await tester.pumpWidget(_buildApp(_buildRouter(), textScale: textScale));
  await tester.pumpAndSettle();
}

/// 找到包住指定分支页面的 RepaintBoundary（父级是分支的 Opacity）。
/// 手动向上遍历祖先，绕开 find.ancestor 对 Offstage 子树的默认过滤。
RenderRepaintBoundary? _branchBoundary(WidgetTester tester, String marker) {
  RenderRepaintBoundary? boundary;
  tester.element(find.text(marker, skipOffstage: false)).visitAncestorElements((
    element,
  ) {
    final renderObject = element.renderObject;
    if (renderObject is RenderRepaintBoundary &&
        renderObject.parent is RenderOpacity) {
      boundary = renderObject;
      return false;
    }
    return true;
  });
  return boundary;
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

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      'navigation update badge and notices remain available on $platform',
      (tester) async {
        final oldUpdateBadge = AppUpdateService.hasUnseenUpdate.value;
        final oldNoticeCount = RemoteNoticeService.unreadActiveCount.value;
        addTearDown(() {
          AppUpdateService.hasUnseenUpdate.value = oldUpdateBadge;
          RemoteNoticeService.unreadActiveCount.value = oldNoticeCount;
        });
        AppUpdateService.hasUnseenUpdate.value = true;
        RemoteNoticeService.unreadActiveCount.value = 0;
        final router = _buildRouter();
        await tester.pumpWidget(
          wrapWithApp(Router.withConfig(config: router), wrapInScaffold: false),
        );
        await tester.pumpAndSettle();
        await _pumpThroughWarmUp(tester);

        Finder badge() => find.descendant(
          of: find.byType(NavigationRail),
          matching: find.byType(Positioned),
        );
        expect(badge(), findsOneWidget);
        AppUpdateService.hasUnseenUpdate.value = false;
        await tester.pump();
        expect(badge(), findsNothing);
        RemoteNoticeService.unreadActiveCount.value = 1;
        await tester.pump();
        expect(badge(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(wrapWithApp(const SizedBox.shrink()));
        router.dispose();
      },
      variant: TargetPlatformVariant({platform}),
    );
  }

  testWidgets('胶囊导航在窄宽和大字号下不横向溢出', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pumpShell(tester, textScale: 1.35);
    await _pumpThroughWarmUp(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('滑动切页保状态，且所有分支 widget 结构稳定', (tester) async {
    await _pumpShell(tester);

    // 结构稳定：隐藏分支也保持同一套包装结构（Offstage>TickerMode>ExcludeFocus>
    // IgnorePointer>Opacity>RepaintBoundary），5 个分支各有一份。
    const branchMarkers = [
      'page-comic',
      'page-search',
      'page-bookshelf',
      'page-profile',
      'page-novel',
    ];
    for (final marker in branchMarkers) {
      expect(_branchBoundary(tester, marker), isNotNull, reason: marker);
    }

    // 预热后：不可见的相邻分支应已被绘制（无待重绘标记），首次滑入不再付
    // 首次光栅化的开销。未登录时书架分支仍然可见（本地小说进度也挂在那里），
    // 所以它同样会被预热。
    await _pumpThroughWarmUp(tester);
    expect(_branchBoundary(tester, 'page-search')!.debugNeedsPaint, isFalse);
    expect(_branchBoundary(tester, 'page-profile')!.debugNeedsPaint, isFalse);
    expect(_branchBoundary(tester, 'page-bookshelf')!.debugNeedsPaint, isFalse);

    // 未登录也必须有书架入口：小说阅读记录等本地内容在那里。
    // 默认 800x600 视口宽>高，主导航走左侧 NavigationRail。
    expect(
      tester
          .widget<NavigationRail>(find.byType(NavigationRail))
          .destinations
          .length,
      5,
    );

    Future<void> swipeLeft(String marker, String expected) async {
      await tester.timedDrag(
        find.text(marker),
        const Offset(-400, 0),
        const Duration(milliseconds: 300),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(expected), findsOneWidget);
      expect(find.text(marker), findsNothing);
    }

    Future<void> swipeRight(String marker, String expected) async {
      await tester.timedDrag(
        find.text(marker),
        const Offset(400, 0),
        const Duration(milliseconds: 300),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(expected), findsOneWidget);
      expect(find.text(marker), findsNothing);
    }

    // 可见序为 comic → novel → search → bookshelf → profile，逐页左滑。
    await swipeLeft('page-comic', 'page-novel');
    await swipeLeft('page-novel', 'page-search');

    // 改动搜索页内部状态，滑走再滑回来，状态必须保留。
    await tester.tap(find.text('count:0'));
    await tester.pump();
    expect(find.text('count:1'), findsOneWidget);

    await swipeLeft('page-search', 'page-bookshelf');
    await swipeLeft('page-bookshelf', 'page-profile');

    await swipeRight('page-profile', 'page-bookshelf');
    await swipeRight('page-bookshelf', 'page-search');
    expect(find.text('count:1'), findsOneWidget);

    // 滑动结束后结构依旧稳定。
    for (final marker in branchMarkers) {
      expect(_branchBoundary(tester, marker), isNotNull, reason: marker);
    }
  });
}
