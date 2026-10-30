import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kira/api/novel/novel_api.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/models/comment_settings.dart';
import 'package:kira/models/novel.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/chapter_comments_sheet.dart'
    show CommentFontScaler, CommentSettingsPanel;
import 'package:kira/providers/app_providers.dart';
import 'package:kira/providers/novel_providers.dart';
import 'package:kira/providers/settings_providers.dart';
import 'package:kira/routing/app_router.dart';
import 'package:kira/widgets/account_avatar.dart';
import 'package:kira/widgets/app_sheet.dart';
import 'package:kira/widgets/comment_skeleton.dart';
import 'package:kira/widgets/novel_comments_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

const _bookUuid = 'book-uuid';
const _parentId = 'parent-comment-uuid';
const _comment = NovelComment(
  id: _parentId,
  comment: '评论正文',
  userName: '小说读者',
  createAt: '2099-01-01 12:30:00',
  count: 2,
);

NovelPage<NovelComment> _page(
  List<NovelComment> list, {
  int? total,
  int offset = 0,
}) => NovelPage(
  list: list,
  total: total ?? list.length,
  limit: 10,
  offset: offset,
);

// No real transport, authentication, images or platform storage is used.
class _Api implements NovelApi {
  Future<NovelPage<NovelComment>> Function(String? replyId, int offset)? load;
  Future<void> Function(String content, String? replyId)? post;
  final requests = <(String, String?, int)>[];
  final posts = <(String, String, String?)>[];

  @override
  Future<NovelPage<NovelComment>> getComments({
    required String bookUuid,
    String? replyId,
    int limit = 10,
    int offset = 0,
  }) {
    requests.add((bookUuid, replyId, offset));
    return load?.call(replyId, offset) ?? Future.value(_page([_comment]));
  }

