// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'comic.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Author _$AuthorFromJson(Map<String, dynamic> json) => Author(
  name: json['name'] as String? ?? '',
  pathWord: json['path_word'] as String? ?? '',
);

Map<String, dynamic> _$AuthorToJson(Author instance) => <String, dynamic>{
  'name': instance.name,
  'path_word': instance.pathWord,
};

MangaTopic _$MangaTopicFromJson(Map<String, dynamic> json) => MangaTopic(
  title: json['title'] as String? ?? '',
  cover: json['cover'] as String? ?? '',
  period: json['period'] as String? ?? '',
  pathWord: json['path_word'] as String? ?? '',
  brief: json['brief'] as String? ?? '',
  type: _intFromDynamic(json['type']),
  datetimeCreated: json['datetime_created'] as String?,
);

Map<String, dynamic> _$MangaTopicToJson(MangaTopic instance) =>
    <String, dynamic>{
      'title': instance.title,
      'cover': instance.cover,
      'period': instance.period,
      'path_word': instance.pathWord,
      'brief': instance.brief,
      'type': instance.type,
      'datetime_created': instance.datetimeCreated,
    };

Theme _$ThemeFromJson(Map<String, dynamic> json) => Theme(
  name: json['name'] as String? ?? '',
  pathWord: json['path_word'] as String? ?? '',
  count: (json['count'] as num?)?.toInt() ?? 0,
);

Map<String, dynamic> _$ThemeToJson(Theme instance) => <String, dynamic>{
  'name': instance.name,
  'path_word': instance.pathWord,
  'count': instance.count,
};

ComicGroup _$ComicGroupFromJson(Map<String, dynamic> json) => ComicGroup(
  pathWord: json['path_word'] as String? ?? '',
  count: (json['count'] as num?)?.toInt() ?? 0,
  name: json['name'] as String? ?? '',
);

Map<String, dynamic> _$ComicGroupToJson(ComicGroup instance) =>
    <String, dynamic>{
      'path_word': instance.pathWord,
      'count': instance.count,
      'name': instance.name,
    };
