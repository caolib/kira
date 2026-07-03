// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'anime.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AnimeTag _$AnimeTagFromJson(Map<String, dynamic> json) => AnimeTag(
  name: json['name'] as String? ?? '',
  pathWord: json['path_word'] as String? ?? '',
);

Map<String, dynamic> _$AnimeTagToJson(AnimeTag instance) => <String, dynamic>{
  'name': instance.name,
  'path_word': instance.pathWord,
};

AnimeCompany _$AnimeCompanyFromJson(Map<String, dynamic> json) => AnimeCompany(
  name: json['name'] as String? ?? '',
  pathWord: json['path_word'] as String? ?? '',
);

Map<String, dynamic> _$AnimeCompanyToJson(AnimeCompany instance) =>
    <String, dynamic>{'name': instance.name, 'path_word': instance.pathWord};

AnimeChapterLine _$AnimeChapterLineFromJson(Map<String, dynamic> json) =>
    AnimeChapterLine(
      name: json['name'] as String? ?? '',
      pathWord: json['path_word'] as String? ?? '',
      config: _toBool(json['config']),
    );

Map<String, dynamic> _$AnimeChapterLineToJson(AnimeChapterLine instance) =>
    <String, dynamic>{
      'name': instance.name,
      'path_word': instance.pathWord,
      'config': instance.config,
    };
