import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../api/novel/novel_api.dart';
import '../api/novel/novel_text.dart';
import '../models/cached_repository.dart';
import '../models/novel.dart';
import '../models/novel_volume_snapshot.dart';
import '../utils/app_logger.dart';
import '../utils/app_storage.dart';
import '../utils/json_helpers.dart';

export 'novel_bookshelf_repository.dart';

/// Metadata uses cache_-prefixed SharedPreferences. Whole-volume text uses
/// files, never SharedPreferences. Tests can replace both with an in-memory store.
abstract class NovelCacheStore {
  Future<Map<String, dynamic>?> readMetadata(String key);
  Future<void> writeMetadata(
    String key,
    Map<String, dynamic> data,
    Duration ttl,
  );
  Future<void> removeMetadata(String key);
  Future<NovelTextCacheEntry?> readText(String key);
  Future<void> writeText(String key, NovelTextCacheEntry entry);
}

class NovelTextCacheEntry {
  final NovelVolumeDetail detail;
  final String text;
  final DateTime expiresAt;

  const NovelTextCacheEntry({
    required this.detail,
    required this.text,
    required this.expiresAt,
  });

  bool isFresh(DateTime now) => now.isBefore(expiresAt);

  Map<String, dynamic> toJson() => {
    'detail': detail.toJson(),
    'text': text,
    'expires_at': expiresAt.millisecondsSinceEpoch,
  };

  factory NovelTextCacheEntry.fromJson(Map<String, dynamic> json) =>
      NovelTextCacheEntry(
        detail: NovelVolumeDetail.fromJson(jsonMap(json, 'detail') ?? {}),
        text: jsonString(json, 'text'),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          jsonInt(json, 'expires_at'),
        ),
      );
}

class FileNovelCacheStore implements NovelCacheStore {
  static const directoryName = 'novel_text_cache_v1';
  final Future<Directory> Function() _directory;

  /// Inject a temporary directory to test files without platform channels.
  FileNovelCacheStore({Future<Directory> Function()? directory})
    : _directory = directory ?? _defaultDirectory;

  static Future<Directory> _defaultDirectory() async => Directory(
    '${(await getApplicationSupportDirectory()).path}/$directoryName',
  );

  Future<File> _file(String key) async {
    final dir = await _directory();
    await dir.create(recursive: true);
    final safeKey = sha256.convert(utf8.encode(key)).toString();
    return File('${dir.path}/$safeKey.json');
  }

  @override
  Future<Map<String, dynamic>?> readMetadata(String key) async {
    final raw = await AppStorage.cache.get(key);
    return jsonMap({'value': raw}, 'value');
  }

  @override
  Future<void> writeMetadata(
    String key,
    Map<String, dynamic> data,
    Duration ttl,
  ) => AppStorage.cache.put(key, data, ttl: ttl);

  @override
  Future<void> removeMetadata(String key) => AppStorage.cache.remove(key);

  @override
  Future<NovelTextCacheEntry?> readText(String key) async {
    final file = await _file(key);
    if (!await file.exists()) return null;
    try {
      final raw = jsonDecode(await file.readAsString());
      final json = jsonMap({'value': raw}, 'value');
      if (json == null ||
          json['text'] is! String ||
          jsonMap(json, 'detail') == null) {
        throw const FormatException('小说正文缓存格式异常');
      }
      // Expired text remains available for explicit offline continuation.
      return NovelTextCacheEntry.fromJson(json);
    } on FormatException catch (error, stack) {
      await AppLogger.instance.recordWarning(
        error,
        stackTrace: stack,
        source: 'novel_cache.read',
      );
      await file.delete();
      return null;
    }
  }

  @override
  Future<void> writeText(String key, NovelTextCacheEntry entry) async {
    final file = await _file(key);
    // A single atomic snapshot keeps the directory's line ranges and text paired.
    final temporary = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await temporary.writeAsString(jsonEncode(entry.toJson()), flush: true);
    await temporary.rename(file.path);
  }
}

class _NovelMetadataRepository extends CachedRepository<Map<String, dynamic>> {
  final NovelCacheStore store;
  final Future<Map<String, dynamic>> Function() fetch;
  final void Function() checkIdentity;

  _NovelMetadataRepository({
    required super.cacheKey,
    required Duration super.ttl,
    required this.store,
    required this.fetch,
    required this.checkIdentity,
    required super.skipApiIfCacheFresh,
  }) : super(deserialize: _identity, serialize: _identity);

  static Map<String, dynamic> _identity(Map<String, dynamic> json) => json;

  @override
  Future<Map<String, dynamic>> fetchFromApi() async {
    checkIdentity();
    final data = await fetch();
    checkIdentity();
    return data;
  }

  @override
  Future<Map<String, dynamic>?> loadFromCache() async {
    checkIdentity();
    final data = await store.readMetadata(cacheKey);
    checkIdentity();
    return data;
  }

