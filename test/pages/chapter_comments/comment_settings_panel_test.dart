import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/api/ai_api.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/chapter_comments_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_helpers.dart';

CommentSettingsPanel _panel({
  bool isChapterComments = true,
  bool showFilteringSettings = true,
  int initialPages = 2,
  ValueChanged<int>? onInitialPagesChanged,
}) => CommentSettingsPanel(
  isChapterComments: isChapterComments,
  showFilteringSettings: showFilteringSettings,
  useCompactLayout: true,
  showUserAvatar: true,
  showUserName: true,
  showCommentTime: true,
  commentFontScale: 1,
  commentPreload: true,
  commentInitialPages: initialPages,
  onLayoutChanged: (_) {},
  onShowAvatarChanged: (_) {},
  onShowUserNameChanged: (_) {},
  onShowCommentTimeChanged: (_) {},
  onFontScaleChanged: (_) {},
  onPreloadChanged: (_) {},
  onInitialPagesChanged: onInitialPagesChanged ?? (_) {},
);

Future<void> _pumpPanel(
  WidgetTester tester, {
  Widget? panel,
  bool dark = false,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    wrapWithApp(
      Builder(
        builder: (context) => Theme(
          data: ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: panel ?? _panel(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(CommentSettingsPanel)))!;

void _expectOrder(WidgetTester tester, List<String> labels) {
  for (var i = 1; i < labels.length; i++) {
    expect(
      tester.getTopLeft(find.text(labels[i - 1])).dy,
      lessThan(tester.getTopLeft(find.text(labels[i])).dy),
      reason: '${labels[i - 1]} 应在 ${labels[i]} 前面',
    );
  }
}

void main() {
  setUp(() async {
    setupSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({});
    await UserManager().init();
    await AiSettings().reloadFromPrefs(persistMigrations: false);
  });
  tearDown(teardownSecureCredentialStoreForTest);

  testWidgets('初始页数单选 1–5，点击立即回调并更新选中值', (tester) async {
    final changes = <int>[];
    await _pumpPanel(tester, panel: _panel(onInitialPagesChanged: changes.add));
    final pages = find.byType(SegmentedButton<int>);
    var control = tester.widget<SegmentedButton<int>>(pages);
    expect(control.segments.map((segment) => segment.value), [1, 2, 3, 4, 5]);
    expect(control.selected, {2});
    expect(find.text('初始加载20条评论'), findsOneWidget);
    expect(control.multiSelectionEnabled, isFalse);
    expect(control.emptySelectionAllowed, isFalse);

    await tester.ensureVisible(pages);
    await tester.pumpAndSettle();
    for (final value in [5, 1, 3]) {
      await tester.tap(
        find.descendant(of: pages, matching: find.text('$value')),
      );
      await tester.pumpAndSettle();
      control = tester.widget<SegmentedButton<int>>(pages);
      expect(control.selected, {value});
      expect(
        find.text(_l10n(tester).commentSettingsInitialCountTitle(value * 10)),
        findsOneWidget,
      );
    }
    expect(changes, [5, 1, 3]);
    expect(find.text('自动加载全部评论'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('章节原设置入口直接保存页数，关闭重开及重新读偏好后保留', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        const ChapterCommentsSheet(
          chapterUuid: 'comment-settings-persistence',
          chapterName: '测试章节',
          initialComments: [],
          initialTotal: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('评论区设置'));
    await tester.pumpAndSettle();
    final pages = find.byType(SegmentedButton<int>);
    expect(tester.widget<SegmentedButton<int>>(pages).selected, {2});
    await tester.ensureVisible(pages);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: pages, matching: find.text('4')));
    await tester.pumpAndSettle();
    expect(UserManager().commentInitialPages, 4);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('comment_initial_pages'), 4);

    Navigator.of(tester.element(find.byType(CommentSettingsPanel))).pop();
    await tester.pumpAndSettle();
    await UserManager().init(persistMigrations: false);
    await tester.tap(find.byTooltip('评论区设置'));
    await tester.pumpAndSettle();
    expect(tester.widget<SegmentedButton<int>>(pages).selected, {4});
    expect(tester.takeException(), isNull);
  });

  testWidgets('章节单列分组顺序为显示、加载、AI 总结、屏蔽', (tester) async {
    await _pumpPanel(tester);
    final l10n = _l10n(tester);
    expect(find.text(l10n.commentSettingsTitle), findsNothing);
    final dividers = find.byWidgetPredicate(
      (widget) =>
          widget is Divider &&
          widget.key.toString().contains('comment-settings-divider-'),
    );
    expect(dividers, findsNWidgets(3));
    final headings = [
      l10n.commentSettingsLoadingSection,
      l10n.commentSettingsAiSummarySection,
      l10n.commentSettingsFilteringSection,
    ];
    for (var i = 0; i < headings.length; i++) {
      final gap =
          tester.getTopLeft(find.text(headings[i])).dy -
          tester.getBottomLeft(dividers.at(i)).dy;
      expect(gap, greaterThanOrEqualTo(16));
    }
    _expectOrder(tester, [
      l10n.commentSettingsDisplaySection,
      l10n.commentSettingsCompactLayout,
      l10n.commentSettingsShowAvatar,
      l10n.commentSettingsShowUserName,
      l10n.commentSettingsShowCommentTime,
      l10n.commentSettingsFontSizeTitle,
      l10n.commentSettingsLoadingSection,
      l10n.commentSettingsInitialCountTitle(20),
      l10n.commentSettingsPreloadTitle,
      l10n.commentSettingsAiSummarySection,
      l10n.commentSettingsFilteringSection,
      l10n.commentSettingsBlockwordsSection,
      l10n.commentSettingsBlockGroupSpam,
      l10n.commentSettingsBlacklistSection,
    ]);
    expect(find.text(l10n.commentSettingsPreloadDesc), findsOneWidget);
    expect(find.byType(SegmentedButton<bool>), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final filtering in [false, true]) {
    testWidgets('非章节隐藏布局、加载和 AI，屏蔽可见性遵循 $filtering', (tester) async {
      await AiSettings().setApiKey('test-only-key');
      await AiSettings().setSummaryEnabled(true);
      await _pumpPanel(
        tester,
        panel: _panel(
          isChapterComments: false,
          showFilteringSettings: filtering,
        ),
      );
      final l10n = _l10n(tester);
      expect(find.text(l10n.commentSettingsDisplaySection), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.byType(SegmentedButton<bool>), findsNothing);
      expect(find.byType(SegmentedButton<int>), findsNothing);
      for (final label in [
        l10n.commentSettingsCompactLayout,
        l10n.commentSettingsListLayout,
        l10n.commentSettingsLoadingSection,
        l10n.commentSettingsInitialCountTitle(20),
        l10n.commentSettingsPreloadTitle,
        l10n.commentSettingsAiSummarySection,
        l10n.commentSettingsEnableAiSummary,
      ]) {
        expect(find.text(label), findsNothing);
      }
      expect(find.byType(SwitchListTile), findsNWidgets(filtering ? 4 : 3));
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Divider &&
              widget.key.toString().contains('comment-settings-divider-'),
        ),
        filtering ? findsOneWidget : findsNothing,
      );
      for (final label in [
        l10n.commentSettingsFilteringSection,
        l10n.commentSettingsBlockwordsSection,
        l10n.commentSettingsBlockGroupSpam,
        l10n.commentSettingsBlacklistSection,
      ]) {
        expect(find.text(label), filtering ? findsOneWidget : findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final config in [
    (dark: false, scale: 1.0, chapter: true),
    (dark: true, scale: 2.0, chapter: true),
    (dark: false, scale: 2.0, chapter: false),
  ]) {
    testWidgets('375px ${config.dark ? '暗色' : '亮色'} ${config.scale} 倍字号无溢出', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // 展开全部现有 AI 条件，避免只检查默认折叠态。
      await AiSettings().setApiKey('test-only-key');
      await AiSettings().setSummaryEnabled(true);
      await AiSettings().setAutoSummary(true);
      await AiSettings().setSpoilerAnalysis(true);
      await _pumpPanel(
        tester,
        panel: _panel(isChapterComments: config.chapter),
        dark: config.dark,
        textScale: config.scale,
      );
      expect(tester.takeException(), isNull);
      final l10n = _l10n(tester);
      if (config.chapter) {
        final pages = find.byType(SegmentedButton<int>);
        await tester.ensureVisible(pages);
        await tester.pumpAndSettle();
        final rect = tester.getRect(pages);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(375));
        expect(rect.width / 5, greaterThanOrEqualTo(48));
        expect(rect.height, greaterThanOrEqualTo(48));
        await tester.ensureVisible(
          find.text(l10n.commentSettingsTriggerTiming),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(SegmentedButton<AiAutoSummaryTiming>),
          findsOneWidget,
        );
      }
      await tester.ensureVisible(
        find.text(l10n.commentSettingsBlacklistSection),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
