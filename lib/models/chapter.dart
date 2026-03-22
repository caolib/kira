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
  });

  factory ChapterDetail.fromJson(Map<String, dynamic> json) {
    final chapter = json['chapter'] as Map<String, dynamic>;
    final images = (chapter['contents'] as List?)
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
    );
  }
}
