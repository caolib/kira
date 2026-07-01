// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'comic_comment.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ComicComment _$ComicCommentFromJson(Map<String, dynamic> json) => ComicComment(
  id: _intOrStringToInt(json['id']),
  createAt: json['create_at'] as String? ?? '',
  userId: json['user_id'] as String? ?? '',
  userName: json['user_name'] as String? ?? '匿名用户',
  userAvatar: json['user_avatar'] as String? ?? '',
  comment: json['comment'] as String? ?? '',
  replyCount: _intOrStringToInt(json['count']),
  parentId: _nullableIntOrStringToInt(json['parent_id']),
  parentUserId: json['parent_user_id'] as String?,
  parentUserName: json['parent_user_name'] as String?,
);

Map<String, dynamic> _$ComicCommentToJson(ComicComment instance) =>
    <String, dynamic>{
      'id': instance.id,
      'create_at': instance.createAt,
      'user_id': instance.userId,
      'user_name': instance.userName,
      'user_avatar': instance.userAvatar,
      'comment': instance.comment,
      'count': instance.replyCount,
      'parent_id': instance.parentId,
      'parent_user_id': instance.parentUserId,
      'parent_user_name': instance.parentUserName,
    };
