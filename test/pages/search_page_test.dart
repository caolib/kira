import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/search_page.dart';
import 'package:kira/repositories/search_init_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    setupSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({'anime_feature_enabled': false});
    await UserManager().init();
  });

  tearDown(teardownSecureCredentialStoreForTest);

  /// 测试环境下所有 HTTP 请求都会返回 400，搜索初始化必然失败；
  /// 等它跑完（失败会被页面自身捕获并记日志）再断言。
  Future<void> settleInitFailure(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// 往缓存里塞足够多的热搜词，让页面有可滚动的内容。
  Future<void> seedScrollableContent() async {
    await SearchInitRepository().saveToCache(
      SearchInitData(
        keywords: List.generate(80, (i) => '热搜关键词$i'),
        tags: const [],
      ),
    );
  }

  /// 输入框一聚焦光标就开始闪，`pumpAndSettle` 永远等不到静止；
  /// 这里按固定时长推进，足够跑完 200ms 的头部滑动动画。
  Future<void> settleAnimation(WidgetTester tester) =>
      tester.pump(const Duration(milliseconds: 400));

  Offset headerOffset(WidgetTester tester) =>
      tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset;

  ScrollPosition scrollPosition(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        ),
      )
      .position;

  testWidgets('search bar is pinned outside the scroll view', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(const SearchPage(), wrapInScaffold: false),
    );
    await settleInitFailure(tester);

    expect(find.byType(SearchBar), findsOneWidget);
    // 关键不变量：搜索框不在滚动视图内。放进去（例如 floating SliverAppBar）
    // 时聚焦会触发「把焦点控件滚进可视区」，头部被滚走后失焦、键盘收起。
    expect(
      find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(SearchBar),
      ),
      findsNothing,
    );
    expect(headerOffset(tester), Offset.zero);
  });

  testWidgets('header hides on scroll down and returns on scroll up', (
    tester,
  ) async {
    await seedScrollableContent();
    await tester.pumpWidget(
      wrapWithApp(const SearchPage(), wrapInScaffold: false),
    );
    await settleInitFailure(tester);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await settleAnimation(tester);
    expect(headerOffset(tester), const Offset(0, -1));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 60));
    await settleAnimation(tester);
    expect(headerOffset(tester), Offset.zero);
  });

  testWidgets('tapping the search bar focuses it without scrolling the list', (
    tester,
  ) async {
    await seedScrollableContent();
    await tester.pumpWidget(
      wrapWithApp(const SearchPage(), wrapInScaffold: false),
    );
    await settleInitFailure(tester);

    await tester.enterText(find.byType(SearchBar), '海贼王');
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await settleAnimation(tester);
    // 有关键词 + 已下滑，就是用户报的复现条件。
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 60));
    await settleAnimation(tester);

    final offsetBeforeTap = scrollPosition(tester).pixels;
    expect(offsetBeforeTap, greaterThan(0));

    await tester.tap(find.byType(SearchBar));
    await settleAnimation(tester);

    expect(scrollPosition(tester).pixels, offsetBeforeTap);
    expect(headerOffset(tester), Offset.zero);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('clear button shows with input and empties the keyword', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapWithApp(const SearchPage(), wrapInScaffold: false),
    );
    await settleInitFailure(tester);

    expect(find.byIcon(Icons.clear), findsNothing);

    await tester.enterText(find.byType(SearchBar), '海贼王');
    await tester.pump();

    expect(find.text('海贼王'), findsOneWidget);
    expect(find.byIcon(Icons.clear), findsOneWidget);

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();

    expect(find.text('海贼王'), findsNothing);
    expect(find.byIcon(Icons.clear), findsNothing);
  });
}
