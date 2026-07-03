// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chapter_comment.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChapterComment _$ChapterCommentFromJson(Map<String, dynamic> json) =>
    ChapterComment(
      id: _intOrStringToInt(json['id']),
      createAt: json['create_at'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      userName: json['user_name'] as String? ?? '匿名用户',
      userAvatar: json['user_avatar'] as String? ?? '',
      comment: json['comment'] as String? ?? '',
    );

Map<String, dynamic> _$ChapterCommentToJson(ChapterComment instance) =>
    <String, dynamic>{
      'id': instance.id,
      'create_at': instance.createAt,
      'user_id': instance.userId,
      'user_name': instance.userName,
      'user_avatar': instance.userAvatar,
      'comment': instance.comment,
    };
