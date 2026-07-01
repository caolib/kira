import '../api/api_client.dart';
import '../models/cached_repository.dart';
import '../models/comic.dart' as m;

/// Simple data holder for search init (hot keywords + tags).
class SearchInitData {
  final List<String> keywords;
  final List<m.Theme> tags;

  const SearchInitData({required this.keywords, required this.tags});

  factory SearchInitData.fromJson(Map<String, dynamic> json) => SearchInitData(
    keywords: List<String>.from(json['keywords'] ?? []),
    tags:
        (json['tags'] as List?)?.map((t) => m.Theme.fromJson(t)).toList() ?? [],
  );

  Map<String, dynamic> toJson() => {
    'keywords': keywords,
    'tags': tags.map((t) => t.toJson()).toList(),
  };
}

/// Cached repository for search init data (hot keywords + tags).
class SearchInitRepository extends CachedRepository<SearchInitData> {
  SearchInitRepository()
    : super(
        cacheKey: 'search_init_v2',
        ttl: const Duration(hours: 1),
        deserialize: SearchInitData.fromJson,
        serialize: (d) => d.toJson(),
      );

  final _api = ApiClient();

  @override
  Future<SearchInitData> fetchFromApi() async {
    final keywordsFuture = _api.getHotKeywords();
    final tagsFuture = _api.getComicTags();
    final keywords = await keywordsFuture;
    final tags = await tagsFuture;
    return SearchInitData(keywords: keywords, tags: tags);
  }
}
