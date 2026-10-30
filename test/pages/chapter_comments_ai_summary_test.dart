import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/api/ai_api.dart';
import 'package:kira/api/api_client.dart';
import 'package:kira/api/manga/manga_api.dart';
import 'package:kira/models/chapter_comment.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/chapter_comments/comment_scroll_behavior.dart';
import 'package:kira/pages/chapter_comments_sheet.dart';
import 'package:kira/utils/chapter_comment_paging.dart';
import 'package:kira/utils/chapter_summary_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

ChapterComment _comment(int id) => ChapterComment(
  id: id,
  createAt: '2026-05-03 12:00:00',
  userId: 'user-$id',
  userName: '用户$id',
  userAvatar: '',
  comment: '评论$id：这一话的剧情很有意思，人物之间的互动也很自然，期待接下来的发展。',
);

class _CommentsApi extends Fake implements MangaApi {
  final comments = List.generate(60, (index) => _comment(index + 1));
  final offsets = <int>[];

  @override
  Future<({List<ChapterComment> list, int total})> getChapterComments(
    String chapterUuid, {
    int limit = 10,
    int offset = 0,
  }) async {
    offsets.add(offset);
    return (
      list: comments.skip(offset).take(limit).toList(),
      total: comments.length,
    );
  }
}

class _Client extends Fake implements ApiClient {
  _Client(this.manga);

  @override
  final MangaApi manga;
}

// Count AI attempts without opening sockets or sending comments to a provider.
class _AiNetwork extends HttpOverrides {
  final requests = <Uri>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) => _AiClient(requests);
}

class _AiClient extends Fake implements HttpClient {
  _AiClient(this.requests);

  final List<Uri> requests;

  @override
  Duration idleTimeout = Duration.zero;

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    requests.add(url);
    throw const SocketException('test AI unavailable');
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const autoChapterUuid = 'chapter-auto-summary';
  late ApiClient originalApi;
  late HttpOverrides? originalHttpOverrides;
  late _CommentsApi commentsApi;
  late _AiNetwork aiNetwork;

  setUp(() async {
    setupSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({
      'comment_compact_layout': false,
      'comment_show_avatar': false,
      'comment_show_user_name': false,
      'comment_show_time': false,
      'zhipu_api_key': 'test-api-key',
      'zhipu_base_url': 'https://summary.invalid/v1',
      'zhipu_summary_enabled': true,
      'zhipu_summary_collapsed': true,
      'zhipu_auto_summary': true,
      'zhipu_auto_summary_min': 25,
    });
    originalApi = ApiClient();
    commentsApi = _CommentsApi();
    ApiClient.setTestInstance(_Client(commentsApi));
    originalHttpOverrides = HttpOverrides.current;
    aiNetwork = _AiNetwork();
    HttpOverrides.global = aiNetwork;
    await UserManager().init();
    await AiSettings().reloadFromPrefs();
  });

  tearDown(() {
    ChapterSummaryCache.clearProgress(autoChapterUuid);
    ApiClient.setTestInstance(originalApi);
    HttpOverrides.global = originalHttpOverrides;
    teardownSecureCredentialStoreForTest();
  });

