typedef BookmarkSection<T> = ({
  String pathWord,
  List<T> bookmarks,
  bool pinned,
});

/// 保留空组和组内原顺序。置顶组在前，同一区内按最新书签（空组按建组时间）排序。
List<BookmarkSection<T>> groupBookmarks<T>({
  required Iterable<T> bookmarks,
  required Iterable<({String pathWord, bool pinned, DateTime updatedAt})>
  groups,
  required String Function(T) pathWordOf,
  required DateTime? Function(T) dateOf,
}) {
  final items = <String, List<T>>{};
  final metadata = {for (final group in groups) group.pathWord: group};
  for (final bookmark in bookmarks) {
    (items[pathWordOf(bookmark)] ??= []).add(bookmark);
  }
  for (final key in metadata.keys) {
    items.putIfAbsent(key, () => []);
  }
  int timestamp(BookmarkSection<T> section) =>
      (section.bookmarks.isEmpty
              ? metadata[section.pathWord]?.updatedAt
              : dateOf(section.bookmarks.first))
          ?.microsecondsSinceEpoch ??
      0;
  return [
    for (final entry in items.entries)
      (
        pathWord: entry.key,
        bookmarks: entry.value,
        pinned: metadata[entry.key]?.pinned ?? false,
      ),
  ]..sort((a, b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    final byDate = timestamp(b).compareTo(timestamp(a));
    return byDate == 0 ? a.pathWord.compareTo(b.pathWord) : byDate;
  });
}
