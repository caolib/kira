part of '../reader_page.dart';

/// Kind of item rendered in the scroll-mode list.
enum _ScrollItemKind { header, chapterDivider, image, tail, loadMore }

/// Describes a single item in the scroll-mode list.
class _ScrollItem {
  final _ScrollItemKind kind;
  final ChapterDetail? chapter;
  final int? localIndex;
  final int? globalIndex;

  const _ScrollItem._({
    required this.kind,
    this.chapter,
    this.localIndex,
    this.globalIndex,
  });

  factory _ScrollItem.header() =>
      const _ScrollItem._(kind: _ScrollItemKind.header);
  factory _ScrollItem.chapterDivider(ChapterDetail c) =>
      _ScrollItem._(kind: _ScrollItemKind.chapterDivider, chapter: c);
  factory _ScrollItem.image(ChapterDetail c, int local, int global) =>
      _ScrollItem._(
        kind: _ScrollItemKind.image,
        chapter: c,
        localIndex: local,
        globalIndex: global,
      );
  factory _ScrollItem.tail() => const _ScrollItem._(kind: _ScrollItemKind.tail);
  factory _ScrollItem.loadMore() =>
      const _ScrollItem._(kind: _ScrollItemKind.loadMore);
}
