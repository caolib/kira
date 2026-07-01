import 'package:json_annotation/json_annotation.dart';

part 'comic_comment.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class ComicComment {
  @JsonKey(fromJson: _intOrStringToInt)
  final int id;
  @JsonKey(defaultValue: '')
  final String createAt;
  @JsonKey(defaultValue: '')
  final String userId;
  @JsonKey(name: 'user_name', defaultValue: '匿名用户')
  final String userName;
  @JsonKey(defaultValue: '')
  final String userAvatar;
  @JsonKey(defaultValue: '')
  final String comment;
  @JsonKey(name: 'count', fromJson: _intOrStringToInt)
  final int replyCount;
  @JsonKey(name: 'parent_id', fromJson: _nullableIntOrStringToInt)
  final int? parentId;
  final String? parentUserId;
  final String? parentUserName;

  const ComicComment({
    required this.id,
    required this.createAt,
    required this.userId,
    required this.userName,
    required this.userAvatar,
    required this.comment,
    required this.replyCount,
    this.parentId,
    this.parentUserId,
    this.parentUserName,
  });

  factory ComicComment.fromJson(Map<String, dynamic> json) =>
      _$ComicCommentFromJson(json);

  Map<String, dynamic> toJson() => _$ComicCommentToJson(this);
}

int _intOrStringToInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _nullableIntOrStringToInt(dynamic value) {
  if (value is int) return value;
  if (value == null) return null;
  return int.tryParse(value.toString());
}
