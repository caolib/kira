import 'dart:async';
import 'dart:io';

import 'package:charset/charset.dart' show gbk;
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/api/novel/novel_api.dart';
import 'package:kira/repositories/novel_repository.dart';

import 'novel_api_test.dart'
    show NovelTestAdapter, NovelTestUser, novelFixtureDetail, novelJsonResponse;

class _MemoryStore implements NovelCacheStore {
  DateTime now = DateTime.utc(2026);
  final metadata = <String, ({Map<String, dynamic> json, DateTime expires})>{};
  final texts = <String, NovelTextCacheEntry>{};
  final ttls = <Duration>[];
  Future<void> Function()? beforeReadText;
  Future<void> Function()? beforeReadMetadata;

  @override
  Future<Map<String, dynamic>?> readMetadata(String key) async {
    await beforeReadMetadata?.call();
    final value = metadata[key];
    return value != null && now.isBefore(value.expires) ? value.json : null;
  }

  @override
  Future<void> writeMetadata(
    String key,
    Map<String, dynamic> data,
    Duration ttl,
  ) async {
    metadata[key] = (json: data, expires: now.add(ttl));
    ttls.add(ttl);
  }

  @override
  Future<void> removeMetadata(String key) async => metadata.remove(key);

  @override
  Future<NovelTextCacheEntry?> readText(String key) async {
    await beforeReadText?.call();
    return texts[key];
  }

