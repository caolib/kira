import '../models/novel.dart';
import '../utils/comment_grouping.dart';

List<NovelCommentDisplayEntry> groupNovelComments(
  Iterable<NovelComment> comments, {
  int Function(NovelComment)? replyCountOf,
  bool mergeEnabled = true,
}) => groupCommentsByContent(
  comments,
  contentOf: (comment) => comment.comment,
  userIdOf: (comment) => comment.userId,
  canMerge: (comment) =>
      mergeEnabled && (replyCountOf?.call(comment) ?? comment.count) <= 0,
).map((group) => NovelCommentDisplayEntry(comments: group)).toList();

class NovelCommentDisplayEntry extends CommentDisplayEntry<NovelComment> {
  NovelCommentDisplayEntry({required super.comments});

  @override
  String textOf(NovelComment comment) => comment.comment;
  @override
  String userIdOf(NovelComment comment) => comment.userId;
  @override
  String userNameOf(NovelComment comment) => comment.userName;
  @override
  String userAvatarOf(NovelComment comment) => comment.userAvatar;
  @override
  String idOf(NovelComment comment) => comment.id;
  @override
  String timeOf(NovelComment comment) => comment.createAt;
}