  Future<void> pumpAutoSummarySheet(
    WidgetTester tester, {
    int initialCount = 20,
  }) async {
    await tester.pumpWidget(
      wrapWithApp(
        ChapterCommentsSheet(
          chapterUuid: autoChapterUuid,
          chapterName: '第 1 话',
          initialComments: commentsApi.comments.take(initialCount).toList(),
          initialTotal: commentsApi.comments.length,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> loadNextPage(WidgetTester tester) async {
    final state = tester.state(find.byType(ChapterCommentsSheet));
    if (state is! CommentScrollBehavior<ChapterCommentsSheet>) {
      fail('ChapterCommentsSheet must expose its comment scroll behavior');
    }
    state.loadMoreComments();
    await tester.pumpAndSettle();
  }

  for (final timing in AiAutoSummaryTiming.values) {
    testWidgets('$timing: 翻页从20条达到30条时自动总结，失败后继续翻页不重复请求', (tester) async {
      await AiSettings().setAutoSummaryTiming(timing);
      await pumpAutoSummarySheet(tester);
      expect(find.text('20/60'), findsOneWidget);
      expect(aiNetwork.requests, isEmpty);

      await loadNextPage(tester);
      expect(find.text('30/60'), findsOneWidget);
      expect(commentsApi.offsets, [20]);
      expect(aiNetwork.requests, hasLength(1));
      expect(aiNetwork.requests.single.host, 'summary.invalid');
      expect(
        ChapterSummaryCache.progressOf(autoChapterUuid).error,
        contains('test AI unavailable'),
      );

      await loadNextPage(tester);
      expect(find.text('40/60'), findsOneWidget);
      expect(commentsApi.offsets, [20, 30]);
      expect(aiNetwork.requests, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('首屏补页达到阈值时自动总结', (tester) async {
    await AiSettings().setAutoSummaryMin(15);
    await pumpAutoSummarySheet(tester, initialCount: 10);
    expect(aiNetwork.requests, isEmpty);

    await tester.pump(chapterCommentPageGap);
    await tester.pumpAndSettle();
    expect(find.text('20/60'), findsOneWidget);
    expect(commentsApi.offsets, [10]);
    expect(aiNetwork.requests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('自动加载全部途中达到阈值时总结一次', (tester) async {
    await UserManager().setCommentAutoLoadAll(true);
    await pumpAutoSummarySheet(tester);
    expect(find.text('30/60'), findsOneWidget);
    expect(aiNetwork.requests, hasLength(1));

    for (var page = 0; page < 3; page++) {
      await tester.pump(chapterCommentPageGap);
      await tester.pumpAndSettle();
    }
    expect(find.text('60 条'), findsOneWidget);
    expect(commentsApi.offsets, [20, 30, 40, 50]);
    expect(aiNetwork.requests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('已有持久化总结时，打开和翻页均不重复请求', (tester) async {
    await AiSettings().setAutoSummaryMin(20);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('zhipu_chapter_summary_$autoChapterUuid', '已缓存的总结');
    await pumpAutoSummarySheet(tester);
    await loadNextPage(tester);

    expect(find.text('30/60'), findsOneWidget);
    expect(aiNetwork.requests, isEmpty);
    expect(await ChapterSummaryCache.get(autoChapterUuid), '已缓存的总结');
    expect(tester.takeException(), isNull);
  });

  testWidgets('共享总结正在生成或已停止时，翻页不重复请求', (tester) async {
    await AiSettings().setAutoSummaryMin(20);
    ChapterSummaryCache.startProgress(autoChapterUuid);
    await pumpAutoSummarySheet(tester);
    await loadNextPage(tester);
    expect(aiNetwork.requests, isEmpty);

    ChapterSummaryCache.clearProgress(autoChapterUuid);
    await tester.pumpAndSettle();
    await loadNextPage(tester);
    expect(find.text('40/60'), findsOneWidget);
    expect(aiNetwork.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('已有总结被清空后不随翻页重试，仍允许手动总结', (tester) async {
    await AiSettings().setAutoSummaryMin(20);
    await ChapterSummaryCache.set(autoChapterUuid, '已有总结');
    await pumpAutoSummarySheet(tester);

    await ChapterSummaryCache.remove(autoChapterUuid);
    await tester.pumpAndSettle();
    await loadNextPage(tester);
    expect(aiNetwork.requests, isEmpty);

    await tester.tap(find.byIcon(Icons.smart_toy_outlined));
    await tester.pumpAndSettle();
    expect(aiNetwork.requests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('上次打开总结失败后，重新打开允许再次自动尝试', (tester) async {
    await AiSettings().setAutoSummaryMin(20);
    await pumpAutoSummarySheet(tester);
    expect(aiNetwork.requests, hasLength(1));
    expect(ChapterSummaryCache.progressOf(autoChapterUuid).error, isNotNull);

    await tester.pumpWidget(wrapWithApp(const SizedBox.shrink()));
    await tester.pumpAndSettle();
    await pumpAutoSummarySheet(tester);
    expect(aiNetwork.requests, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('未开启自动总结时，翻页达标不发起请求', (tester) async {
    await AiSettings().setAutoSummary(false);
    await pumpAutoSummarySheet(tester);
    await loadNextPage(tester);

    expect(find.text('30/60'), findsOneWidget);
    expect(aiNetwork.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'AI summary stays collapsed while generating until user expands',
    (tester) async {
      const chapterUuid = 'chapter-ai-generating';
      SharedPreferences.setMockInitialValues({
        'zhipu_api_key': 'test-api-key',
        'zhipu_summary_enabled': true,
        'zhipu_summary_collapsed': true,
      });
      addTearDown(() => ChapterSummaryCache.clearProgress(chapterUuid));
      ChapterSummaryCache.startProgress(chapterUuid);
      await UserManager().init();
      await AiSettings().reloadFromPrefs();

      await tester.pumpWidget(
        wrapWithApp(
          ChapterCommentsSheet(
            chapterUuid: chapterUuid,
            chapterName: '第 1 话',
            initialComments: [_comment(1)],
            initialTotal: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate(
          (w) => w is Text && w.data?.contains('总结') == true,
        ),
        findsOneWidget,
      );
      expect(find.text('正在生成中…'), findsNothing);

      await tester.tap(find.byTooltip('展开'));
      await tester.pumpAndSettle();

      expect(find.text('正在生成中…'), findsOneWidget);
    },
  );
}
