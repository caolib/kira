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
///
/// 数据源感知：COPY 源没有热门搜索词接口（请求返回 HTML），因此它的
/// init 数据只含标签，[SearchInitData.keywords] 为空。
/// 两个源使用各自的缓存条目，避免互相覆盖。
///
/// 题材/热搜都很少变化，启用 [skipApiIfCacheFresh]：TTL 内直接读缓存、
/// 不发请求。下拉刷新走 [forceRefreshApi] 绕过缓存。
class SearchInitRepository extends CachedRepository<SearchInitData> {
  SearchInitRepository({this.source = 'hot', ApiClient? api})
    : _api = api ?? ApiClient(),
      super(
        cacheKey: 'search_init_v3_$source',
        ttl: const Duration(hours: 12),
        skipApiIfCacheFresh: true,
        deserialize: SearchInitData.fromJson,
        serialize: (d) => d.toJson(),
      );

  /// 'hot'（默认）或 'copy'，决定请求哪个源、读写哪条缓存。
  final String source;

  final ApiClient _api;

  @override
  Future<SearchInitData> fetchFromApi() async {
    if (source == 'copy') {
      final tags = await _api.manga.getCopyComicTags();
      return SearchInitData(keywords: const [], tags: tags);
    }
    // 用记录版 wait 并行：任一请求失败时另一个的错误也会被消费，
    // 否则先失败的那个会让另一个变成未捕获的异步错误。
    final (keywords, tags) = await (
      _api.manga.getHotKeywords(),
      _api.manga.getComicTags(),
    ).wait;
    return SearchInitData(keywords: keywords, tags: tags);
  }
}

/// Cached repository for COPY 源的大分类筛选项（全部/日漫/韓漫/美漫/已完結）。
///
/// 这些分类是服务端固定枚举，几乎不变，TTL 内直接读缓存不发请求。
class CopyFilterRepository extends CachedRepository<m.CopyFilterOptions> {
  CopyFilterRepository({ApiClient? api})
    : _api = api ?? ApiClient(),
      super(
        cacheKey: 'copy_filter_options_v1',
        ttl: const Duration(hours: 12),
        skipApiIfCacheFresh: true,
        deserialize: m.CopyFilterOptions.fromJson,
        serialize: (d) => d.toJson(),
      );

  final ApiClient _api;

  @override
  Future<m.CopyFilterOptions> fetchFromApi() =>
      _api.manga.getCopyFilterOptions();
}
