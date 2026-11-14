import '../models/comic_comment.dart';
import '../utils/comment_grouping.dart';

List<ComicCommentDisplayEntry> groupComicComments(
  Iterable<ComicComment> comments, {
  int Function(ComicComment)? replyCountOf,
}) => groupCommentsByContent(
  comments,
  contentOf: (comment) => comment.comment,
  userIdOf: (comment) => comment.userId,
  canMerge: (comment) =>
      (replyCountOf?.call(comment) ?? comment.replyCount) <= 0,
).map((group) => ComicCommentDisplayEntry(comments: group)).toList();

class ComicCommentDisplayEntry extends CommentDisplayEntry<ComicComment> {
  ComicCommentDisplayEntry({required super.comments});

  @override
  String textOf(ComicComment comment) => comment.comment;
  @override
  String userIdOf(ComicComment comment) => comment.userId;
  @override
  String userNameOf(ComicComment comment) => comment.userName;
  @override
  String userAvatarOf(ComicComment comment) => comment.userAvatar;
  @override
  String idOf(ComicComment comment) => comment.id.toString();
  @override
  String timeOf(ComicComment comment) => comment.createAt;
}
