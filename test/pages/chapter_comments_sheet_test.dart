import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/chapter_comment.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/chapter_comments/comment_toolbar.dart';
import 'package:kira/pages/chapter_comments_sheet.dart';
import 'package:kira/widgets/load_more_footer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(setupSecureCredentialStoreForTest);
  tearDown(teardownSecureCredentialStoreForTest);

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

  Future<void> pumpCommentsSheet(
    WidgetTester tester, {
    List<ChapterComment>? comments,
    int? initialTotal,
    int initialPages = 2,
    Size viewSize = const Size(593, 279),
    bool reducedMotion = false,
    double textScale = 1,
    bool hasNextChapter = false,
  }) async {
    SharedPreferences.setMockInitialValues({
      'comment_compact_layout': true,
      'comment_show_avatar': false,
      'comment_show_user_name': false,
      'comment_show_time': false,
      'comment_initial_pages': initialPages,
    });
    await UserManager().init();

    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = viewSize;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final resolvedComments =
        comments ??
        <ChapterComment>[
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
      wrapWithApp(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: reducedMotion,
              textScaler: TextScaler.linear(textScale),
            ),
            child: ChapterCommentsSheet(
              chapterUuid: 'chapter-1',
              chapterName: '第 1 话',
              initialComments: resolvedComments,
              initialTotal: initialTotal ?? resolvedComments.length,
              hasNextChapter: hasNextChapter,
              onNextChapter: () {},
            ),
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

  testWidgets('shows a load more footer for the remaining pages', (
    tester,
  ) async {
    await pumpCommentsSheet(
      tester,
      comments: mergedComments('会赢的', 10, 1000),
      initialTotal: 78,
      initialPages: 1,
      viewSize: const Size(593, 1200),
    );

    expect(find.byType(LoadMoreFooter), findsOneWidget);
    expect(find.text('加载更多（10/78）'), findsOneWidget);
  });

  testWidgets('hides the load more footer once everything is loaded', (
    tester,
  ) async {
    await pumpCommentsSheet(tester);

    expect(find.byType(LoadMoreFooter), findsNothing);
  });

  testWidgets('评论计数显示在章节名之后', (tester) async {
    await pumpCommentsSheet(tester, viewSize: const Size(360, 800));

    final nameRect = tester.getRect(find.text('第 1 话'));
    final countRect = tester.getRect(
      find.byKey(const ValueKey('chapter-comments-count')),
    );
    expect(countRect.left, greaterThan(nameRect.right));
    expect(countRect.center.dy, closeTo(nameRect.center.dy, 1));
    final rowRect = tester.getRect(
      find.byKey(const ValueKey('chapter-comments-subtitle')),
    );
    expect(countRect.right, closeTo(rowRect.right, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('顶部不再提供布局切换，设置面板仍可切换并保存布局', (tester) async {
    await pumpCommentsSheet(tester, viewSize: const Size(360, 800));
    expect(find.byTooltip('切换为列表布局'), findsNothing);
    expect(find.byTooltip('切换为紧凑布局'), findsNothing);
    expect(find.byIcon(Icons.dashboard_outlined), findsNothing);
    expect(find.byIcon(Icons.view_agenda_outlined), findsNothing);

    await tester.tap(find.byTooltip('评论区设置'));
    await tester.pumpAndSettle();
    expect(find.byType(CommentSettingsPanel), findsOneWidget);
    final layouts = find.byType(SegmentedButton<bool>);
    expect(tester.widget<SegmentedButton<bool>>(layouts).selected, {true});
    final listLayout = find.text('列表布局');
    await tester.ensureVisible(listLayout);
    await tester.tap(listLayout);
    await tester.pumpAndSettle();
    expect(tester.widget<SegmentedButton<bool>>(layouts).selected, {false});
    expect(UserManager().commentCompactLayout, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('comment_compact_layout'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('隐藏工具组不接收点击，减少动画时直接显隐', (tester) async {
    await pumpCommentsSheet(
      tester,
      viewSize: const Size(360, 800),
      reducedMotion: true,
      comments: List.generate(
        30,
        (i) => comment(
          id: i,
          userId: 'user-$i',
          userName: '读者$i',
          content: '不同评论$i',
        ),
      ),
    );
    final toolbar = find.byKey(const ValueKey('chapter_comment_action'));
    final opacity = find.ancestor(
      of: toolbar,
      matching: find.byType(AnimatedOpacity),
    );
    final pointer = find.ancestor(
      of: toolbar,
      matching: find.byType(IgnorePointer),
    );
    expect(tester.widget<AnimatedOpacity>(opacity).duration, Duration.zero);
    await tester.drag(find.byType(ListView).last, const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(opacity).opacity, 0);
    expect(tester.widget<IgnorePointer>(pointer.first).ignoring, isTrue);
    final focus = find.ancestor(
      of: toolbar,
      matching: find.byType(ExcludeFocus),
    );
    expect(tester.widget<ExcludeFocus>(focus.first).excluding, isTrue);
    expect(toolbar.hitTestable(), findsNothing);
  });

  testWidgets('评论列表留白跟随恢复后的按钮组高度', (tester) async {
    await pumpCommentsSheet(
      tester,
      viewSize: const Size(320, 800),
      textScale: 2,
      hasNextChapter: true,
      comments: List.generate(
        20,
        (i) => comment(
          id: i,
          userId: 'reader-$i',
          userName: '读者$i',
          content: '内容$i',
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final toolbar = find.byType(ChapterCommentToolbar);
    final list = tester.widget<ListView>(find.byType(ListView).last);
    expect(
      list.padding!.resolve(TextDirection.ltr).bottom,
      greaterThan(tester.getSize(toolbar).height),
    );
  });

  testWidgets('floating buttons reappear at the bottom', (tester) async {
    await pumpCommentsSheet(
      tester,
      comments: List.generate(
        60,
        (i) => comment(
          id: i,
          userId: 'scroll-reader-$i',
          userName: '读者$i',
          content: '滚动内容$i',
        ),
      ),
    );

    final list = find.byType(ListView).last;
    final opacity = find.ancestor(
      of: find.byIcon(Icons.comment_outlined),
      matching: find.byType(AnimatedOpacity),
    );

    final dragStart = tester.getTopLeft(list) + const Offset(24, 24);
    await tester.dragFrom(dragStart, const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(opacity).opacity, 0);

    await tester.flingFrom(dragStart, const Offset(0, -10000), 10000);
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(opacity).opacity, 1);
    expect(tester.takeException(), isNull);
  });
}
