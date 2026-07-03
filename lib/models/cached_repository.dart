import 'dart:async';

import '../utils/app_storage.dart';

/// A generic repository that unifies the "cache-then-load" pattern used
/// across the app.  Subclasses specify how to fetch fresh data from the
/// API, how to serialize/deserialize it, and what cache key and TTL to use.
///
/// ## Usage
///
/// ```dart
/// class MangaHomeRepository extends CachedRepository<MangaHome> {
///   MangaHomeRepository() : super(
///     cacheKey: 'manga_home_v1',
///     ttl: const Duration(hours: 1),
///     deserialize: MangaHome.fromJson,
///   );
///
///   @override
///   Future<MangaHome> fetchFromApi() => MangaApi().getMangaHome();
///
///   @override
///   Map<String, dynamic> serialize(MangaHome data) => data.toJson();
/// }
/// ```
///
/// Callers then use:
/// ```dart
/// final repo = MangaHomeRepository();
/// final cached = await repo.loadFromCache();  // fast, may be null
/// final fresh = await repo.load();             // cache-or-API
/// ```
///
/// ## Pattern variants
///
/// - **Parallel** (default): `loadFromCache()` + `load()` are called in
///   `initState`; cache shows stale data, API overwrites with fresh data.
/// - **TTL-gate**: `load()` skips the API call when the cache is still
///   fresh.  Enable with `skipApiIfCacheFresh: true`.
/// - **Sequential**: `loadFromCache()` then `load()` in sequence.
///   Works automatically with the two-call pattern.
/// - **API-transparent**: Use [load] inside an API method; it resolves
///   from cache first when available.
abstract class CachedRepository<T> {
  final String cacheKey;
  final Duration? ttl;
  final bool skipApiIfCacheFresh;
  final T Function(Map<String, dynamic>) deserialize;
  final Map<String, dynamic> Function(T) serialize;

  final _cache = AppStorage.cache;

  CachedRepository({
    required this.cacheKey,
    required this.deserialize,
    required this.serialize,
    this.ttl,
    this.skipApiIfCacheFresh = false,
  });

  /// Subclasses implement this to fetch fresh data from the remote API.
  Future<T> fetchFromApi();

  // ── Read ──────────────────────────────────────────────────────────

  /// Load data from cache only. Returns `null` if not cached or expired.
  Future<T?> loadFromCache() async {
    final raw = await _cache.get(cacheKey);
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return deserialize(raw);
    // The cache may return a plain Map (not typed); coerce gently.
    if (raw is Map) return deserialize(Map<String, dynamic>.from(raw));
    return null;
  }

  /// Load with the cache-then-API pattern:
  /// - If `skipApiIfCacheFresh` and cache is valid → return cache only.
  /// - Otherwise → fetch from API, write to cache, return fresh data.
  Future<T> load() async {
    if (skipApiIfCacheFresh) {
      final cached = await loadFromCache();
      // Cache hit with TTL not yet expired (AppPersistentCache already
      // checks TTL in .get, so non-null means fresh).
      if (cached != null) return cached;
    }

    final data = await fetchFromApi();
    await saveToCache(data);
    return data;
  }

  // ── Write ─────────────────────────────────────────────────────────

  /// Persist [data] to the cache with the configured TTL.
  Future<void> saveToCache(T data) async {
    await _cache.put(cacheKey, serialize(data), ttl: ttl);
  }

  /// Remove the cached entry (e.g. on forced refresh).
  Future<void> invalidateCache() async {
    await _cache.remove(cacheKey);
  }
}

/// A composite repository that manages **two** independent cache entries
/// sharing the same TTL.  Used by pages that fetch two unrelated data
/// sources in parallel (e.g. manga home + copy-manga home on the same page).
///
/// ```dart
/// class MangaHomePageRepository extends DualCachedRepository<MangaHome, CopyMangaHome> {
///   ...
/// }
/// ```
abstract class DualCachedRepository<A, B> {
  final String cacheKeyA;
  final String cacheKeyB;
  final Duration? ttlA;
  final Duration? ttlB;

  final A Function(Map<String, dynamic>) deserializeA;
  final B Function(Map<String, dynamic>) deserializeB;
  final Map<String, dynamic> Function(A) serializeA;
  final Map<String, dynamic> Function(B) serializeB;

  final _cache = AppStorage.cache;

  DualCachedRepository({
    required this.cacheKeyA,
    required this.cacheKeyB,
    required this.deserializeA,
    required this.deserializeB,
    required this.serializeA,
    required this.serializeB,
    this.ttlA,
    this.ttlB,
  });

  Future<A> fetchAFromApi();
  Future<B> fetchBFromApi();

  Future<A?> loadAFromCache() async {
    final raw = await _cache.get(cacheKeyA);
    if (raw is Map) return deserializeA(Map<String, dynamic>.from(raw));
    return null;
  }

  Future<B?> loadBFromCache() async {
    final raw = await _cache.get(cacheKeyB);
    if (raw is Map) return deserializeB(Map<String, dynamic>.from(raw));
    return null;
  }

  Future<A> loadA() async {
    final data = await fetchAFromApi();
    await _cache.put(cacheKeyA, serializeA(data), ttl: ttlA);
    return data;
  }

  Future<B> loadB() async {
    final data = await fetchBFromApi();
    await _cache.put(cacheKeyB, serializeB(data), ttl: ttlB);
    return data;
  }

  Future<void> saveAToCache(A data) async {
    await _cache.put(cacheKeyA, serializeA(data), ttl: ttlA);
  }

  Future<void> saveBToCache(B data) async {
    await _cache.put(cacheKeyB, serializeB(data), ttl: ttlB);
  }
}
