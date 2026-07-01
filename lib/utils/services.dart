import '../api/ai_api.dart';
import '../api/api_client.dart';
import '../api/dandanplay_api.dart';
import '../models/comment_settings.dart';
import '../models/danmaku_settings.dart';
import '../models/network_settings.dart';
import '../models/reader_settings.dart';
import '../models/theme_settings.dart';
import '../models/user_manager.dart';
import 'anime_download_manager.dart';
import 'download_manager.dart';

/// Lightweight service locator that centralizes access to app-wide
/// singletons and allows test-only overrides.
///
/// Usage in production:
/// ```dart
/// final api = Services.api;
/// final reader = Services.reader;
/// ```
///
/// Usage in tests:
/// ```dart
/// Services.override<ApiClient>(() => MockApiClient());
/// // ... test code ...
/// Services.reset(); // clean up
/// ```
class Services {
  Services._();

  static final _factories = <Type, Function>{};
  static final _instances = <Type, dynamic>{};

  // ── Production accessors ───────────────────────────────────────────

  static ApiClient get api => resolve<ApiClient>();
  static UserManager get user => resolve<UserManager>();
  static ReaderSettings get reader => resolve<ReaderSettings>();
  static DanmakuSettings get danmaku => resolve<DanmakuSettings>();
  static CommentSettings get comment => resolve<CommentSettings>();
  static ThemeSettings get theme => resolve<ThemeSettings>();
  static NetworkSettings get network => resolve<NetworkSettings>();
  static AiSettings get ai => resolve<AiSettings>();
  static DandanplayApi get dandanplay => resolve<DandanplayApi>();
  static DownloadManager get downloadManager => resolve<DownloadManager>();
  static AnimeDownloadManager get animeDownloadManager =>
      resolve<AnimeDownloadManager>();

  // ── Core resolve / register ────────────────────────────────────────

  /// Lazily resolves a service.  Uses a registered factory (if any) or
  /// falls back to the default singleton constructor.
  static T resolve<T>() {
    final existing = _instances[T];
    if (existing != null) return existing as T;

    final factory = _factories[T];
    if (factory != null) {
      final instance = factory() as T;
      _instances[T] = instance;
      return instance;
    }

    // Default factories for all known services.
    final instance = _defaultFactory<T>();
    _instances[T] = instance;
    return instance;
  }

  /// Register a factory override (typically in tests).
  static void override<T>(T Function() factory) {
    _factories[T] = factory;
    _instances.remove(T);
  }

  /// Clear all overrides and cached instances (call in test tearDown).
  static void reset() {
    _factories.clear();
    _instances.clear();
  }

  // ── Default factories ──────────────────────────────────────────────

  static T _defaultFactory<T>() {
    // The existing singletons use factory constructors, so calling
    // them always returns the same instance.  We just delegate.
    if (T == ApiClient) return ApiClient() as T;
    if (T == UserManager) return UserManager() as T;
    if (T == ReaderSettings) return ReaderSettings() as T;
    if (T == DanmakuSettings) return DanmakuSettings() as T;
    if (T == CommentSettings) return CommentSettings() as T;
    if (T == ThemeSettings) return ThemeSettings() as T;
    if (T == NetworkSettings) return NetworkSettings() as T;
    if (T == AiSettings) return AiSettings() as T;
    if (T == DandanplayApi) return DandanplayApi() as T;
    if (T == DownloadManager) return DownloadManager() as T;
    if (T == AnimeDownloadManager) return AnimeDownloadManager() as T;
    throw StateError('No default factory registered for $T');
  }
}
