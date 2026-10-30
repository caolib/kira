import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/novel.dart';
import 'package:kira/models/novel_dialogue_style.dart';
import 'package:kira/models/novel_reader_settings.dart';
import 'package:kira/pages/novel_reader/novel_reader_dialogue.dart';
import 'package:kira/pages/novel_reader/novel_reader_document.dart';
import 'package:kira/pages/novel_reader/novel_reader_page_view.dart';
import 'package:kira/pages/novel_reader/novel_reader_paginator.dart';
import 'package:kira/pages/novel_reader/novel_reader_viewport.dart';
import 'package:kira/theme/novel_reader_theme.dart';

import '../test_helpers.dart';

NovelReaderEntry _entry(List<String> paragraphs) => NovelReaderEntry(
  entryIndex: 0,
  entry: const NovelContentEntry(name: '', contentType: 1),
  paragraphs: paragraphs,
);

const _baseStyle = TextStyle(fontSize: 20, height: 1.8);

NovelDialoguePresentation _presentation({FontWeight? weight}) =>
    NovelDialoguePresentation(
      foreground: const Color(0xFF476B83),
      background: const Color(0x207D94B0),
      fontWeight: weight,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(setupSecureCredentialStoreForTest);
  tearDown(teardownSecureCredentialStoreForTest);

  for (final paged in [false, true]) {
    testWidgets(
      'dialogue is styled without changing text in ${paged ? 'paged' : 'scroll'} mode',
      (tester) async {
        final entry = _entry(['旁白「你好『引用』再见」结束。']);
        final document = NovelReaderDocument([entry]);
        final key = GlobalKey();
        Widget view(NovelReaderSettings settings) {
          final palette = NovelReaderPalette.resolve(
            settings,
            Brightness.light,
          );
          return wrapWithApp(
            paged
                ? NovelReaderPageView(
                    key: key,
                    document: document,
                    settings: settings,
                    palette: palette,
                    target: const NovelReaderAnchor(entryIndex: 0),
                    jumpRevision: 0,
                    emptyChapterText: '空',
                    contentPadding: EdgeInsets.zero,
                    onPosition: (_) {},
                    toolbarVisible: false,
                    onTap: () {},
                  )
                : NovelReaderViewport(
                    key: key,
                    document: document,
                    settings: settings,
                    palette: palette,
                    target: const NovelReaderAnchor(entryIndex: 0),
                    jumpRevision: 0,
                    onPosition: (_) {},
                    onTap: () {},
                  ),
          );
        }

        const enabled = NovelReaderSettings(dialogueEnabled: true);
        await tester.pumpWidget(view(enabled));
        await tester.pumpAndSettle();
        final styled = find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.textSpan?.toPlainText() == entry.paragraphs.single,
        );
        expect(styled, findsOneWidget);
        final rich = tester.widget<Text>(styled);
        expect(rich.textSpan, isNotNull);
        await tester.pumpWidget(view(const NovelReaderSettings()));
        await tester.pumpAndSettle();
        expect(find.text(entry.paragraphs.single), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

  test('dialogue fill adds vertical padding without changing text width', () {
    for (final height in [10.0, 20.0, 48.0, 96.0]) {
      final glyph = Rect.fromLTWH(12, 24, 100, height);
      final fill = novelDialogueBackgroundRect(glyph);
      expect(fill.left, glyph.left);
      expect(fill.right, glyph.right);
      expect(glyph.top - fill.top, inInclusiveRange(2.0, 4.0));
      expect(fill.bottom - glyph.bottom, glyph.top - fill.top);
      expect(fill.contains(glyph.topLeft), isTrue);
      expect(fill.height, greaterThan(glyph.height));
    }
  });

  test('wrapped dialogue fill may meet without removing paragraph spacing', () {
    final first = novelDialogueBackgroundRect(
      const Rect.fromLTWH(0, 0, 100, 20),
    );
    final wrapped = novelDialogueBackgroundRect(
      const Rect.fromLTWH(0, 20, 60, 20),
    );
    final nextParagraph = novelDialogueBackgroundRect(
      const Rect.fromLTWH(0, 36, 60, 20),
    );
    expect(first.overlaps(wrapped), isTrue);
    expect(first.overlaps(nextParagraph), isFalse);
  });

  testWidgets('preview uses real paragraph spacing with rounded fill', (
    tester,
  ) async {
    final presentation = _presentation();
    final count = novelDialogueCache.parsedChapters;
    await tester.pumpWidget(
      wrapWithApp(
        NovelDialogueText.preview(
          text: '「第一句」\n『第二句』',
          baseStyle: _baseStyle,
          dialogue: presentation,
          paragraphSpacing: 16,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final first = find.byWidgetPredicate(
      (widget) => widget is Text && widget.textSpan?.toPlainText() == '「第一句」',
    );
    final second = find.byWidgetPredicate(
      (widget) => widget is Text && widget.textSpan?.toPlainText() == '『第二句』',
    );
    expect(
      tester.getTopLeft(second).dy - tester.getBottomLeft(first).dy,
      closeTo(16, 0.01),
    );
    final span = tester.widget<Text>(first).textSpan;
    expect(span, isA<TextSpan>());
    if (span is TextSpan) {
      expect(span.children!.single.style!.backgroundColor, isNull);
    }
    expect(novelDialogueCache.parsedChapters, count);
    expect(tester.takeException(), isNull);
  });

  test('only corner quotes match; nested pairs share merged ranges', () {
    final cache = NovelDialogueCache();
    final entry = _entry(['旁白「你好『引用』再见」，“不变” "不变"。']);
    final paragraph = cache.paragraph(NovelReaderParagraph(entry, 0));
    expect(paragraph.ranges, hasLength(1));
    final range = paragraph.ranges.single;
    expect(paragraph.text.substring(range.start, range.end), '「你好『引用』再见」');
    expect(paragraph.text, entry.paragraphs.single);
    expect(entry.paragraphs.single, '旁白「你好『引用』再见」，“不变” "不变"。');
  });

  test('pairs cross paragraphs but never cross chapters', () async {
    final cache = NovelDialogueCache();
    final entry = _entry(['旁白「第一行', '', '第二行」结束']);
    final orphan = _entry(['「缺少结尾']);
    final other = _entry(['只有结尾」']);
    await cache.prepare([entry, orphan, other]);
    expect(
      cache.paragraph(NovelReaderParagraph(entry, 0)).ranges.single.start,
      2,
    );
    final ending = cache.paragraph(NovelReaderParagraph(entry, 2));
    expect(ending.text.substring(0, ending.ranges.single.end), '第二行」');
    expect(ending.text, '第二行」结束');
    expect(cache.paragraph(NovelReaderParagraph(orphan, 0)).ranges, isEmpty);
    expect(cache.paragraph(NovelReaderParagraph(other, 0)).ranges, isEmpty);
  });

  test('orphan outer quotes remain; complete inner quotes still match', () {
    final cache = NovelDialogueCache();
    final entry = _entry(['「没闭合，但『内部完整』。']);
    final paragraph = cache.paragraph(NovelReaderParagraph(entry, 0));
    expect(paragraph.ranges, hasLength(1));
    final range = paragraph.ranges.single;
    expect(paragraph.text.substring(range.start, range.end), '『内部完整』');
    expect(paragraph.text, entry.paragraphs.single);
  });

  test(
    'cache survives settings changes and source document rebuilds',
    () async {
      final cache = NovelDialogueCache();
      final entry = _entry(['「缓存」', '', '『继续』']);
      await Future.wait([
        cache.prepare([entry]),
        cache.prepare([entry]),
      ]);
      final first = cache.paragraph(NovelReaderParagraph(entry, 0));
      final rebuilt = NovelReaderDocument([entry], ignoreBlankParagraphs: true);
      expect(identical(first, cache.paragraph(rebuilt.paragraphAt(0))), isTrue);
      expect(cache.parsedChapters, 1);
    },
  );

  test(
    'page fragments retain dialogue styling without their opening quote',
    () {
      final cache = NovelDialogueCache();
      final entry = _entry(['旁白「一二三四五六七八」结尾']);
      final paragraph = cache.paragraph(NovelReaderParagraph(entry, 0));
      final span = paragraph.span(
        baseStyle: _baseStyle,
        dialogue: _presentation(),
        start: 5,
        end: 9,
      );
      expect(span.toPlainText(), entry.paragraphs.single.substring(5, 9));
      expect(span.children!.single.style!.color, _presentation().foreground);
    },
  );

  test('disabled dialogue bypasses parsing and preserves source text', () {
    final entry = _entry(['「原文」']);
    final paragraph = NovelReaderParagraph(entry, 0);
    final count = novelDialogueCache.parsedChapters;
    expect(novelParagraphDialogue(paragraph, null), isNull);
    expect(novelParagraphDisplayText(paragraph, '空'), '「原文」');
    expect(novelDialogueCache.parsedChapters, count);
  });

  test(
    'default dialogue follows body with ten percent light and dark fills',
    () {
      const settings = NovelReaderSettings(dialogueEnabled: true);
      for (final dark in [false, true]) {
        final foreground = dark
            ? const Color(0xFFE5DEC1)
            : const Color(0xFF302A22);
        final presentation = resolveNovelDialoguePresentation(
          settings,
          dark: dark,
          foreground: foreground,
          background: dark ? const Color(0xFF222222) : const Color(0xFFFFFFFF),
        )!;
        expect(presentation.foreground, foreground);
        expect(presentation.fontWeight, isNull);
        expect(
          presentation.background,
          (dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000)).withValues(
            alpha: 0.1,
          ),
        );
      }
    },
  );

  test('automatic colors contrast with both reading backgrounds', () {
    const automatic = NovelDialogueStyle(
      colorMode: NovelDialogueColorMode.automatic,
      backgroundEnabled: false,
    );
    const settings = NovelReaderSettings(
      dialogueEnabled: true,
      lightDialogueStyle: automatic,
      darkDialogueStyle: automatic,
    );
    for (final background in [
      const Color(0xFFFFFFFF),
      const Color(0xFF222222),
      const Color(0xFFF3EEDC),
      const Color(0xFF777777),
    ]) {
      final presentation = resolveNovelDialoguePresentation(
        settings,
        dark: background.computeLuminance() < 0.179,
        foreground: const Color(0xFF212121),
        background: background,
      )!;
      final a = presentation.foreground.computeLuminance();
      final b = background.computeLuminance();
      final contrast = a > b
          ? (a + 0.05) / (b + 0.05)
          : (b + 0.05) / (a + 0.05);
      expect(contrast, greaterThanOrEqualTo(4.5));
    }
  });

  test('paint-only preferences do not change the pagination layout key', () {
    const settings = NovelReaderSettings(dialogueEnabled: true);
    NovelDialoguePresentation resolve(NovelReaderSettings value) =>
        resolveNovelDialoguePresentation(
          value,
          dark: false,
          foreground: const Color(0xFF212121),
          background: const Color(0xFFFFFFFF),
        )!;
    final paintChange = settings.copyWith(
      lightDialogueStyle: const NovelDialogueStyle(
        colorMode: NovelDialogueColorMode.custom,
        textColor: 0xFF673AB7,
        backgroundOpacity: 0.3,
      ),
    );
    expect(resolve(settings).layoutKey, resolve(paintChange).layoutKey);
    expect(
      resolve(
        settings.copyWith(
          lightDialogueStyle: const NovelDialogueStyle(
            weight: NovelDialogueWeight.bold,
          ),
        ),
      ).layoutKey,
      isNot(resolve(settings).layoutKey),
    );
  });

  test('bold spans share paginator text offsets without losing quotes', () {
    final entry = _entry(['旁白「${'长对白『嵌套』' * 80}」收尾']);
    final document = NovelReaderDocument([entry]);
    final presentation = _presentation(weight: FontWeight.w700);
    final paginator = NovelReaderPaginator(
      document: document,
      spec: NovelPaginationSpec(
        textStyle: _baseStyle,
        titleStyle: const TextStyle(fontSize: 24),
        textScaler: TextScaler.noScaling,
        textDirection: TextDirection.ltr,
        size: const Size(240, 180),
        viewportHeight: 180,
        contentTopInset: 0,
        paragraphSpacing: 16,
        titleSpacing: 24,
        emptyChapterText: '空',
        dialogue: presentation,
      ),
    );
    while (paginator.buildMore()) {}
    final display = novelParagraphDialogue(
      document.paragraphAt(0),
      presentation,
    )!;
    final result = StringBuffer();
    var previous = 0;
    for (final page in paginator.pages) {
      for (final slice in page.slices) {
        expect(slice.startOffset, previous);
        final span = display.span(
          baseStyle: _baseStyle,
          dialogue: presentation,
          start: slice.startOffset,
          end: slice.endOffset,
        );
        result.write(span.toPlainText());
        previous = slice.endOffset;
      }
    }
    expect(paginator.pages.length, greaterThan(1));
    expect(result.toString(), display.text);
    expect(result.toString(), entry.paragraphs.single);
  });

  test('empty matched quote still keeps its punctuation', () {
    final paragraph = NovelReaderParagraph(_entry(['「」']), 0);
    final display = novelParagraphDialogue(paragraph, _presentation())!;
    expect(display.text, '「」');
    expect(display.ranges, hasLength(1));
  });
}