  @override
  Future<void> saveToCache(Map<String, dynamic> data) async {
    checkIdentity();
    await store.writeMetadata(cacheKey, data, ttl!);
    checkIdentity();
  }

  @override
  Future<void> invalidateCache() async {
    checkIdentity();
    await store.removeMetadata(cacheKey);
    checkIdentity();
  }
}

class NovelRepository {
  static const homeTtl = Duration(hours: 1);

  /// 详情接口的 TTL 门控窗口：6h 内再进同一本书，详情请求静默跳过。
  static const detailTtl = Duration(hours: 6);

  /// 卷目录每次都发请求（对齐漫画详情的章节策略），TTL 仅用于清理
  /// 长期不再打开的书籍占用的存储；每次拉新回写都会刷新它。
  static const volumesTtl = Duration(days: 7);
  static const volumeDetailTtl = Duration(days: 1);
  static const textTtl = Duration(days: 30);

  final NovelApi api;
  final NovelCacheStore _store;
  final DateTime Function() _now;
  final _metadata = <String, _NovelMetadataRepository>{};
  final _textLoads = <String, Future<NovelVolumeSnapshot>>{};

  NovelRepository({
    required this.api,
    NovelCacheStore? store,
    DateTime Function()? now,
  }) : _store = store ?? FileNovelCacheStore(),
       _now = now ?? DateTime.now;

  String _key(
    String kind,
    String scope, [
    String path = '',
    String volume = '',
  ]) {
    final entity = sha256.convert(utf8.encode('$path\n$volume'));
    return 'novel_${kind}_${scope}_${entity}_v1';
  }

  Future<Map<String, dynamic>> _loadMetadata({
    required String kind,
    required Duration ttl,
    required Future<Map<String, dynamic>> Function() fetch,
    required bool skipApiIfCacheFresh,
    String path = '',
    String volume = '',
    bool refresh = false,
  }) {
    final identity = api.requestIdentity;
    final key = _key(kind, identity.cacheScope, path, volume);
    // In-flight repositories are generation-specific; persistent keys are not.
    final registryKey = '${key}_${identity.generation}';
    // Bound the repository registry; the actual payloads stay in persistent cache.
    if (_metadata.length > 120) _metadata.clear();
    final repository = _metadata.putIfAbsent(
      registryKey,
      () => _NovelMetadataRepository(
        cacheKey: key,
        ttl: ttl,
        store: _store,
        fetch: fetch,
        checkIdentity: () => api.ensureIdentity(identity),
        skipApiIfCacheFresh: skipApiIfCacheFresh,
      ),
    );
    return refresh ? repository.forceRefreshApi() : repository.load();
  }

  Future<NovelHome> loadHome({bool refresh = false}) => api.withIdentity(
    () async => NovelHome.fromJson(
      await _loadMetadata(
        kind: 'home',
        ttl: homeTtl,
        skipApiIfCacheFresh: true,
        refresh: refresh,
        fetch: () async => (await api.getHome()).toJson(),
      ),
    ),
  );

  Future<NovelDetail> loadDetail(String pathWord, {bool refresh = false}) =>
      api.withIdentity(
        () async => NovelDetail.fromJson(
          await _loadMetadata(
            kind: 'detail',
            path: pathWord,
            ttl: detailTtl,
            skipApiIfCacheFresh: true,
            refresh: refresh,
            fetch: () async => (await api.getDetail(pathWord)).toJson(),
          ),
        ),
      );

  /// Cache-only read for fast first paint; may be null or expired.
  Future<NovelDetail?> loadDetailFromCache(String pathWord) =>
      api.withIdentity(() async {
        final identity = api.requestIdentity;
        final key = _key('detail', identity.cacheScope, pathWord);
        final cached = await _store.readMetadata(key);
        api.ensureIdentity(identity);
        return cached == null ? null : NovelDetail.fromJson(cached);
      });

  /// 卷目录每次都发请求；缓存仅用于页面先渲染（[loadVolumesFromCache]）。
  Future<List<NovelVolume>> loadVolumes(
    String pathWord, {
    bool refresh = false,
  }) => api.withIdentity(() async {
    final json = await _loadMetadata(
      kind: 'volumes',
      path: pathWord,
      ttl: volumesTtl,
      skipApiIfCacheFresh: false,
      refresh: refresh,
      fetch: () async => {
        'list': (await api.getVolumes(
          pathWord,
        )).map((e) => e.toJson()).toList(),
      },
    );
    return NovelPage.fromJson(json, NovelVolume.fromJson).list;
  });

