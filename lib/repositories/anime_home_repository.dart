import '../api/api_client.dart';
import '../models/anime.dart';
import '../models/cached_repository.dart';

/// Cached repository for the anime home page.
class AnimeHomeRepository extends CachedRepository<AnimeHome> {
  AnimeHomeRepository()
    : super(
        cacheKey: 'anime_home_v1',
        deserialize: AnimeHome.fromJson,
        serialize: (d) => d.toJson(),
      );

  final _api = ApiClient();

  @override
  Future<AnimeHome> fetchFromApi() => _api.anime.getAnimeHome();
}
