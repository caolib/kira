import 'package:json_annotation/json_annotation.dart';

part 'anime.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class AnimeTag {
  @JsonKey(defaultValue: '')
  final String name;
  @JsonKey(defaultValue: '')
  final String pathWord;

  const AnimeTag({required this.name, required this.pathWord});

  factory AnimeTag.fromJson(Map<String, dynamic> json) =>
      _$AnimeTagFromJson(json);

  Map<String, dynamic> toJson() => _$AnimeTagToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class AnimeCompany {
  @JsonKey(defaultValue: '')
  final String name;
  @JsonKey(defaultValue: '')
  final String pathWord;

  const AnimeCompany({required this.name, required this.pathWord});

  factory AnimeCompany.fromJson(Map<String, dynamic> json) =>
      _$AnimeCompanyFromJson(json);

  Map<String, dynamic> toJson() => _$AnimeCompanyToJson(this);
}

class Anime {
  final String? uuid;
  final String name;
  final String pathWord;
  final String cover;
  final int popular;
  final List<AnimeTag> themes;
  final AnimeCompany? company;
  final String? years;
  final int count;
  final String? brief;
  final String? datetimeUpdated;
  final Map<String, dynamic>? freeType;
  final Map<String, dynamic>? grade;
  final Map<String, dynamic>? cartoonType;
  final Map<String, dynamic>? category;
  final Map<String, dynamic>? lastChapter;
  final bool bSubtitle;

  const Anime({
    this.uuid,
    required this.name,
    required this.pathWord,
    required this.cover,
    this.popular = 0,
    this.themes = const [],
    this.company,
    this.years,
    this.count = 0,
    this.brief,
    this.datetimeUpdated,
    this.freeType,
    this.grade,
    this.cartoonType,
    this.category,
    this.lastChapter,
    this.bSubtitle = false,
  });

  factory Anime.fromJson(Map<String, dynamic> json) => Anime(
    uuid: json['uuid']?.toString(),
    name: json['name']?.toString() ?? '',
    pathWord: json['path_word']?.toString() ?? '',
    cover: json['cover']?.toString() ?? '',
    popular: json['popular'] as int? ?? 0,
    themes:
        (json['theme'] as List?)
            ?.map((e) => AnimeTag.fromJson(Map<String, dynamic>.from(e)))
            .toList() ??
        const [],
    company: json['company'] is Map
        ? AnimeCompany.fromJson(Map<String, dynamic>.from(json['company']))
        : null,
    years: json['years']?.toString(),
    count: json['count'] as int? ?? 0,
    brief: json['brief']?.toString(),
    datetimeUpdated: json['datetime_updated']?.toString(),
    freeType: json['free_type'] is Map
        ? Map<String, dynamic>.from(json['free_type'])
        : null,
    grade: json['grade'] is Map
        ? Map<String, dynamic>.from(json['grade'])
        : null,
    cartoonType: json['cartoon_type'] is Map
        ? Map<String, dynamic>.from(json['cartoon_type'])
        : null,
    category: json['category'] is Map
        ? Map<String, dynamic>.from(json['category'])
        : null,
    lastChapter: json['last_chapter'] is Map
        ? Map<String, dynamic>.from(json['last_chapter'])
        : null,
    bSubtitle: json['b_subtitle'] == true,
  );

  factory Anime.fromDetailJson(Map<String, dynamic> json) {
    final animeJson = json['cartoon'] is Map
        ? Map<String, dynamic>.from(json['cartoon'])
        : <String, dynamic>{};
    if (json['popular'] != null) animeJson['popular'] = json['popular'];
    return Anime.fromJson(animeJson);
  }

  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'name': name,
    'path_word': pathWord,
    'cover': cover,
    'popular': popular,
    'theme': themes.map((e) => e.toJson()).toList(),
    'company': company?.toJson(),
    'years': years,
    'count': count,
    'brief': brief,
    'datetime_updated': datetimeUpdated,
    'free_type': freeType,
    'grade': grade,
    'cartoon_type': cartoonType,
    'category': category,
    'last_chapter': lastChapter,
    'b_subtitle': bSubtitle,
  };
}

class AnimeQuery {
  final bool isLogin;
  final bool isMobileBind;
  final bool isVip;
  final bool isLock;
  final int? collect;

  const AnimeQuery({
    required this.isLogin,
    required this.isMobileBind,
    required this.isVip,
    required this.isLock,
    this.collect,
  });

  bool get isCollected => collect != null;