  /// Cache-only read for fast first paint; may be null or expired.
  Future<List<NovelVolume>?> loadVolumesFromCache(String pathWord) =>
      api.withIdentity(() async {
        final identity = api.requestIdentity;
        final key = _key('volumes', identity.cacheScope, pathWord);
        final cached = await _store.readMetadata(key);
        api.ensureIdentity(identity);
        if (cached == null) return null;
        return NovelPage.fromJson(cached, NovelVolume.fromJson).list;
      });

  Future<NovelVolumeDetail> loadVolumeDetail(
    String pathWord,
    String volumeId, {
    bool refresh = false,
  }) => api.withIdentity(
    () async => NovelVolumeDetail.fromJson(
      await _loadMetadata(
        kind: 'volume_detail',
        path: pathWord,
        volume: volumeId,
        ttl: volumeDetailTtl,
        skipApiIfCacheFresh: true,
        refresh: refresh,
        fetch: () async =>
            (await api.getVolumeDetail(pathWord, volumeId)).toJson(),
      ),
    ),
  );

  /// Cache-only, including expired text, to continue previously read volumes.
  /// This never triggers a business or CDN request and does not promise that
  /// previously unseen volumes are available to guests.
  Future<NovelVolumeContent?> getCachedVolumeContent(
    String pathWord,
    String volumeId,
  ) => api.withIdentity(() async {
    final identity = api.requestIdentity;
    final cached = await _store.readText(
      _key('text', identity.cacheScope, pathWord, volumeId),
    );
    api.ensureIdentity(identity);
    if (cached == null || cached.detail.isLocked || !cached.detail.hasText) {
      return null;
    }
    return NovelText.parse(cached.detail, cached.text);
  });

  Future<NovelVolumeContent> loadVolumeContent(
    String pathWord,
    String volumeId, {
    bool refresh = false,
  }) async =>
      (await loadVolumeSnapshot(pathWord, volumeId, refresh: refresh)).content;

  Future<NovelVolumeSnapshot> loadVolumeSnapshot(
    String pathWord,
    String volumeId, {
    bool refresh = false,
    CancelToken? cancelToken,
  }) => api.withIdentity(() {
    final identity = api.requestIdentity;
    final key = _key('text', identity.cacheScope, pathWord, volumeId);
    if (cancelToken != null) {
      // Downloads own their requests. Sharing the normal registry here would
      // let pausing a download cancel a reader that awaits the same volume.
      return api.withCancellation(
        cancelToken,
        () => _loadText(
          pathWord,
          volumeId,
          key,
          identity,
          refresh,
          null,
          cancelToken: cancelToken,
        ),
      );
    }
    final loadKey = '${key}_${identity.generation}';
    final pendingKey = refresh ? '${loadKey}_refresh' : loadKey;
    return _textLoads.putIfAbsent(pendingKey, () {
      final pending = refresh ? _textLoads[loadKey] : null;
      final future = _loadText(
        pathWord,
        volumeId,
        key,
        identity,
        refresh,
        pending,
      );
      return future.whenComplete(() {
        // Do not return Map.remove's Future here: it is this very future and
        // whenComplete would wait on itself indefinitely.
        _textLoads.remove(pendingKey);
      });
    });
  });

  Future<NovelVolumeSnapshot> _loadText(
    String pathWord,
    String volumeId,
    String key,
    NovelRequestIdentity identity,
    bool refresh,
    Future<NovelVolumeSnapshot>? pending, {
    CancelToken? cancelToken,
  }) async {
    if (pending != null) {
      try {
        await pending;
      } catch (error, stack) {
        await AppLogger.instance.recordWarning(
          error,
          stackTrace: stack,
          source: 'novel_cache.wait_before_refresh',
        );
      }
    }
    api.ensureIdentity(identity);
    if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
    final cached = await _store.readText(key);
    api.ensureIdentity(identity);
    if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
    if (!refresh && cached != null && cached.isFresh(_now())) {
      final snapshot = NovelVolumeSnapshot(
        detail: cached.detail,
        text: cached.text,
      );
      snapshot.validate(pathWord: pathWord, volumeId: volumeId);
      return snapshot;
    }
    // No silent stale fallback after an explicit server lock/401. The reader may
    // offer getCachedVolumeContent as a clearly labelled offline action instead.
    final detail = cancelToken == null
        ? await loadVolumeDetail(pathWord, volumeId, refresh: refresh)
        : await api.getVolumeDetail(pathWord, volumeId);
    api.ensureIdentity(identity);
    if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
    final text = await api.getVolumeText(detail);
    api.ensureIdentity(identity);
    if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
    final result = NovelVolumeSnapshot(detail: detail, text: text);
    result.validate(pathWord: pathWord, volumeId: volumeId);
    await _store.writeText(
      key,
      NovelTextCacheEntry(
        detail: detail,
        text: text,
        expiresAt: _now().add(textTtl),
      ),
    );
    api.ensureIdentity(identity);
    return result;
  }
}
