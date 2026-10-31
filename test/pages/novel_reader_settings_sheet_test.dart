import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/models/novel_dialogue_style.dart';
import 'package:kira/models/novel_reader_settings.dart';
import 'package:kira/models/novel_reader_status_settings.dart';
import 'package:kira/models/reader_settings.dart';
import 'package:kira/pages/novel_reader/novel_reader_dialogue.dart';
import 'package:kira/pages/novel_reader/novel_reader_settings_sheet.dart';
import 'package:kira/theme/novel_reader_theme.dart';
import 'package:kira/widgets/app_sheet.dart';
import 'package:kira/widgets/collapsible_content.dart';
import 'package:kira/widgets/reader_settings_fold.dart';
import 'package:kira/widgets/reader_status_settings.dart';
import 'package:kira/widgets/select_tile.dart';
import 'package:kira/widgets/settings_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

Future<void> _mount(
  WidgetTester tester, {
  NovelReaderSettings settings = const NovelReaderSettings(),
  required ValueChanged<NovelReaderSettings> onChanged,
  Size size = const Size(420, 850),
  double textScale = 1,
  Locale locale = const Locale('zh'),
  Brightness systemBrightness = Brightness.light,
  bool reduceMotion = false,
  ValueNotifier<bool>? dragPreview,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          platformBrightness: systemBrightness,
          disableAnimations: reduceMotion,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppSheet<void>(
              context,
              maxHeightFactor: 0.7,
              barrierColor: Colors.transparent,
              fadeOutWhen: dragPreview,
              child: NovelReaderSettingsSheet(
                settings: settings,
                systemBrightness: systemBrightness,
                dragPreview: dragPreview,
                onChanged: onChanged,
              ),
            ),
            child: const Text('打开阅读设置'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开阅读设置'));
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, String key) async {
  if (key == 'novel-theme-add' || key.startsWith('novel-custom-theme-')) {
    await _openTheme(tester);
    final fold = find.byKey(const ValueKey('novel-custom-theme-settings'));
    if (find
        .descendant(of: fold, matching: find.byIcon(Icons.expand_more))
        .evaluate()
        .isNotEmpty) {
      await _toggleFold(tester, 'novel-custom-theme-settings');
    }
  }
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _openTheme(WidgetTester tester, {bool? dark}) async {
  if (find
      .byKey(const ValueKey('novel-theme-settings-sheet'))
      .evaluate()
      .isEmpty) {
    await _tapVisible(tester, 'novel-theme-settings-entry');
  }
  if (dark != null) {
    final finder = find.byKey(const ValueKey('novel-theme-edit-mode'));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    tester.widget<SegmentedButton<bool>>(finder).onSelectionChanged!({dark});
    await tester.pumpAndSettle();
  }
}

Future<void> _closeTheme(WidgetTester tester) async {
  await _tapVisible(tester, 'novel-theme-settings-back');
}

Future<void> _setSelect<T>(WidgetTester tester, String key, T value) async {
  final row = find.byKey(ValueKey(key));
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  final select = find.descendant(of: row, matching: find.byType(SelectTile<T>));
  tester.widget<SelectTile<T>>(select).onChanged(value);
  await tester.pumpAndSettle();
}

List<RichText> _previewRichTexts(WidgetTester tester) => tester
    .widgetList<RichText>(
      find.descendant(
        of: find.byKey(const ValueKey('novel-settings-preview-text')),
        matching: find.byType(RichText),
      ),
    )
    .toList();

TextSpan _previewSpan(WidgetTester tester) => TextSpan(
  children: [for (final text in _previewRichTexts(tester)) text.text],
);

Iterable<TextSpan> _descendantSpans(InlineSpan root) sync* {
  if (root is TextSpan) {
    yield root;
    for (final child in root.children ?? const <InlineSpan>[]) {
      yield* _descendantSpans(child);
    }
  }
}

Future<void> _toggleFold(WidgetTester tester, String key) async {
  if (key == 'novel-custom-theme-settings') await _openTheme(tester);
  final fold = find.byKey(ValueKey(key));
  final header = find
      .descendant(of: fold, matching: find.byType(InkWell))
      .first;
  await tester.ensureVisible(header);
  await tester.pumpAndSettle();
  await tester.tap(header);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    setupSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({});
    final reader = ReaderSettings()..resetPrefsCache();
    await reader.initFromPrefs(await SharedPreferences.getInstance());
  });

  tearDown(teardownSecureCredentialStoreForTest);

  for (final (locale, label) in [
    (const Locale('zh'), '自定义主题'),
    (const Locale('zh', 'Hant'), '自訂主題'),
  ]) {
    testWidgets('custom theme group uses its complete label in $locale', (
      tester,
    ) async {
      await _mount(tester, locale: locale, onChanged: (_) {});
      await _openTheme(tester);
      final group = find.byKey(const ValueKey('novel-custom-theme-settings'));
      await tester.ensureVisible(group);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: group, matching: find.text(label)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('font family sits above font size and stays out of the theme '
      'panel', (tester) async {
    var latest = const NovelReaderSettings();
    await _mount(tester, onChanged: (value) => latest = value);
    expect(find.byKey(const ValueKey('novel-font-family')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('novel-font-family'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('novel-font-size'))).dy,
      ),
    );
    // 默认跟随应用字体：空字符串。
    expect(latest.fontFamily, isEmpty);
    await _setSelect<String>(tester, 'novel-font-family', 'system');
    expect(latest.fontFamily, 'system');
    await _setSelect<String>(tester, 'novel-font-family', '');
    expect(latest.fontFamily, isEmpty);

    await _openTheme(tester);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('novel-theme-settings-sheet')),
        matching: find.byKey(const ValueKey('novel-font-family')),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  for (final (size, textScale, brightness) in [
    (const Size(375, 812), 1.0, Brightness.light),
    (const Size(320, 850), 2.0, Brightness.dark),
    (const Size(812, 375), 1.0, Brightness.dark),
  ]) {
    testWidgets('theme settings use independent cards at $size', (
      tester,
    ) async {
      var latest = const NovelReaderSettings();
      await _mount(
        tester,
        onChanged: (value) => latest = value,
        size: size,
        textScale: textScale,
        systemBrightness: brightness,
      );
      await _openTheme(tester);
      final colorCard = find.byKey(const ValueKey('novel-color-scheme-card'));
      final dialogueCard = find.byKey(const ValueKey('novel-dialogue-card'));
      expect(
        find.descendant(
          of: colorCard,
          matching: find.byKey(const ValueKey('novel-theme-edit-mode')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: colorCard,
          matching: find.byKey(const ValueKey('novel-dialogue-enabled')),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: dialogueCard,
          matching: find.byKey(const ValueKey('novel-dialogue-enabled')),
        ),
        findsOneWidget,
      );
      final toggle = find.byKey(const ValueKey('novel-dialogue-enabled'));
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      tester.widget<SwitchListTile>(toggle).onChanged!(true);
      await tester.pumpAndSettle();
      for (final key in [
        'novel-dialogue-color-mode',
        'novel-dialogue-weight',
        'novel-dialogue-background-enabled',
      ]) {
        final control = find.descendant(
          of: dialogueCard,
          matching: find.byKey(ValueKey(key)),
        );
        await tester.ensureVisible(control);
        await tester.pumpAndSettle();
        final target = find
            .descendant(of: control, matching: find.byType(InkWell))
            .first;
        expect(target.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      expect(
        find.descendant(
          of: dialogueCard,
          matching: find.byType(SettingsSection),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('novel-custom-theme-settings')),
          matching: find.byType(SettingsSection),
        ),
        findsOneWidget,
      );
      // 主题面板仍在返回时统一提交，不因卡片包装提前写入宿主。
      expect(latest.dialogueEnabled, isFalse);
      await _closeTheme(tester);
      expect(latest.dialogueEnabled, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'font slider keeps live updates and theme entry owns the preview',
    (tester) async {
      var latest = const NovelReaderSettings();
      await _mount(tester, onChanged: (value) => latest = value);
      final finder = find.byKey(const ValueKey('novel-font-size'));
      final slider = tester.widget<Slider>(finder);
      expect(slider.min, 10);
      expect(slider.max, 48);
      expect(slider.divisions, 38);
      for (final fontSize in [10.0, 11.0, 47.0, 48.0]) {
        tester.widget<Slider>(finder).onChanged!(fontSize);
        await tester.pumpAndSettle();
        expect(latest.fontSize, fontSize);
        expect(tester.widget<Slider>(finder).value, fontSize);
        expect(
          find.byKey(const ValueKey('novel-settings-preview-text')),
          findsNothing,
        );
      }
      await _openTheme(tester);
      expect(_previewRichTexts(tester).first.text.style?.fontSize, 48);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('line height and paragraph spacing offer the wider ranges', (
    tester,
  ) async {
    var latest = const NovelReaderSettings();
    await _mount(tester, onChanged: (value) => latest = value);
    final line = tester.widget<Slider>(
      find.byKey(const ValueKey('novel-line-height')),
    );
    expect(line.min, 1.0);
    expect(line.max, 3.0);
    final spacing = tester.widget<Slider>(
      find.byKey(const ValueKey('novel-paragraph-spacing')),
    );
    expect(spacing.min, 0);
    expect(spacing.max, 64);
    tester
        .widget<Slider>(find.byKey(const ValueKey('novel-line-height')))
        .onChanged!(1.0);
    tester
        .widget<Slider>(find.byKey(const ValueKey('novel-paragraph-spacing')))
        .onChanged!(0.0);
    await tester.pumpAndSettle();
    expect(latest.lineHeight, 1.0);
    expect(latest.paragraphSpacing, 0);
    expect(tester.takeException(), isNull);
  });

  for (final mode in NovelReaderMode.values) {
    testWidgets('content width slider updates settings in ${mode.name} mode', (
      tester,
    ) async {
      var latest = NovelReaderSettings(mode: mode);
      await _mount(
        tester,
        settings: latest,
        onChanged: (value) => latest = value,
      );
      final finder = find.byKey(const ValueKey('novel-content-width'));
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      final slider = tester.widget<Slider>(finder);
      expect(slider.min, 320);
      expect(slider.max, 1200);
      expect(slider.divisions, 22);
      expect(slider.value, 720);
      expect(find.text('正文宽度 · 720 dp'), findsOneWidget);
      for (final width in [320.0, 960.0, 1200.0]) {
        tester.widget<Slider>(finder).onChanged!(width);
        await tester.pumpAndSettle();
        expect(latest.contentWidth, width);
        expect(latest.mode, mode);
        expect(tester.widget<Slider>(finder).value, width);
        expect(find.text('正文宽度 · ${width.round()} dp'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'light and dark mode bindings commit together when theme closes',
    (tester) async {
      var latest = const NovelReaderSettings();
      var changes = 0;
      await _mount(
        tester,
        onChanged: (value) {
          latest = value;
          changes++;
        },
      );
      await _openTheme(tester, dark: false);
      final lightTile = find.byKey(const ValueKey('novel-light-theme'));
      await tester.ensureVisible(lightTile);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: lightTile,
          matching: find.byType(SelectTile<String>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('纸张').last);
      await tester.pumpAndSettle();
      expect(changes, 0);
      expect(
        tester
            .widget<SelectTile<String>>(
              find.descendant(
                of: lightTile,
                matching: find.byType(SelectTile<String>),
              ),
            )
            .value,
        'paper',
      );
      await _openTheme(tester, dark: true);
      final darkTile = find.byKey(const ValueKey('novel-dark-theme'));
      await tester.ensureVisible(darkTile);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: darkTile,
          matching: find.byType(SelectTile<String>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('护眼绿').last);
      await tester.pumpAndSettle();
      expect(changes, 0);
      await _closeTheme(tester);
      expect(changes, 1);
      expect(latest.lightThemeId, 'paper');
      expect(latest.darkThemeId, 'green');
      expect(tester.takeException(), isNull);
    },
  );

  for (final dismissal in ['back', 'system', 'drag']) {
    testWidgets('theme draft commits once on $dismissal dismissal', (
      tester,
    ) async {
      var changes = 0;
      var latest = const NovelReaderSettings();
      await _mount(
        tester,
        onChanged: (value) {
          latest = value;
          changes++;
        },
      );
      await _openTheme(tester);

      final original = _previewSpan(tester).toPlainText();
      expect(original, contains('『未说完的话』'));
      await _tapVisible(tester, 'novel-dialogue-enabled');

      await _setSelect(
        tester,
        'novel-dialogue-weight',
        NovelDialogueWeight.bold,
      );
      final backgroundToggle = find.byKey(
        const ValueKey('novel-dialogue-background-enabled'),
      );
      await tester.ensureVisible(backgroundToggle);
      tester.widget<SwitchListTile>(backgroundToggle).onChanged!(true);
      await tester.pumpAndSettle();
      final opacity = find.byKey(
        const ValueKey('novel-dialogue-background-opacity'),
      );
      for (final value in [0.2, 0.35, 0.5]) {
        tester.widget<Slider>(opacity).onChanged!(value);
        await tester.pumpAndSettle();
      }
      expect(changes, 0);
      final displayed = _previewSpan(tester).toPlainText();
      expect(displayed, contains('『未说完的话』'));
      expect(displayed, contains('她说：「这一句尚未结束'));
      final spans = _descendantSpans(_previewSpan(tester));
      expect(
        spans.any((span) => span.style?.fontWeight == FontWeight.w700),
        isTrue,
      );
      switch (dismissal) {
        case 'back':
          await _closeTheme(tester);
        case 'system':
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();

        case 'drag':
          final sheet = find.byKey(
            const ValueKey('novel-theme-settings-sheet'),
          );
          final handle = find.descendant(
            of: find.ancestor(of: sheet, matching: find.byType(AppSheet)),
            matching: find.byType(AppSheetHandle),
          );
          await tester.fling(handle, const Offset(0, 500), 1500);
          await tester.pumpAndSettle();
      }
      expect(
        find.byKey(const ValueKey('novel-theme-settings-sheet')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('novel-theme-settings-entry')),
        findsOneWidget,
      );
      expect(changes, 1);
      expect(latest.dialogueEnabled, isTrue);
      expect(latest.lightDialogueStyle.weight, NovelDialogueWeight.bold);
      expect(latest.lightDialogueStyle.backgroundOpacity, 0.5);
      expect(
        latest.darkDialogueStyle,
        const NovelDialogueStyle(backgroundColor: 0xFFFFFFFF),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'closing unchanged theme or switching edit mode does not submit',
    (tester) async {
      var changes = 0;
      await _mount(tester, onChanged: (_) => changes++);
      await _openTheme(tester, dark: true);
      await _openTheme(tester, dark: false);
      await _closeTheme(tester);
      expect(changes, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'preview follows selected light and dark palette, not app brightness',
    (tester) async {
      final settings =
          const NovelReaderSettings(
                dialogueEnabled: true,
                lightThemeId: 'light-custom',
                darkThemeId: 'dark-custom',
                lightDialogueStyle: NovelDialogueStyle(
                  colorMode: NovelDialogueColorMode.custom,
                  textColor: 0xFF335577,
                ),
                darkDialogueStyle: NovelDialogueStyle(
                  colorMode: NovelDialogueColorMode.custom,
                  textColor: 0xFFAABBCC,
                ),
              )
              .upsertCustomTheme(
                const NovelReaderCustomTheme(
                  id: 'light-custom',
                  name: '浅色纸',
                  backgroundColor: 0xFFF8F4E8,
                  textColor: 0xFF302A22,
                ),
              )
              .upsertCustomTheme(
                const NovelReaderCustomTheme(
                  id: 'dark-custom',
                  name: '深色纸',
                  backgroundColor: 0xFF142332,
                  textColor: 0xFFE5DEC1,
                ),
              );
      var changes = 0;
      await _mount(
        tester,
        settings: settings,
        systemBrightness: Brightness.dark,
        onChanged: (_) => changes++,
      );
      await _openTheme(tester);
      for (final dark in [true, false, true]) {
        await _openTheme(tester, dark: dark);
        final palette = NovelReaderPalette.resolve(
          settings,
          dark ? Brightness.dark : Brightness.light,
        );
        final container = tester.widget<Container>(
          find.byKey(const ValueKey('novel-settings-preview')),
        );
        expect(
          (container.decoration! as BoxDecoration).color,
          palette.background,
        );
        expect(
          _previewRichTexts(tester).first.text.style?.color,
          palette.foreground,
        );
        final dialogue = resolveNovelDialoguePresentation(
          settings,
          dark: dark,
          foreground: palette.foreground,
          background: palette.background,
        )!;
        expect(
          _descendantSpans(
            _previewSpan(tester),
          ).any((span) => span.style?.color == dialogue.foreground),
          isTrue,
        );
      }
      await _closeTheme(tester);
      expect(changes, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('low contrast warns without blocking color and opacity edits', (
    tester,
  ) async {
    var latest = const NovelReaderSettings(
      dialogueEnabled: true,
      lightDialogueStyle: NovelDialogueStyle(
        colorMode: NovelDialogueColorMode.custom,
        textColor: 0xFF666666,
        backgroundColor: 0xFF666666,
        backgroundOpacity: 1,
      ),
    );
    await _mount(
      tester,
      settings: latest,
      onChanged: (value) => latest = value,
    );
    await _openTheme(tester);
    expect(
      find.byKey(const ValueKey('novel-dialogue-low-contrast')),
      findsOneWidget,
    );
    tester
        .widget<Slider>(
          find.byKey(const ValueKey('novel-dialogue-background-opacity')),
        )
        .onChanged!(0);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('novel-dialogue-low-contrast')),
      findsNothing,
    );
    await _setSelect(
      tester,
      'novel-dialogue-color-mode',
      NovelDialogueColorMode.body,
    );
    expect(
      find.byKey(const ValueKey('novel-dialogue-text-color')),
      findsNothing,
    );
    await _setSelect(
      tester,
      'novel-dialogue-color-mode',
      NovelDialogueColorMode.custom,
    );
    await _tapVisible(tester, 'novel-dialogue-text-color');
    tester
        .widget<ColorPicker>(find.byType(ColorPicker))
        .onColorChanged(Colors.white);
    final context = tester.element(find.byType(ColorPicker));
    await tester.tap(
      find.text(MaterialLocalizations.of(context).okButtonLabel).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('novel-dialogue-low-contrast')),
      findsOneWidget,
    );
    await _closeTheme(tester);
    expect(latest.lightDialogueStyle.textColor, 0xFFFFFFFF);
    expect(latest.lightDialogueStyle.backgroundOpacity, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'disabling dialogue preserves style and restores original preview',
    (tester) async {
      var latest = const NovelReaderSettings(dialogueEnabled: true);
      await _mount(
        tester,
        settings: latest,
        onChanged: (value) => latest = value,
      );
      await _openTheme(tester);
      await _setSelect(
        tester,
        'novel-dialogue-weight',
        NovelDialogueWeight.medium,
      );
      await _tapVisible(tester, 'novel-dialogue-enabled');
      final plain = _previewSpan(tester).toPlainText();
      expect(plain, contains('『未说完的话』'));
      expect(find.byKey(const ValueKey('novel-dialogue-weight')), findsNothing);
      await _closeTheme(tester);
      expect(latest.dialogueEnabled, isFalse);
      expect(latest.lightDialogueStyle.weight, NovelDialogueWeight.medium);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (size, textScale) in [
    (const Size(375, 812), 1.0),
    (const Size(320, 640), 2.0),
    (const Size(812, 375), 1.0),
  ]) {
    testWidgets(
      'theme fills screen and pins scrollable preview at $size $textScale',
      (tester) async {
        await _mount(
          tester,
          settings: const NovelReaderSettings(
            fontSize: 48,
            lineHeight: 3,
            paragraphSpacing: 64,
            dialogueEnabled: true,
          ),
          onChanged: (_) {},
          size: size,
          textScale: textScale,
          reduceMotion: true,
        );
        await _openTheme(tester);
        final sheet = find.byKey(const ValueKey('novel-theme-settings-sheet'));
        final frame = find.ancestor(of: sheet, matching: find.byType(AppSheet));
        expect(tester.widget<AppSheet>(frame).heightFactor, 1);
        expect(tester.getSize(frame).height, closeTo(size.height, 1));
        final preview = find.byKey(const ValueKey('novel-settings-preview'));
        final previewScroll = find.byKey(
          const ValueKey('novel-theme-preview-scroll'),
        );
        expect(
          tester.getSize(preview).height,
          lessThanOrEqualTo(size.height * 0.4 + 1),
        );
        final previewPosition = tester.getTopLeft(preview);
        final headerPosition = tester.getTopLeft(
          find.byKey(const ValueKey('novel-theme-settings-back')),
        );
        final scroll = find.byKey(
          const ValueKey('novel-theme-settings-scroll'),
        );
        expect(find.descendant(of: scroll, matching: preview), findsNothing);
        expect(_previewRichTexts(tester).length, 7);
        final innerScrollable = find.descendant(
          of: previewScroll,
          matching: find.byType(Scrollable),
        );
        expect(
          tester
              .state<ScrollableState>(innerScrollable)
              .position
              .maxScrollExtent,
          greaterThan(0),
        );
        for (final key in [
          'novel-light-theme',
          'novel-dialogue-color-mode',
          'novel-dialogue-weight',
        ]) {
          final row = find.byKey(ValueKey(key));
          await tester.ensureVisible(row);
          await tester.pumpAndSettle();
          final select = find.descendant(
            of: row,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is SelectTile<String> ||
                  widget is SelectTile<NovelDialogueColorMode> ||
                  widget is SelectTile<NovelDialogueWeight>,
            ),
          );
          expect(
            tester.getBottomRight(select).dx,
            closeTo(tester.getBottomRight(row).dx, 1),
          );
        }
        final backgroundToggle = find.byKey(
          const ValueKey('novel-dialogue-background-enabled'),
        );
        await tester.ensureVisible(backgroundToggle);
        tester.widget<SwitchListTile>(backgroundToggle).onChanged!(true);
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('novel-dialogue-background-opacity')),
        );
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(preview), previewPosition);
        expect(
          tester.getTopLeft(
            find.byKey(const ValueKey('novel-theme-settings-back')),
          ),
          headerPosition,
        );
        expect(
          find
              .byKey(const ValueKey('novel-dialogue-background-opacity'))
              .hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'add dialog edits name and colors together, then binds to dark mode',
    (tester) async {
      var latest = const NovelReaderSettings();
      await _mount(tester, onChanged: (value) => latest = value);
      await _tapVisible(tester, 'novel-theme-add');
      // 新建直接弹出编辑对话框，名称为空时确认按钮禁用。
      FilledButton confirmButton() => tester.widget<FilledButton>(
        find.byKey(const ValueKey('novel-theme-edit-confirm')),
      );
      expect(confirmButton().onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('novel-theme-name-field')),
        '夜航',
      );
      await tester.pumpAndSettle();
      expect(confirmButton().onPressed, isNotNull);
      // 背景与文字两个颜色字段分别打开色轮并确认，色块/HEX 同步刷新。
      for (final (key, color) in [
        ('novel-theme-edit-background', const Color(0xFF152337)),
        ('novel-theme-edit-text', const Color(0xFFE8DDBA)),
      ]) {
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        expect(find.byType(ColorPicker), findsOneWidget);
        tester
            .widget<ColorPicker>(find.byType(ColorPicker))
            .onColorChanged(color);
        final context = tester.element(find.byType(ColorPicker));
        final okLabel = MaterialLocalizations.of(context).okButtonLabel;
        await tester.tap(find.text(okLabel).first);
        await tester.pumpAndSettle();
        final hex =
            '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
        expect(find.text(hex), findsOneWidget);
      }
      // 预览实时反映当前颜色。
      final preview = tester.widget<Container>(
        find.byKey(const ValueKey('novel-theme-edit-preview')),
      );
      expect(
        (preview.decoration! as BoxDecoration).color,
        const Color(0xFF152337),
      );
      final previewText = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('novel-theme-edit-preview')),
          matching: find.byType(Text),
        ),
      );
      expect(previewText.style?.color, const Color(0xFFE8DDBA));
      await tester.tap(find.byKey(const ValueKey('novel-theme-edit-confirm')));
      await tester.pumpAndSettle();
      await _closeTheme(tester);
      expect(latest.customThemes, hasLength(1));
      expect(latest.customThemes.single.name, '夜航');
      expect(latest.customThemes.single.backgroundColor, 0xFF152337);
      expect(latest.customThemes.single.textColor, 0xFFE8DDBA);
      await _openTheme(tester, dark: true);
      final darkTile = find.byKey(const ValueKey('novel-dark-theme'));
      await tester.ensureVisible(darkTile);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: darkTile,
          matching: find.byType(SelectTile<String>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('夜航').last);
      await tester.pumpAndSettle();
      await _closeTheme(tester);
      expect(latest.darkThemeId, latest.customThemes.single.id);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('edit dialog renames an existing theme and updates its colors', (
    tester,
  ) async {
    const theme = NovelReaderCustomTheme(
      id: 'c1',
      name: '米黄',
      backgroundColor: 0xFF182839,
      textColor: 0xFFEFDFC1,
    );
    var latest = const NovelReaderSettings().upsertCustomTheme(theme);
    await _mount(
      tester,
      settings: latest,
      onChanged: (value) => latest = value,
    );
    await _tapVisible(tester, 'novel-custom-theme-edit-c1');
    await tester.enterText(
      find.byKey(const ValueKey('novel-theme-name-field')),
      '暮色',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('novel-theme-edit-background')));
    await tester.pumpAndSettle();
    tester
        .widget<ColorPicker>(find.byType(ColorPicker))
        .onColorChanged(const Color(0xFF223344));
    final context = tester.element(find.byType(ColorPicker));
    await tester.tap(
      find.text(MaterialLocalizations.of(context).okButtonLabel).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('novel-theme-edit-confirm')));
    await tester.pumpAndSettle();
    await _closeTheme(tester);
    expect(latest.customThemes.single.id, 'c1');
    expect(latest.customThemes.single.name, '暮色');
    expect(latest.customThemes.single.backgroundColor, 0xFF223344);
    expect(latest.customThemes.single.textColor, 0xFFEFDFC1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delete a custom theme falls its binding back safely', (
    tester,
  ) async {
    const theme = NovelReaderCustomTheme(
      id: 'c1',
      name: '米黄',
      backgroundColor: 0xFF182839,
      textColor: 0xFFEFDFC1,
    );
    var latest = const NovelReaderSettings(
      darkThemeId: 'c1',
    ).upsertCustomTheme(theme);
    await _mount(
      tester,
      settings: latest,
      onChanged: (value) => latest = value,
    );
    await _tapVisible(tester, 'novel-custom-theme-delete-c1');
    await tester.tap(find.byType(FilledButton).last);
    await tester.pumpAndSettle();
    await _closeTheme(tester);
    expect(latest.customThemes, isEmpty);
    // 绑定保留原 ID，展示时由 themeIdFor 兜底回退到深色默认（灰）。
    expect(latest.themeIdFor(dark: true), 'gray');
    expect(tester.takeException(), isNull);
  });

  testWidgets('screen-on preference is independent and persists', (
    tester,
  ) async {
    var latest = const NovelReaderSettings();
    await _mount(tester, onChanged: (value) => latest = value);
    await _tapVisible(tester, 'novel-keep-screen-on');
    expect(latest.keepScreenOn, isFalse);
    await tester.runAsync(() async {
      await latest.save();
      final saved = await NovelReaderSettings.load();
      expect(saved.keepScreenOn, isFalse);
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('ignore blank paragraphs toggles and persists', (tester) async {
    var latest = const NovelReaderSettings();
    await _mount(tester, onChanged: (value) => latest = value);
    // 默认关闭；开关在排版区（段距滑块之后）。
    final toggle = find.byKey(const ValueKey('novel-ignore-blank-paragraphs'));
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await _tapVisible(tester, 'novel-ignore-blank-paragraphs');
    expect(latest.ignoreBlankParagraphs, isTrue);
    await tester.runAsync(() async {
      await latest.save();
      final saved = await NovelReaderSettings.load();
      expect(saved.ignoreBlankParagraphs, isTrue);
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('dense hint appears only when hiding blanks with tight spacing', (
    tester,
  ) async {
    Future<bool> hintVisible() async {
      final tile = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('novel-ignore-blank-paragraphs')),
      );
      return tile.subtitle != null;
    }

    // 关闭隐藏：无论段距多小都不提醒。
    await _mount(
      tester,
      settings: const NovelReaderSettings(paragraphSpacing: 4),
      onChanged: (_) {},
    );
    expect(await hintVisible(), isFalse);
    await _tapVisible(tester, 'novel-ignore-blank-paragraphs');
    // 开启隐藏且段距 < 20：出现提醒。
    expect(await hintVisible(), isTrue);
    expect(find.text('可以适当增大段距以免文字过于密集'), findsOneWidget);
    // 段距调到 20：提醒消失。
    final slider = find.byKey(const ValueKey('novel-paragraph-spacing'));
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    await tester.drag(slider, const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('novel-ignore-blank-paragraphs')),
          )
          .subtitle,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('focus mode reveals sliders and edits bounds and opacity', (
    tester,
  ) async {
    var latest = const NovelReaderSettings();
    await _mount(tester, onChanged: (value) => latest = value);
    final focusCard = find.byKey(const ValueKey('novel-focus-card'));
    final focusControls = find.descendant(
      of: focusCard,
      matching: find.byType(Slider),
    );
    expect(focusControls, findsNWidgets(3));
    expect(
      find.descendant(
        of: focusCard,
        matching: find.byKey(const ValueKey('novel-keep-screen-on')),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: focusCard,
        matching: find.byType(ReaderStatusSettingsSection),
      ),
      findsNothing,
    );
    final typographyCard = find.byKey(const ValueKey('novel-typography-card'));
    for (final key in [
      'novel-font-family',
      'novel-font-size',
      'novel-line-height',
      'novel-paragraph-spacing',
      'novel-content-width',
      'novel-ignore-blank-paragraphs',
    ]) {
      expect(
        find.descendant(
          of: typographyCard,
          matching: find.byKey(ValueKey(key)),
        ),
        findsOneWidget,
      );
    }
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('novel-keep-screen-on')),
        matching: find.byType(SettingsSection),
      ),
      findsOneWidget,
    );
    // 默认关闭且收起；开关与展开分别操作。
    expect(
      tester
          .widget<Switch>(find.byKey(const ValueKey('novel-focus-mode')))
          .value,
      isFalse,
    );
    expect(
      find.byKey(const ValueKey('novel-focus-top')).hitTestable(),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('novel-focus-bottom')).hitTestable(),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('novel-focus-opacity')).hitTestable(),
      findsNothing,
    );
    await _tapVisible(tester, 'novel-focus-mode');
    expect(latest.focusModeEnabled, isTrue);
    expect(find.byKey(const ValueKey('novel-focus-top')), findsOneWidget);
    expect(find.byKey(const ValueKey('novel-focus-bottom')), findsOneWidget);
    expect(find.byKey(const ValueKey('novel-focus-opacity')), findsOneWidget);
    expect(
      tester
          .widget<CollapsibleContent>(
            find.byKey(const ValueKey('novel-focus-details')),
          )
          .expanded,
      isFalse,
    );
    expect(
      find.byKey(const ValueKey('novel-focus-top')).hitTestable(),
      findsNothing,
    );
    await _tapVisible(tester, 'novel-focus-details-toggle');
    expect(
      tester
          .widget<CollapsibleContent>(
            find.byKey(const ValueKey('novel-focus-details')),
          )
          .expanded,
      isTrue,
    );
    // 两边界范围放开，浓度仍为 10%~90%；均为 1% 步进。
    final top = tester.widget<Slider>(
      find.byKey(const ValueKey('novel-focus-top')),
    );
    expect(top.min, 0.0);
    expect(top.max, 0.9);
    expect(top.divisions, 90);
    final bottom = tester.widget<Slider>(
      find.byKey(const ValueKey('novel-focus-bottom')),
    );
    expect(bottom.min, 0.1);
    expect(bottom.max, 1.0);
    expect(bottom.divisions, 90);
    final opacity = tester.widget<Slider>(
      find.byKey(const ValueKey('novel-focus-opacity')),
    );
    expect(opacity.min, 0.1);
    expect(opacity.max, 0.9);
    expect(opacity.divisions, 80);
    // 比例按百分比展示。
    expect(find.text('上边界 · 20%'), findsOneWidget);
    expect(find.text('下边界 · 55%'), findsOneWidget);
    expect(find.text('遮罩浓度 · 50%'), findsOneWidget);
    tester
        .widget<Slider>(find.byKey(const ValueKey('novel-focus-top')))
        .onChanged!(0.3);
    await tester.pumpAndSettle();
    expect(latest.focusTopRatio, 0.3);
    expect(find.text('上边界 · 30%'), findsOneWidget);
    tester
        .widget<Slider>(find.byKey(const ValueKey('novel-focus-bottom')))
        .onChanged!(0.65);
    tester
        .widget<Slider>(find.byKey(const ValueKey('novel-focus-opacity')))
        .onChanged!(0.7);
    await tester.pumpAndSettle();
    expect(latest.focusBottomRatio, 0.65);
    expect(latest.focusOpacity, 0.7);
    // 关闭开关不改变展开状态，数值仍保留。
    await _tapVisible(tester, 'novel-focus-mode');
    expect(latest.focusModeEnabled, isFalse);
    expect(
      tester
          .widget<CollapsibleContent>(
            find.byKey(const ValueKey('novel-focus-details')),
          )
          .expanded,
      isTrue,
    );
    expect(latest.focusTopRatio, 0.3);
    await tester.runAsync(() async {
      await latest.save();
      final saved = await NovelReaderSettings.load();
      expect(saved.focusTopRatio, 0.3);
      expect(saved.focusBottomRatio, 0.65);
      expect(saved.focusOpacity, 0.7);
      expect(saved.focusModeEnabled, isFalse);
    });
    expect(tester.takeException(), isNull);
  });

  for (final (locale, label, size, textScale, brightness, reduceMotion) in [
    (
      const Locale('zh'),
      '不遮挡状态组件',
      const Size(375, 812),
      1.0,
      Brightness.light,
      false,
    ),
    (
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      '不遮擋狀態元件',
      const Size(320, 850),
      2.0,
      Brightness.dark,
      true,
    ),
    (
      const Locale('zh'),
      '不遮挡状态组件',
      const Size(812, 375),
      1.0,
      Brightness.dark,
      true,
    ),
  ]) {
    testWidgets(
      'focus status switch follows the focus details at $size $locale',
      (tester) async {
        var latest = const NovelReaderSettings();
        await _mount(
          tester,
          settings: latest,
          onChanged: (value) => latest = value,
          size: size,
          textScale: textScale,
          locale: locale,
          systemBrightness: brightness,
          reduceMotion: reduceMotion,
        );
        final finder = find.byKey(
          const ValueKey('novel-focus-keep-status-visible'),
        );
        expect(finder.hitTestable(), findsNothing);
        await _tapVisible(tester, 'novel-focus-mode');
        expect(tester.widget<SwitchListTile>(finder).value, isFalse);
        expect(finder.hitTestable(), findsNothing);
        await _tapVisible(tester, 'novel-focus-details-toggle');
        await _tapVisible(tester, 'novel-focus-keep-status-visible');
        expect(find.text(label), findsOneWidget);
        expect(latest.focusKeepStatusVisible, isTrue);
        expect(tester.widget<SwitchListTile>(finder).value, isTrue);
        await _tapVisible(tester, 'novel-focus-mode');
        expect(finder, findsOneWidget);
        expect(latest.focusModeEnabled, isFalse);
        expect(latest.focusKeepStatusVisible, isTrue);
        await _tapVisible(tester, 'novel-focus-mode');
        expect(tester.widget<SwitchListTile>(finder).value, isTrue);
        await _tapVisible(tester, 'novel-focus-keep-status-visible');
        expect(latest.focusKeepStatusVisible, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('focus boundaries move each other to keep a ten percent gap', (
    tester,
  ) async {
    var latest = const NovelReaderSettings(focusModeEnabled: true);
    await _mount(
      tester,
      settings: latest,
      onChanged: (value) => latest = value,
    );
    await _tapVisible(tester, 'novel-focus-details-toggle');
    final top = find.byKey(const ValueKey('novel-focus-top'));
    final bottom = find.byKey(const ValueKey('novel-focus-bottom'));

    tester.widget<Slider>(top).onChanged!(0.9);
    await tester.pumpAndSettle();
    expect(latest.focusTopRatio, 0.9);
    expect(latest.focusBottomRatio, 1.0);
    expect(tester.widget<Slider>(bottom).value, 1.0);

    tester.widget<Slider>(bottom).onChanged!(0.1);
    await tester.pumpAndSettle();
    expect(latest.focusTopRatio, 0.0);
    expect(latest.focusBottomRatio, 0.1);
    expect(tester.widget<Slider>(top).value, 0.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'entering page mode silently disables focus and allows re-enabling',
    (tester) async {
      var latest = const NovelReaderSettings(focusModeEnabled: true);
      await _mount(
        tester,
        settings: latest,
        onChanged: (value) => latest = value,
      );
      await tester.tap(find.text('翻页'));
      await tester.pumpAndSettle();
      expect(latest.mode, NovelReaderMode.paged);
      expect(latest.focusModeEnabled, isFalse);
      expect(
        find.byKey(const ValueKey('novel-focus-top')).hitTestable(),
        findsNothing,
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SnackBar), findsNothing);

      await _tapVisible(tester, 'novel-focus-mode');
      expect(latest.focusModeEnabled, isTrue);
      expect(latest.mode, NovelReaderMode.paged);
      expect(find.byKey(const ValueKey('novel-focus-top')), findsOneWidget);
      await _tapVisible(tester, 'novel-focus-details-toggle');
      tester
          .widget<Slider>(find.byKey(const ValueKey('novel-focus-top')))
          .onChanged!(0.4);
      await tester.pumpAndSettle();
      expect(latest.focusModeEnabled, isTrue);
      expect(latest.focusTopRatio, 0.4);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('focus details default collapsed and retain edits when toggled', (
    tester,
  ) async {
    var latest = const NovelReaderSettings(focusModeEnabled: true);
    await _mount(
      tester,
      settings: latest,
      onChanged: (value) => latest = value,
    );
    final details = find.byKey(const ValueKey('novel-focus-details'));
    expect(tester.widget<CollapsibleContent>(details).expanded, isFalse);
    final title = find.text('专注模式');
    await tester.ensureVisible(title);
    await tester.pumpAndSettle();
    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(tester.widget<CollapsibleContent>(details).expanded, isTrue);
    expect(latest.focusModeEnabled, isTrue);
    tester
        .widget<Slider>(find.byKey(const ValueKey('novel-focus-top')))
        .onChanged!(0.4);
    await tester.pumpAndSettle();
    await _tapVisible(tester, 'novel-focus-details-toggle');
    expect(tester.widget<CollapsibleContent>(details).expanded, isFalse);
    expect(latest.focusTopRatio, 0.4);
    expect(latest.focusModeEnabled, isTrue);
    await _tapVisible(tester, 'novel-focus-mode');
    expect(tester.widget<CollapsibleContent>(details).expanded, isFalse);
    await _tapVisible(tester, 'novel-focus-mode');
    expect(tester.widget<CollapsibleContent>(details).expanded, isFalse);
    expect(latest.focusTopRatio, 0.4);
    expect(tester.takeException(), isNull);
  });

  for (final key in [
    'novel-focus-top',
    'novel-focus-bottom',
    'novel-focus-opacity',
  ]) {
    testWidgets('dragging $key fades out the whole sheet', (tester) async {
      var latest = const NovelReaderSettings(focusModeEnabled: true);
      final dragPreview = ValueNotifier<bool>(false);
      addTearDown(dragPreview.dispose);
      await _mount(
        tester,
        settings: latest,
        dragPreview: dragPreview,
        onChanged: (value) => latest = value,
      );
      await _tapVisible(tester, 'novel-focus-details-toggle');
      final slider = find.byKey(ValueKey(key));
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      final fade = find.byKey(const ValueKey('app-sheet-fade'));
      expect(tester.widget<AnimatedOpacity>(fade).opacity, 1);

      final gesture = await tester.startGesture(tester.getCenter(slider));
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      expect(dragPreview.value, isTrue);
      expect(tester.widget<AnimatedOpacity>(fade).opacity, 0);
      // 面板整体淡出（含底色与设置文本），不是只隐藏文字。
      expect(
        find.descendant(of: fade, matching: find.text('阅读设置')),
        findsOneWidget,
      );
      // 淡出期间滑块仍可继续拖动并更新设置。
      final before = {
        'novel-focus-top': latest.focusTopRatio,
        'novel-focus-bottom': latest.focusBottomRatio,
        'novel-focus-opacity': latest.focusOpacity,
      }[key];
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      final after = {
        'novel-focus-top': latest.focusTopRatio,
        'novel-focus-bottom': latest.focusBottomRatio,
        'novel-focus-opacity': latest.focusOpacity,
      }[key];
      expect(after, isNot(before));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(dragPreview.value, isFalse);
      expect(tester.widget<AnimatedOpacity>(fade).opacity, 1);
      expect(latest.focusModeEnabled, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reading mode switch reveals and edits page-turn settings', (
    tester,
  ) async {
    var latest = const NovelReaderSettings();
    await _mount(tester, onChanged: (value) => latest = value);
    // 滚动模式下不显示翻页分组。
    expect(find.byKey(const ValueKey('novel-volume-key')), findsNothing);
    expect(
      find.byKey(const ValueKey('novel-realistic-page-turn')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('novel-instant-page-turn')), findsNothing);
    await tester.tap(find.text('翻页'));
    await tester.pumpAndSettle();
    expect(latest.mode, NovelReaderMode.paged);
    expect(
      find.byKey(const ValueKey('novel-volume-key')).hitTestable(),
      findsNothing,
    );
    await _toggleFold(tester, 'novel-page-turn-settings');
    // 排版和配色在前，翻页细调展开后不改变参数与原有回调。
    final fontTop = tester
        .getTopLeft(find.byKey(const ValueKey('novel-font-size')))
        .dy;
    final volumeTop = tester
        .getTopLeft(find.byKey(const ValueKey('novel-volume-key')))
        .dy;
    final realisticTop = tester
        .getTopLeft(find.byKey(const ValueKey('novel-realistic-page-turn')))
        .dy;
    final instantTop = tester
        .getTopLeft(find.byKey(const ValueKey('novel-instant-page-turn')))
        .dy;
    expect(volumeTop, greaterThan(fontTop));
    expect(realisticTop, greaterThan(volumeTop));
    expect(instantTop, greaterThan(realisticTop));
    // 翻页设置默认值：音量键与仿真翻页开启、无动画关闭。
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('novel-volume-key')),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('novel-realistic-page-turn')),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('novel-instant-page-turn')),
          )
          .value,
      isFalse,
    );
    await _tapVisible(tester, 'novel-volume-key');
    expect(latest.volumeKey, isFalse);
    await _tapVisible(tester, 'novel-realistic-page-turn');
    expect(latest.realisticPageTurn, isFalse);
    await _tapVisible(tester, 'novel-instant-page-turn');
    expect(latest.instantPageTurn, isTrue);
    expect(latest.realisticPageTurn, isFalse);
    // 切回滚动模式后翻页分组收起，已改的开关值仍保留。
    final modeButton = find.byKey(const ValueKey('novel-reader-mode'));
    await tester.ensureVisible(modeButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('滚动'));
    await tester.pumpAndSettle();
    expect(latest.mode, NovelReaderMode.scroll);
    expect(latest.volumeKey, isFalse);
    expect(latest.realisticPageTurn, isFalse);
    expect(latest.instantPageTurn, isTrue);
    expect(
      find.byKey(const ValueKey('novel-realistic-page-turn')),
      findsNothing,
    );
    // 切回翻页后仍保持关闭，可重新开启；不改动无动画偏好。
    await tester.tap(find.text('翻页'));
    await tester.pumpAndSettle();
    await _toggleFold(tester, 'novel-page-turn-settings');
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('novel-realistic-page-turn')),
          )
          .value,
      isFalse,
    );
    await _tapVisible(tester, 'novel-realistic-page-turn');
    expect(latest.realisticPageTurn, isTrue);
    expect(latest.instantPageTurn, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'novel settings use their own status settings and support first-to-last drag',
    (tester) async {
      var latest = const NovelReaderSettings();
      await _mount(tester, onChanged: (value) => latest = value);
      expect(find.byType(ReaderStatusSettingsSection), findsOneWidget);
      await _tapVisible(tester, 'reader-status-overlay-switch');
      final novelStatus = NovelReaderStatusSettings();
      expect(novelStatus.statusOverlay, isTrue);
      // 独立配置：漫画侧不被联动改动。
      expect(ReaderSettings().statusOverlay, isFalse);
      await _tapVisible(tester, 'reader-status-details-toggle');
      await tester.ensureVisible(find.byType(ReorderableListView));
      await tester.pumpAndSettle();
      final handles = find.byType(ReorderableDragStartListener);
      final target = tester.getCenter(handles.last) + const Offset(0, 100);
      final gesture = await tester.startGesture(
        tester.getCenter(handles.first),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesture.moveTo(target);
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.moveBy(const Offset(0, 1));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      const expected = ['time', 'network', 'battery', 'page', 'fps', 'chapter'];
      expect(novelStatus.statusOverlayOrder, expected);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('novel_status_overlay_order'), expected);
      expect(
        prefs.getStringList('reader_status_overlay_order'),
        isNot(expected),
      );
      expect(latest.fontSize, const NovelReaderSettings().fontSize);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('folded page-turn settings preserve edits and persist them', (
    tester,
  ) async {
    var latest = const NovelReaderSettings(mode: NovelReaderMode.paged);
    await _mount(
      tester,
      settings: latest,
      onChanged: (value) => latest = value,
      reduceMotion: true,
    );
    expect(find.byType(ReaderSettingsFold), findsOneWidget);
    expect(
      find.byKey(const ValueKey('novel-volume-key')).hitTestable(),
      findsNothing,
    );
    await _toggleFold(tester, 'novel-page-turn-settings');
    await _tapVisible(tester, 'novel-volume-key');
    expect(latest.volumeKey, isFalse);
    await _toggleFold(tester, 'novel-page-turn-settings');
    expect(
      find.byKey(const ValueKey('novel-volume-key')).hitTestable(),
      findsNothing,
    );
    await _toggleFold(tester, 'novel-page-turn-settings');
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('novel-volume-key')),
          )
          .value,
      isFalse,
    );
    await tester.runAsync(() async {
      await latest.save();
      expect((await NovelReaderSettings.load()).volumeKey, isFalse);
    });
    expect(tester.takeException(), isNull);
  });

  for (final locale in [
    const Locale('zh'),
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ]) {
    testWidgets(
      'settings remain scrollable at 320px and 2x text scale (${locale.toLanguageTag()})',
      (tester) async {
        var latest = const NovelReaderSettings(
          fontSize: 48,
          lineHeight: 3.0,
          paragraphSpacing: 64,
          mode: NovelReaderMode.paged,
        );
        await _mount(
          tester,
          settings: latest,
          onChanged: (value) => latest = value,
          size: const Size(320, 640),
          textScale: 2,
          locale: locale,
        );
        await _toggleFold(tester, 'novel-page-turn-settings');
        final realisticTile = find.byKey(
          const ValueKey('novel-realistic-page-turn'),
        );
        final label = locale.scriptCode == 'Hant' ? '仿真翻頁' : '仿真翻页';
        expect(
          find.descendant(of: realisticTile, matching: find.text(label)),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        for (final key in [
          'novel-volume-key',
          'novel-realistic-page-turn',
          'novel-instant-page-turn',
          'novel-theme-settings-entry',
          'novel-keep-screen-on',
          'reader-status-overlay-switch',
        ]) {
          final finder = find.byKey(ValueKey(key));
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          expect(finder, findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        await _openTheme(tester, dark: false);
        await _toggleFold(tester, 'novel-custom-theme-settings');
        await tester.ensureVisible(
          find.byKey(const ValueKey('novel-theme-add')),
        );
        await tester.pumpAndSettle();
        await _tapVisible(tester, 'novel-dialogue-enabled');
        for (final key in [
          'novel-dialogue-color-mode',
          'novel-dialogue-weight',
          'novel-dialogue-background-enabled',
        ]) {
          final control = find.byKey(ValueKey(key));
          await tester.ensureVisible(control);
          await tester.pumpAndSettle();
          expect(control.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        final backgroundToggle = find.byKey(
          const ValueKey('novel-dialogue-background-enabled'),
        );
        await tester.ensureVisible(backgroundToggle);
        tester.widget<SwitchListTile>(backgroundToggle).onChanged!(true);
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('novel-dialogue-background-opacity')),
        );
        await tester.pumpAndSettle();
        for (final dark in [false, true]) {
          await _openTheme(tester, dark: dark);
          final tile = find.byKey(
            ValueKey(dark ? 'novel-dark-theme' : 'novel-light-theme'),
          );
          await tester.ensureVisible(tile);
          await tester.pumpAndSettle();
          expect(tile, findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
