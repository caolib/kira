class Author {
  final String name;
  final String pathWord;

  Author({required this.name, required this.pathWord});

  factory Author.fromJson(Map<String, dynamic> json) =>
      Author(name: json['name'] ?? '', pathWord: json['path_word'] ?? '');

  Map<String, dynamic> toJson() => {'name': name, 'path_word': pathWord};
}

class MangaBanner {
  final String cover;
  final String brief;
  final String outUuid;
  final int type;
  final Comic? comic;

  const MangaBanner({
    required this.cover,
    required this.brief,
    required this.outUuid,
    this.type = 0,
    this.comic,
  });

  factory MangaBanner.fromJson(Map<String, dynamic> json) => MangaBanner(
    cover: json['cover']?.toString() ?? '',
    brief: json['brief']?.toString() ?? '',
    outUuid: json['out_uuid']?.toString() ?? '',
    type: json['type'] is int ? json['type'] as int : 0,
    comic: json['comic'] is Map
        ? Comic.fromJson(Map<String, dynamic>.from(json['comic']))
        : null,
  );

  Map<String, dynamic> toJson() => {
    'cover': cover,
    'brief': brief,
    'out_uuid': outUuid,
    'type': type,
    'comic': comic?.toJson(),
  };
}

class MangaHome {
  final List<MangaBanner> banners;
  final List<Comic> recommendations;

  const MangaHome({this.banners = const [], this.recommendations = const []});

  factory MangaHome.fromJson(Map<String, dynamic> json) => MangaHome(
    banners:
        (json['banners'] as List?)
            ?.map((e) => MangaBanner.fromJson(Map<String, dynamic>.from(e)))
            .toList() ??
        const [],
    recommendations: _parseRecList(json['recs']),
  );

  Map<String, dynamic> toJson() => {
    'banners': banners.map((e) => e.toJson()).toList(),
    'recs': {
      'list': recommendations.map((e) => {'comic': e.toJson()}).toList(),
    },
  };

  static List<Comic> _parseRecList(dynamic section) {
    final list = section is Map ? section['list'] as List? : null;
    if (list == null) return const [];
    return list
        .where((e) => e is Map && e['comic'] is Map)
        .map(
          (e) => Comic.fromJson(Map<String, dynamic>.from((e as Map)['comic'])),
        )
        .toList();
  }
}

/// COPY 首页专题条目
class MangaTopic {
  final String title;
  final String cover;
  final String period;
  final String pathWord;
  final String brief;
  final int type;
  final String? datetimeCreated;

  const MangaTopic({
    required this.title,
    required this.cover,
    required this.period,
    required this.pathWord,
    required this.brief,
    required this.type,
    this.datetimeCreated,
  });

  factory MangaTopic.fromJson(Map<String, dynamic> json) => MangaTopic(
    title: json['title']?.toString() ?? '',
    cover: json['cover']?.toString() ?? '',
    period: json['period']?.toString() ?? '',
    pathWord: json['path_word']?.toString() ?? '',
    brief: json['brief']?.toString() ?? '',
    type: json['type'] is int ? json['type'] as int : 0,
    datetimeCreated: json['datetime_created']?.toString(),
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'cover': cover,
    'period': period,
    'path_word': pathWord,
    'brief': brief,
    'type': type,
    'datetime_created': datetimeCreated,
  };
}

/// COPY 漫画首页
class CopyMangaHome {
  final List<MangaBanner> banners;
  final List<Comic> recComics;
  final List<Comic> rankDayComics;
  final List<Comic> rankWeekComics;
  final List<Comic> rankMonthComics;
  final List<Comic> hotComics;
  final List<Comic> newComics;
  final List<Comic> finishComics;
  final List<MangaTopic> topics;
  final List<MangaTopic> topicsList;

  const CopyMangaHome({
    this.banners = const [],
    this.recComics = const [],
    this.rankDayComics = const [],
    this.rankWeekComics = const [],
    this.rankMonthComics = const [],
    this.hotComics = const [],
    this.newComics = const [],
    this.finishComics = const [],
    this.topics = const [],
    this.topicsList = const [],
  });