  factory AnimeQuery.fromJson(Map<String, dynamic> json) => AnimeQuery(
    isLogin: json['is_login'] == true,
    isMobileBind: json['is_mobile_bind'] == true,
    isVip: json['is_vip'] == true,
    isLock: json['is_lock'] == true,
    collect: json['collect'] is int ? json['collect'] as int : null,
  );
}

class AnimeBookshelfItem {
  final Anime anime;
  final String? lastBrowseId;
  final String? lastBrowseName;

  const AnimeBookshelfItem({
    required this.anime,
    this.lastBrowseId,
    this.lastBrowseName,
  });

  factory AnimeBookshelfItem.fromJson(Map<String, dynamic> json) =>
      AnimeBookshelfItem(
        anime: Anime.fromJson(Map<String, dynamic>.from(json['anime'] ?? {})),
        lastBrowseId: json['last_browse_id']?.toString(),
        lastBrowseName: json['last_browse_name']?.toString(),
      );

  Map<String, dynamic> toJson() => {
    'anime': anime.toJson(),
    'last_browse_id': lastBrowseId,
    'last_browse_name': lastBrowseName,
  };
}

class AnimeBrowseHistoryItem {
  final int id;
  final Anime anime;
  final String? lastBrowseId;
  final String? lastBrowseName;

  const AnimeBrowseHistoryItem({
    required this.id,
    required this.anime,
    this.lastBrowseId,
    this.lastBrowseName,
  });
}

@JsonSerializable(fieldRename: FieldRename.snake)
class AnimeChapterLine {
  @JsonKey(defaultValue: '')
  final String name;
  @JsonKey(defaultValue: '')
  final String pathWord;
  @JsonKey(fromJson: _toBool)
  final bool config;

  const AnimeChapterLine({
    required this.name,
    required this.pathWord,
    required this.config,
  });

  factory AnimeChapterLine.fromJson(Map<String, dynamic> json) =>
      _$AnimeChapterLineFromJson(json);

  Map<String, dynamic> toJson() => _$AnimeChapterLineToJson(this);
}

bool _toBool(dynamic value) => value == true;

class AnimeChapter {
  final String name;
  final String uuid;
  final String vCover;
  final List<AnimeChapterLine> lines;

  const AnimeChapter({
    required this.name,
    required this.uuid,
    required this.vCover,
    this.lines = const [],
  });

  factory AnimeChapter.fromJson(Map<String, dynamic> json) => AnimeChapter(
    name: json['name']?.toString() ?? '',
    uuid: json['uuid']?.toString() ?? '',
    vCover: json['v_cover']?.toString() ?? '',
    lines:
        (json['lines'] as List?)
            ?.map(
              (e) => AnimeChapterLine.fromJson(Map<String, dynamic>.from(e)),
            )
            .toList() ??
        const [],
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'uuid': uuid,
    'v_cover': vCover,
    'lines': lines.map((e) => e.toJson()).toList(),
  };
}

class AnimePlayback {
  final Anime anime;
  final AnimePlaybackChapter chapter;
  final bool isLogin;
  final bool isMobileBind;
  final bool isVip;
  final bool isLock;

  const AnimePlayback({
    required this.anime,
    required this.chapter,
    required this.isLogin,
    required this.isMobileBind,
    required this.isVip,
    required this.isLock,
  });

  factory AnimePlayback.fromJson(Map<String, dynamic> json) => AnimePlayback(
    anime: Anime.fromJson(Map<String, dynamic>.from(json['cartoon'] ?? {})),
    chapter: AnimePlaybackChapter.fromJson(
      Map<String, dynamic>.from(json['chapter'] ?? {}),
    ),
    isLogin: json['is_login'] == true,
    isMobileBind: json['is_mobile_bind'] == true,
    isVip: json['is_vip'] == true,
    isLock: json['is_lock'] == true,
  );

  Map<String, dynamic> toJson() => {
    'cartoon': anime.toJson(),
    'chapter': chapter.toJson(),
    'is_login': isLogin,
    'is_mobile_bind': isMobileBind,
    'is_vip': isVip,
    'is_lock': isLock,
  };
}

class AnimePlaybackChapter {
  final int count;
  final String name;
  final String cover;
  final String? vid;
  final String video;
  final String uuid;
  final Map<String, AnimeChapterLine> lines;
  final List<String> videoList;
  final String vCover;

  const AnimePlaybackChapter({
    required this.count,
    required this.name,
    required this.cover,
    this.vid,
    required this.video,
    required this.uuid,
    this.lines = const {},
    this.videoList = const [],
    required this.vCover,
  });

