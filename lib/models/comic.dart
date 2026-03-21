class Author {
  final String name;
  final String pathWord;

  Author({required this.name, required this.pathWord});

  factory Author.fromJson(Map<String, dynamic> json) => Author(
        name: json['name'] ?? '',
        pathWord: json['path_word'] ?? '',
      );
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
        authors: (json['author'] as List?)
                ?.map((a) => Author.fromJson(a))
                .toList() ??
            [],
        themes: (json['theme'] as List?)
                ?.map((t) => Theme.fromJson(t))
                .toList() ??
            [],
        datetimeUpdated: json['datetime_updated'],
        brief: json['brief'],
        status: json['status'] is Map ? json['status'] : null,
        lastChapter: json['last_chapter'] is Map ? json['last_chapter'] : null,
        lastChapterId: json['last_chapter_id']?.toString(),
        lastChapterName: json['last_chapter_name']?.toString(),
        region: json['region'] is Map ? json['region'] : null,
      );

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
