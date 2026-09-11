import '../api/api_client.dart';
import '../models/api_ordering.dart';
import '../models/cached_repository.dart';
import '../models/comic.dart' hide Theme;

/// Wraps comic bookshelf data for cache storage.
class ComicBookshelfData {
  final List<BookshelfItem> items;
  final int total;
  final DateTime? cacheTime;

  const ComicBookshelfData({
    required this.items,
    required this.total,
    this.cacheTime,
  });

  factory ComicBookshelfData.fromJson(Map<String, dynamic> json) =>
      ComicBookshelfData(
        items:
            (json['items'] as List?)
                ?.map(
                  (e) => BookshelfItem.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList() ??
            [],
        total: json['total'] as int? ?? 0,
        cacheTime: json['cache_time'] is int
            ? DateTime.fromMillisecondsSinceEpoch(json['cache_time'] as int)
            : null,
      );

  Map<String, dynamic> toJson() => {
    'items': items.map((e) => e.toJson()).toList(),
    'total': total,
    'cache_time': cacheTime?.millisecondsSinceEpoch,
  };
}

/// Cached repository for the comic bookshelf with 30-min TTL and
/// skip-api-if-cache-fresh behaviour.
class ComicBookshelfRepository extends CachedRepository<ComicBookshelfData> {
  ComicBookshelfRepository()
    : super(
        cacheKey: 'bookshelf_comic',
        ttl: const Duration(minutes: 30),
        skipApiIfCacheFresh: true,
        deserialize: ComicBookshelfData.fromJson,
        serialize: (d) => d.toJson(),
      );

  final _api = ApiClient();

  String _ordering = ApiOrdering.datetimeUpdated;

  /// Update the ordering parameter before fetching.
  set ordering(String value) => _ordering = value;

  @override
  Future<ComicBookshelfData> fetchFromApi() async {
    final data = await _api.manga.getBookshelf(ordering: _ordering);
    return ComicBookshelfData(
      items: data.list,
      total: data.total,
      cacheTime: DateTime.now(),
    );
  }
}