  factory AnimePlaybackChapter.fromJson(Map<String, dynamic> json) {
    final linesJson = json['lines'];
    final videoListJson = json['video_list'];
    return AnimePlaybackChapter(
      count: json['count'] as int? ?? 0,
      name: json['name']?.toString() ?? '',
      cover: json['cover']?.toString() ?? '',
      vid: json['vid']?.toString(),
      video: json['video']?.toString() ?? '',
      uuid: json['uuid']?.toString() ?? '',
      lines: linesJson is Map
          ? linesJson.map(
              (key, value) => MapEntry(
                key.toString(),
                AnimeChapterLine.fromJson(Map<String, dynamic>.from(value)),
              ),
            )
          : const {},
      videoList: videoListJson is List
          ? videoListJson.map((e) => e.toString()).toList()
          : const [],
      vCover: json['v_cover']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'count': count,
    'name': name,
    'cover': cover,
    'vid': vid,
    'video': video,
    'uuid': uuid,
    'lines': lines.map((key, value) => MapEntry(key, value.toJson())),
    'video_list': videoList,
    'v_cover': vCover,
  };
}

class AnimeBanner {
  final String cover;
  final String brief;
  final String outUuid;
  final Anime? anime;

  const AnimeBanner({
    required this.cover,
    required this.brief,
    required this.outUuid,
    this.anime,
  });

  factory AnimeBanner.fromJson(Map<String, dynamic> json) => AnimeBanner(
    cover: json['cover']?.toString() ?? '',
    brief: json['brief']?.toString() ?? '',
    outUuid: json['out_uuid']?.toString() ?? '',
    anime: json['comic'] is Map
        ? Anime.fromJson(Map<String, dynamic>.from(json['comic']))
        : null,
  );

  Map<String, dynamic> toJson() => {
    'cover': cover,
    'brief': brief,
    'out_uuid': outUuid,
    'comic': anime?.toJson(),
  };
}

class AnimeUpdate {
  final String name;
  final String? datetimeCreated;
  final Anime anime;

  const AnimeUpdate({
    required this.name,
    required this.datetimeCreated,
    required this.anime,
  });

  factory AnimeUpdate.fromJson(Map<String, dynamic> json) => AnimeUpdate(
    name: json['name']?.toString() ?? '',
    datetimeCreated: json['datetime_created']?.toString(),
    anime: Anime.fromJson(Map<String, dynamic>.from(json['cartoon'] ?? {})),
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'datetime_created': datetimeCreated,
    'cartoon': anime.toJson(),
  };
}

class AnimeHome {
  final List<AnimeBanner> banners;
  final List<Anime> recommendations;
  final List<AnimeUpdate> updates;
  final List<Anime> classics;
  final List<Anime> hots;

  const AnimeHome({
    this.banners = const [],
    this.recommendations = const [],
    this.updates = const [],
    this.classics = const [],
    this.hots = const [],
  });

  factory AnimeHome.fromJson(Map<String, dynamic> json) => AnimeHome(
    banners:
        (json['banners'] as List?)
            ?.map((e) => AnimeBanner.fromJson(Map<String, dynamic>.from(e)))
            .toList() ??
        const [],
    recommendations: _parseRecList(json['recs']),
    updates:
        ((json['updateWeeklyFreeCartoons'] as Map?)?['list'] as List?)
            ?.map((e) => AnimeUpdate.fromJson(Map<String, dynamic>.from(e)))
            .toList() ??
        const [],
    classics: _parseRecList(json['recClassics']),
    hots: _parseRecList(json['recHots']),
  );

  Map<String, dynamic> toJson() => {
    'banners': banners.map((e) => e.toJson()).toList(),
    'recs': {
      'list': recommendations.map((e) => {'comic': e.toJson()}).toList(),
    },
    'updateWeeklyFreeCartoons': {
      'list': updates.map((e) => e.toJson()).toList(),
    },
    'recClassics': {
      'list': classics.map((e) => {'comic': e.toJson()}).toList(),
    },
    'recHots': {
      'list': hots.map((e) => {'comic': e.toJson()}).toList(),
    },
  };

  static List<Anime> _parseRecList(dynamic section) {
    final list = section is Map ? section['list'] as List? : null;
    if (list == null) return const [];
    return list
        .where((e) => e is Map && e['comic'] is Map)
        .map(
          (e) => Anime.fromJson(Map<String, dynamic>.from((e as Map)['comic'])),
        )
        .toList();
  }
}
