import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/api/novel/novel_text.dart';
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
        final entry = _entry(['旁白「你好『引用』再见」“再会”结束。']);
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

        const enabled = NovelReaderSettings();
        await tester.pumpWidget(view(enabled));
        await tester.pumpAndSettle();
        final styled = find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.textSpan?.toPlainText() == entry.paragraphs.single,
        );
        expect(styled, findsOneWidget);
        List<String?> styledParts() {
          final span = tester.widget<Text>(styled).textSpan! as TextSpan;
          return [
            for (final part in span.children!.whereType<TextSpan>())
              if (part.style != null) part.text,
          ];
        }

        expect(styledParts(), ['「你好『引用』再见」']);
        final quotes = NovelDialogueQuotes.none.withQuote(
          NovelDialogueQuote.curlyDouble,
          true,
        );
        await tester.pumpWidget(view(enabled.copyWith(dialogueQuotes: quotes)));
        await tester.pumpAndSettle();
        expect(styledParts(), ['“再会”']);
        await tester.pumpWidget(
          view(const NovelReaderSettings(dialogueEnabled: false)),
        );
        await tester.pumpAndSettle();
        expect(find.text(entry.paragraphs.single), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('decoded characters keep a continuous fill across text runs', (
    tester,
  ) async {
    final content = NovelText.parse(
      const NovelVolumeDetail(
        book: NovelBook(pathWord: 'book', name: '书名'),
        volume: NovelVolume(
          id: 'v1',
          name: '第一卷',
          contents: [
            NovelContentEntry(name: '正文', contentType: 1, endLines: 1),
          ],
        ),
      ),
      '「文本&#16034;&#15970;文本」',
    );
    final paragraph = NovelDialogueCache().paragraph(
      NovelReaderParagraph(content.entries.single, 0),
    );
    expect(paragraph.text, '「文本㺢㹢文本」');
    expect(paragraph.ranges, hasLength(1));
    final presentation = _presentation();
    await tester.pumpWidget(
      wrapWithApp(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 500,
            child: NovelDialogueText(
              paragraph: paragraph,
              baseStyle: _baseStyle,
              dialogue: presentation,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final renderParagraph = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byType(NovelDialogueText),
        matching: find.byType(RichText),
      ),
    );
    // Test fonts do not reproduce device-specific fallback. Force three runs
    // with different metrics, as fallback fonts can do, without changing text.
    renderParagraph.text = const TextSpan(
      style: _baseStyle,
      children: [
        TextSpan(text: '「文本'),
        TextSpan(text: '㺢㹢', style: TextStyle(fontSize: 24)),
        TextSpan(text: '文本」'),
      ],
    );
    await tester.pump();
    final boxes = renderParagraph.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: paragraph.text.length),
      boxHeightStyle: ui.BoxHeightStyle.max,
    );
    expect(boxes.length, greaterThanOrEqualTo(3));
    final bounds = boxes
        .map((box) => box.toRect())
        .reduce((a, b) => a.expandToInclude(b));
    final fill = novelDialogueBackgroundRect(bounds);
    final background = tester.renderObject(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_DialogueBackground',
      ),
    );
    expect(
      background,
      paints..path(
        color: presentation.background,
        includes: [
          Offset(boxes[0].right, fill.top + 0.2),
          Offset(boxes[1].right, fill.top + 0.2),
        ],
        excludes: [Offset(fill.left + 0.1, fill.top + 0.1)],
      ),
    );
    expect(renderParagraph.text.toPlainText(), paragraph.text);
    expect(tester.takeException(), isNull);
  });

  for (final text in [
    '「123」456',
    '456「123」',
    '456「123」789',
    '前「中文」后',
    'אב「123」גד',
  ]) {
    for (final direction in TextDirection.values) {
      testWidgets('inline fill excludes narration in $text $direction', (
        tester,
      ) async {
        final paragraph = NovelDialogueCache().paragraph(
          NovelReaderParagraph(_entry([text]), 0),
        );
        final presentation = _presentation();
        Widget view(bool withFill) => wrapWithApp(
          Directionality(
            textDirection: direction,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 400,
                child: NovelDialogueText(
                  paragraph: paragraph,
                  baseStyle: _baseStyle,
                  dialogue: NovelDialoguePresentation(
                    foreground: presentation.foreground,
                    background: withFill ? presentation.background : null,
                    fontWeight: presentation.fontWeight,
                  ),
                ),
              ),
            ),
          ),
        );
        RenderParagraph renderParagraph() =>
            tester.renderObject<RenderParagraph>(
              find.descendant(
                of: find.byType(NovelDialogueText),
                matching: find.byType(RichText),
              ),
            );
        List<Rect> boundsFor(RenderParagraph render, int start, int end) =>
            novelDialogueBackgroundRuns(
              render.getBoxesForSelection(
                TextSelection(baseOffset: start, extentOffset: end),
                boxHeightStyle: ui.BoxHeightStyle.max,
              ),
            );

        await tester.pumpWidget(view(false));
        await tester.pumpAndSettle();
        final sizeBefore = renderParagraph().size;
        final boxesBefore = boundsFor(renderParagraph(), 0, text.length);

        await tester.pumpWidget(view(true));
        await tester.pumpAndSettle();
        final render = renderParagraph();
        expect(render.size, sizeBefore);
        expect(boundsFor(render, 0, text.length), boxesBefore);
        final range = paragraph.ranges.single;
        final narration = [
          if (range.start > 0) ...boundsFor(render, 0, range.start),
          if (range.end < text.length)
            ...boundsFor(render, range.end, text.length),
        ];
        expect(narration, isNotEmpty);
        expect(
          tester.renderObject(
            find.byWidgetPredicate(
              (widget) =>
                  widget.runtimeType.toString() == '_DialogueBackground',
            ),
          ),
          paints..path(
            color: presentation.background,
            includes: [
              for (final run in boundsFor(render, range.start, range.end))
                run.center,
            ],
            excludes: [
              for (final run in narration) ...[
                Offset(run.left + 0.25, run.center.dy),
                Offset(run.right - 0.25, run.center.dy),
                Offset(run.left - 1, run.center.dy),
                Offset(run.right + 1, run.center.dy),
              ],
            ],
          ),
        );
        expect(render.text.toPlainText(), text);
        expect(tester.takeException(), isNull);
      });
    }
  }

  test('dialogue fill adds equal padding on all four sides', () {
    for (final height in [10.0, 20.0, 48.0, 96.0]) {
      final glyph = Rect.fromLTWH(12, 24, 100, height);
      final fill = novelDialogueBackgroundRect(glyph);
      final padding = glyph.top - fill.top;
      expect(padding, inInclusiveRange(2.0, 4.0));
      expect(glyph.left - fill.left, closeTo(padding, 0.001));
      expect(fill.right - glyph.right, closeTo(padding, 0.001));
      expect(fill.bottom - glyph.bottom, closeTo(padding, 0.001));
      expect(fill.contains(glyph.topLeft), isTrue);
      expect(fill.height, greaterThan(glyph.height));
    }
  });

  test('inline padding leaves a gap on both sides of narration', () {
    const glyph = Rect.fromLTRB(20, 10, 100, 30);
    for (final whitespace in [0.0, 1.0, 4.0]) {
      final fill = novelDialogueBackgroundRect(
        glyph,
        narrationBounds: [
          Rect.fromLTRB(0, 10, glyph.left - whitespace, 30),
          Rect.fromLTRB(glyph.right + whitespace, 10, 120, 30),
        ],
      );
      expect(fill.left, glyph.left - whitespace + 2);
      expect(fill.right, glyph.right + whitespace - 2);
      expect(fill.top, lessThan(glyph.top));
      expect(fill.bottom, greaterThan(glyph.bottom));
    }
  });

  test('narrow visual runs retain a nonempty fill between narration', () {
    const glyph = Rect.fromLTRB(20, 10, 22, 30);
    final fill = novelDialogueBackgroundRect(
      glyph,
      narrationBounds: const [
        Rect.fromLTRB(0, 10, 20, 30),
        Rect.fromLTRB(22, 10, 40, 30),
      ],
    );
    expect(fill.left, greaterThan(glyph.left));
    expect(fill.right, lessThan(glyph.right));
    expect(fill.width, 1);
    expect(fill.isEmpty, isFalse);
  });

  test('narration on other lines does not remove wrap-edge padding', () {
    const glyph = Rect.fromLTRB(20, 30, 100, 50);
    expect(
      novelDialogueBackgroundRect(
        glyph,
        narrationBounds: const [
          Rect.fromLTRB(0, 10, 20, 30),
          Rect.fromLTRB(100, 50, 120, 70),
        ],
      ),
      novelDialogueBackgroundRect(glyph),
    );
  });

  for (final width in [240.0, 400.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'wrapped fill pads both ends without reflow at width $width scale $scale',
        (tester) async {
          final text = '「${'一二三四五六七八九十' * 3}」';
          final paragraph = NovelDialogueCache().paragraph(
            NovelReaderParagraph(_entry([text]), 0),
          );
          final presentation = _presentation();
          Widget view(bool withFill) => wrapWithApp(
            Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: width,
                  child: NovelDialogueText(
                    paragraph: paragraph,
                    baseStyle: _baseStyle,
                    textScaler: TextScaler.linear(scale),
                    dialogue: NovelDialoguePresentation(
                      foreground: presentation.foreground,
                      background: withFill ? presentation.background : null,
                      fontWeight: presentation.fontWeight,
                    ),
                  ),
                ),
              ),
            ),
          );
          RenderParagraph renderParagraph() =>
              tester.renderObject<RenderParagraph>(
                find.descendant(
                  of: find.byType(NovelDialogueText),
                  matching: find.byType(RichText),
                ),
              );
          List<Rect> glyphRuns(RenderParagraph render) =>
              novelDialogueBackgroundRuns(
                render.getBoxesForSelection(
                  TextSelection(baseOffset: 0, extentOffset: text.length),
                  boxHeightStyle: ui.BoxHeightStyle.max,
                ),
              );

          await tester.pumpWidget(view(false));
          await tester.pumpAndSettle();
          final sizeBefore = renderParagraph().size;
          final runsBefore = glyphRuns(renderParagraph());
          expect(runsBefore.length, greaterThan(1));
          final positionBefore = renderParagraph().localToGlobal(Offset.zero);

          await tester.pumpWidget(view(true));
          await tester.pumpAndSettle();
          final render = renderParagraph();
          final runs = glyphRuns(render);
          expect(render.size, sizeBefore);
          expect(render.localToGlobal(Offset.zero), positionBefore);
          expect(runs, runsBefore);
          expect(render.text.toPlainText(), text);
          final background = tester.renderObject<RenderBox>(
            find.byWidgetPredicate(
              (widget) =>
                  widget.runtimeType.toString() == '_DialogueBackground',
            ),
          );
          final paddedPoints = [
            for (final run in runs) ...[
              Offset(run.left - 1, run.center.dy),
              Offset(run.right + 1, run.center.dy),
            ],
          ];
          expect(
            background,
            paints..path(
              color: presentation.background,
              includes: paddedPoints,
              excludes: [
                for (final run in runs) ...[
                  Offset(run.left - 5, run.center.dy),
                  Offset(run.right + 5, run.center.dy),
                ],
              ],
            ),
          );
          for (final point in paddedPoints) {
            expect(background.paintBounds.contains(point), isTrue);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  test('background joins touching runs in visual order, including RTL', () {
    final runs = novelDialogueBackgroundRuns(const [
      ui.TextBox.fromLTRBD(60, 10, 100, 30, TextDirection.ltr),
      ui.TextBox.fromLTRBD(40, 10, 60, 30, TextDirection.rtl),
      ui.TextBox.fromLTRBD(0, 10, 40, 30, TextDirection.ltr),
      ui.TextBox.fromLTRBD(100, 10, 100, 30, TextDirection.ltr),
    ]);
    expect(runs, [const Rect.fromLTRB(0, 10, 100, 30)]);
  });

  test('background preserves gaps and separate wrapped lines', () {
    final runs = novelDialogueBackgroundRuns(const [
      ui.TextBox.fromLTRBD(0, 0, 40, 20, TextDirection.ltr),
      ui.TextBox.fromLTRBD(60, 0, 100, 20, TextDirection.rtl),
      ui.TextBox.fromLTRBD(0, 18, 60, 38, TextDirection.ltr),
      ui.TextBox.fromLTRBD(60, 18, 90, 38, TextDirection.ltr),
    ]);
    expect(runs, [
      const Rect.fromLTRB(0, 0, 40, 20),
      const Rect.fromLTRB(60, 0, 100, 20),
      const Rect.fromLTRB(0, 18, 90, 38),
    ]);
    expect(novelDialogueBackgroundRuns(const []), isEmpty);
  });

  test('background tolerates only subpixel gaps and merges overlaps', () {
    final runs = novelDialogueBackgroundRuns(const [
      ui.TextBox.fromLTRBD(0, 0, 40, 20, TextDirection.ltr),
      ui.TextBox.fromLTRBD(40.005, 0, 60, 20, TextDirection.ltr),
      ui.TextBox.fromLTRBD(58, 0, 80, 20, TextDirection.rtl),
      ui.TextBox.fromLTRBD(81, 0, 100, 20, TextDirection.ltr),
    ]);
    expect(runs, [
      const Rect.fromLTRB(0, 0, 80, 20),
      const Rect.fromLTRB(81, 0, 100, 20),
    ]);
  });

  testWidgets('separate dialogues retain their own rounded ends', (
    tester,
  ) async {
    const text = '「前句」旁白「后句」';
    final paragraph = NovelDialogueCache().paragraph(
      NovelReaderParagraph(_entry([text]), 0),
    );
    final presentation = _presentation();
    await tester.pumpWidget(
      wrapWithApp(
        Align(
          alignment: Alignment.topLeft,
          child: NovelDialogueText(
            paragraph: paragraph,
            baseStyle: _baseStyle,
            dialogue: presentation,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final renderParagraph = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byType(NovelDialogueText),
        matching: find.byType(RichText),
      ),
    );
    Rect boundsFor(TextSelection selection) => renderParagraph
        .getBoxesForSelection(selection, boxHeightStyle: ui.BoxHeightStyle.max)
        .map((box) => box.toRect())
        .reduce((a, b) => a.expandToInclude(b));
    final fills = [
      for (final selection in paragraph.selections(0, text.length))
        novelDialogueBackgroundRect(boundsFor(selection)),
    ];
    final narration = boundsFor(
      const TextSelection(baseOffset: 4, extentOffset: 6),
    );
    expect(fills, hasLength(2));
    expect(
      tester.renderObject(
        find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == '_DialogueBackground',
        ),
      ),
      paints..path(
        color: presentation.background,
        includes: fills.map((fill) => fill.center),
        excludes: [
          narration.center,
          for (final fill in fills) Offset(fill.left + 0.1, fill.top + 0.1),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
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

  test(
    'quote choices apply independently to the same cached chapter',
    () async {
      final cache = NovelDialogueCache();
      final entry = _entry(['「甲」『乙』“丙”"丁"‘戊’\'己\'']);
      final paragraph = NovelReaderParagraph(entry, 0);
      for (final mask in List.generate(16, (i) => i)) {
        var quotes = NovelDialogueQuotes.none;
        for (final q in NovelDialogueQuote.values) {
          quotes = quotes.withQuote(q, (mask & (1 << q.index)) != 0);
        }
        await cache.prepare([entry], quotes: quotes);
        final result = cache.paragraph(paragraph, quotes: quotes);
        expect(
          [
            for (final r in result.ranges)
              result.text.substring(r.start, r.end),
          ],
          [
            if (quotes.contains(NovelDialogueQuote.corner)) '「甲」',
            if (quotes.contains(NovelDialogueQuote.doubleCorner)) '『乙』',
            if (quotes.contains(NovelDialogueQuote.curlyDouble)) '“丙”',
            if (quotes.contains(NovelDialogueQuote.straightDouble)) '"丁"',
          ],
        );
      }
    },
  );

  test(
    'optional double quotes nest, cross paragraphs, and stop at chapter end',
    () async {
      final cache = NovelDialogueCache();
      final quotes = NovelDialogueQuotes.defaults
          .withQuote(NovelDialogueQuote.curlyDouble, true)
          .withQuote(NovelDialogueQuote.straightDouble, true);
      final entry = _entry(['前“甲「乙」"丙"', '丁”中"戊', '己"后"孤立']);
      final next = _entry(['孤立"']);
      await cache.prepare([entry, next], quotes: quotes);
      List<String> matched(NovelReaderEntry source, int i) {
        final p = cache.paragraph(
          NovelReaderParagraph(source, i),
          quotes: quotes,
        );
        return [for (final r in p.ranges) p.text.substring(r.start, r.end)];
      }

      expect(matched(entry, 0), ['“甲「乙」"丙"']);
      expect(matched(entry, 1), ['丁”', '"戊']);
      expect(matched(entry, 2), ['己"']);
      expect(matched(next, 0), isEmpty);
    },
  );

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

  test('old view reads keep a new quote combination warm', () async {
    final cache = NovelDialogueCache();
    final entry = _entry(['「第一组」“第二组”']);
    final paragraph = NovelReaderParagraph(entry, 0);
    final old = cache.paragraph(paragraph);
    final quotes = NovelDialogueQuotes.none.withQuote(
      NovelDialogueQuote.curlyDouble,
      true,
    );
    final preparing = cache.prepare([entry], quotes: quotes);
    expect(cache.paragraph(paragraph), same(old));
    await preparing;
    final current = cache.paragraph(paragraph, quotes: quotes);
    final range = current.ranges.single;
    expect(current.text.substring(range.start, range.end), '“第二组”');
    expect(cache.parsedChapters, 2);
  });

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
      const settings = NovelReaderSettings();
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
    const settings = NovelReaderSettings();
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
    final quotes = NovelDialogueQuotes.none.withQuote(
      NovelDialogueQuote.curlyDouble,
      true,
    );
    expect(
      resolve(settings.copyWith(dialogueQuotes: quotes)).layoutKey,
      resolve(settings).layoutKey,
    );
    final bold = settings.copyWith(
      lightDialogueStyle: const NovelDialogueStyle(
        weight: NovelDialogueWeight.bold,
      ),
    );
    expect(
      resolve(bold.copyWith(dialogueQuotes: quotes)).layoutKey,
      isNot(resolve(bold).layoutKey),
    );
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
