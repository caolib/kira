import '../models/chapter_comment.dart';

List<ChapterCommentDisplayEntry> groupChapterComments(
  Iterable<ChapterComment> comments,
) {
  final groupedByContent = <String, List<ChapterComment>>{};
  final orderedKeys = <String>[];
  final duplicates = <ChapterComment>[];

  for (final comment in comments) {
    final key = comment.comment;
    final bucket = groupedByContent.putIfAbsent(key, () {
      orderedKeys.add(key);
      return <ChapterComment>[];
    });
    // 同一用户重复发相同内容的评论不参与合并，保留为独立条目
    if (bucket.any(
      (c) => c.userId == comment.userId && c.userId.isNotEmpty,
    )) {
      duplicates.add(comment);
      continue;
    }
    bucket.add(comment);
  }

  final entries = [
    for (final key in orderedKeys)
      ChapterCommentDisplayEntry(comments: groupedByContent[key]!),
    for (final dup in duplicates)
      ChapterCommentDisplayEntry(comments: [dup]),
  ];

  final firstAppearanceOrder = <String, int>{
    for (var i = 0; i < orderedKeys.length; i++) orderedKeys[i]: i,
  };

  final mergedEntries = entries.where((entry) => entry.isMerged).toList()
    ..sort((a, b) {
      final countCompare = b.count.compareTo(a.count);
      if (countCompare != 0) return countCompare;
      return firstAppearanceOrder[a.content]!.compareTo(
        firstAppearanceOrder[b.content]!,
      );
    });

  final singleEntries = entries.where((entry) => !entry.isMerged).toList();

  return [...mergedEntries, ...singleEntries];
}

class ChapterCommentDisplayEntry {
  ChapterCommentDisplayEntry({required List<ChapterComment> comments})
    : assert(comments.isNotEmpty),
      comments = List.unmodifiable(comments);

  final List<ChapterComment> comments;

  bool get isMerged => comments.length > 1;

  ChapterComment get primaryComment => comments.first;

  String get content => primaryComment.comment;

  int get count => comments.length;

  String get createAt => primaryComment.createAt;

  List<ChapterComment> avatarComments({int maxCount = 5}) {
    final avatars = <ChapterComment>[];
    final seenUsers = <String>{};

    for (final comment in comments) {
      final identity = _userIdentity(comment);
      if (!seenUsers.add(identity)) continue;

      avatars.add(comment);
      if (avatars.length >= maxCount) break;
    }

    return avatars;
  }

  String _userIdentity(ChapterComment comment) {
    if (comment.userId.isNotEmpty) return 'id:${comment.userId}';
    if (comment.userAvatar.isNotEmpty) return 'avatar:${comment.userAvatar}';
    if (comment.userName.isNotEmpty) return 'name:${comment.userName}';
    return 'comment:${comment.id}';
  }
}