  @override
  Future<void> postComment({
    required String bookUuid,
    required String content,
    String? replyId,
  }) async {
    posts.add((bookUuid, content, replyId));
    await post?.call(content, replyId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected API call: ${invocation.memberName}');
}

class _User extends ChangeNotifier implements UserManager {
  @override
  String? copyToken;
  bool hotLoggedIn = false;

  // 屏蔽配置：对应 UserManager 类体上的同名成员（判定逻辑为类成员，
  // 假体覆写后才可在测试中驱动屏蔽过滤）。
  List<String> blockedUsers = const [];
  List<String> blockwords = const [];
  bool blockGroupSpam = false;
  bool blockNoRemind = false;
  final blockedCalls = <(String, String)>[];

  @override
  bool get isCopyLoggedIn => copyToken?.isNotEmpty == true;

  @override
  bool get isLoggedIn => hotLoggedIn || isCopyLoggedIn;

  @override
  List<String> get commentBlockedUsers => blockedUsers;

  @override
  List<String> get commentBlockwords => blockwords;

  @override
  bool get commentBlockGroupSpam => blockGroupSpam;

  @override
  bool get commentBlockNoRemind => blockNoRemind;

  @override
  bool isCommentUserBlocked(String userId, String userName) {
    for (final raw in blockedUsers) {
      final sep = raw.indexOf('|');
      final id = sep < 0 ? raw : raw.substring(0, sep);
      final name = sep < 0 ? '' : raw.substring(sep + 1);
      if (userId.isNotEmpty && id == userId) return true;
      if (userId.isEmpty && name.isNotEmpty && name == userName) return true;
    }
    return false;
  }

  @override
  bool isCommentBlockedByWord(String content) {
    final lower = content.toLowerCase();
    return blockwords.any(
      (word) => word.isNotEmpty && lower.contains(word.toLowerCase()),
    );
  }

  @override
  bool isCommentGroupSpam(String content) =>
      blockGroupSpam &&
      content.contains('群') &&
      RegExp(r'\d{8,12}').hasMatch(content);

  @override
  Future<void> blockCommentUser(String userId, String userName) async {
    blockedCalls.add((userId, userName));
    final key = '$userId|$userName';
    if (!blockedUsers.contains(key)) {
      blockedUsers = [...blockedUsers, key];
      notifyListeners();
    }
  }

  @override
  Future<void> setCommentBlockNoRemind(bool value) async {
    blockNoRemind = value;
    notifyListeners();
  }

  void setBlockedUsers(List<String> list) {
    blockedUsers = List.unmodifiable(list);
    notifyListeners();
  }

  void switchAccount(String? token) {
    copyToken = token;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected account field: ${invocation.memberName}');
}

class _Harness {
  final api = _Api();
  final user = _User();
  final settings = CommentSettings();
  late GoRouter router;
  String? loginCopyOnly;

  Future<void> pump(
    WidgetTester tester, {
    bool allowPosting = true,
    String? replyId,
    bool dark = false,
    bool reducedMotion = false,
    double textScale = 1,
    double keyboardInset = 0,
    String bookName = '测试小说',
  }) async {
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: AppSheet(
              heightFactor: 0.85,
              child: NovelCommentsSheet(
                bookUuid: _bookUuid,
                bookName: bookName,
                replyId: replyId,
                allowPosting: allowPosting,
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/login',
          name: AppRoutes.login,
          builder: (_, state) {
            loginCopyOnly = state.uri.queryParameters['copyOnly'];
            return const Scaffold(body: Text('COPY 登录'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    addTearDown(user.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          novelApiProvider.overrideWithValue(api),
          userManagerProvider.overrideWithValue(user),
          commentSettingsProvider.overrideWithValue(settings),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: reducedMotion,
              viewInsets: EdgeInsets.only(bottom: keyboardInset),
            ),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pump();
  }
}

void main() {
  setUp(() async {
    setupSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({});
    final settings = CommentSettings()..resetPrefsCache();
    await settings.initFromPrefs(await SharedPreferences.getInstance());
  });
  tearDown(teardownSecureCredentialStoreForTest);

  testWidgets('沿用漫画的元信息、正文层次和间距，头像复用账号组件', (tester) async {
    final h = _Harness();
    await h.pump(tester);
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('novel-comment-$_parentId'));
    final avatar = find.byType(AccountAvatar);
    final name = find.text('小说读者');
    final time = find.text('刚刚');
    final body = find.text('评论正文');
    expect(card, findsOneWidget);
    expect(avatar, findsOneWidget);
    expect(tester.widget<AccountAvatar>(avatar).radius, 14);
    expect(time, findsOneWidget);
    expect(tester.getCenter(name).dy, tester.getCenter(time).dy);
    expect(
      tester.getRect(body).top,
      greaterThan(tester.getRect(avatar).bottom),
    );
    final style = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .style!;
    expect(style.fontSize, 16);
    expect(style.height, 1.55);
    expect(style.fontWeight, FontWeight.w500);
    // 展开回复与漫画评论区一致：inline 展开控件而非「查看回复」链接。
    expect(find.text('展开 2 条回复'), findsOneWidget);
    expect(find.text('查看回复 (2)'), findsNothing);
    // 悬浮按钮组：评论、回到顶部、关闭（展开回复箭头也用向下图标，共 2 个）。
    expect(find.byIcon(Icons.comment_outlined), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNWidgets(2));
    expect(find.byIcon(Icons.tune), findsOneWidget);
    expect(h.api.requests, [(_bookUuid, null, 0)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置入口复用漫画面板：外观三项 + 屏蔽过滤区，写原键', (tester) async {
    final h = _Harness();
    await h.pump(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    final panel = tester.widget<CommentSettingsPanel>(
      find.byType(CommentSettingsPanel),
    );
    expect(panel.isChapterComments, isFalse);
    // 与漫画评论区一致：屏蔽词/群广告/黑名单过滤区对本评论区开放。
    expect(panel.showFilteringSettings, isTrue);
    // 显示三项 + 群广告开关；布局/初始页数/预加载/AI 总结仍不出现。
    final l10n = AppLocalizations.of(
      tester.element(find.byType(CommentSettingsPanel)),
    )!;
    expect(find.byType(SwitchListTile), findsNWidgets(4));
    expect(find.byType(Slider), findsOneWidget);
    expect(find.byType(SegmentedButton<bool>), findsNothing);
    expect(find.byType(SegmentedButton<int>), findsNothing);
    expect(find.text(l10n.commentSettingsDisplaySection), findsOneWidget);
    expect(find.text(l10n.commentSettingsFilteringSection), findsOneWidget);
    expect(find.text(l10n.commentSettingsLoadingSection), findsNothing);
    expect(find.text(l10n.commentSettingsInitialCountTitle(20)), findsNothing);
    expect(find.text(l10n.commentSettingsAiSummarySection), findsNothing);
    expect(find.text('自动加载全部评论'), findsNothing);
    // 屏蔽词编辑器出现；黑名单为空时只有说明文案。
    expect(
      find.descendant(
        of: find.byType(CommentSettingsPanel),
        matching: find.byType(TextField),
      ),
      findsOneWidget,
    );
    for (final tile in tester.widgetList<SwitchListTile>(
      find.byType(SwitchListTile),
    )) {
      tile.onChanged!(false);
    }
    tester.widget<Slider>(find.byType(Slider)).onChanged!(24);
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('comment_show_avatar'), isFalse);
    expect(prefs.getBool('comment_show_user_name'), isFalse);
    expect(prefs.getBool('comment_show_time'), isFalse);
    expect(prefs.getDouble('comment_font_scale'), 1.5);
    expect(prefs.getBool('comment_block_group_spam'), isFalse);
    expect(prefs.containsKey('comment_preload'), isFalse);
    expect(prefs.containsKey('comment_initial_pages'), isFalse);
    h.router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(AccountAvatar), findsNothing);
    expect(find.text('小说读者'), findsNothing);
    expect(find.text('刚刚'), findsNothing);
    expect(find.text('评论正文'), findsOneWidget);
    expect(
      tester.widget<CommentFontScaler>(find.byType(CommentFontScaler)).scale,
      1.5,
    );
    expect(h.api.requests, hasLength(1));
  });

  testWidgets('其他评论区修改共享显示设置，立即更新且不重新加载', (tester) async {
    final h = _Harness();
    h.user.switchAccount('copy-a');
    await h.pump(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.comment_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '尚未发送的草稿');
    await tester.pump();
    await h.settings.setShowAvatar(false);
    await h.settings.setShowUserName(false);
    await h.settings.setShowTime(false);
    await h.settings.setFontScale(1.25);
    await tester.pumpAndSettle();
    expect(find.byType(AccountAvatar), findsNothing);
    expect(find.text('小说读者'), findsNothing);
    expect(find.text('刚刚'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '尚未发送的草稿',
    );
    expect(h.api.requests, hasLength(1));
    final bodyContext = tester.element(find.text('评论正文'));
    expect(MediaQuery.textScalerOf(bodyContext).scale(16), 20);
    final editorContext = tester.element(find.byType(TextField));
    expect(MediaQuery.textScalerOf(editorContext).scale(16), 16);
  });

  testWidgets('空用户名采用共用匿名文案，空时间不留时间标签', (tester) async {
    final h = _Harness();
    h.api.load = (_, _) async =>
        _page([const NovelComment(id: 'anonymous', comment: '匿名内容')]);
    await h.pump(tester);
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(NovelCommentsSheet)),
    )!;
    expect(find.text(l10n.commentSettingsAnonymousUser), findsOneWidget);
    expect(find.text('刚刚'), findsNothing);
    expect(find.text('展开'), findsNothing);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
  });

  for (final hotOnly in [false, true]) {
    testWidgets('${hotOnly ? '仅热辣登录' : '游客'}可展开回复浏览，回复别人才进COPY登录', (
      tester,
    ) async {
      final h = _Harness();
      h.user.hotLoggedIn = hotOnly;
      h.api.load = (replyId, _) async => replyId == null
          ? _page([_comment])
          : _page([const NovelComment(id: 'reply', comment: '公开回复')]);
      await h.pump(tester);
      await tester.pumpAndSettle();
      // inline 展开回复，不再另开 sheet。
      await tester.tap(find.text('展开 2 条回复'));
      await tester.pumpAndSettle();
      expect(find.text('公开回复'), findsOneWidget);
      expect(h.api.requests, [(_bookUuid, null, 0), (_bookUuid, _parentId, 0)]);
      expect(find.byType(NovelCommentsSheet), findsOneWidget);
      // 游客点回复 → 打开 COPY 登录，不发请求。
      expect(h.loginCopyOnly, isNull);
      await tester.tap(find.text('评论正文'));
      await tester.pumpAndSettle();
      expect(h.loginCopyOnly, 'true');
      expect(h.api.posts, isEmpty);
    });
  }

  testWidgets('禁评只隐藏发表入口，历史评论与回复仍可浏览', (tester) async {
    final h = _Harness();
    h.user.switchAccount('copy-a');
    h.api.load = (replyId, _) async => replyId == null
        ? _page([_comment])
        : _page([const NovelComment(id: 'reply', comment: '历史回复')]);
    await h.pump(tester, allowPosting: false);
    await tester.pumpAndSettle();
    expect(find.text('评论正文'), findsOneWidget);
    // 禁评仍保留评论入口（禁用状态）以及回顶/关闭按钮；卡片点击不弹发表对话框。
    expect(find.byIcon(Icons.comment_outlined), findsOneWidget);
    final commentButton = tester.widget<FilledButton>(
      find.ancestor(
        of: find.byIcon(Icons.comment_outlined),
        matching: find.byType(FilledButton),
      ),
    );
    expect(commentButton.onPressed, isNull);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNWidgets(2));
    await tester.tap(find.text('评论正文'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    // 回复仍可 inline 展开。
    await tester.tap(find.text('展开 2 条回复'));
    await tester.pumpAndSettle();
    expect(find.text('历史回复'), findsOneWidget);
    expect(find.byTooltip('发表评论'), findsNothing);
    expect(h.api.posts, isEmpty);
  });

  testWidgets('加载更多失败保留已有卡片，重试维持原始offset并去重', (tester) async {
    final h = _Harness();
    var failed = false;
    h.api.load = (_, offset) async {
      if (offset == 0) return _page([_comment, _comment], total: 3);
      if (!failed) {
        failed = true;
        throw const NovelApiException('offline');
      }
      return _page(
        [const NovelComment(id: 'next', comment: '下一页评论')],
        total: 3,
        offset: offset,
      );
    };
    await h.pump(tester);
    await tester.pumpAndSettle();
    expect(find.text('评论正文'), findsOneWidget);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(NovelCommentsSheet)),
    )!;
    expect(find.text(l10n.novelLoadMoreFailed), findsOneWidget);
    // 失败原因必须可见，否则截图只有「加载失败」无从排查。
    expect(find.text('offline'), findsOneWidget);
    await tester.tap(find.text(l10n.novelLoadMoreFailed));
    await tester.pumpAndSettle();
    expect(find.text('下一页评论'), findsOneWidget);
    expect(h.api.requests, [
      (_bookUuid, null, 0),
      (_bookUuid, null, 2),
      (_bookUuid, null, 2),
    ]);
    expect(find.text('加载更多'), findsNothing);
  });

  testWidgets('回复加载失败可重试，发送沿用字符串父ID而非漫画接口', (tester) async {
    final h = _Harness();
    h.user.switchAccount('copy-a');
    var attempts = 0;
    h.api.load = (replyId, _) async {
      expect(replyId, _parentId);
      if (++attempts == 1) throw const NovelApiException('offline');
      return _page([const NovelComment(id: 'reply', comment: '恢复的回复')]);
    };
    await h.pump(tester, replyId: _parentId);
    await tester.pumpAndSettle();
    expect(find.text('offline'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('恢复的回复'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('退出账户后加载游客评论，丢弃迟到的旧列表', (tester) async {
    final h = _Harness();
    h.user.switchAccount('copy-a');
    final old = Completer<NovelPage<NovelComment>>();
    h.api.load = (_, _) => h.user.copyToken == 'copy-a'
        ? old.future
        : Future.value(
            _page([const NovelComment(id: 'public', comment: '游客列表')]),
          );
    await h.pump(tester);
    h.user.switchAccount(null);
    await tester.pumpAndSettle();
    expect(find.text('游客列表'), findsOneWidget);
    old.complete(_page([const NovelComment(id: 'old', comment: '迟到的甲列表')]));
    await tester.pumpAndSettle();
    expect(find.text('迟到的甲列表'), findsNothing);
  });

  for (final fail in [false, true]) {
    testWidgets('账户切换后旧发送${fail ? '失败' : '成功'}不刷新、不提示', (tester) async {
      final h = _Harness();
      h.user.switchAccount('copy-a');
      final old = Completer<void>();
      h.api.post = (_, _) => old.future;
      await h.pump(tester);
      await tester.pumpAndSettle();
      // 通过悬浮评论按钮打开发表对话框并提交。
      await tester.tap(find.byIcon(Icons.comment_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '账户甲评论');
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('novel-comment-submit')),
        warnIfMissed: false,
      );
      await tester.pump();
      h.user.switchAccount('copy-b');
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.byIcon(Icons.comment_outlined));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      final requests = h.api.requests.length;
      if (fail) {
        old.completeError(const NovelApiException('old account failure'));
      } else {
        old.complete();
      }
      await tester.pumpAndSettle();
      expect(h.api.requests, hasLength(requests));
      final l10n = AppLocalizations.of(
        tester.element(find.byType(NovelCommentsSheet)),
      )!;
      expect(find.text(l10n.novelCommentPosted), findsNothing);
      expect(find.text(l10n.novelCommentFailed), findsNothing);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('发送失败可重试且不重复提交', (tester) async {
    final h = _Harness();
    h.user.switchAccount('copy-a');
    final sending = Completer<void>();
    h.api.post = (_, _) => sending.future;
    await h.pump(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.comment_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '待重试内容');
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('novel-comment-submit')),
      warnIfMissed: false,
    );
    await tester.pump();
    // 对话框提交中：按钮禁用，不重复提交。
    await tester.tap(
      find.byKey(const ValueKey('novel-comment-submit')),
      warnIfMissed: false,
    );
    expect(h.api.posts, hasLength(1));
    sending.completeError(const NovelApiException('offline'));
    await tester.pumpAndSettle();
    // 发送失败对话框保留，原草稿可直接重试。
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '待重试内容',
    );
    h.api.post = (_, _) async {};
    await tester.tap(
      find.byKey(const ValueKey('novel-comment-submit')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(h.api.posts, hasLength(2));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  for (final dark in [false, true]) {
    testWidgets('${dark ? '深色' : '浅色'}窄屏大字下长昵称与日期不溢出', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final h = _Harness();
      h.user.switchAccount('copy-a');
      await h.settings.setFontScale(1.5);
      h.api.load = (_, _) async => _page([
        NovelComment(
          id: 'long',
          userName: '很长的读者名字' * 10,
          createAt: '不可解析的日期' * 10,
          comment: '短正文',
        ),
      ]);
      await h.pump(tester, dark: dark, textScale: 2);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('短正文'), findsOneWidget);
      final bodyContext = tester.element(find.text('短正文'));
      expect(MediaQuery.textScalerOf(bodyContext).scale(16), 48);
      final card = tester.getRect(
        find.byKey(const ValueKey('novel-comment-long')),
      );
      expect(card.left, greaterThanOrEqualTo(0));
      expect(card.right, lessThanOrEqualTo(320));
    });
  }

  testWidgets('inline 展开回复：分页加载、时间正序、回复目标与再回复', (tester) async {
    final h = _Harness();
    h.user.switchAccount('copy-a');
    h.api.load = (replyId, offset) async {
      if (replyId == null) return _page([_comment]);
      // 首次展开拉 3 条（limit=3），再点「加载更多」补第 4 条。
      if (offset == 0) {
        return _page([
          const NovelComment(
            id: 'r3',
            comment: '第三条（最新）',
            userName: '丙',
            createAt: '2099-01-03 10:00:00',
          ),
          const NovelComment(
            id: 'r1',
            comment: '第一条（最早）',
            userName: '甲',
            createAt: '2099-01-01 10:00:00',
          ),
          const NovelComment(
            id: 'r2',
            comment: '第二条',
            userName: '乙',
            createAt: '2099-01-02 10:00:00',
            parentUserName: '甲',
          ),
        ], total: 4);
      }
      return _page(
        [
          const NovelComment(
            id: 'r4',
            comment: '第四条',
            userName: '丁',
            createAt: '2099-01-04 10:00:00',
          ),
        ],
        total: 4,
        offset: offset,
      );
    };
    await h.pump(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('展开 2 条回复'));
    await tester.pumpAndSettle();
    // 时间正序。
    expect(
      tester.getRect(find.text('第一条（最早）')).top,
      lessThan(tester.getRect(find.text('第二条')).top),
    );
    // 乙 → 甲 的回复目标（非 OP 回复）。
    expect(find.text('甲').last, findsOneWidget);
    expect(find.byIcon(Icons.arrow_right_alt_rounded), findsOneWidget);
    // 已加载 3/4 → 加载更多入口。
    expect(find.text('加载更多回复 (3/4)'), findsOneWidget);
    await tester.tap(find.text('加载更多回复 (3/4)'));
    await tester.pumpAndSettle();
    expect(find.text('第四条'), findsOneWidget);
    expect(find.text('收起回复'), findsOneWidget);
    await tester.tap(find.text('收起回复'));
    await tester.pumpAndSettle();
    expect(find.text('第四条'), findsNothing);
    expect(find.text('展开 4 条回复'), findsOneWidget);
    expect(h.api.requests, [
      (_bookUuid, null, 0),
      (_bookUuid, _parentId, 0),
      (_bookUuid, _parentId, 3),
    ]);
  });

  testWidgets('点击评论或回复打开发表对话框，回复带 reply_id', (tester) async {
    final h = _Harness();
    h.user.switchAccount('copy-a');
    h.api.load = (replyId, _) async => replyId == null
        ? _page([_comment])
        : _page([
            const NovelComment(id: 'reply-1', comment: '已有回复', userName: '回复者'),
          ]);
    await h.pump(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('展开 2 条回复'));
    await tester.pumpAndSettle();
    // 点击楼中楼回复 → 对话框标题引用回复者。
    await tester.tap(find.text('已有回复'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('回复 回复者'), findsOneWidget);
    expect(find.text('已有回复'), findsNWidgets(2));
    await tester.enterText(find.byType(TextField), '楼中楼回复内容');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('novel-comment-submit')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(
      find.byKey(const ValueKey('novel-comment-submit')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(h.api.posts, [(_bookUuid, '楼中楼回复内容', 'reply-1')]);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    // 点击主评论 → reply_id 为该评论 id。
    await tester.tap(find.text('评论正文'));
    await tester.pumpAndSettle();
    expect(find.text('回复 小说读者'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '主评论回复');
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('novel-comment-submit')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(h.api.posts, hasLength(2));
    expect(h.api.posts.last, (_bookUuid, '主评论回复', _parentId));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  for (final failFirstLoad in [false, true]) {
    testWidgets('零回复首次发送后卡片立即展开${failFirstLoad ? '，加载失败仍可重试' : ''}', (
      tester,
    ) async {
      final h = _Harness();
      h.user.switchAccount('copy-a');
      const root = NovelComment(
        id: _parentId,
        comment: '尚无回复的评论',
        userName: '楼主',
      );
      const reply = NovelComment(id: 'first-reply', comment: '第一条新回复');
      final loading = Completer<NovelPage<NovelComment>>();
      h.api.load = (replyId, _) =>
          replyId == null ? Future.value(_page([root])) : loading.future;
      await h.pump(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('展开'), findsNothing);
      await tester.tap(find.text(root.comment));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), reply.comment);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('novel-comment-submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('收起回复'), findsOneWidget);
      expect(find.byType(CommentReplySkeleton), findsOneWidget);
      if (failFirstLoad) {
        loading.completeError(const NovelApiException('offline'));
        await tester.pumpAndSettle();
        expect(find.text('收起回复'), findsOneWidget);
        h.api.load = (_, _) async => _page([reply]);
        await tester.tap(find.text('重试'));
      } else {
        loading.complete(_page([reply]));
      }
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('novel-comment-$_parentId')),
          matching: find.text(reply.comment),
        ),
        findsOneWidget,
      );
      expect(find.byType(NovelCommentsSheet), findsOneWidget);
      expect(h.api.posts, [(_bookUuid, reply.comment, _parentId)]);
      expect(
        h.api.requests.where((request) => request.$2 == null),
        hasLength(1),
      );
      await tester.tap(find.text('收起回复'));
      await tester.pumpAndSettle();
      expect(find.text('展开 1 条回复'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final fail in [false, true]) {
    testWidgets('切账号后迟到的回复${fail ? '失败' : '成功'}不污染同ID新回复区', (tester) async {
      final h = _Harness();
      h.user.switchAccount('copy-a');
      final old = Completer<NovelPage<NovelComment>>();
      h.api.load = (replyId, _) {
        if (replyId == null) return Future.value(_page([_comment]));
        return h.user.copyToken == 'copy-a'
            ? old.future
            : Future.value(
                _page([const NovelComment(id: 'b', comment: '乙的回复')]),
              );
      };
      await h.pump(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('展开 2 条回复'));
      await tester.pump();
      h.user.switchAccount('copy-b');
      await tester.pumpAndSettle();
      await tester.tap(find.text('展开 2 条回复'));
      await tester.pumpAndSettle();
      expect(find.text('乙的回复'), findsOneWidget);
      if (fail) {
        old.completeError(const NovelApiException('old reply failure'));
      } else {
        old.complete(_page([const NovelComment(id: 'a', comment: '迟到的甲回复')]));
      }
      await tester.pumpAndSettle();
      expect(find.text('乙的回复'), findsOneWidget);
      expect(find.text('迟到的甲回复'), findsNothing);
      expect(find.text('重试'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('减少动画时工具立即显隐，隐藏后不接收点击', (tester) async {
    final h = _Harness();
    h.api.load = (_, _) async => _page([
      for (var i = 0; i < 20; i++)
        NovelComment(id: 'c$i', comment: '第 $i 条评论正文'),
    ]);
    await h.pump(tester, reducedMotion: true);
    await tester.pumpAndSettle();
    final opacity = find.byKey(
      const ValueKey('novel-comment-floating-buttons-opacity'),
    );
    expect(tester.widget<AnimatedOpacity>(opacity).duration, Duration.zero);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(opacity).opacity, 0);
    final pointer = find.ancestor(
      of: opacity,
      matching: find.byType(IgnorePointer),
    );
    expect(tester.widget<IgnorePointer>(pointer.first).ignoring, isTrue);
    final focus = find.ancestor(
      of: opacity,
      matching: find.byType(ExcludeFocus),
    );
    expect(tester.widget<ExcludeFocus>(focus.first).excluding, isTrue);
  });

  testWidgets('小说评论保留左侧评论与右侧上下按钮，不使用共用底板', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = _Harness();
    await h.pump(tester, textScale: 2);
    await tester.pumpAndSettle();

    final post = find.byKey(const ValueKey('novel-comment-post-action'));
    final scrollTop = find.byKey(
      const ValueKey('novel-comment-scroll-top-action'),
    );
    final close = find.byKey(const ValueKey('novel-comment-close-action'));
    final postRect = tester.getRect(post);
    final topRect = tester.getRect(scrollTop);
    final closeRect = tester.getRect(close);
    expect(postRect.right, lessThan(topRect.left));
    expect(topRect.left, closeTo(closeRect.left, 0.01));
    expect(topRect.bottom + 8, closeTo(closeRect.top, 0.01));
    expect(postRect.bottom, closeTo(closeRect.bottom, 0.01));
    expect(topRect.size, const Size.square(52));
    expect(closeRect.size, const Size.square(52));

    final floating = find.byKey(
      const ValueKey('novel-comment-floating-buttons-opacity'),
    );
    expect(tester.getSize(floating).width, lessThan(320 - 32));
    final materials = find.descendant(
      of: floating,
      matching: find.byType(Material),
    );
    for (final action in [post, scrollTop, close]) {
      expect(find.ancestor(of: action, matching: materials), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('小说评论保留辅助按钮颜色，列表末条可滚到按钮组上方', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = _Harness();
    h.api.load = (_, _) async => _page([
      for (var i = 0; i < 20; i++)
        NovelComment(id: 'c$i', comment: '第 $i 条评论正文'),
    ]);
    await h.pump(tester, textScale: 2);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('回到顶部'), findsOneWidget);
    expect(find.byTooltip('关闭'), findsOneWidget);
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -10000),
      10000,
    );
    await tester.pumpAndSettle();
    final last = tester.getRect(
      find.byKey(const ValueKey('novel-comment-c19')),
    );
    final toolbar = tester.getRect(
      find.byKey(const ValueKey('novel-comment-floating-buttons-opacity')),
    );
    expect(last.bottom, lessThanOrEqualTo(toolbar.top));
  });

  testWidgets('悬浮按钮向下滚动隐藏、向上滚动或抵达底部恢复', (tester) async {
    final h = _Harness();
    h.api.load = (_, _) async => _page([
      for (var i = 0; i < 20; i++)
        NovelComment(id: 'c$i', comment: '第 $i 条评论正文', userName: '用户$i'),
    ], total: 20);
    await h.pump(tester);
    await tester.pumpAndSettle();
    // 初始可见。
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    // 向下滚动 → 隐藏。
    await tester.drag(
      find.byKey(const ValueKey('novel-comment-c0')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(
              const ValueKey('novel-comment-floating-buttons-opacity'),
            ),
          )
          .opacity,
      0,
    );
    // 向上滚动 → 恢复。
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    // 回到顶部按钮滚动列表到顶。
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!
          .position
          .pixels,
      0,
    );
    // 关闭按钮退出 sheet（顶层 sheet 由 pump 的 Scaffold 弹出，maybePop 应消费）。
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('标题栏展示书名副标题与计数：分页中 N/M，全部加载后 N 条', (tester) async {
    final h = _Harness();
    var failed = false;
    h.api.load = (_, offset) async {
      if (offset == 0) {
        return _page([
          const NovelComment(id: 'a', comment: '第一条', userName: '甲'),
        ], total: 3);
      }
      if (!failed) {
        failed = true;
        throw const NovelApiException('offline');
      }
      return _page(
        [
          const NovelComment(id: 'b', comment: '第二条', userName: '乙'),
          const NovelComment(id: 'c', comment: '第三条', userName: '丙'),
        ],
        total: 3,
        offset: 1,
      );
    };
    await h.pump(tester, bookName: '魔法图书');
    await tester.pumpAndSettle();
    expect(find.text('魔法图书'), findsOneWidget);
    // 首页加载后自动续拉失败，计数保持「已加载/总数」。
    expect(find.text('1/3'), findsOneWidget);
    final bookRect = tester.getRect(find.text('魔法图书'));
    final countRect = tester.getRect(find.text('1/3'));
    expect(countRect.left, greaterThan(bookRect.right));
    expect(countRect.center.dy, closeTo(bookRect.center.dy, 1));
    final rowRect = tester.getRect(
      find.byKey(const ValueKey('novel-comments-subtitle')),
    );
    expect(countRect.right, closeTo(rowRect.right, 0.01));
    final l10n = AppLocalizations.of(
      tester.element(find.byType(NovelCommentsSheet)),
    )!;
    await tester.tap(find.text(l10n.novelLoadMoreFailed));
    await tester.pumpAndSettle();
    expect(find.text('3 条'), findsOneWidget);
  });

  testWidgets('屏蔽用户：评论即时隐藏并计显示屏蔽数，解除后恢复', (tester) async {
    final h = _Harness();
    h.user.blockedUsers = const ['|小说读者'];
    h.api.load = (_, _) async => _page([
      _comment,
      const NovelComment(id: 'other', comment: '正常评论', userName: '好用户'),
    ], total: 2);
    await h.pump(tester);
    await tester.pumpAndSettle();
    expect(find.text('正常评论'), findsOneWidget);
    expect(find.text('评论正文'), findsNothing);
    expect(find.text('1/2|1'), findsOneWidget);
    // 黑名单变更通知即时重过滤，无需重进评论区。
    h.user.setBlockedUsers(const []);
    await tester.pumpAndSettle();
    expect(find.text('评论正文'), findsOneWidget);
    expect(find.text('2 条'), findsOneWidget);
  });

  testWidgets('屏蔽词与群广告开关过滤列表，计数显示屏蔽数', (tester) async {
    final h = _Harness();
    h.user.blockwords = const ['广告'];
    h.user.blockGroupSpam = true;
    h.api.load = (_, _) async => _page([
      _comment,
      const NovelComment(id: 'ad', comment: '促销广告内容', userName: '甲'),
      const NovelComment(id: 'spam', comment: '加群12345678领福利', userName: '乙'),
      const NovelComment(id: 'ok', comment: '正常讨论', userName: '丙'),
    ], total: 4);
    await h.pump(tester);
    await tester.pumpAndSettle();
    expect(find.text('评论正文'), findsOneWidget);
    expect(find.text('正常讨论'), findsOneWidget);
    expect(find.text('促销广告内容'), findsNothing);
    expect(find.text('加群12345678领福利'), findsNothing);
    expect(find.text('2/4|2'), findsOneWidget);
  });

  testWidgets('楼中楼回复按屏蔽配置过滤', (tester) async {
    final h = _Harness();
    h.user.blockwords = const ['广告'];
    h.api.load = (replyId, _) async => replyId == null
        ? _page([_comment])
        : _page([
            const NovelComment(id: 'r1', comment: '干净的回复', userName: '甲'),
            const NovelComment(id: 'r2', comment: '垃圾广告回复', userName: '乙'),
          ], total: 2);
    await h.pump(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('展开 2 条回复'));
    await tester.pumpAndSettle();
    expect(find.text('干净的回复'), findsOneWidget);
    expect(find.text('垃圾广告回复'), findsNothing);
    // 服务端回复总数不变，可见数减少后仍提示补全。
    expect(find.text('加载更多回复 (1/2)'), findsOneWidget);
  });

  testWidgets('长按评论弹出操作菜单：复制、+1 发同内容顶层评论', (tester) async {
    final h = _Harness();
    h.user.switchAccount('copy-a');
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    await h.pump(tester);
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(NovelCommentsSheet)),
    )!;
    // 长按用户名打开菜单；正文是 SelectableText，长按仍走文本选择。
    await tester.longPress(find.text('小说读者'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.chapterCommentsActionTitle), findsOneWidget);
    await tester.tap(find.text(l10n.copyButton));
    await tester.pumpAndSettle();
    expect(copied, '评论正文');
    await tester.longPress(find.text('小说读者'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+1'));
    await tester.pumpAndSettle();
    expect(h.api.posts, [(_bookUuid, '评论正文', null)]);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('游客长按 +1 先跳 COPY 登录，不发送', (tester) async {
    final h = _Harness();
    await h.pump(tester);
    await tester.pumpAndSettle();
    await tester.longPress(find.text('小说读者'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+1'));
    await tester.pumpAndSettle();
    expect(h.loginCopyOnly, 'true');
    expect(h.api.posts, isEmpty);
  });

  testWidgets('长按屏蔽用户走确认弹窗，确认后评论立即隐藏', (tester) async {
    final h = _Harness();
    await h.pump(tester);
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(NovelCommentsSheet)),
    )!;
    await tester.longPress(find.text('小说读者'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.chapterCommentsBlockUser));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.text(l10n.comicCommentBlockNamedConfirm('小说读者')),
      findsOneWidget,
    );
    await tester.tap(find.text(l10n.chapterCommentsNoRemindAgain));
    await tester.tap(find.text(l10n.chapterCommentsBlock));
    await tester.pumpAndSettle();
    expect(find.text('评论正文'), findsNothing);
    expect(find.text('0/1|1'), findsOneWidget);
    expect(h.user.blockedCalls, [('', '小说读者')]);
    expect(h.user.blockNoRemind, isTrue);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
