import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/api/ai_api.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/chapter_comments_sheet.dart';
import 'package:kira/widgets/collapsible_content.dart';
import 'package:kira/widgets/reader_settings_fold.dart';
import 'package:kira/widgets/section_header.dart';
import 'package:kira/widgets/settings_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_helpers.dart';

CommentSettingsPanel _panel({
  bool isChapterComments = true,
  bool showFilteringSettings = true,
  bool preload = true,
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
  commentPreload: preload,
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
  bool reducedMotion = false,
}) async {
  await tester.pumpWidget(
    wrapWithApp(
      Builder(
        builder: (context) => Theme(
          data: ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: reducedMotion,
            ),
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

Finder _aiHeader() => find.descendant(
  of: find.byType(ReaderSettingsFold),
  matching: find.byType(SectionHeader),
);

Future<void> _toggleAiSection(WidgetTester tester) async {
  final header = _aiHeader();
  await tester.ensureVisible(header);
  await tester.pumpAndSettle();
  await tester.tap(header);
  await tester.pumpAndSettle();
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

  testWidgets('章节按显示、加载、AI 总结、屏蔽分为四张独立卡片', (tester) async {
    await _pumpPanel(tester);
    final l10n = _l10n(tester);
    expect(find.text(l10n.commentSettingsTitle), findsNothing);
    expect(find.byType(Divider), findsNothing);
    final sections = find.byType(SettingsSection);
    expect(sections, findsNWidgets(4));
    expect(
      tester
          .widgetList<SettingsSection>(sections)
          .map((section) => section.title),
      [
        l10n.commentSettingsDisplaySection,
        l10n.commentSettingsLoadingSection,
        null,
        l10n.commentSettingsFilteringSection,
      ],
    );
    expect(find.byType(ReaderSettingsFold), findsOneWidget);
    expect(find.byType(CollapsibleContent), findsOneWidget);
    expect(find.text(l10n.commentSettingsAiSummarySection), findsOneWidget);
    expect(
      tester
          .widget<CollapsibleContent>(find.byType(CollapsibleContent))
          .expanded,
      isFalse,
    );
    expect(find.byType(Card), findsNWidgets(4));
    for (var i = 0; i < 4; i++) {
      final section = sections.at(i);
      expect(
        find.descendant(of: section, matching: find.byType(SettingsSection)),
        findsNothing,
      );
      final card = find.descendant(of: section, matching: find.byType(Card));
      expect(
        tester.widget<Card>(card).color,
        Theme.of(tester.element(card)).colorScheme.surfaceBright,
      );
      if (i > 0) {
        expect(
          tester.getTopLeft(section).dy -
              tester.getBottomLeft(sections.at(i - 1)).dy,
          greaterThanOrEqualTo(12),
        );
      }
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

  testWidgets('AI 主开关与依赖项同卡，普通开关即时保存并保持条件显示', (tester) async {
    final settings = AiSettings();
    await settings.setApiKey('test-only-key');
    await settings.setSummaryEnabled(true);
    await settings.setAutoSummary(true);
    await settings.setSpoilerAnalysis(true);
    await _pumpPanel(tester, panel: _panel(preload: false));
    final l10n = _l10n(tester);
    await _toggleAiSection(tester);
    final aiSection = find.byType(ReaderSettingsFold);
    for (final label in [
      l10n.commentSettingsEnableAiSummary,
      l10n.commentSettingsCollapseAiComment,
    ]) {
      final tile = find.ancestor(
        of: find.text(label),
        matching: find.byType(SwitchListTile),
      );
      expect(tester.widget<SwitchListTile>(tile).subtitle, isNull);
    }
    for (final label in [
      l10n.commentSettingsEnableAiSummary,
      l10n.commentSettingsAutoAiSummary,
      l10n.commentSettingsMinCommentCount,
      l10n.commentSettingsTriggerTiming,
      l10n.commentSettingsSpoilerAnalysis,
      l10n.commentSettingsSpoilerWarn,
      l10n.commentSettingsPromptPresets,
    ]) {
      expect(
        find.descendant(of: aiSection, matching: find.text(label)),
        findsOneWidget,
      );
    }
    final timing = tester.widget<SegmentedButton<AiAutoSummaryTiming>>(
      find.byType(SegmentedButton<AiAutoSummaryTiming>),
    );
    expect(timing.selected, {AiAutoSummaryTiming.onOpen});
    expect(timing.segments.last.enabled, isFalse);
    expect(
      find.text(l10n.commentSettingsPreloadRequiredForTiming),
      findsOneWidget,
    );

    for (final label in [
      l10n.commentSettingsAutoAiSummary,
      l10n.commentSettingsSpoilerAnalysis,
      l10n.commentSettingsEnableAiSummary,
    ]) {
      final tile = find.ancestor(
        of: find.text(label),
        matching: find.byType(SwitchListTile),
      );
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      if (label == l10n.commentSettingsAutoAiSummary) {
        expect(settings.autoSummary, isFalse);
        expect(find.text(l10n.commentSettingsTriggerTiming), findsNothing);
      } else if (label == l10n.commentSettingsSpoilerAnalysis) {
        expect(settings.spoilerAnalysis, isFalse);
        expect(find.text(l10n.commentSettingsSpoilerWarn), findsNothing);
      } else {
        expect(settings.summaryEnabled, isFalse);
        expect(find.text(l10n.commentSettingsAutoAiSummary), findsNothing);
        expect(find.text(l10n.commentSettingsPromptPresets), findsNothing);
      }
    }
    await settings.reloadFromPrefs(persistMigrations: false);
    expect(settings.summaryEnabled, isFalse);
    expect(settings.autoSummary, isFalse);
    expect(settings.spoilerAnalysis, isFalse);
    expect(find.byType(SettingsSection), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI 卡片默认收起，折叠不写偏好、不清空未提交输入或 AI 配置', (tester) async {
    final settings = AiSettings();
    await settings.setApiKey('test-only-key');
    await settings.setSummaryEnabled(true);
    await settings.setAutoSummary(true);
    await settings.setSpoilerAnalysis(true);
    final minimum = settings.autoSummaryMin;
    final prefs = await SharedPreferences.getInstance();
    final before = {for (final key in prefs.getKeys()) key: prefs.get(key)};
    await _pumpPanel(tester);
    final l10n = _l10n(tester);
    final content = find.byType(CollapsibleContent);
    expect(tester.widget<CollapsibleContent>(content).expanded, isFalse);
    expect(tester.getSize(content).height, 0);
    expect(
      find.text(l10n.commentSettingsEnableAiSummary).hitTestable(),
      findsNothing,
    );
    expect(
      find.text(l10n.commentSettingsShowAvatar).hitTestable(),
      findsOneWidget,
    );

    await _toggleAiSection(tester);
    expect(tester.widget<CollapsibleContent>(content).expanded, isTrue);
    final field = find.byType(TextFormField);
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, '123');
    final editable = find.descendant(
      of: field,
      matching: find.byType(EditableText),
    );
    final controller = tester.widget<EditableText>(editable).controller;
    expect(settings.autoSummaryMin, minimum);
    await _toggleAiSection(tester);
    expect(tester.getSize(content).height, 0);
    expect(
      find.text(l10n.commentSettingsEnableAiSummary).hitTestable(),
      findsNothing,
    );
    await _toggleAiSection(tester);
    expect(tester.widget<EditableText>(editable).controller, same(controller));
    expect(controller.text, '123');
    expect(settings.autoSummaryMin, minimum);
    expect(settings.summaryEnabled, isTrue);
    expect(settings.autoSummary, isTrue);
    expect(settings.spoilerAnalysis, isTrue);
    expect({for (final key in prefs.getKeys()) key: prefs.get(key)}, before);
    expect(find.byType(SettingsSection), findsNWidgets(4));
    expect(find.text(l10n.commentSettingsAiSummarySection), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('减少动画时 AI 分组一帧展开或收起，不改变主开关', (tester) async {
    final settings = AiSettings();
    await settings.setApiKey('test-only-key');
    await settings.setSummaryEnabled(true);
    await _pumpPanel(tester, reducedMotion: true);
    final content = find.byType(CollapsibleContent);
    final header = _aiHeader();
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();
    await tester.tap(header);
    await tester.pump();
    expect(tester.widget<CollapsibleContent>(content).expanded, isTrue);
    expect(tester.getSize(content).height, greaterThan(0));
    final heightAlign = find
        .descendant(
          of: content,
          matching: find.byWidgetPredicate(
            (widget) => widget is Align && widget.heightFactor != null,
          ),
        )
        .first;
    expect(tester.widget<Align>(heightAlign).heightFactor, 1);
    await tester.tap(header);
    await tester.pump();
    expect(tester.widget<CollapsibleContent>(content).expanded, isFalse);
    expect(tester.getSize(content).height, 0);
    expect(tester.widget<Align>(heightAlign).heightFactor, 0);
    expect(settings.summaryEnabled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('章节设置入口关闭重开后 AI 卡片仍默认收起，但保留启用状态', (tester) async {
    final settings = AiSettings();
    await settings.setApiKey('test-only-key');
    await settings.setSummaryEnabled(true);
    await tester.pumpWidget(
      wrapWithApp(
        const ChapterCommentsSheet(
          chapterUuid: 'comment-settings-ai-fold',
          chapterName: '测试章节',
          initialComments: [],
          initialTotal: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('评论区设置'));
    await tester.pumpAndSettle();
    final content = find.byType(CollapsibleContent);
    expect(tester.widget<CollapsibleContent>(content).expanded, isFalse);
    await _toggleAiSection(tester);
    expect(tester.widget<CollapsibleContent>(content).expanded, isTrue);
    Navigator.of(tester.element(find.byType(CommentSettingsPanel))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('评论区设置'));
    await tester.pumpAndSettle();
    expect(tester.widget<CollapsibleContent>(content).expanded, isFalse);
    expect(settings.summaryEnabled, isTrue);
    expect(find.byType(SettingsSection), findsNWidgets(4));
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
      expect(find.byType(ReaderSettingsFold), findsNothing);
      expect(find.byType(CollapsibleContent), findsNothing);
      expect(find.byType(SwitchListTile), findsNWidgets(filtering ? 4 : 3));
      expect(find.byType(SettingsSection), findsNWidgets(filtering ? 2 : 1));
      expect(find.byType(Card), findsNWidgets(filtering ? 2 : 1));
      expect(find.byType(Divider), findsNothing);
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
        await _toggleAiSection(tester);
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
