import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/api/novel/novel_api.dart';
import 'package:kira/models/novel.dart';
import 'package:kira/models/novel_download.dart';
import 'package:kira/repositories/novel_reader_source.dart';
import 'package:kira/repositories/novel_repository.dart';
import 'package:kira/utils/app_logger.dart';
import 'package:kira/utils/novel_download_store.dart';
import 'package:kira/utils/novel_illustration_cache.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../novel_api_test.dart' show NovelTestAdapter, NovelTestUser;
import '../test_helpers.dart';
import '../utils/novel_download_store_test.dart'
    show downloadSnapshot, downloadVolume, saveFixture;
import '../utils/novel_illustration_cache_test.dart'
    show createIllustrationTestManager, illustrationPng;

class _OnlineSource implements NovelReaderSource {
  final calls = <String>[];
  Object? error;
  NovelVolumeContent? cached;

  @override
  bool get localOnly => false;

  @override
  Future<List<NovelVolume>> loadVolumes(String pathWord) async {
    calls.add('volumes/$pathWord');
    if (error case final error?) throw error;
    return [downloadVolume];
  }

  @override
  Future<NovelVolumeDetail> loadVolumeDetail(
    String pathWord,
    String volumeId,
  ) async {
    calls.add('detail/$pathWord/$volumeId');
    if (error case final error?) throw error;
    return downloadSnapshot.detail;
  }

  @override
  Future<NovelVolumeContent?> loadContent(
    String pathWord,
    String volumeId, {
    bool refresh = false,
    bool cachedOnly = false,
  }) async {
    calls.add('content/$pathWord/$volumeId/$refresh/$cachedOnly');
    if (cachedOnly) return cached;
    if (error case final error?) throw error;
    return downloadSnapshot.content;
  }

  @override
  Future<List<int>> loadImageBytes(
    String pathWord,
    String volumeId,
    String url,
  ) async {
    calls.add('image/$pathWord/$volumeId/$url');
    if (error case final error?) throw error;
    return [4, 5, 6];
  }
}

class _ReaderTestPaths extends PathProviderPlatform {
  _ReaderTestPaths(this.root);

  final String root;
  int calls = 0;

  @override
  Future<String?> getTemporaryPath() async {
    calls++;
    return root;
  }

  @override
  Future<String?> getApplicationSupportPath() async {
    calls++;
    return root;
  }
}

class _ConstNovelRepository implements NovelRepository {
  const _ConstNovelRepository();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late NovelDownloadStore store;
  late _OnlineSource online;
  late DownloadFirstNovelReaderSource source;
  late Directory logRoot;
  late PathProviderPlatform originalSuitePaths;

  setUpAll(() async {
    originalSuitePaths = PathProviderPlatform.instance;
    logRoot = await Directory.systemTemp.createTemp(
      'novel_reader_source_logs_',
    );
    PathProviderPlatform.instance = _ReaderTestPaths(logRoot.path);
    SharedPreferences.setMockInitialValues({});
    await AppLogger.instance.init();
  });

  tearDownAll(() async {
    await AppLogger.instance.readEntries();
    PathProviderPlatform.instance = originalSuitePaths;
    await logRoot.delete(recursive: true);
  });

  setUp(() async {
    setupSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('novel_reader_source_');
    store = NovelDownloadStore.forTesting(rootDirectory: root);
    await store.init();
    await saveFixture(store, complete: true);
    online = _OnlineSource();
    source = DownloadFirstNovelReaderSource(store, online);
  });

  tearDown(() async {
    await root.delete(recursive: true);
    teardownSecureCredentialStoreForTest();
  });

  test('已下载卷的正文、目录和插图离线读取，不请求在线来源', () async {
    online.error = StateError('network unavailable');
    expect(source.localOnly, isFalse);
    expect((await source.loadVolumes('book')).map((v) => v.id), ['v1', 'v2']);
    expect((await source.loadVolumeDetail('book', 'v1')).volume.id, 'v1');
    final content = await source.loadContent('book', 'v1', refresh: true);
    expect(content!.entries.first.paragraphs, ['', '正文', '', '结尾']);
    expect(
      await source.loadImageBytes(
        'book',
        'v1',
        downloadSnapshot.imageUrls.first,
      ),
      [1, 2, 3],
    );
    expect(online.calls, isEmpty);
  });

