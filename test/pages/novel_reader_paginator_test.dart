import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/novel.dart';
import 'package:kira/pages/novel_reader/novel_reader_document.dart';
import 'package:kira/pages/novel_reader/novel_reader_paginator.dart';

NovelReaderEntry _entry({
  required int entryIndex,
  required String name,
  List<String>? paragraphs,
  int contentType = 1,
}) => NovelReaderEntry(
  entryIndex: entryIndex,
  entry: NovelContentEntry(name: name, contentType: contentType),
  paragraphs: paragraphs ?? const [],
);

NovelReaderDocument _document(List<NovelReaderEntry> entries) =>
    NovelReaderDocument(entries);

const _style = TextStyle(fontSize: 20, height: 1.8);

NovelPaginationSpec _spec({
  Size size = const Size(360, 360),
  double? viewportHeight,
  double contentTopInset = 0,
  String emptyChapterText = '本章节暂无正文',
  double paragraphSpacing = 16,
}) => NovelPaginationSpec(
  textStyle: _style,
  titleStyle: const TextStyle(fontSize: 24, height: 1.2),
  textScaler: TextScaler.noScaling,
  textDirection: TextDirection.ltr,
  size: size,
  // 测试环境无系统栏：默认整屏高 = 正文区高、顶部无 inset。
  viewportHeight: viewportHeight ?? size.height,
  contentTopInset: contentTopInset,
  paragraphSpacing: paragraphSpacing,
  titleSpacing: 24,
  emptyChapterText: emptyChapterText,
);

/// 分页结构快照：每页每片段的 (段落, 起始行, 结束行)。
List<List<List<int>>> _structure(NovelReaderPaginator paginator) => [
  for (final page in paginator.pages)
    [
      for (final slice in page.slices)
        [slice.itemIndex, slice.startLine, slice.endLine],
    ],
];

/// 段落被分页覆盖到的行数（应等于测量行数）。
int _coveredLines(NovelReaderPaginator paginator, int itemIndex) {
  var lines = 0;
  for (final page in paginator.pages) {
    for (final slice in page.slices) {
      if (slice.itemIndex == itemIndex) {
        lines += slice.endLine - slice.startLine;
      }
    }
  }
  return lines;
}

/// 每页的填充高度（校验不超页高）。
double _pageHeight(NovelReaderPaginator paginator, NovelPaginatedPage page) =>
    page.slices.fold(0.0, (sum, slice) => sum + paginator.sliceHeight(slice));

