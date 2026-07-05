import '../models/chapter_comment.dart';

// 标点符号正则，用于规范化评论文本
final _punctuationRegex = RegExp(r'[^\w\s一-鿿]');

/// 规范化评论文本：去除标点符号、转小写、去除首尾空格
String _normalizeComment(String text) {
  return text.replaceAll(_punctuationRegex, '').toLowerCase().trim();
}

/// 从评论列表中选择出现次数最多的原始文本作为显示文本
String _selectDisplayText(List<ChapterComment> comments) {
  final counts = <String, int>{};
  for (final comment in comments) {
    counts[comment.comment] = (counts[comment.comment] ?? 0) + 1;
  }
  return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
}

List<ChapterCommentDisplayEntry> groupChapterComments(
  Iterable<ChapterComment> comments,
) {
  final groupedByNormalized = <String, List<ChapterComment>>{};
  final orderedKeys = <String>[];
  final unmergeableComments = <ChapterComment>[];
  final seenExactUserComments = <String>{};

  for (final comment in comments) {
    final duplicateKey = _exactUserCommentKey(comment);
    if (duplicateKey != null && !seenExactUserComments.add(duplicateKey)) {
      continue;
    }

    final normalizedKey = _normalizeComment(comment.comment);
    if (normalizedKey.isEmpty) {
      unmergeableComments.add(comment);
      continue;
    }
    final bucket = groupedByNormalized.putIfAbsent(normalizedKey, () {
      orderedKeys.add(normalizedKey);
      return <ChapterComment>[];
    });
    bucket.add(comment);
  }

  final entries = [
    for (final normalizedKey in orderedKeys)
      ChapterCommentDisplayEntry(comments: groupedByNormalized[normalizedKey]!),
    for (final comment in unmergeableComments)
      ChapterCommentDisplayEntry(comments: [comment]),
  ];

  final firstAppearanceOrder = <String, int>{
    for (var i = 0; i < orderedKeys.length; i++) orderedKeys[i]: i,
  };

  final mergedEntries = entries.where((entry) => entry.isMerged).toList()
    ..sort((a, b) {
      final countCompare = b.count.compareTo(a.count);
      if (countCompare != 0) return countCompare;
      return firstAppearanceOrder[a._normalizedKey]!.compareTo(
        firstAppearanceOrder[b._normalizedKey]!,
      );
    });

  final singleEntries = entries.where((entry) => !entry.isMerged).toList();

  return [...mergedEntries, ...singleEntries];
}

String? _exactUserCommentKey(ChapterComment comment) {
  final userId = comment.userId.trim();
  if (userId.isEmpty) return null;
  return '$userId\u0000${comment.comment}';
}

class ChapterCommentDisplayEntry {
  ChapterCommentDisplayEntry({required List<ChapterComment> comments})
    : assert(comments.isNotEmpty),
      comments = List.unmodifiable(comments);

  final List<ChapterComment> comments;

  /// 规范化后的分组key，用于排序时保持稳定顺序
  late final String _normalizedKey = _normalizeComment(primaryComment.comment);

  bool get isMerged => comments.length > 1;

  ChapterComment get primaryComment => comments.first;

  /// 合并评论时显示多数优先的原始文本，单条评论直接显示原文
  String get content =>
      isMerged ? _selectDisplayText(comments) : primaryComment.comment;

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