  @override
  Future<void> writeText(String key, NovelTextCacheEntry entry) async {
    texts[key] = entry;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _MemoryStore store;
  late NovelTestUser user;
  late NovelTestAdapter apiAdapter;
  late NovelTestAdapter textAdapter;
  late NovelApi api;
  late NovelRepository repository;
  var offline = false;
  var locked = false;

  setUp(() {
    store = _MemoryStore();
    user = NovelTestUser();
    offline = false;
    locked = false;
    apiAdapter = NovelTestAdapter((options, body) {
      if (offline) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      }
      final path = options.uri.path;
      if (path.contains('/volume/')) {
        return novelJsonResponse(novelFixtureDetail(locked: locked).toJson());
      }
      if (path.endsWith('/volumes')) {
        return novelJsonResponse({
          'list': [novelFixtureDetail().volume.toJson()],
        });
      }
      if (path.endsWith('/book/book')) {
        return novelJsonResponse({'book': novelFixtureDetail().book.toJson()});
      }
      return novelJsonResponse({
        'list': [novelFixtureDetail().book.toJson()],
        'total': 1,
        'limit': 18,
        'offset': 0,
      });
    });
    textAdapter = NovelTestAdapter((options, body) {
      if (offline) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      }
      return ResponseBody.fromString('正文\r\n', 200);
    });
    api = NovelApi.withDio(
      user: user,
      dio: Dio()..httpClientAdapter = apiAdapter,
      contentDio: Dio()..httpClientAdapter = textAdapter,
    );
    repository = NovelRepository(api: api, store: store, now: () => store.now);
  });

  tearDown(() => api.close());

  test('home and details use explicit TTL persistent caches', () async {
    final home = await repository.loadHome();
    expect(home.popular.single.pathWord, 'book');
    await repository.loadHome();
    expect(apiAdapter.requests.length, 2);
    await repository.loadDetail('book');
    await repository.loadDetail('book');
    expect(apiAdapter.requests.length, 3);
    await repository.loadVolumeDetail('book', '7');
    await repository.loadVolumeDetail('book', '7');
    expect(apiAdapter.requests.length, 4);
    expect(store.ttls, [
      NovelRepository.homeTtl,
      NovelRepository.detailTtl,
      NovelRepository.volumeDetailTtl,
    ]);
    expect(
      store.metadata.keys.every(
        (key) =>
            key.startsWith('novel_') &&
            key.endsWith('_v1') &&
            !key.startsWith('cache_'),
      ),
      isTrue,
    );
    store.now = store.now.add(const Duration(hours: 2));
    await repository.loadHome();
    expect(apiAdapter.requests.length, 6);
    await repository.loadDetail('book');
    expect(apiAdapter.requests.length, 6);
    await repository.loadDetail('book', refresh: true);
    expect(apiAdapter.requests.length, 7);
    store.now = store.now.add(NovelRepository.detailTtl);
    await repository.loadDetail('book');
    expect(apiAdapter.requests.length, 8);
    expect(store.ttls, [
      NovelRepository.homeTtl,
      NovelRepository.detailTtl,
      NovelRepository.volumeDetailTtl,
      NovelRepository.homeTtl,
      NovelRepository.detailTtl,
      NovelRepository.detailTtl,
    ]);
  });

  test(
    'directory refreshes every load and keeps a cache-only snapshot',
    () async {
      expect(await repository.loadVolumesFromCache('book'), isNull);
      expect(apiAdapter.requests, isEmpty);
      final first = await repository.loadVolumes('book');
      expect(first.single.toJson(), novelFixtureDetail().volume.toJson());
      expect(apiAdapter.requests.length, 1);
      expect(
        store.metadata.values.single.expires,
        store.now.add(NovelRepository.volumesTtl),
      );

      // 串行调用即使仍在 TTL 内也要拉新，并刷新缓存的清理期限。
      store.now = store.now.add(const Duration(hours: 1));
      final refreshed = await repository.loadVolumes('book');
      expect(refreshed.single.toJson(), first.single.toJson());
      expect(apiAdapter.requests.length, 2);
      expect(store.ttls, [
        NovelRepository.volumesTtl,
        NovelRepository.volumesTtl,
      ]);
      expect(store.metadata.keys.single, startsWith('novel_volumes_'));
      expect(store.metadata.keys.single, endsWith('_v1'));
      expect(
        store.metadata.values.single.expires,
        store.now.add(NovelRepository.volumesTtl),
      );

      offline = true;
      final restarted = NovelRepository(
        api: api,
        store: store,
        now: () => store.now,
      );
      final cached = await restarted.loadVolumesFromCache('book');
      expect(cached?.single.toJson(), refreshed.single.toJson());
      expect(apiAdapter.requests.length, 2);
      expect(store.ttls, [
        NovelRepository.volumesTtl,
        NovelRepository.volumesTtl,
      ]);
    },
  );

  test(
    'whole volume and its metadata survive repository recreation offline',
    () async {
      final first = await repository.loadVolumeContent('book', '7');
      expect(first.entries.first.paragraphs, ['正文', '']);
      expect(textAdapter.requests.length, 1);
      expect(
        store.texts.values.single.expiresAt,
        store.now.add(NovelRepository.textTtl),
      );
      offline = true;
      final restarted = NovelRepository(
        api: api,
        store: store,
        now: () => store.now,
      );
      final second = await restarted.loadVolumeContent('book', '7');
      expect(second.entries.first.paragraphs, first.entries.first.paragraphs);
      expect(apiAdapter.requests.length, 1);
      await pumpEventQueue();
      expect(apiAdapter.requests.length, 1);
      expect(textAdapter.requests.length, 1);
    },
  );

  test(
    'expired text remains cache-only readable, never attempts a network request',
    () async {
      await repository.loadVolumeContent('book', '7');
      store.now = store.now.add(const Duration(days: 365));
      offline = true;
      final cached = await repository.getCachedVolumeContent('book', '7');
      expect(cached!.entries.first.paragraphs, ['正文', '']);
      expect(cached.entries[1].imageUrl, 'https://cdn.invalid/image.png');
      expect(apiAdapter.requests.length, 1);
      expect(textAdapter.requests.length, 1);
      expect(await repository.getCachedVolumeContent('book', 'unseen'), isNull);
      expect(apiAdapter.requests.length, 1);
    },
  );

  test(
    'expired text fetches volume detail and text again for normal reading',
    () async {
      await repository.loadVolumeContent('book', '7');
      store.now = store.now.add(NovelRepository.textTtl);
      final refreshed = await repository.loadVolumeContent('book', '7');
      expect(refreshed.entries.first.paragraphs, ['正文', '']);
      expect(apiAdapter.requests.length, 2);
      expect(textAdapter.requests.length, 2);
      expect(
        store.texts.values.single.expiresAt,
        store.now.add(NovelRepository.textTtl),
      );
    },
  );

  test(
    'refresh respects server lock instead of silently masking it with old text',
    () async {
      await repository.loadVolumeContent('book', '7');
      locked = true;
      await expectLater(
        repository.loadVolumeContent('book', '7', refresh: true),
        throwsA(isA<NovelAccessException>()),
      );
      expect(textAdapter.requests.length, 1);
      // Existing offline copy is preserved, requiring explicit user selection.
      expect(await repository.getCachedVolumeContent('book', '7'), isNotNull);
    },
  );

  test(
    'concurrent content requests share one metadata and one text fetch',
    () async {
      final values = await Future.wait([
        repository.loadVolumeContent('book', '7'),
        repository.loadVolumeContent('book', '7'),
        repository.loadVolumeContent('book', '7'),
      ]);
      expect(values.length, 3);
      expect(apiAdapter.requests.length, 1);
      expect(textAdapter.requests.length, 1);
    },
  );

  test(
    'cache scope separates COPY identity and host, never persists raw tokens',
    () async {
      user.copyToken = 'COPY_A_TEST_SECRET';
      await repository.loadVolumeContent('book', '7');
      user.copyToken = 'COPY_B_TEST_SECRET';
      expect(await repository.getCachedVolumeContent('book', '7'), isNull);
      await repository.loadVolumeContent('book', '7');
      expect(textAdapter.requests.length, 2);
      expect(store.texts.keys.join(), isNot(contains('COPY_')));
      expect(
        store.texts.values.map((e) => e.toJson()).toString(),
        isNot(contains('TEST_SECRET')),
      );
      user.copyApiHost = 'another-copy.invalid';
      expect(await repository.getCachedVolumeContent('book', '7'), isNull);
    },
  );

  test(
    'fresh text cache skips volume detail and text requests across account switches',
    () async {
      user.copyToken = 'COPY_A';
      await repository.loadVolumeContent('book', '7');
      expect(apiAdapter.requests.length, 1);
      expect(textAdapter.requests.length, 1);

      // 正文快照自带目录，元数据缓存缺失也不应为浏览记录补发请求。
      store.metadata.clear();
      await repository.loadVolumeContent('book', '7');
      await repository.loadVolumeSnapshot('book', '7');
      await pumpEventQueue();
      expect(apiAdapter.requests.length, 1);
      expect(textAdapter.requests.length, 1);
      expect(store.metadata, isEmpty);

      // 新身份没有正文缓存，仍需正常请求卷详情与正文。
      user.copyToken = 'COPY_B';
      await repository.loadVolumeContent('book', '7');
      expect(apiAdapter.requests.length, 2);
      expect(textAdapter.requests.length, 2);

      store.metadata.clear();
      await repository.loadVolumeContent('book', '7');
      user.copyToken = 'COPY_A';
      await repository.loadVolumeContent('book', '7');
      await pumpEventQueue();
      expect(apiAdapter.requests.length, 2);
      expect(textAdapter.requests.length, 2);
      expect(store.metadata, isEmpty);
    },
  );

  test(
    'account ABA while reading text cache aborts before any new request',
    () async {
      user.copyToken = 'COPY_A';
      final entered = Completer<void>();
      final release = Completer<void>();
      store.beforeReadText = () async {
        entered.complete();
        await release.future;
      };
      final assertion = expectLater(
        repository.loadVolumeContent('book', '7'),
        throwsA(isA<NovelIdentityChangedException>()),
      );
      await entered.future;
      user.copyToken = 'COPY_B';
      user.copyToken = 'COPY_A';
      release.complete();
      await assertion;
      expect(apiAdapter.requests, isEmpty);
      expect(textAdapter.requests, isEmpty);
      expect(store.texts, isEmpty);
      store.beforeReadText = null;
      await repository.loadVolumeContent('book', '7');
      await repository.loadVolumeContent('book', '7');
      expect(apiAdapter.requests.length, 1);
      await pumpEventQueue();
      expect(textAdapter.requests.length, 1);
    },
  );

  test(
    'metadata ABA cannot reuse an old generation repository or return stale cache',
    () async {
      user.copyToken = 'COPY_A';
      await repository.loadDetail('book');
      final entered = Completer<void>();
      final release = Completer<void>();
      store.beforeReadMetadata = () async {
        entered.complete();
        await release.future;
      };
      final assertion = expectLater(
        repository.loadDetail('book'),
        throwsA(isA<NovelIdentityChangedException>()),
      );
      await entered.future;
      user.copyToken = 'COPY_B';
      user.copyToken = 'COPY_A';
      release.complete();
      await assertion;
      store.beforeReadMetadata = null;
      // Returning to A creates a new in-memory repository, but reuses A's disk key.
      final result = await repository.loadDetail('book');
      expect(result.book.pathWord, 'book');
      expect(apiAdapter.requests.length, 1);
      await repository.loadDetail('book', refresh: true);
      await repository.loadDetail('book');
      expect(apiAdapter.requests.length, 2);
    },
  );

  test(
    'host ABA invalidates cache-only content without contacting the network',
    () async {
      await repository.loadVolumeContent('book', '7');
      final entered = Completer<void>();
      final release = Completer<void>();
      store.beforeReadText = () async {
        entered.complete();
        await release.future;
      };
      final assertion = expectLater(
        repository.getCachedVolumeContent('book', '7'),
        throwsA(isA<NovelIdentityChangedException>()),
      );
      await entered.future;
      user.copyApiHost = 'other-copy.invalid';
      user.copyApiHost = 'copy.invalid';
      release.complete();
      await assertion;
      store.beforeReadText = null;
      expect(await repository.getCachedVolumeContent('book', '7'), isNotNull);
      expect(apiAdapter.requests.length, 1);
      expect(textAdapter.requests.length, 1);
    },
  );

  test(
    'account ABA during CDN response cannot write text into the old account cache',
    () async {
      user.copyToken = 'COPY_A';
      final entered = Completer<void>();
      final release = Completer<ResponseBody>();
      var requests = 0;
      final adapter = NovelTestAdapter((options, body) {
        requests++;
        if (requests == 1) {
          entered.complete();
          return release.future;
        }
        return ResponseBody.fromString('A正文\n', 200);
      });
      final client = NovelApi.withDio(
        user: user,
        dio: Dio()..httpClientAdapter = apiAdapter,
        contentDio: Dio()..httpClientAdapter = adapter,
      );
      addTearDown(client.close);
      final repo = NovelRepository(
        api: client,
        store: store,
        now: () => store.now,
      );
      final assertion = expectLater(
        repo.loadVolumeContent('book', '7'),
        throwsA(isA<NovelIdentityChangedException>()),
      );
      await entered.future;
      user.copyToken = 'COPY_B';
      user.copyToken = 'COPY_A';
      release.complete(ResponseBody.fromString('旧正文\n', 200));
      await assertion;
      expect(store.texts, isEmpty);
      final next = await repo.loadVolumeContent('book', '7');
      expect(next.entries.first.paragraphs.first, 'A正文');
      await repo.loadVolumeContent('book', '7');
      expect(requests, 2);
    },
  );

  for (final encoding in ['UTF-8', 'GBK']) {
    test(
      'snapshot keeps raw $encoding references, whitespace and directory indices',
      () async {
        const text = '\r\n第一行&#16034;&#15970;狓\r\n\r\n末行\r\n';
        final contentAdapter = NovelTestAdapter(
          (options, body) => encoding == 'GBK'
              ? ResponseBody.fromBytes(gbk.encode(text), 200)
              : ResponseBody.fromString(text, 200),
        );
        final client = NovelApi.withDio(
          user: user,
          dio: Dio()
            ..httpClientAdapter = NovelTestAdapter(
              (options, body) => novelJsonResponse(
                novelFixtureDetail(encoding: encoding).toJson(),
              ),
            ),
          contentDio: Dio()..httpClientAdapter = contentAdapter,
        );
        addTearDown(client.close);
        final repo = NovelRepository(
          api: client,
          store: store,
          now: () => store.now,
        );
        final snapshot = await repo.loadVolumeSnapshot('book', '7');
        expect(snapshot.text, text);
        expect(snapshot.content.entries.first.paragraphs, ['', '第一行㺢㹢狓']);
        expect(snapshot.content.entries[1].entryIndex, 1);
        expect(snapshot.detail.volume.txtEncoding, encoding);
        expect(store.texts.values.single.text, text);
        final restored = await repo.loadVolumeSnapshot('book', '7');
        expect(restored.text, text);
        expect(restored.content.entries.first.paragraphs, ['', '第一行㺢㹢狓']);
        // A new reader also decodes pre-existing raw cache, even when expired.
        store.now = store.now.add(const Duration(days: 365));
        final cachedRepo = NovelRepository(
          api: client,
          store: store,
          now: () => store.now,
        );
        final cached = await cachedRepo.getCachedVolumeContent('book', '7');
        expect(cached!.entries.first.paragraphs, ['', '第一行㺢㹢狓']);
        expect(store.texts.values.single.text, text);
        await pumpEventQueue();
        expect(contentAdapter.requests, hasLength(1));
      },
    );
  }

  test(
    'refresh snapshot waits for old fetch then updates the paired cache',
    () async {
      final entered = Completer<void>();
      final release = Completer<ResponseBody>();
      var requests = 0;
      final contentAdapter = NovelTestAdapter((options, body) {
        if (++requests == 1) {
          entered.complete();
          return release.future;
        }
        return ResponseBody.fromString('新版本\n', 200);
      });
      final client = NovelApi.withDio(
        user: user,
        dio: Dio()..httpClientAdapter = apiAdapter,
        contentDio: Dio()..httpClientAdapter = contentAdapter,
      );
      addTearDown(client.close);
      final repo = NovelRepository(
        api: client,
        store: store,
        now: () => store.now,
      );
      final old = repo.loadVolumeSnapshot('book', '7');
      await entered.future;
      final fresh = repo.loadVolumeSnapshot('book', '7', refresh: true);
      await Future<void>.delayed(Duration.zero);
      expect(requests, 1);
      expect(apiAdapter.requests, hasLength(1));
      release.complete(ResponseBody.fromString('旧版本\n', 200));
      expect((await old).text, '旧版本\n');
      expect((await fresh).text, '新版本\n');
      expect((await repo.loadVolumeSnapshot('book', '7')).text, '新版本\n');
      await pumpEventQueue();
      expect(apiAdapter.requests, hasLength(2));
      expect(requests, 2);
    },
  );

  test(
    'cancelling task-owned snapshot does not cancel shared reader fetch',
    () async {
      final readerEntered = Completer<void>();
      final taskEntered = Completer<void>();
      final readerRelease = Completer<ResponseBody>();
      final taskRelease = Completer<ResponseBody>();
      var requests = 0;
      final contentAdapter = NovelTestAdapter((options, body) {
        if (++requests == 1) {
          readerEntered.complete();
          return readerRelease.future;
        }
        taskEntered.complete();
        return taskRelease.future;
      });
      final client = NovelApi.withDio(
        user: user,
        dio: Dio()..httpClientAdapter = apiAdapter,
        contentDio: Dio()..httpClientAdapter = contentAdapter,
      );
      addTearDown(client.close);
      final repo = NovelRepository(
        api: client,
        store: store,
        now: () => store.now,
      );
      final reader = repo.loadVolumeContent('book', '7');
      await readerEntered.future;
      final token = CancelToken();
      final assertion = expectLater(
        repo.loadVolumeSnapshot('book', '7', cancelToken: token),
        throwsA(
          isA<DioException>().having(CancelToken.isCancel, 'cancelled', isTrue),
        ),
      );
      await taskEntered.future;
      token.cancel();
      await assertion;
      readerRelease.complete(ResponseBody.fromString('阅读正文\n', 200));
      expect((await reader).entries.first.paragraphs.first, '阅读正文');
      taskRelease.complete(ResponseBody.fromString('已取消旧正文\n', 200));
      await Future<void>.delayed(Duration.zero);
      expect(store.texts.values.single.text, '阅读正文\n');
    },
  );

  test(
    'file text snapshots persist large content without SharedPreferences',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'kira_novel_test_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final files = FileNovelCacheStore(directory: () async => directory);
      final content = List.filled(20000, '正文 空行\r\n\r\n').join();
      final entry = NovelTextCacheEntry(
        detail: novelFixtureDetail(),
        text: content,
        expiresAt: DateTime.utc(2027),
      );
      await files.writeText('book/volume', entry);
      final restarted = FileNovelCacheStore(directory: () async => directory);
      expect((await restarted.readText('book/volume'))!.text, content);
      // Replacement preserves a complete single-file snapshot.
      await restarted.writeText(
        'book/volume',
        NovelTextCacheEntry(
          detail: novelFixtureDetail(),
          text: '更新\n',
          expiresAt: DateTime.utc(2028),
        ),
      );
      expect((await files.readText('book/volume'))!.text, '更新\n');
      expect(await directory.list().length, 1);
    },
  );
}
