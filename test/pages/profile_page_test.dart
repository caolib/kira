import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/models/copy_account_store.dart';
import 'package:kira/models/novel_reading_progress.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/about_page.dart' show AboutPage;
import 'package:kira/pages/profile_page.dart';
import 'package:kira/utils/app_update.dart';
import 'package:kira/utils/novel_reading_store.dart';
import 'package:kira/utils/reading_history.dart';
import 'package:kira/utils/remote_notice_service.dart';
import 'package:kira/widgets/account_avatar.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

Widget _buildTestApp(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(setupSecureCredentialStoreForTest);
  tearDown(teardownSecureCredentialStoreForTest);

  Future<void> pumpProfilePage(WidgetTester tester) async {
    RemoteNoticeService.unreadActiveCount.value = 0;
    SharedPreferences.setMockInitialValues({
      'user_token': 'current-token',
      'user_user_id': '1',
      'user_username': 'alice',
      'user_nickname': 'Alice',
      'user_avatar': '',
      'saved_username': 'alice',
      'saved_password': 'alice-pass',
      'saved_credentials': jsonEncode([
        {
          'username': 'alice',
          'password': 'alice-pass',
          'token': 'current-token',
          'user_id': '1',
          'nickname': 'Alice',
          'avatar': '',
        },
        {
          'username': 'bob',
          'password': 'bob-pass',
          'token': 'bob-token',
          'user_id': '2',
          'nickname': 'Bob',
          'avatar': '',
        },
      ]),
    });
    await UserManager().init();

    await tester.pumpWidget(_buildTestApp(const ProfilePage()));
    await tester.pumpAndSettle();
  }

  testWidgets('account entry shows nickname and avatar', (tester) async {
    await pumpProfilePage(tester);
    final tile = tester.widget<ListTile>(
      find.byKey(const ValueKey('profile-account-entry')),
    );
    expect(find.byType(AccountAvatar), findsOneWidget);
    expect(tester.widget<AccountAvatar>(find.byType(AccountAvatar)).radius, 12);
    expect(find.byIcon(Icons.manage_accounts_rounded), findsNothing);
    expect(find.byType(CircleAvatar), findsOneWidget);
    expect(tile.subtitle, isNull);
    expect(tile.trailing, isNull);
    expect(tile.onTap, isNotNull);
    expect(find.text('账号中心'), findsNothing);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('alice'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Alice')).dy,
      lessThan(tester.getTopLeft(find.text('通用')).dy),
    );
  });

  testWidgets('manual novel selection does not replace the profile identity', (
    tester,
  ) async {
    await pumpProfilePage(tester);
    await UserManager().copyAccount.saveSession(
      const CopyAccountSession(
        token: 'independent-copy-token',
        userId: 'copy-id',
        username: 'copy-user',
        avatar: 'user/cover/copy.png',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AccountAvatar), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('alice'), findsNothing);
    expect(find.text('copy-user'), findsNothing);
    await UserManager().logout();
    await tester.pumpAndSettle();
    expect(find.text('未登录'), findsOneWidget);
    expect(find.text('copy-user'), findsNothing);
  });

  testWidgets('a token-only comic account is shown as logged in', (
    tester,
  ) async {
    await pumpProfilePage(tester);
    // 漫画未登录时，令牌登录才会接管主账号并成为「我的」页显示的身份。
    await UserManager().logout();
    await UserManager().authenticateAndLogin(
      source: 'copy',
      authenticate: () async => {'token': 'token-only-profile'},
    );
    await tester.pumpAndSettle();
    expect(find.text('已登录（未获取资料）'), findsOneWidget);
    expect(find.text('未登录'), findsNothing);
    expect(find.text('token-only-profile'), findsNothing);
  });

  testWidgets('a new comic login does not replace the profile identity', (
    tester,
  ) async {
    await pumpProfilePage(tester);
    await UserManager().authenticateAndLogin(
      source: 'copy',
      authenticate: () async => {'token': 'token-only-profile'},
    );
    await tester.pumpAndSettle();
    // 已有漫画账号 alice 时，登录只入库，不接管「我的」页身份。
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('已登录（未获取资料）'), findsNothing);
  });

  testWidgets('profile page shows general settings entry', (tester) async {
    await pumpProfilePage(tester);

    expect(find.text('通用'), findsOneWidget);
  });

  testWidgets('wide screen puts the data card in the right column', (
    tester,
  ) async {
    // 900 逻辑宽触发宽屏双列:左列账号/通用 + 关于,右列数据卡(下载中心…)。
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(900 * 3, 1000 * 3);
    addTearDown(tester.view.reset);

    await pumpProfilePage(tester);

    final download = tester.getTopLeft(find.text('下载中心'));
    final general = tester.getTopLeft(find.text('通用'));
    final about = tester.getTopLeft(find.text('关于'));

    expect(download.dx, greaterThan(general.dx));
    expect(about.dx, general.dx);
    expect(about.dy, greaterThan(general.dy));
  });

  testWidgets('notice center follows AI configuration and keeps its red dot', (
    tester,
  ) async {
    // 单列分组：通用/网络 → 下载/记录 → 统计/AI/通知/关于。
    // 显式使用600逻辑宽，避免默认800宽触发双列布局。
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(600 * 3, 1000 * 3);
    addTearDown(tester.view.reset);

    await pumpProfilePage(tester);

    expect(
      MediaQuery.sizeOf(tester.element(find.byType(ProfilePage))).width,
      600,
    );
    final networkTop = tester.getTopLeft(find.byIcon(Icons.dns_rounded)).dy;
    final aiTop = tester.getTopLeft(find.text('AI配置')).dy;
    final noticeTop = tester.getTopLeft(find.text('通知中心')).dy;
    final downloadTop = tester.getTopLeft(find.text('下载中心')).dy;
    final statsTop = tester.getTopLeft(find.text('阅读统计')).dy;

    expect(downloadTop, greaterThan(networkTop));
    expect(downloadTop, lessThan(statsTop));
    expect(statsTop, lessThan(aiTop));
    expect(noticeTop, greaterThan(aiTop));
    expect(noticeTop, lessThan(tester.getTopLeft(find.text('关于')).dy));
  });

  testWidgets('notice red dot uses notice icon color', (tester) async {
    await pumpProfilePage(tester);

    RemoteNoticeService.unreadActiveCount.value = 1;
    await tester.pump();

    expect(
      find.byWidgetPredicate((widget) {
        final decoration = widget is Container ? widget.decoration : null;
        return widget is Container &&
            decoration is BoxDecoration &&
            decoration.color == const Color(0xFFEB6F92);
      }),
      findsOneWidget,
    );
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      'update and notice badges remain available on $platform',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        await UserManager().init();
        final oldUpdateBadge = AppUpdateService.hasUnseenUpdate.value;
        final oldNoticeCount = RemoteNoticeService.unreadActiveCount.value;
        addTearDown(() {
          AppUpdateService.hasUnseenUpdate.value = oldUpdateBadge;
          RemoteNoticeService.unreadActiveCount.value = oldNoticeCount;
        });
        AppUpdateService.hasUnseenUpdate.value = true;
        RemoteNoticeService.unreadActiveCount.value = 1;
        await tester.pumpWidget(
          wrapWithApp(const ProfilePage(), wrapInScaffold: false),
        );
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.widgetWithText(ListTile, '关于'),
            matching: find.byType(Positioned),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.widgetWithText(ListTile, '通知中心'),
            matching: find.byType(Positioned),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(wrapWithApp(const SizedBox.shrink()));
      },
      variant: TargetPlatformVariant({platform}),
    );
  }

  testWidgets('about page shows error log entry', (tester) async {
    SharedPreferences.setMockInitialValues({'app_logging_enabled': true});
    PackageInfo.setMockInitialValues(
      appName: 'Kira',
      packageName: 'com.example.kira',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    await UserManager().init();
    // This test only checks the log entry. Suppress AboutPage's automatic
    // network update check without running a real HTTP client.
    final previousUpdateState = AppUpdateService.state.value;
    AppUpdateService.state.value = const AppUpdateState.checking();
    addTearDown(() => AppUpdateService.state.value = previousUpdateState);

    await tester.pumpWidget(_buildTestApp(const AboutPage()));
    // AboutPage 的更新检查指示器常驻动画会让 pumpAndSettle 永不结束，
    // 用固定 pump 等首帧与异步初始化完成。
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('日志'), findsOneWidget);
    expect(find.byIcon(Icons.bug_report_outlined), findsOneWidget);
  });

  testWidgets('继续阅读漫画：名称可截断，页/总页进度留在副标题里', (tester) async {
    _useNarrowScreen(tester);
    await pumpProfilePage(tester);
    await ReadingHistory.save(
      pathWord: 'comic-long',
      comicName: '夏日回忆',
      chapterUuid: 'chapter-12',
      chapterName: '第12话 这是一个特别特别长的章节标题用来把副标题整行都塞满',
      page: 12,
      totalPage: 30,
    );
    await ReadingHistory.flush();
    await tester.pumpAndSettle();

    final tile = find.widgetWithText(ListTile, '继续阅读漫画');
    expect(tile, findsOneWidget);
    final progress = find.descendant(of: tile, matching: find.text('12/30'));
    expect(progress, findsOneWidget);
    expect(
      find.descendant(of: tile, matching: find.text('第 12 页')),
      findsNothing,
    );

    _expectNameTruncatedButProgressIntact(
      tester,
      tile: tile,
      progress: progress,
      namePrefix: '夏日回忆 ·',
    );
  });

  testWidgets('继续阅读漫画：没有总页数的老记录退回「第 N 页」', (tester) async {
    _useNarrowScreen(tester);
    await pumpProfilePage(tester);
    await ReadingHistory.save(
      pathWord: 'comic-legacy',
      comicName: '旧记录',
      chapterUuid: 'chapter-3',
      chapterName: '第3话',
      page: 3,
    );
    await ReadingHistory.flush();
    await tester.pumpAndSettle();

    final tile = find.widgetWithText(ListTile, '继续阅读漫画');
    expect(
      find.descendant(of: tile, matching: find.text('第 3 页')),
      findsOneWidget,
    );
  });

  testWidgets('继续阅读轻小说：名称可截断，卷内整数百分比不被挤掉', (tester) async {
    _useNarrowScreen(tester);
    await pumpProfilePage(tester);
    await NovelReadingStore().saveProgress(
      NovelReadingProgress(
        pathWord: 'novel-long',
        name: '特别特别长的书名用来把副标题整行都占满',
        cover: '',
        volumeId: 'vol-1',
        volumeName: '第一卷',
        chapterName: '第一章 标题同样长到会把整行塞满',
        updatedAt: DateTime.now(),
        progress: 0.4237,
      ),
    );
    await tester.pumpAndSettle();

    final tile = find.widgetWithText(ListTile, '继续阅读轻小说');
    expect(tile, findsOneWidget);
    final progress = find.descendant(of: tile, matching: find.text('42%'));
    expect(progress, findsOneWidget);
    // 章节名不进副标题：只剩书名 · 卷名。
    expect(
      find.descendant(of: tile, matching: find.text('第一章 标题同样长到会把整行塞满')),
      findsNothing,
    );
    _expectNameTruncatedButProgressIntact(
      tester,
      tile: tile,
      progress: progress,
      namePrefix: '特别特别长的书名用来把副标题整行都占满 ·',
    );

    // 未读到卷末不得四舍五入成 100%。
    await NovelReadingStore().saveProgress(
      NovelReadingProgress(
        pathWord: 'novel-long',
        name: '特别特别长的书名用来把副标题整行都占满',
        cover: '',
        volumeId: 'vol-1',
        volumeName: '第一卷',
        chapterName: '第一章 标题同样长到会把整行塞满',
        updatedAt: DateTime.now().add(const Duration(minutes: 1)),
        progress: 0.9999,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: tile, matching: find.text('99%')),
      findsOneWidget,
    );
  });
}