  test('未下载卷直接在线加载正文与目录，不写入永久下载', () async {
    await source.loadContent('book', 'v2');
    await source.loadVolumeDetail('book', 'v2');
    expect(online.calls, ['content/book/v2/false/false', 'detail/book/v2']);
    expect(store.downloadedVolumes('book'), {'v1'});
  });

  test('只读预取未命中时返回空，真正加载仍走在线来源', () async {
    expect(await source.loadContent('book', 'v2', cachedOnly: true), isNull);
    expect(await source.loadContent('book', 'v2'), isNotNull);
    expect(online.calls, [
      'content/book/v2/false/true',
      'content/book/v2/false/false',
    ]);
  });

  test('未下载卷可从阅读缓存读取，显式重试参数传给在线来源', () async {
    online.cached = downloadSnapshot.content;
    expect(await source.loadContent('book', 'v2', cachedOnly: true), isNotNull);
    await source.loadContent('book', 'v2', refresh: true);
    expect(online.calls.last, 'content/book/v2/true/false');
  });

  test('本地快照损坏自动在线回退，并保留待修复状态', () async {
    final snapshot = await root
        .list(recursive: true)
        .where((entry) => entry is File && entry.path.contains('snapshot_'))
        .first;
    await File(snapshot.path).writeAsString('broken');
    expect(await source.loadContent('book', 'v1'), isNotNull);
    expect(online.calls, ['content/book/v1/false/false']);
    expect(
      store.getLocalNovelInfo('book')!.downloaded['v1']!.status,
      NovelDownloadStatus.needsRepair,
    );
  });

  test('缺失插图自动在线加载，不修改永久下载', () async {
    const url = 'https://cdn.invalid/missing-image';
    expect(await source.loadImageBytes('book', 'v1', url), [4, 5, 6]);
    expect(online.calls, ['image/book/v1/$url']);
    expect(await store.readImageBytes('book', 'v1', url), isNull);
  });

  test('未下载卷联网失败保留原始错误，不替换为未下载提示', () async {
    final error = StateError('connection refused');
    online.error = error;
    await expectLater(source.loadContent('book', 'v2'), throwsA(same(error)));
    await expectLater(
      source.loadVolumeDetail('book', 'v2'),
      throwsA(same(error)),
    );
  });

  test('没有本地目录的书籍使用在线目录', () async {
    await source.loadVolumes('other-book');
    expect(online.calls, ['volumes/other-book']);
  });

  test('下载目录尚未初始化时使用在线来源，不触发平台目录读取', () async {
    final uninitialized = NovelDownloadStore.forTesting(rootDirectory: root);
    final source = DownloadFirstNovelReaderSource(uninitialized, online);
    await source.loadContent('book', 'v1');
    expect(uninitialized.rootPath, isNull);
    expect(online.calls, ['content/book/v1/false/false']);
  });

  test('显式本地来源只读永久下载，插图缺失不联网回退', () async {
    final local = DownloadedNovelReaderSource(store);
    expect(local.localOnly, isTrue);
    expect(
      await local.loadImageBytes(
        'book',
        'v1',
        downloadSnapshot.imageUrls.first,
      ),
      [1, 2, 3],
    );
    await expectLater(
      local.loadImageBytes('book', 'v1', 'https://cdn.invalid/missing'),
      throwsA(isA<NovelDownloadUnavailableException>()),
    );
    expect(online.calls, isEmpty);
  });