  factory CopyMangaHome.fromJson(Map<String, dynamic> json) => CopyMangaHome(
    banners:
        (json['banners'] as List?)
            ?.map((e) => MangaBanner.fromJson(Map<String, dynamic>.from(e)))
            .where((b) => b.type == 1)
            .toList() ??
        const [],
    recComics: _parseComicSection(json['recComics']),
    rankDayComics: _parseComicSection(json['rankDayComics']),
    rankWeekComics: _parseComicSection(json['rankWeekComics']),
    rankMonthComics: _parseComicSection(json['rankMonthComics']),
    hotComics: _parseComicSection(json['hotComics']),
    newComics: _parseComicSection(json['newComics']),
    finishComics: _parseFinishSection(json['finishComics']),
    topics: _parseTopicList(json['topics']),
    topicsList: _parseTopicList(json['topicsList']),
  );

  Map<String, dynamic> toJson() => {
    'banners': banners.map((e) => e.toJson()).toList(),
    'recComics': {
      'list': recComics.map((e) => {'comic': e.toJson()}).toList(),
    },
    'rankDayComics': {
      'list': rankDayComics.map((e) => {'comic': e.toJson()}).toList(),
    },
    'rankWeekComics': {
      'list': rankWeekComics.map((e) => {'comic': e.toJson()}).toList(),
    },
    'rankMonthComics': {
      'list': rankMonthComics.map((e) => {'comic': e.toJson()}).toList(),
    },
    'hotComics': hotComics.map((e) => {'comic': e.toJson()}).toList(),
    'newComics': newComics.map((e) => {'comic': e.toJson()}).toList(),
    'finishComics': {'list': finishComics.map((e) => e.toJson()).toList()},
    'topics': {'list': topics.map((e) => e.toJson()).toList()},
    'topicsList': {'list': topicsList.map((e) => e.toJson()).toList()},
  };

  static List<Comic> _parseComicSection(dynamic section) {
    // recComics / rank*：{list:[{comic:{...}}]}；hot/new：[{comic:{...}}] 裸数组
    final list = section is Map
        ? section['list'] as List?
        : (section is List ? section : null);
    if (list == null) return const [];
    return list
        .where((e) => e is Map && e['comic'] is Map)
        .map(
          (e) => Comic.fromJson(Map<String, dynamic>.from((e as Map)['comic'])),
        )
        .toList();
  }

