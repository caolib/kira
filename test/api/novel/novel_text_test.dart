import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kira/api/novel/novel_text.dart';
import 'package:kira/models/novel.dart';

NovelVolumeDetail _detail(List<NovelContentEntry> entries) => NovelVolumeDetail(
  book: const NovelBook(pathWord: 'book', name: '书名'),
  volume: NovelVolume(id: 'volume', name: '第一卷', contents: entries),
);

String _parseParagraph(String text) => NovelText.parse(
  _detail(const [NovelContentEntry(name: '正文', contentType: 1, endLines: 1)]),
  text,
).entries.single.paragraphs.single;

void main() {
  test('decodes decimal character references in novel prose', () {
    expect(
      _parseParagraph(
        '「难得来一次，先看&#16034;&#15970;狓再去看鳄鱼吧。&#16034;&#15970;狓就在那边。」',
      ),
      '「难得来一次，先看㺢㹢狓再去看鳄鱼吧。㺢㹢狓就在那边。」',
    );
  });

  test('supports hexadecimal references and supplementary Unicode', () {
    expect(
      _parseParagraph('&#x3eA2;&#X3E62;狓 &#131072;&#x20000; &#00016034;'),
      '㺢㹢狓 \u{20000}\u{20000} 㺢',
    );
  });

  test('decodes once without interpreting plain text as HTML', () {
    expect(
      _parseParagraph('<正文> A&B &amp;#16034; &#38;#16034; &#60;正文&#62;'),
      '<正文> A&B &amp;#16034; &#16034; <正文>',
    );
  });

  test('preserves malformed references and invalid Unicode values', () {
    const text =
        '&#; &#x; &#-1; &#xZZ; &#16034 &# 16034; '
        '&#1114112; &#x110000; &#55296; &#xDFFF; '
        '&#99999999999999999999999999999; &#xFFFFFFFFFFFFFFFF;';
    expect(_parseParagraph(text), text);
  });

  test('does not turn control references into whitespace or line breaks', () {
    const text =
        '&#0; &#9; &#10; &#13; &#31; &#127; &#x85; &#159; '
        '&#x2028; &#8233;';
    expect(_parseParagraph(text), text);
  });

  test('retains paragraph indices, blank lines and independent images', () {
    final content = NovelText.parse(
      _detail(const [
        NovelContentEntry(name: '第一章', contentType: 1, endLines: 3),
        NovelContentEntry(
          name: '插图',
          contentType: 2,
          content: 'https://cdn.invalid/image.png',
        ),
        NovelContentEntry(
          name: '第二章',
          contentType: 1,
          startLines: 3,
          endLines: 5,
        ),
      ]),
      '\r\n  &#16034;&#15970;狓  \r\n\r\n&#x20000;\r\n',
    );
    expect(content.entries.map((entry) => entry.entryIndex), [0, 1, 2]);
    expect(content.entries[0].paragraphs, ['', '  㺢㹢狓  ', '']);
    expect(content.entries[1].paragraphs, isEmpty);
    expect(content.entries[1].imageUrl, 'https://cdn.invalid/image.png');
    expect(content.entries[2].paragraphs, ['\u{20000}', '']);
  });

  for (final encoding in ['UTF-8', 'GBK', 'GB18030']) {
    test('$encoding byte decoding preserves the raw TXT references', () {
      const raw = '&#16034;&#15970;';
      final text = NovelText.decode(ascii.encode(raw), encoding);
      expect(text, raw);
      expect(_parseParagraph(text), '㺢㹢');
    });
  }
}