  group('RepositoryNovelReaderSource illustration cache', () {
    const url = 'https://cdn.invalid/image.png';
    late PathProviderPlatform originalPaths;
    late _ReaderTestPaths paths;
    late CacheManager manager;
    late NovelTestAdapter adapter;
    late NovelApi api;
    late NovelRepository repository;
    late RepositoryNovelReaderSource reader;
    Completer<ResponseBody>? response;

    setUp(() {
      originalPaths = PathProviderPlatform.instance;
      paths = _ReaderTestPaths(root.path);
      PathProviderPlatform.instance = paths;
      manager = createIllustrationTestManager(root.path);
      response = null;
      adapter = NovelTestAdapter(
        (options, body) =>
            response?.future ??
            Future.value(ResponseBody.fromBytes(illustrationPng, 200)),
      );
      final user = NovelTestUser()
        ..copyToken = 'COPY_TEST'
        ..token = 'HOT_TEST';
      api = NovelApi.withDio(
        user: user,
        dio: Dio()
          ..httpClientAdapter = NovelTestAdapter(
            (options, body) => throw StateError('Unexpected metadata request'),
          ),
        contentDio: Dio(
          BaseOptions(
            headers: {
              'Authorization': 'LEAK',
              'Cookie': 'session=LEAK',
              'x-auth-signature': 'LEAK',
            },
          ),
        )..httpClientAdapter = adapter,
      );
      repository = NovelRepository(api: api);
      reader = RepositoryNovelReaderSource(
        repository,
        illustrationCache: NovelIllustrationCache(cacheManager: manager),
      );
    });

    tearDown(() async {
      api.close();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await manager.dispose();
      PathProviderPlatform.instance = originalPaths;
    });

    test('默认构造保持 const，创建来源不触发默认 manager 平台 IO', () async {
      paths.calls = 0;
      const source = RepositoryNovelReaderSource(_ConstNovelRepository());
      expect(source.localOnly, isFalse);
      expect(RepositoryNovelReaderSource(repository).localOnly, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(paths.calls, 0);
    });

    test('按 URL 跨书卷命中缓存，miss 仍用 credential-free 小说 API', () async {
      expect(await reader.loadImageBytes('book', 'v1', url), illustrationPng);
      expect(await reader.loadImageBytes('other', 'v2', url), illustrationPng);
      expect(adapter.requests, hasLength(1));
      final request = adapter.requests.single;
      expect(request.uri.toString(), url);
      expect(request.responseType, ResponseType.bytes);
      expect(request.followRedirects, isFalse);
      final headers = request.headers.keys.map((key) => key.toLowerCase());
      expect(headers, isNot(contains('authorization')));
      expect(headers, isNot(contains('cookie')));
      expect(headers, isNot(contains('x-auth-signature')));
      expect(request.headers.toString(), isNot(contains('COPY_TEST')));
      expect(request.headers.toString(), isNot(contains('HOT_TEST')));
    });

    test('不同 Repository 与缓存服务实例同 URL 并发只发一次请求', () async {
      response = Completer<ResponseBody>();
      final other = RepositoryNovelReaderSource(
        NovelRepository(api: api),
        illustrationCache: NovelIllustrationCache(cacheManager: manager),
      );
      final first = reader.loadImageBytes('book', 'v1', url);
      final second = other.loadImageBytes('other', 'v2', url);
      expect(identical(first, second), isTrue);
      response!.complete(ResponseBody.fromBytes(illustrationPng, 200));
      expect(await first, illustrationPng);
      expect(await second, illustrationPng);
      expect(adapter.requests, hasLength(1));
    });

    test('下载优先来源绕过全局缓存，缺失图回退缓存但不写永久下载', () async {
      final cache = reader.illustrationCache!;
      final downloadedUrl = downloadSnapshot.imageUrls.first;
      await cache.loadBytes(downloadedUrl, load: () async => illustrationPng);
      final hybrid = DownloadFirstNovelReaderSource(store, reader);
      expect(await hybrid.loadImageBytes('book', 'v1', downloadedUrl), [
        1,
        2,
        3,
      ]);
      expect(adapter.requests, isEmpty);
      expect(await hybrid.loadImageBytes('book', 'v1', url), illustrationPng);
      expect(await hybrid.loadImageBytes('book', 'v2', url), illustrationPng);
      expect(adapter.requests, hasLength(1));
      expect(await store.readImageBytes('book', 'v1', url), isNull);
      await cache.clear();
      expect(await hybrid.loadImageBytes('book', 'v1', downloadedUrl), [
        1,
        2,
        3,
      ]);
      final local = DownloadedNovelReaderSource(store);
      await expectLater(
        local.loadImageBytes('book', 'v1', url),
        throwsA(isA<NovelDownloadUnavailableException>()),
      );
      expect(adapter.requests, hasLength(1));
    });
  });
}