/// 把分页结果还原成每段的完整文本，验证无丢字、无重复。
List<String> _reconstruct(
  NovelReaderDocument document,
  NovelReaderPaginator paginator,
) {
  final buffers = <int, StringBuffer>{};
  for (final page in paginator.pages) {
    for (final slice in page.slices) {
      final paragraph = document.paragraphAt(slice.itemIndex);
      final display = novelParagraphDisplayText(paragraph, '本章节暂无正文');
      buffers
          .putIfAbsent(slice.itemIndex, StringBuffer.new)
          .write(display.substring(slice.startOffset, slice.endOffset));
    }
  }
  return [
    for (var item = 0; item < document.itemCount; item++)
      buffers[item]?.toString() ?? '',
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pages never overflow and cover every paragraph in order', () {
    final document = _document([
      _entry(
        entryIndex: 0,
        name: '第一章',
        paragraphs: [for (var i = 0; i < 40; i++) '第一章第 $i 段。' * 4],
      ),
      _entry(
        entryIndex: 1,
        name: '第二章',
        paragraphs: [
          '',
          '短段落。',
          for (var i = 0; i < 20; i++) '更长的段落内容 $i。' * 6,
        ],
      ),
    ]);
    final paginator = NovelReaderPaginator(document: document, spec: _spec());
    while (paginator.buildMore()) {}

    expect(paginator.complete, isTrue);
    expect(paginator.pages, isNotEmpty);
    for (final page in paginator.pages) {
      expect(page.slices, isNotEmpty);
      expect(_pageHeight(paginator, page), lessThanOrEqualTo(360.001));
    }
    // 目录顺序：页内片段与页间片段均按 itemIndex 单调不减。
    var last = -1;
    for (final page in paginator.pages) {
      for (final slice in page.slices) {
        expect(slice.itemIndex, greaterThanOrEqualTo(last));
        last = slice.itemIndex;
      }
    }
    expect(last, document.itemCount - 1);

    // 无丢字：还原文本与原文一致。
    final expected = [
      for (var item = 0; item < document.itemCount; item++)
        novelParagraphDisplayText(document.paragraphAt(item), '本章节暂无正文'),
    ];
    expect(_reconstruct(document, paginator), expected);
  });

  test('a long paragraph splits across pages at line boundaries', () {
    final long = List.filled(400, '长段落文字').join();
    final document = _document([
      _entry(entryIndex: 0, name: '第一章', paragraphs: [long]),
    ]);
    final paginator = NovelReaderPaginator(document: document, spec: _spec());
    while (paginator.buildMore()) {}

    expect(paginator.pages.length, greaterThan(1));
    // 每页只包含整行（行边界切分）：字符区间按页连续覆盖整段。
    var previousEnd = 0;
    for (var i = 0; i < paginator.pages.length; i++) {
      final slice = paginator.pages[i].slices.single;
      expect(slice.startOffset, previousEnd);
      expect(slice.endOffset, greaterThan(slice.startOffset));
      previousEnd = slice.endOffset;
      expect(slice.startLine, i == 0 ? 0 : greaterThan(0));
      expect(slice.endLine, greaterThan(slice.startLine));
    }
    expect(previousEnd, long.length);
    // 还原后与原文一致。
    expect(_reconstruct(document, paginator).single, long);
  });

  test(
    'chapter title stays with its first line and empty entries render once',
    () {
      final document = _document([
        _entry(
          entryIndex: 0,
          name: '标题',
          paragraphs: [for (var i = 0; i < 30; i++) '正文段落 $i。' * 5],
        ),
        _entry(entryIndex: 1, name: '空章', paragraphs: []),
        _entry(entryIndex: 2, name: '第三章', paragraphs: ['', '结束。']),
      ]);
      final paginator = NovelReaderPaginator(document: document, spec: _spec());
      while (paginator.buildMore()) {}

      // 标题与首行同页：带标题的片段所在页必须有正文片段。
      for (final page in paginator.pages) {
        final titled = page.slices.where((slice) => slice.hasTitle);
        for (final slice in titled) {
          expect(
            slice.endLine,
            greaterThan(slice.startLine),
            reason: '标题片段必须含至少一行正文',
          );
        }
      }
      final reconstructed = _reconstruct(document, paginator);
      // 空章节合成 1 个 item，渲染占位文案且只出现一次。
      final emptyChapter = document.itemFor(
        const NovelReaderAnchor(entryIndex: 1),
      );
      expect(reconstructed[emptyChapter], '本章节暂无正文');
      expect(reconstructed.where((text) => text == '本章节暂无正文'), hasLength(1));
      final blank = document.itemFor(const NovelReaderAnchor(entryIndex: 2));
      expect(reconstructed[blank], ' ');
      expect(reconstructed[blank + 1], '结束。');
    },
  );

  test('anchorForPage and pageForAnchor round-trip for every page', () {
    final document = _document([
      _entry(
        entryIndex: 0,
        name: '第一章',
        paragraphs: [for (var i = 0; i < 60; i++) '段落 $i 的内容。' * 3],
      ),
    ]);
    final paginator = NovelReaderPaginator(document: document, spec: _spec());
    while (paginator.buildMore()) {}

    for (var page = 0; page < paginator.pages.length; page++) {
      final anchor = paginator.anchorForPage(page);
      expect(paginator.pageForAnchor(anchor), page);
    }
  });

  test('negative alignment maps to the page containing the estimated line', () {
    final long = List.filled(400, '长段落文字').join();
    final document = _document([
      _entry(entryIndex: 0, name: '第一章', paragraphs: [long]),
      _entry(entryIndex: 1, name: '第二章', paragraphs: ['尾巴。']),
    ]);
    final paginator = NovelReaderPaginator(document: document, spec: _spec());
    while (paginator.buildMore()) {}

    final pageCount = paginator.pages.length;
    expect(pageCount, greaterThan(2));
    // 段落顶部越靠上（负值越大），落在越靠后的页。
    final early = paginator.pageForAnchor(
      const NovelReaderAnchor(entryIndex: 0, alignment: -0.5),
    );
    final late = paginator.pageForAnchor(
      const NovelReaderAnchor(entryIndex: 0, alignment: -3.0),
    );
    expect(early, isNotNull);
    expect(late, isNotNull);
    expect(late!, greaterThan(early!));
    // 超出段落范围时收敛到该段落最后一页，而不是越界或跳到后一章节。
    final beyond = paginator.pageForAnchor(
      const NovelReaderAnchor(entryIndex: 0, alignment: -100),
    );
    expect(beyond, isNotNull);
    expect(beyond, lessThan(pageCount));
    expect(beyond, greaterThanOrEqualTo(late));
    expect(
      beyond,
      paginator.pages.lastIndexWhere(
        (page) => page.slices.any((slice) => slice.itemIndex == 0),
      ),
    );
  });

  test('rebuilding an unchanged tail preserves page structure and anchors', () {
    final document = _document([
      _entry(
        entryIndex: 0,
        name: '第一章',
        paragraphs: [for (var i = 0; i < 40; i++) '段落 $i 的内容稍微长一点点。' * 3],
      ),
    ]);
    final paginator = NovelReaderPaginator(document: document, spec: _spec());
    while (paginator.buildMore()) {}
    final before = _structure(paginator);
    final pages = List.of(paginator.pages);
    final anchors = [
      for (var page = 0; page < pages.length; page++)
        paginator.anchorForPage(page),
    ];
    final pageOfFive = paginator.pageForAnchor(
      const NovelReaderAnchor(entryIndex: 0, paragraphIndex: 5),
    )!;
    expect(pageOfFive, greaterThan(0));

    paginator.rebuildFrom(5);
    while (paginator.buildMore()) {}

    expect(paginator.complete, isTrue);
    expect(_structure(paginator), before);
    for (var page = 0; page < pageOfFive; page++) {
      expect(paginator.pages[page], same(pages[page]));
    }
    for (var page = 0; page < anchors.length; page++) {
      expect(paginator.pageForAnchor(anchors[page]), page);
      expect(
        _pageHeight(paginator, paginator.pages[page]),
        lessThanOrEqualTo(360.001),
      );
    }
    expect(_reconstruct(document, paginator), [
      for (var item = 0; item < document.itemCount; item++)
        novelParagraphDisplayText(document.paragraphAt(item), '本章节暂无正文'),
    ]);
  });

  test('locationForPage progress increases and reaches 1.0 at the end', () {
    final document = _document([
      _entry(
        entryIndex: 0,
        name: '第一章',
        paragraphs: [for (var i = 0; i < 30; i++) '段落 $i。' * 4],
      ),
    ]);
    final paginator = NovelReaderPaginator(document: document, spec: _spec());
    while (paginator.buildMore()) {}

    var previous = -1.0;
    for (var page = 0; page < paginator.pages.length; page++) {
      final location = paginator.locationForPage(page);
      expect(location.progress, greaterThanOrEqualTo(previous));
      previous = location.progress;
    }
    expect(paginator.locationForPage(paginator.pages.length - 1).progress, 1.0);
  });

  test('center paragraph skips blank lines and returns text paragraphs', () {
    final document = _document([
      _entry(
        entryIndex: 0,
        name: '第一章',
        paragraphs: ['', '', '有正文的段落。', '', ''],
      ),
    ]);
    final paginator = NovelReaderPaginator(
      document: document,
      spec: _spec(size: const Size(360, 720)),
    );
    while (paginator.buildMore()) {}

    final center = paginator.centerParagraph(0);
    expect(center, isNotNull);
    expect(center!.text, '有正文的段落。');
  });

  test('blank-only document still paginates without infinite loop', () {
    final document = _document([
      _entry(
        entryIndex: 0,
        name: '',
        paragraphs: ['', '', '', '', '', '', '', '', '', '', '', ''],
      ),
    ]);
    final paginator = NovelReaderPaginator(
      document: document,
      spec: _spec(size: const Size(360, 200)),
    );
    var guard = 0;
    while (paginator.buildMore() && guard++ < 1000) {}
    expect(paginator.complete, isTrue);
    expect(_reconstruct(document, paginator).length, 12);
  });

  test(
    'anchorForPage round-trips when the viewport is taller than the page',
    () {
      final document = _document([
        // 无标题：段落内深度 = 行号 × 行高（36px），页边界落在精确的行顶，
        // 正是除法/乘法舍入最容易把深度算小 1ulp 的位置。
        _entry(
          entryIndex: 0,
          name: '',
          paragraphs: [List.filled(400, '长段落文字').join()],
        ),
      ]);
      final paginator = NovelReaderPaginator(
        document: document,
        // 整屏 800 而正文区 360、顶部 inset 44（接近真机状态栏）。
        spec: _spec(viewportHeight: 800, contentTopInset: 44),
      );
      while (paginator.buildMore()) {}

      var checked = 0;
      for (var page = 0; page < paginator.pages.length; page++) {
        final anchor = paginator.anchorForPage(page);
        // alignment ≥ 0：段落顶仍在屏内，映射到段落起始页（非本页）。
        if (anchor.alignment >= 0) continue;
        expect(paginator.pageForAnchor(anchor), page);
        checked++;
      }
      expect(checked, greaterThan(paginator.pages.length ~/ 2));
    },
  );

  test(
    'pageForAnchor uses the content inset and the viewport height together',
    () {
      final long = List.filled(600, '长段落文字').join();
      final document = _document([
        // 无标题：段落内深度 = 行号 × 行高，便于精确推算期望值。
        _entry(entryIndex: 0, name: '', paragraphs: [long]),
      ]);
      const inset = 40.0;
      const viewport = 800.0;
      final paginator = NovelReaderPaginator(
        document: document,
        spec: _spec(
          size: const Size(360, 480),
          viewportHeight: viewport,
          contentTopInset: inset,
        ),
      );
      while (paginator.buildMore()) {}

      final firstSlice = paginator.pages.first.slices.first;
      final lineHeight =
          paginator.sliceHeight(firstSlice) /
          (firstSlice.endLine - firstSlice.startLine);
      int pageOfLine(int line) => paginator.pages.indexWhere(
        (page) => page.slices.any(
          (slice) =>
              slice.itemIndex == 0 &&
              line >= slice.startLine &&
              line < slice.endLine,
        ),
      );

      // 屏幕顶端落在第 2 页首行稍下方：深度 = 页首行深 + 半行。
      final secondPageTop =
          paginator.pages[1].slices.first.startLine * lineHeight;
      final depth = secondPageTop + lineHeight / 2;
      final anchor = NovelReaderAnchor(
        entryIndex: 0,
        alignment: (inset - depth) / viewport,
      );
      expect(pageOfLine((depth / lineHeight).floor()), 1);
      // 忽略 inset 会落到上一页——本用例正是为了区分这两种实现。
      expect(pageOfLine(((depth - inset) / lineHeight).floor()), 0);
      expect(paginator.pageForAnchor(anchor), 1);
    },
  );

  test('progress stays below 1.0 until every paragraph is paginated', () {
    final document = _document([
      _entry(
        entryIndex: 0,
        name: '第一章',
        paragraphs: [for (var i = 0; i < 30; i++) '段落 $i。' * 4],
      ),
    ]);
    final paginator = NovelReaderPaginator(document: document, spec: _spec());
    var guard = 0;
    while (!paginator.complete && guard++ < 200) {
      paginator.buildMore(maxItems: 1);
      if (paginator.complete) break;
      expect(
        paginator.locationForPage(paginator.pages.length - 1).progress,
        lessThan(1.0),
        reason: '未建完时不得报告读到卷末',
      );
    }
    expect(paginator.complete, isTrue);
    expect(paginator.locationForPage(paginator.pages.length - 1).progress, 1.0);
  });

  test('reset discards all measurements before rebuilding the document', () {
    final paragraphs = [for (var i = 0; i < 12; i++) '第$i段的正文。' * 4];
    final document = _document([
      _entry(entryIndex: 0, name: '第一章', paragraphs: paragraphs),
    ]);
    final paginator = NovelReaderPaginator(document: document, spec: _spec());
    while (paginator.buildMore()) {}
    final linesBefore = _coveredLines(paginator, 0);
    paragraphs[0] *= 4;

    paginator.reset();
    expect(paginator.builtItems, 0);
    expect(paginator.complete, isFalse);
    expect(paginator.pages.single.slices, isEmpty);
    expect(
      paginator.pageForAnchor(const NovelReaderAnchor(entryIndex: 0)),
      isNull,
    );
    while (paginator.buildMore()) {}
    final fresh = NovelReaderPaginator(document: document, spec: _spec());
    while (fresh.buildMore()) {}

    expect(_coveredLines(paginator, 0), greaterThan(linesBefore));
    expect(_structure(paginator), _structure(fresh));
    expect(_reconstruct(document, paginator), paragraphs);
  });

  test('rebuildFrom invalidates the metrics of every changed paragraph', () {
    // 保留段落身份，只修改文本长度，验证同批多段变化不会沿用旧测量。
    final paragraphs = [
      for (var i = 0; i < 12; i++) '第$i段${List.filled(32, '字').join()}',
    ];
    final document = _document([
      _entry(entryIndex: 0, name: '第一章', paragraphs: paragraphs),
    ]);
    NovelReaderPaginator build() {
      final paginator = NovelReaderPaginator(document: document, spec: _spec());
      while (paginator.buildMore()) {}
      return paginator;
    }

    final baseline = build();
    final incremental = build();
    final prefix = _structure(baseline)
        .take(
          baseline.pageForAnchor(
            const NovelReaderAnchor(entryIndex: 0, paragraphIndex: 5),
          )!,
        )
        .toList();
    for (final item in [5, 9]) {
      paragraphs[item] *= 4;
    }
    // 只从最早的段落重建，但同一批里变化的段落都要失效测量缓存。
    incremental.rebuildFrom(5, invalidate: {5, 9});
    while (incremental.buildMore()) {}
    final fresh = build();

    for (final item in [5, 9]) {
      expect(
        _coveredLines(fresh, item),
        greaterThan(_coveredLines(baseline, item)),
      );
    }
    expect(_structure(incremental), _structure(fresh));
    expect(_structure(incremental).take(prefix.length).toList(), prefix);
    expect(_reconstruct(document, incremental), paragraphs);
    for (var page = 0; page < incremental.pages.length; page++) {
      expect(
        _pageHeight(incremental, incremental.pages[page]),
        lessThanOrEqualTo(360.001),
      );
      expect(incremental.pageForAnchor(incremental.anchorForPage(page)), page);
    }
  });
}
