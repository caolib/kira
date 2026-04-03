import 'chapter_comment.dart';

class Chapter {
  final String uuid;
  final int index;
  final String name;
  final int size;
  final String? datetimeCreated;
  final String? prev;
  final String? next;
  final int ordered;

  Chapter({
    required this.uuid,
    required this.index,
    required this.name,
    this.size = 0,
    this.datetimeCreated,
    this.prev,
    this.next,
    this.ordered = 0,
  });

  factory Chapter.fromJson(Map<String, dynamic> json) => Chapter(
    uuid: json['uuid'] ?? '',
    index: json['index'] ?? 0,
    name: json['name'] ?? '',
    size: json['size'] ?? 0,
    datetimeCreated: json['datetime_created'],
    prev: json['prev'],
    next: json['next'],
    ordered: json['ordered'] ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'index': index,
    'name': name,
    'size': size,
    'datetime_created': datetimeCreated,
    'prev': prev,
    'next': next,
    'ordered': ordered,
  };
}

class ChapterDetail extends Chapter {
  final List<String> contents;
  final bool isLong;
  final bool isDownloaded;
  final List<ChapterComment> comments;
  final int commentTotal;

  ChapterDetail({
    required super.uuid,
    required super.index,
    required super.name,
    super.size,
    super.datetimeCreated,
    super.prev,
    super.next,
    super.ordered,
    required this.contents,
    this.isLong = false,
    this.isDownloaded = false,
    this.comments = const [],
    this.commentTotal = 0,
  });

  factory ChapterDetail.fromJson(Map<String, dynamic> json) {
    final chapter = json['chapter'] as Map<String, dynamic>;
    final images =
        (chapter['contents'] as List?)
            ?.map((c) => c['url'] as String)
            .toList() ??
        [];
    return ChapterDetail(
      uuid: chapter['uuid'] ?? '',
      index: chapter['index'] ?? 0,
      name: chapter['name'] ?? '',
      size: chapter['size'] ?? 0,
      datetimeCreated: chapter['datetime_created'],
      prev: chapter['prev'],
      next: chapter['next'],
      ordered: chapter['ordered'] ?? 0,
      contents: images,
      isLong: chapter['is_long'] ?? false,
      comments: const [],
      commentTotal: 0,
    );
  }

  factory ChapterDetail.fromDownloadedJson(Map<String, dynamic> json) =>
      ChapterDetail(
        uuid: json['uuid'] ?? '',
        index: json['index'] ?? 0,
        name: json['name'] ?? '',
        size: json['size'] ?? 0,
        datetimeCreated: json['datetime_created'],
        prev: json['prev'],
        next: json['next'],
        ordered: json['ordered'] ?? 0,
        contents:
            (json['contents'] as List?)
                ?.map((item) => item.toString())
                .toList() ??
            const [],
        isLong: json['is_long'] == true,
        isDownloaded: true,
        comments:
            (json['comments'] as List?)
                ?.map(
                  (item) => ChapterComment.fromJson(
                    Map<String, dynamic>.from(item as Map),
                  ),
                )
                .toList() ??
            const [],
        commentTotal: json['comment_total'] as int? ?? 0,
      );

  ChapterDetail copyWith({
    String? uuid,
    int? index,
    String? name,
    int? size,
    String? datetimeCreated,
    String? prev,
    String? next,
    int? ordered,
    List<String>? contents,
    bool? isLong,
    bool? isDownloaded,
    List<ChapterComment>? comments,
    int? commentTotal,
  }) {
    return ChapterDetail(
      uuid: uuid ?? this.uuid,
      index: index ?? this.index,
      name: name ?? this.name,
      size: size ?? this.size,
      datetimeCreated: datetimeCreated ?? this.datetimeCreated,
      prev: prev ?? this.prev,
      next: next ?? this.next,
      ordered: ordered ?? this.ordered,
      contents: contents ?? this.contents,
      isLong: isLong ?? this.isLong,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      comments: comments ?? this.comments,
      commentTotal: commentTotal ?? this.commentTotal,
    );
  }

  Map<String, dynamic> toDownloadJson() => {
    'uuid': uuid,
    'index': index,
    'name': name,
    'size': size,
    'datetime_created': datetimeCreated,
    'prev': prev,
    'next': next,
    'ordered': ordered,
    'contents': contents,
    'is_long': isLong,
    'comments': comments.map((item) => item.toJson()).toList(),
    'comment_total': commentTotal,
  };
}
