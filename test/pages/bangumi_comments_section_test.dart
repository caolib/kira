import 'package:flutter_test/flutter_test.dart';
import 'package:kira/api/dandanplay_api.dart';
import 'package:kira/pages/bangumi_comments_section.dart';

import '../test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DandanplayBangumiComment comment({
    required int id,
    required String userName,
    required String text,
    required int rating,
    required String updatedTime,
  }) {
    return DandanplayBangumiComment(
      id: id,
      userId: 0,
      externalUserId: '/user/$id',
      userName: userName,
      imageUrl: '',
      source: 'Bangumi',
      text: text,
      rating: rating,
      updatedTime: updatedTime,
    );
  }

  testWidgets('shows comments and loads more pages', (tester) async {
    var calls = 0;
    Future<DandanplayBangumiCommentsPage> loader(
      String bangumiId, {
      int page = 0,
      bool forceRefresh = false,
    }) async {
      calls++;
      if (page == 0) {
        return DandanplayBangumiCommentsPage(
          count: 2,
          hasMore: true,
          comments: [
            comment(
              id: 1,
              userName: 'Alice',
              text: '第一页评论',
              rating: 7,
              updatedTime: DateTime.now()
                  .subtract(const Duration(hours: 2))
                  .toIso8601String(),
            ),
          ],
        );
      }
      return DandanplayBangumiCommentsPage(
        count: 1,
        hasMore: false,
        comments: [
          comment(
            id: 2,
            userName: 'Bob',
            text: '第二页评论',
            rating: 8,
            updatedTime: DateTime.now()
                .subtract(const Duration(minutes: 30))
                .toIso8601String(),
          ),
        ],
      );
    }

    await tester.pumpWidget(
      wrapWithApp(
        BangumiCommentsSection(
          bangumiId: '18319',
          animeTitle: '测试番剧',
          loader: loader,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('第一页评论'), findsOneWidget);
    expect(find.text('2小时前'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('加载更多'), findsOneWidget);

    await tester.tap(find.text('加载更多'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('第二页评论'), findsOneWidget);
    expect(find.text('30分钟前'), findsOneWidget);
    expect(find.text('加载更多'), findsNothing);
    expect(calls, 2);
  });

  testWidgets('shows error retry state', (tester) async {
    var calls = 0;
    Future<DandanplayBangumiCommentsPage> loader(
      String bangumiId, {
      int page = 0,
      bool forceRefresh = false,
    }) async {
      calls++;
      throw Exception('boom');
    }

    await tester.pumpWidget(
      wrapWithApp(
        BangumiCommentsSection(
          bangumiId: '18319',
          animeTitle: '测试番剧',
          loader: loader,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('评论加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(calls, 2);
  });
}
