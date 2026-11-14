/// 漫画与小说作品评论共用的展示层分组；回复线程不进入分组或内容去重。
String normalizeCommentContent(String text) =>
    text.replaceAll(_punctuationRegex, '').toLowerCase().trim();

final _punctuationRegex = RegExp(r'[^\w\s一-鿿]');

List<List<T>> groupCommentsByContent<T>(
  Iterable<T> comments, {
  required String Function(T) contentOf,
  required String Function(T) userIdOf,
  required bool Function(T) canMerge,
}) {
  final buckets = <String, List<T>>{};
  final orderedGroups = <List<T>>[];
  final seenExactUserComments = <String>{};

  for (final comment in comments) {
    // 先保留线程，再进行同用户同文去重，避免不同 ID 的回复被吞掉。
    if (!canMerge(comment)) {
      orderedGroups.add([comment]);
      continue;
    }
    final content = contentOf(comment);
    final userId = userIdOf(comment).trim();
    if (userId.isNotEmpty &&
        !seenExactUserComments.add('$userId\u0000$content')) {
      continue;
    }
    final key = normalizeCommentContent(content);
    if (key.isEmpty) {
      orderedGroups.add([comment]);
      continue;
    }
    final bucket = buckets.putIfAbsent(key, () {
      final group = <T>[];
      orderedGroups.add(group);
      return group;
    });
    bucket.add(comment);
  }

  final firstAppearance = {
    for (var i = 0; i < orderedGroups.length; i++) orderedGroups[i]: i,
  };
  final merged = orderedGroups.where((group) => group.length > 1).toList()
    ..sort((a, b) {
      final countOrder = b.length.compareTo(a.length);
      return countOrder != 0
          ? countOrder
          : firstAppearance[a]!.compareTo(firstAppearance[b]!);
    });
  return [...merged, ...orderedGroups.where((group) => group.length == 1)];
}

/// 保留原评论及 ID，合并只改变显示，不改变回复对象。
abstract class CommentDisplayEntry<T> {
  CommentDisplayEntry({required List<T> comments})
    : assert(comments.isNotEmpty),
      comments = List.unmodifiable(comments);

  final List<T> comments;

  String textOf(T comment);
  String userIdOf(T comment);
  String userNameOf(T comment);
  String userAvatarOf(T comment);
  String idOf(T comment);
  String timeOf(T comment);

  bool get isMerged => comments.length > 1;
  T get primaryComment => comments.first;
  int get count => comments.length;
  String get createAt => timeOf(primaryComment);

  late final String content = _selectDisplayText();

  String _selectDisplayText() {
    if (!isMerged) return textOf(primaryComment);
    final counts = <String, int>{};
    for (final comment in comments) {
      final text = textOf(comment);
      counts[text] = (counts[text] ?? 0) + 1;
    }
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  List<T> avatarComments({int maxCount = 5}) {
    final avatars = <T>[];
    final seenUsers = <String>{};
    for (final comment in comments) {
      if (!seenUsers.add(_userIdentity(comment))) continue;
      avatars.add(comment);
      if (avatars.length >= maxCount) break;
    }
    return avatars;
  }

  List<String> userNames() {
    final names = <String>[];
    final seenUsers = <String>{};
    for (final comment in comments) {
      if (!seenUsers.add(_userIdentity(comment))) continue;
      names.add(userNameOf(comment).trim());
    }
    return names;
  }

  String _userIdentity(T comment) {
    final id = userIdOf(comment);
    if (id.isNotEmpty) return 'id:$id';
    final avatar = userAvatarOf(comment);
    if (avatar.isNotEmpty) return 'avatar:$avatar';
    final name = userNameOf(comment);
    if (name.isNotEmpty) return 'name:$name';
    return 'comment:${idOf(comment)}';
  }
}
