import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/anime/anime_api.dart';
import '../api/api_client.dart';
import '../api/manga/manga_api.dart';
import '../api/network/network_api.dart';
import '../api/user/user_api.dart';
import '../models/user_manager.dart';
import '../utils/data_cache.dart';

/// Provides the shared [UserManager] singleton.
final userManagerProvider = Provider<UserManager>((ref) => UserManager());

/// Provides the shared [ApiClient] singleton.
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

/// Shortcut provider for [MangaApi].
final mangaApiProvider = Provider<MangaApi>((ref) => ApiClient().manga);

/// Shortcut provider for [AnimeApi].
final animeApiProvider = Provider<AnimeApi>((ref) => ApiClient().anime);

/// Shortcut provider for [UserApi].
final userApiProvider = Provider<UserApi>((ref) => ApiClient().user);

/// Shortcut provider for [NetworkApi].
final networkApiProvider = Provider<NetworkApi>((ref) => ApiClient().network);

/// Provides the shared [DataCache] singleton.
final dataCacheProvider = Provider<DataCache>((ref) => DataCache());
