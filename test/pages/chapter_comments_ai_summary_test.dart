import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/chapter_comment.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/chapter_comments_sheet.dart';
import 'package:kira/utils/chapter_summary_cache.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ChapterComment comment() {
    return const ChapterComment(
      id: 1,
      createAt: '2026-05-03 12:00:00',
      userId: 'user-1',
      userName: '用户1',
      userAvatar: '',
      comment: '这话不错',
    );
  }

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

      await tester.pumpWidget(
        wrapWithApp(
          ChapterCommentsSheet(
            chapterUuid: chapterUuid,
            chapterName: '第 1 话',
            initialComments: [comment()],
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
