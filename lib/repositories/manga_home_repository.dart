import '../api/api_client.dart';
import '../models/api_ordering.dart';
import '../models/cached_repository.dart';
import '../models/comic.dart' hide Theme;

/// Wraps the manga home data and its ranking preview for cache storage.
class MangaHomeData {
  final MangaHome home;
  final List<Comic> ranking;

  const MangaHomeData({required this.home, required this.ranking});

  factory MangaHomeData.fromJson(Map<String, dynamic> json) => MangaHomeData(
    home: MangaHome.fromJson(Map<String, dynamic>.from(json['home'])),
    ranking:
        (json['ranking'] as List?)?.map((j) => Comic.fromJson(j)).toList() ??
        [],
  );

  Map<String, dynamic> toJson() => {
    'home': home.toJson(),
    'ranking': ranking.map((c) => c.toJson()).toList(),
  };
}

/// Wraps the copy manga home data for cache storage.
class CopyMangaHomeData {
  final CopyMangaHome home;

  const CopyMangaHomeData({required this.home});

  factory CopyMangaHomeData.fromJson(Map<String, dynamic> json) =>
      CopyMangaHomeData(
        home: CopyMangaHome.fromJson(Map<String, dynamic>.from(json['home'])),
      );

  Map<String, dynamic> toJson() => {'home': home.toJson()};
}

/// Dual-cached repository for the manga home page (HOT + COPY sources).
class MangaHomeRepository
    extends DualCachedRepository<MangaHomeData, CopyMangaHomeData> {
  MangaHomeRepository()
    : super(
        cacheKeyA: 'manga_home_v1',
        cacheKeyB: 'manga_home_copy_v1',
        ttlA: const Duration(hours: 1),
        ttlB: const Duration(hours: 1),
        deserializeA: MangaHomeData.fromJson,
        deserializeB: CopyMangaHomeData.fromJson,
        serializeA: (d) => d.toJson(),
        serializeB: (d) => d.toJson(),
      );

  final _api = ApiClient();

  @override
  Future<MangaHomeData> fetchAFromApi() async {
    final homeFuture = _api.manga.getMangaHome();
    final rankingFuture = _api.manga.getComicList(
      ordering: ApiOrdering.datetimeUpdated,
      limit: 6,
    );
    final home = await homeFuture;
    final ranking = await rankingFuture;
    return MangaHomeData(home: home, ranking: ranking.list);
  }

  @override
  Future<CopyMangaHomeData> fetchBFromApi() async {
    final home = await _api.manga.getCopyMangaHome();
    return CopyMangaHomeData(home: home);
  }
}
