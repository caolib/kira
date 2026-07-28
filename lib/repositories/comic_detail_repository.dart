import '../api/api_client.dart';
import '../models/cached_repository.dart';
import '../models/chapter.dart';
import '../models/comic.dart' hide Theme;

/// Wraps the comic detail data for cache storage.
class ComicDetailData {
  final Comic comic;
  final List<Chapter> chapters;
  final String selectedGroup;
  final int chapterPage;
  final int chapterTotal;
  final bool isCollected;

  const ComicDetailData({
    required this.comic,
    required this.chapters,
    required this.selectedGroup,
    required this.chapterPage,
    required this.chapterTotal,
    required this.isCollected,
  });

  factory ComicDetailData.fromJson(Map<String, dynamic> json) =>
      ComicDetailData(
        comic: Comic.fromJson(Map<String, dynamic>.from(json['comic'])),
        chapters:
            (json['chapters'] as List?)
                ?.map((j) => Chapter.fromJson(Map<String, dynamic>.from(j)))
                .toList() ??
            [],
        selectedGroup: json['selectedGroup']?.toString() ?? 'default',
        chapterPage: json['chapterPage'] as int? ?? 0,
        chapterTotal: json['chapterTotal'] as int? ?? 0,
        isCollected: json['isCollected'] == true,
      );

  Map<String, dynamic> toJson() => {
    'comic': comic.toJson(),
    'chapters': chapters.map((c) => c.toJson()).toList(),
    'selectedGroup': selectedGroup,
    'chapterPage': chapterPage,
    'chapterTotal': chapterTotal,
    'isCollected': isCollected,
  };
}

/// Cached repository for comic detail page.
///
/// Takes [pathWord] as a constructor parameter to build a per-comic cache key.
class ComicDetailRepository extends CachedRepository<ComicDetailData> {
  /// How long an untouched comic detail entry survives.
  ///
  /// This entry carries the full chapter list — the largest payload the app
  /// caches — and one is written per comic ever opened. Without a TTL they
  /// accumulated forever. Because [skipApiIfCacheFresh] is off, [load] still
  /// hits the API every time, so the TTL only bounds how long a comic the user
  /// stopped reading keeps occupying storage; anything reopened is rewritten
  /// and its TTL renewed.
  static const cacheTtl = Duration(days: 7);

  ComicDetailRepository(String pathWord)
    : super(
        cacheKey: 'comic_detail_$pathWord',
        ttl: cacheTtl,
        deserialize: ComicDetailData.fromJson,
        serialize: (d) => d.toJson(),
      );

  final _api = ApiClient();

  @override
  Future<ComicDetailData> fetchFromApi() async {
    // Only fetches the comic detail; chapters and collect state are loaded
    // separately by the page. The page will call saveToCache after assembling
    // the full data.
    final comic = await _api.manga.getComicDetail(_pathWord);
    return ComicDetailData(
      comic: comic,
      chapters: [],
      selectedGroup: 'default',
      chapterPage: 0,
      chapterTotal: 0,
      isCollected: false,
    );
  }

  String get _pathWord => cacheKey.replaceFirst('comic_detail_', '');
}
