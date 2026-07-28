import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:kira/models/cached_repository.dart';

// ── Test data model ───────────────────────────────────────────────────

class _TestItem {
  final String name;
  final int count;
  const _TestItem({required this.name, required this.count});
}

// ── In-memory test repos (no SharedPreferences needed) ─────────────────

class _TestMemRepo extends CachedRepository<_TestItem> {
  int fetchCallCount = 0;
  _TestItem? _mockApiResponse;
  final _store = <String, Map<String, dynamic>>{};

  _TestMemRepo({super.ttl, super.skipApiIfCacheFresh = false})
    : super(
        cacheKey: 'test_mem',
        deserialize: (json) => _TestItem(
          name: json['name'] as String? ?? '',
          count: json['count'] as int? ?? 0,
        ),
        serialize: (item) => {'name': item.name, 'count': item.count},
      );

  void setMockApiResponse(_TestItem item) => _mockApiResponse = item;

  @override
  Future<_TestItem> fetchFromApi() async {
    fetchCallCount++;
    return _mockApiResponse ?? const _TestItem(name: 'from_api', count: 42);
  }

  @override
  Future<_TestItem?> loadFromCache() async {
    final raw = _store[cacheKey];
    if (raw == null) return null;
    return deserialize(raw);
  }

  @override
  Future<void> saveToCache(_TestItem data) async {
    _store[cacheKey] = serialize(data);
  }

  @override
  Future<void> invalidateCache() async {
    _store.remove(cacheKey);
  }
}

class _TestDualMemRepo extends DualCachedRepository<_TestItem, _TestItem> {
  int fetchACallCount = 0;
  int fetchBCallCount = 0;
  final _storeA = <String, Map<String, dynamic>>{};
  final _storeB = <String, Map<String, dynamic>>{};

  _TestDualMemRepo()
    : super(
        cacheKeyA: 'test_dual_a',
        cacheKeyB: 'test_dual_b',
        deserializeA: (json) => _TestItem(
          name: json['name'] as String? ?? '',
          count: json['count'] as int? ?? 0,
        ),
        deserializeB: (json) => _TestItem(
          name: json['name'] as String? ?? '',
          count: json['count'] as int? ?? 0,
        ),
        serializeA: (item) => {'name': item.name, 'count': item.count},
        serializeB: (item) => {'name': item.name, 'count': item.count},
      );

  @override
  Future<_TestItem> fetchAFromApi() async {
    fetchACallCount++;
    return const _TestItem(name: 'a_from_api', count: 10);
  }

  @override
  Future<_TestItem> fetchBFromApi() async {
    fetchBCallCount++;
    return const _TestItem(name: 'b_from_api', count: 20);
  }

  @override
  Future<_TestItem?> loadAFromCache() async {
    final raw = _storeA[cacheKeyA];
    if (raw == null) return null;
    return deserializeA(raw);
  }

  @override
  Future<_TestItem?> loadBFromCache() async {
    final raw = _storeB[cacheKeyB];
    if (raw == null) return null;
    return deserializeB(raw);
  }

  @override
  Future<_TestItem> loadA() async {
    final data = await fetchAFromApi();
    _storeA[cacheKeyA] = serializeA(data);
    return data;
  }

  @override
  Future<_TestItem> loadB() async {
    final data = await fetchBFromApi();
    _storeB[cacheKeyB] = serializeB(data);
    return data;
  }

  @override
  Future<void> saveAToCache(_TestItem data) async {
    _storeA[cacheKeyA] = serializeA(data);
  }

  @override
  Future<void> saveBToCache(_TestItem data) async {
    _storeB[cacheKeyB] = serializeB(data);
  }
}

// ── Tests ─────────────────────────────────────────────────────────────