/// 360 逻辑宽：单列布局，且副标题宽度不足以放下长名称，能压出省略号。
void _useNarrowScreen(WidgetTester tester) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(360 * 3, 800 * 3);
  addTearDown(tester.view.reset);
}

/// 名称被省略号截断、进度保持完整的两条断言。
void _expectNameTruncatedButProgressIntact(
  WidgetTester tester, {
  required Finder tile,
  required Finder progress,
  required String namePrefix,
}) {
  final name = find.descendant(
    of: tile,
    matching: find.textContaining(namePrefix),
  );
  expect(name, findsOneWidget);
  expect(
    tester.renderObject<RenderParagraph>(name).size.width,
    lessThan(_intrinsicTextWidth(tester, name)),
    reason: '名称应被压缩，好给进度让位',
  );
  expect(
    tester.renderObject<RenderParagraph>(progress).size.width,
    moreOrLessEquals(_intrinsicTextWidth(tester, progress), epsilon: 0.5),
    reason: '进度不能被省略号截掉',
  );
}

/// 单行文本的固有宽度：与实际渲染宽度相等即说明没有被截断。
double _intrinsicTextWidth(WidgetTester tester, Finder finder) {
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  return (TextPainter(
    text: paragraph.text,
    textDirection: TextDirection.ltr,
    textScaler: paragraph.textScaler,
    maxLines: 1,
  )..layout()).size.width;
}
