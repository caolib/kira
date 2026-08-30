import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/models/chapter_comment.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/chapter_comments_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ChapterComment comment({
    required int id,
    required String userId,
    required String userName,
    required String content,
  }) {
    return ChapterComment(
      id: id,
      createAt: '2026-05-03 12:00:00',
      userId: userId,
      userName: userName,
      userAvatar: '',
      comment: content,
    );
  }

  List<ChapterComment> mergedComments(String content, int count, int startId) {
    return List.generate(
      count,
      (index) => comment(
        id: startId + index,
        userId: '$content-$index',
        userName: '用户$index',
        content: content,
      ),
      growable: false,
    );
  }

  Future<void> pumpCommentsSheet(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'comment_compact_layout': true,
      'comment_show_avatar': false,
      'comment_show_user_name': false,
      'comment_show_time': false,
    });
    await UserManager().init();

    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(593, 279);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final comments = <ChapterComment>[
      ...mergedComments('会赢的', 101, 1000),
      ...mergedComments('圣地巡礼', 5, 2000),
      ...mergedComments('想你了，牢师', 3, 3000),
      ...mergedComments('惠赢的', 3, 4000),
      ...mergedComments('会赢是你的谎言', 2, 5000),
      ...mergedComments('赢会的', 2, 6000),
      ...mergedComments('周年纪念', 2, 7000),
      ...mergedComments('會贏的', 2, 8000),
    ];

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChapterCommentsSheet(
            chapterUuid: 'chapter-1',
            chapterName: '第 1 话',
            initialComments: comments,
            initialTotal: comments.length,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('comment body style uses theme body size as base', () {
    const textTheme = TextTheme(
      bodyLarge: TextStyle(fontSize: 16),
      bodyMedium: TextStyle(fontSize: 14),
    );

    // 正文字号不再手动乘缩放，由 CommentFontScaler 统一套用。
    expect(buildCommentBodyStyle(textTheme, compact: false)?.fontSize, 16);
    expect(buildCommentBodyStyle(textTheme, compact: true)?.fontSize, 16);
  });

  testWidgets('CommentFontScaler scales every text in subtree', (tester) async {
    double? baseScaled;
    double? scaled;
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            Builder(
              builder: (context) {
                baseScaled = MediaQuery.textScalerOf(context).scale(16);
                return const SizedBox.shrink();
              },
            ),
            CommentFontScaler(
              scale: 1.5,
              child: Builder(
                builder: (context) {
                  scaled = MediaQuery.textScalerOf(context).scale(16);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
      ),
    );

    expect(baseScaled, 16);
    expect(scaled, 24);
  });

  testWidgets('CommentFontScaler keeps ambient scaler at scale 1', (
    tester,
  ) async {
    double? scaled;
    await tester.pumpWidget(
      MaterialApp(
        home: CommentFontScaler(
          scale: 1,
          child: Builder(
            builder: (context) {
              scaled = MediaQuery.textScalerOf(context).scale(16);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(scaled, 16);
  });

  testWidgets('merged compact comments keep one line when avatars are hidden', (
    tester,
  ) async {
    await pumpCommentsSheet(tester);

    expect(find.text('会赢的'), findsOneWidget);
    expect(find.text('圣地巡礼'), findsOneWidget);

    expect(tester.getSize(find.text('会赢的')).height, lessThan(30));
    expect(tester.getSize(find.text('圣地巡礼')).height, lessThan(30));
  });

  testWidgets('floating buttons reappear at the bottom', (tester) async {
    await pumpCommentsSheet(tester);

    final list = find.byType(ListView).last;
    final opacity = find.ancestor(
      of: find.byIcon(Icons.comment_outlined),
      matching: find.byType(AnimatedOpacity),
    );

    await tester.drag(list, const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(opacity).opacity, 0);

    await tester.fling(list, const Offset(0, -10000), 10000);
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(opacity).opacity, 1);
  });
}
