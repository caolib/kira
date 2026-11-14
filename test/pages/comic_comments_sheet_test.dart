import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/api/api_client.dart';
import 'package:kira/api/manga/manga_api.dart';
import 'package:kira/api/user/user_api.dart';
import 'package:kira/models/comic_comment.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/comic_comments_sheet.dart';
import 'package:kira/widgets/app_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

ComicComment _comment(
  int id, {
  String content = '第一条评论',
  String? userId,
  String? userName,
  int replyCount = 0,
  int? parentId,
}) => ComicComment(
  id: id,
  createAt: '2026-05-03 12:00:00',
  userId: userId ?? 'reader-$id',
  userName: userName ?? '读者$id',
  userAvatar: '',
  comment: content,
  replyCount: replyCount,
  parentId: parentId,
);

typedef _CommentPage = ({List<ComicComment> list, int total});

class _ComicCommentsApi extends Fake implements MangaApi {
  List<ComicComment> comments = [_comment(1)];
  int? total;
  final replies = <int, List<ComicComment>>{};
  final getRequests = <({String replyId, int offset})>[];
  final posts = <({String content, int? replyId})>[];
  Completer<_CommentPage>? pendingReplies;

  @override
  Future<_CommentPage> getComicComments(
    String comicId, {
    String replyId = '',
    int limit = 10,
    int offset = 0,
  }) async {
    getRequests.add((replyId: replyId, offset: offset));
    if (replyId.isNotEmpty) {
      if (pendingReplies != null) return pendingReplies!.future;
      final items = replies[int.parse(replyId)] ?? [];
      return (list: items, total: items.length);
    }
    return (
      list: comments.skip(offset).take(limit).toList(),
      total: total ?? comments.length,
    );
  }

  @override
  Future<void> postComicComment(
    String comicId,
    String content, {
    int? replyId,
  }) async {
    posts.add((content: content, replyId: replyId));
    if (replyId == null) return;
    var rootId = replyId;
    for (final entry in replies.entries) {
      if (entry.value.any((reply) => reply.id == replyId)) {
        rootId = entry.key;
        break;
      }
    }
    replies
        .putIfAbsent(rootId, () => [])
        .add(
          _comment(
            100 + posts.length,
            content: content,
            userName: '当前用户',
            parentId: replyId,
          ),
        );
  }
}

class _UserApi extends Fake implements UserApi {
  @override
  void clearAuthState() {}
}

class _Client extends Fake implements ApiClient {
  _Client(this.manga);

  @override
  final MangaApi manga;

  @override
  final UserApi user = _UserApi();
}

