import 'package:json_annotation/json_annotation.dart';

part 'chapter_comment.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class ChapterComment {
  @JsonKey(fromJson: _intOrStringToInt)
  final int id;
  @JsonKey(defaultValue: '')
  final String createAt;
  @JsonKey(defaultValue: '')
  final String userId;
  @JsonKey(defaultValue: '匿名用户')
  final String userName;
  @JsonKey(defaultValue: '')
  final String userAvatar;
  @JsonKey(defaultValue: '')
  final String comment;

  const ChapterComment({
    required this.id,
    required this.createAt,
    required this.userId,
    required this.userName,
    required this.userAvatar,
    required this.comment,
  });

  factory ChapterComment.fromJson(Map<String, dynamic> json) =>
      _$ChapterCommentFromJson(json);

  Map<String, dynamic> toJson() => _$ChapterCommentToJson(this);
}

int _intOrStringToInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