void main() {
  group('CachedRepository', () {
    late _TestMemRepo repo;

    setUp(() {
      repo = _TestMemRepo();
    });

    test('loadFromCache returns null when cache is empty', () async {
      final result = await repo.loadFromCache();
      expect(result, isNull);
    });

    test('load fetches from API and saves to cache', () async {
      repo.setMockApiResponse(const _TestItem(name: 'fresh', count: 99));

      final result = await repo.load();
      expect(result.name, 'fresh');
      expect(result.count, 99);
      expect(repo.fetchCallCount, 1);

      final cached = await repo.loadFromCache();
      expect(cached, isNotNull);
      expect(cached!.name, 'fresh');
    });

    test('load always calls API when skipApiIfCacheFresh is false', () async {
      await repo.saveToCache(const _TestItem(name: 'cached', count: 1));
      repo.setMockApiResponse(const _TestItem(name: 'fresh', count: 2));

      final result = await repo.load();
      expect(repo.fetchCallCount, 1);
      expect(result.name, 'fresh');
    });

    test('skipApiIfCacheFresh returns cached data when fresh', () async {
      final freshRepo = _TestMemRepo(
        ttl: const Duration(hours: 1),
        skipApiIfCacheFresh: true,
      );
      await freshRepo.saveToCache(
        const _TestItem(name: 'freshly_cached', count: 5),
      );

      final result = await freshRepo.load();
      expect(result.name, 'freshly_cached');
      expect(freshRepo.fetchCallCount, 0);
    });

    test('skipApiIfCacheFresh calls API when cache is empty', () async {
      final freshRepo = _TestMemRepo(
        ttl: const Duration(hours: 1),
        skipApiIfCacheFresh: true,
      );
      freshRepo.setMockApiResponse(
        const _TestItem(name: 'from_api', count: 88),
      );

      final result = await freshRepo.load();
      expect(result.name, 'from_api');
      expect(freshRepo.fetchCallCount, 1);
    });

    test('invalidateCache removes the cache entry', () async {
      await repo.saveToCache(const _TestItem(name: 'cached', count: 1));
      expect(await repo.loadFromCache(), isNotNull);

      await repo.invalidateCache();
      expect(await repo.loadFromCache(), isNull);
    });

    test('saveToCache and loadFromCache round-trip correctly', () async {
      const item = _TestItem(name: 'round_trip', count: 77);
      await repo.saveToCache(item);

      final restored = await repo.loadFromCache();
      expect(restored, isNotNull);
      expect(restored!.name, 'round_trip');
      expect(restored.count, 77);
    });
  });

  group('DualCachedRepository', () {
    late _TestDualMemRepo repo;

    setUp(() {
      repo = _TestDualMemRepo();
    });

    test('loadAFromCache returns null when empty', () async {
      expect(await repo.loadAFromCache(), isNull);
    });

    test('loadBFromCache returns null when empty', () async {
      expect(await repo.loadBFromCache(), isNull);
    });

    test('loadA fetches from API and caches', () async {
      final result = await repo.loadA();
      expect(result.name, 'a_from_api');
      expect(repo.fetchACallCount, 1);

      final cached = await repo.loadAFromCache();
      expect(cached, isNotNull);
      expect(cached!.name, 'a_from_api');
    });

    test('loadB fetches from API and caches', () async {
      final result = await repo.loadB();
      expect(result.name, 'b_from_api');
      expect(repo.fetchBCallCount, 1);

      final cached = await repo.loadBFromCache();
      expect(cached, isNotNull);
      expect(cached!.name, 'b_from_api');
    });

    test('A and B caches are independent', () async {
      await repo.loadA();
      await repo.loadB();

      final cachedA = await repo.loadAFromCache();
      final cachedB = await repo.loadBFromCache();

      expect(cachedA?.name, 'a_from_api');
      expect(cachedB?.name, 'b_from_api');
      expect(cachedA?.count, 10);
      expect(cachedB?.count, 20);
    });
  });

  group('CachedRepository in-flight de-duplication', () {
    test('concurrent load calls share one API request', () async {
      final repo = _GatedRepo();

      // 三个调用者在 API 返回之前就发起请求——initState 与下拉刷新同时触发
      // 正是这个场景。
      final calls = [repo.load(), repo.load(), repo.load()];
      repo.gate.complete();
      final results = await Future.wait(calls);

      expect(repo.fetchCallCount, 1);
      expect(results.map((item) => item.name).toList(), [
        'gated',
        'gated',
        'gated',
      ]);
    });

    test(
      'a later load issues a fresh request once the first settles',
      () async {
        final repo = _GatedRepo();
        repo.gate.complete();

        await repo.load();
        await repo.load();

        expect(repo.fetchCallCount, 2);
      },
    );

    test('a failed load does not poison later calls', () async {
      final repo = _FailingOnceRepo();

      await expectLater(repo.load(), throwsA(isA<StateError>()));
      final recovered = await repo.load();

      expect(repo.fetchCallCount, 2);
      expect(recovered.name, 'recovered');
    });
  });
}

/// Holds [fetchFromApi] open until [gate] completes, so concurrent callers are
/// guaranteed to overlap.
class _GatedRepo extends _TestMemRepo {
  final gate = Completer<void>();

  @override
  Future<_TestItem> fetchFromApi() async {
    fetchCallCount++;
    await gate.future;
    return const _TestItem(name: 'gated', count: 7);
  }
}

/// Throws on the first fetch, succeeds afterwards.
class _FailingOnceRepo extends _TestMemRepo {
  @override
  Future<_TestItem> fetchFromApi() async {
    fetchCallCount++;
    if (fetchCallCount == 1) throw StateError('boom');
    return const _TestItem(name: 'recovered', count: 1);
  }
}