void main() {
  late ApiClient originalApi;
  late _ComicCommentsApi api;

  setUp(() async {
    setupSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({});
    await UserManager().init();
    originalApi = ApiClient();
    api = _ComicCommentsApi();
    ApiClient.setTestInstance(_Client(api));
  });

  tearDown(() {
    ApiClient.setTestInstance(originalApi);
    teardownSecureCredentialStoreForTest();
  });

  Finder buttonFor(IconData icon) => find.ancestor(
    of: find.byIcon(icon),
    matching: find.byWidgetPredicate((widget) => widget is FilledButton),
  );

  Finder card(int id) => find.byKey(ValueKey('comic-comment-$id'));
  Finder member(int id) => find.byKey(ValueKey('comic-merged-member-$id'));

  Future<void> login() => UserManager().saveLogin(
    token: 'widget-test-token',
    userId: 'widget-test-user',
    username: 'widget-test-user',
    nickname: '当前用户',
    avatar: '',
    loginSource: 'hotmanga',
  );

  Future<void> pumpSheet(
    WidgetTester tester, {
    double textScale = 1,
    Size size = const Size(400, 800),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      wrapWithApp(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(textScale),
            ),
            child: const ComicCommentsSheet(
              comicId: 'comic-test',
              comicName: '测试漫画',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> submitReply(WidgetTester tester, String content) async {
    await tester.enterText(find.byType(TextField), content);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '回复'));
    await tester.pump();
  }

  testWidgets('有回复的同文主评论独立显示，同用户同文去重不吞掉回复', (tester) async {
    api.comments = [
      _comment(1, content: '相同评论', userId: 'same-user'),
      _comment(2, content: '相同评论'),
      _comment(3, content: '相同评论', userId: 'same-user', replyCount: 1),
    ];
    api.replies[3] = [_comment(31, content: '已有回复', parentId: 3)];
    await pumpSheet(tester);

    expect(card(1), findsOneWidget);
    expect(card(3), findsOneWidget);
    expect(find.text('相同评论'), findsNWidgets(2));
    expect(find.text('展开 1 条回复'), findsOneWidget);
    await tester.tap(find.text('展开 1 条回复'));
    await tester.pumpAndSettle();
    expect(find.text('已有回复'), findsOneWidget);
    expect(api.getRequests.last.replyId, '3');
    expect(tester.takeException(), isNull);
  });

  testWidgets('合并成员点按关闭列表并回复原评论，成功后立即独立且展开回复', (tester) async {
    await login();
    api.comments = [
      _comment(1, content: '相同评论', userName: '读者甲'),
      _comment(2, content: '相同评论', userName: '读者乙'),
      _comment(3, content: '相同评论', userName: '读者丙'),
    ];
    await pumpSheet(tester);
    expect(find.text('相同评论'), findsOneWidget);
    await tester.tap(card(1));
    await tester.pumpAndSettle();
    expect(find.byType(AppSheet), findsOneWidget);
    for (final id in [1, 2, 3]) {
      final ink = tester.widget<InkWell>(member(id));
      expect(ink.onTap, isNotNull);
      expect(ink.onLongPress, isNotNull);
      expect(tester.getSize(member(id)).height, greaterThanOrEqualTo(48));
    }
    await tester.tap(member(2));
    await tester.pumpAndSettle();
    expect(member(2), findsNothing);
    expect(find.byType(AppSheet), findsNothing);
    expect(find.text('回复 读者乙'), findsOneWidget);

    final pending = Completer<_CommentPage>();
    api.pendingReplies = pending;
    await submitReply(tester, '选中成员的回复');
    await tester.pump(const Duration(milliseconds: 400));
    expect(api.posts.single, (content: '选中成员的回复', replyId: 2));
    expect(card(2), findsOneWidget);
    expect(card(1), findsOneWidget);
    expect(find.text('相同评论'), findsNWidgets(2));
    expect(find.text('收起回复'), findsOneWidget);
    expect(api.getRequests.last.replyId, '2');
    pending.complete((list: api.replies[2]!, total: 1));
    api.pendingReplies = null;
    await tester.pumpAndSettle();
    expect(find.text('选中成员的回复'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(AppSheet), findsNothing);

    await tester.tap(find.text('收起回复'));
    await tester.pumpAndSettle();
    expect(find.text('展开 1 条回复'), findsOneWidget);
    await tester.tap(find.text('展开 1 条回复'));
    await tester.pumpAndSettle();
    expect(find.text('选中成员的回复'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('成员长按保留复制、+1和屏蔽，且不会打开回复框', (tester) async {
    api.comments = [
      _comment(1, content: '相同评论', userName: '读者甲'),
      _comment(2, content: '相同评论', userName: '读者乙'),
    ];
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpSheet(tester);
    await tester.tap(card(1));
    await tester.pumpAndSettle();
    await tester.longPress(member(2));
    await tester.pumpAndSettle();
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('+1'), findsOneWidget);
    expect(find.text('屏蔽用户'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(api.posts, isEmpty);
    await tester.tap(find.text('复制'));
    await tester.pumpAndSettle();
    expect(copied, '相同评论');
    expect(member(2), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('楼中楼发送目标是回复ID，但计数与重新加载属于根评论', (tester) async {
    await login();
    api.comments = [_comment(1, content: '根评论', userName: '楼主', replyCount: 1)];
    api.replies[1] = [
      _comment(11, content: '已有回复', userName: '层主', parentId: 1),
    ];
    await pumpSheet(tester);
    await tester.tap(find.text('展开 1 条回复'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('已有回复'));
    await tester.pumpAndSettle();
    expect(find.text('回复 层主'), findsOneWidget);
    await submitReply(tester, '楼中楼的新回复');
    await tester.pumpAndSettle();
    expect(api.posts.single.replyId, 11);
    expect(
      api.getRequests.where((request) => request.replyId == '11'),
      isEmpty,
    );
    expect(api.getRequests.last.replyId, '1');
    expect(find.text('楼中楼的新回复'), findsOneWidget);
    await tester.tap(find.text('收起回复'));
    await tester.pumpAndSettle();
    expect(find.text('展开 2 条回复'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('主评论刷新返回旧计数时，已知回复不重新并入同文评论', (tester) async {
    await login();
    api.comments = [
      _comment(1, content: '相同评论'),
      _comment(2, content: '相同评论'),
      _comment(3, content: '相同评论'),
    ];
    await pumpSheet(tester);
    await tester.tap(card(1));
    await tester.pumpAndSettle();
    await tester.tap(member(2));
    await tester.pumpAndSettle();
    await submitReply(tester, '已知存在的回复');
    await tester.pumpAndSettle();
    expect(card(2), findsOneWidget);

    api.comments = [...api.comments, _comment(4, content: '分页新评论')];
    api.total = 4;
    await tester.longPress(card(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+1'));
    await tester.pumpAndSettle();
    expect(api.posts.last.replyId, isNull);
    expect(api.getRequests.last.replyId, '');
    expect(card(2), findsOneWidget);
    expect(find.text('已知存在的回复'), findsOneWidget);
    expect(find.text('分页新评论'), findsOneWidget);
    expect(find.text('相同评论'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('回复后主列表和回复列表都短暂返回旧计数，仍保留独立线程', (tester) async {
    await login();
    api.comments = [
      _comment(1, content: '相同评论'),
      _comment(2, content: '相同评论'),
      _comment(3, content: '相同评论'),
    ];
    await pumpSheet(tester);
    await tester.tap(card(1));
    await tester.pumpAndSettle();
    await tester.tap(member(2));
    await tester.pumpAndSettle();
    await submitReply(tester, '已确认提交的新回复');
    await tester.pumpAndSettle();
    api.replies[2] = [];
    await tester.tap(find.text('收起回复'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('展开 1 条回复'));
    await tester.pumpAndSettle();
    await tester.longPress(card(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+1'));
    await tester.pumpAndSettle();
    expect(card(2), findsOneWidget);
    expect(find.text('相同评论'), findsNWidgets(2));
    expect(find.text('收起回复'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏大字体的长名称成员卡片保留触区且不溢出', (tester) async {
    api.comments = [
      _comment(1, content: '相同评论', userName: '很长很长很长很长很长的成员名称'),
      _comment(2, content: '相同评论', userName: '另一位读者'),
    ];
    await pumpSheet(tester, textScale: 2, size: const Size(320, 800));
    await tester.tap(card(1));
    await tester.pumpAndSettle();
    expect(tester.getSize(member(1)).height, greaterThanOrEqualTo(48));
    expect(
      tester.getSize(member(1)).width,
      lessThanOrEqualTo((320 - 32) * 0.8),
    );
    expect(tester.takeException(), isNull);
  });

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('作品评论在 $brightness 下评论用主色、辅助按钮用次色并保留布局', (tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          Theme(
            data: ThemeData(brightness: brightness),
            child: const ComicCommentsSheet(
              comicId: 'comic-test',
              comicName: '测试漫画',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final post = buttonFor(Icons.comment_outlined);
      final top = buttonFor(Icons.arrow_upward_rounded);
      final close = buttonFor(Icons.keyboard_arrow_down_rounded);
      final cs = Theme.of(tester.element(post)).colorScheme;
      final postStyle = tester.widget<FilledButton>(post).style!;
      expect(postStyle.backgroundColor!.resolve({}), cs.primary);
      expect(postStyle.foregroundColor!.resolve({}), cs.onPrimary);
      for (final button in [top, close]) {
        final style = tester.widget<FilledButton>(button).style!;
        expect(style.backgroundColor!.resolve({}), cs.secondaryContainer);
        expect(style.foregroundColor!.resolve({}), cs.onSecondaryContainer);
        expect(style.elevation!.resolve({}), 6);
        expect(tester.getSize(button), const Size.square(52));
      }
      expect(postStyle.elevation!.resolve({}), 6);
      expect(tester.getSize(post).height, 52);
      final postRect = tester.getRect(post);
      final topRect = tester.getRect(top);
      final closeRect = tester.getRect(close);
      expect(postRect.right + 8, closeTo(topRect.left, 0.01));
      expect(topRect.left, closeTo(closeRect.left, 0.01));
      expect(topRect.bottom + 8, closeTo(closeRect.top, 0.01));
      expect(postRect.bottom, closeTo(closeRect.bottom, 0.01));

      final nameRect = tester.getRect(find.text('测试漫画'));
      final countRect = tester.getRect(
        find.byKey(const ValueKey('comic-comments-count')),
      );
      expect(countRect.left, greaterThan(nameRect.right));
      expect(countRect.center.dy, closeTo(nameRect.center.dy, 1));
      final rowRect = tester.getRect(
        find.byKey(const ValueKey('comic-comments-subtitle')),
      );
      expect(countRect.right, closeTo(rowRect.right, 0.01));

      final materials = find.descendant(
        of: find.byType(ComicCommentsSheet),
        matching: find.byType(Material),
      );
      expect(find.ancestor(of: post, matching: materials), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