  static List<Comic> _parseFinishSection(dynamic section) {
    // finishComics：list[] 本身即漫画对象
    final list = section is Map ? section['list'] as List? : null;
    if (list == null) return const [];
    return list
        .whereType<Map>()
        .map((e) => Comic.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static List<MangaTopic> _parseTopicList(dynamic section) {
    final list = section is Map ? section['list'] as List? : null;
    if (list == null) return const [];
    return list
        .whereType<Map>()
        .map((e) => MangaTopic.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}

class Theme {
  final String name;
  final String pathWord;
  final int count;

  Theme({required this.name, required this.pathWord, this.count = 0});

  factory Theme.fromJson(Map<String, dynamic> json) => Theme(
    name: json['name'] ?? '',
    pathWord: json['path_word'] ?? '',
    count: json['count'] ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'path_word': pathWord,
    'count': count,
  };
}

class ComicGroup {
  final String pathWord;
  final int count;
  final String name;

  ComicGroup({required this.pathWord, required this.count, required this.name});

  factory ComicGroup.fromJson(Map<String, dynamic> json) => ComicGroup(
    pathWord: json['path_word'] ?? '',
    count: json['count'] ?? 0,
    name: json['name'] ?? '',
  );

  Map<String, dynamic> toJson() => {
    'path_word': pathWord,
    'count': count,
    'name': name,
  };
}

class Comic {
  final String? uuid;
  final String name;
  final String pathWord;
  final String cover;
  final int popular;
  final List<Author> authors;
  final List<Theme> themes;
  final String? datetimeUpdated;
  final String? brief;
  final Map<String, dynamic>? status;
  final Map<String, dynamic>? lastChapter;
  final String? lastChapterId;
  final String? lastChapterName;
  final Map<String, ComicGroup>? groups;
  final Map<String, dynamic>? region;

  Comic({
    this.uuid,
    required this.name,
    required this.pathWord,
    required this.cover,
    this.popular = 0,
    this.authors = const [],
    this.themes = const [],
    this.datetimeUpdated,
    this.brief,
    this.status,
    this.lastChapter,
    this.lastChapterId,
    this.lastChapterName,
    this.groups,
    this.region,
  });

  factory Comic.fromJson(Map<String, dynamic> json) => Comic(
    uuid: json['uuid']?.toString(),
    name: json['name'] ?? '',
    pathWord: json['path_word'] ?? '',
    cover: json['cover'] ?? '',
    popular: json['popular'] ?? 0,
    authors:
        (json['author'] as List?)?.map((a) => Author.fromJson(a)).toList() ??
        [],
    themes:
        (json['theme'] as List?)?.map((t) => Theme.fromJson(t)).toList() ?? [],
    datetimeUpdated: json['datetime_updated'],
    brief: json['brief'],
    status: json['status'] is Map ? json['status'] : null,
    lastChapter: json['last_chapter'] is Map ? json['last_chapter'] : null,
    lastChapterId: json['last_chapter_id']?.toString(),
    lastChapterName: json['last_chapter_name']?.toString(),
    groups: json['groups'] is Map
        ? (json['groups'] as Map).map(
            (k, v) => MapEntry(
              k.toString(),
              ComicGroup.fromJson(Map<String, dynamic>.from(v)),
            ),
          )
        : null,
    region: json['region'] is Map ? json['region'] : null,
  );

  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'name': name,
    'path_word': pathWord,
    'cover': cover,
    'popular': popular,
    'author': authors.map((a) => a.toJson()).toList(),
    'theme': themes.map((t) => t.toJson()).toList(),
    'datetime_updated': datetimeUpdated,
    'brief': brief,
    'status': status,
    'last_chapter': lastChapter,
    'last_chapter_id': lastChapterId,
    'last_chapter_name': lastChapterName,
    'groups': groups?.map((k, v) => MapEntry(k, v.toJson())),
    'region': region,
  };

  factory Comic.fromDetailJson(Map<String, dynamic> json) {
    final comic = Comic.fromJson(json['comic']);
    final groupsMap = <String, ComicGroup>{};
    if (json['groups'] is Map) {
      (json['groups'] as Map).forEach((k, v) {
        groupsMap[k] = ComicGroup.fromJson(v);
      });
    }
    return comic.copyWith(
      popular: json['popular'] as int? ?? comic.popular,
      groups: groupsMap.isEmpty ? comic.groups : groupsMap,
    );
  }

  Comic copyWith({
    String? uuid,
    String? name,
    String? pathWord,
    String? cover,
    int? popular,
    List<Author>? authors,
    List<Theme>? themes,
    String? datetimeUpdated,
    String? brief,
    Map<String, dynamic>? status,
    Map<String, dynamic>? lastChapter,
    String? lastChapterId,
    String? lastChapterName,
    Map<String, ComicGroup>? groups,
    Map<String, dynamic>? region,
  }) {
    return Comic(
      uuid: uuid ?? this.uuid,
      name: name ?? this.name,
      pathWord: pathWord ?? this.pathWord,
      cover: cover ?? this.cover,
      popular: popular ?? this.popular,
      authors: authors ?? this.authors,
      themes: themes ?? this.themes,
      datetimeUpdated: datetimeUpdated ?? this.datetimeUpdated,
      brief: brief ?? this.brief,
      status: status ?? this.status,
      lastChapter: lastChapter ?? this.lastChapter,
      lastChapterId: lastChapterId ?? this.lastChapterId,
      lastChapterName: lastChapterName ?? this.lastChapterName,
      groups: groups ?? this.groups,
      region: region ?? this.region,
    );
  }
}

class BookshelfItem {
  final Comic comic;
  final String? lastBrowseId;
  final String? lastBrowseName;

  BookshelfItem({required this.comic, this.lastBrowseId, this.lastBrowseName});

  bool get hasUpdate =>
      lastBrowseId != null &&
      comic.lastChapterId != null &&
      lastBrowseId != comic.lastChapterId;

  factory BookshelfItem.fromJson(Map<String, dynamic> json) => BookshelfItem(
    comic: Comic.fromJson(Map<String, dynamic>.from(json['comic'] ?? {})),
    lastBrowseId: json['last_browse_id']?.toString(),
    lastBrowseName: json['last_browse_name']?.toString(),
  );

  Map<String, dynamic> toJson() => {
    'comic': comic.toJson(),
    'last_browse_id': lastBrowseId,
    'last_browse_name': lastBrowseName,
  };
}

class BrowseHistoryItem {
  final int id;
  final Comic comic;
  final String? lastBrowseId;
  final String? lastBrowseName;

  BrowseHistoryItem({
    required this.id,
    required this.comic,
    this.lastBrowseId,
    this.lastBrowseName,
  });
}
