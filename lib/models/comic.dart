class Author {
  final String name;
  final String pathWord;

  Author({required this.name, required this.pathWord});

  factory Author.fromJson(Map<String, dynamic> json) =>
      Author(name: json['name'] ?? '', pathWord: json['path_word'] ?? '');

  Map<String, dynamic> toJson() => {'name': name, 'path_word': pathWord};
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
    return Comic(
      uuid: comic.uuid,
      name: comic.name,
      pathWord: comic.pathWord,
      cover: comic.cover,
      popular: json['popular'] ?? comic.popular,
      authors: comic.authors,
      themes: comic.themes,
      datetimeUpdated: comic.datetimeUpdated,
      brief: comic.brief,
      status: comic.status,
      lastChapter: comic.lastChapter,
      lastChapterId: comic.lastChapterId,
      lastChapterName: comic.lastChapterName,
      groups: groupsMap,
      region: comic.region,
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
}
