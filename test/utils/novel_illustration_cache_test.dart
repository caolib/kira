import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/app_logger.dart';
import 'package:kira/utils/novel_illustration_cache.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

final illustrationPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

/// 真实文件与 JSON 索引；路径可重用以验证 dispose 后的新实例读取磁盘。
CacheManager createIllustrationTestManager(String directory) {
  final manager = CacheManager(
    Config(
      'novelIllustrationTest-${directory.hashCode}',
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 300,
      repo: JsonCacheInfoRepository(path: '$directory/index.json'),
      fileService: _NoNetworkFileService(),
    ),
  );
  manager.store.cleanupRunMinInterval = const Duration(milliseconds: 1);
  return manager;
}

class _NoNetworkFileService extends FileService {
  @override
  Future<FileServiceResponse> get(String url, {Map<String, String>? headers}) =>
      throw StateError('Cache fileService must never request the network');
}

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.root);

  final String root;

  @override
  Future<String?> getTemporaryPath() async => root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

class _FaultCacheManager implements BaseCacheManager {
  _FaultCacheManager(this.delegate);

  final BaseCacheManager delegate;
  Object? readError;
  Object? writeError;
  Object? removeError;
  Object? clearError;
  final failureStack = StackTrace.fromString('illustration-cache-test-stack');

  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) async {
    if (readError case final error?) {
      Error.throwWithStackTrace(error, failureStack);
    }
    return delegate.getFileFromCache(key, ignoreMemCache: ignoreMemCache);
  }

  @override
  Future<Never> putFile(
    String url,
    Uint8List fileBytes, {
    String? key,
    String? eTag,
    Duration maxAge = const Duration(days: 30),
    String fileExtension = 'file',
  }) async => Error.throwWithStackTrace(writeError!, failureStack);

  @override
  Future<void> removeFile(String key) async {
    if (removeError case final error?) {
      Error.throwWithStackTrace(error, failureStack);
    }
    await delegate.removeFile(key);
  }

  @override
  Future<void> emptyCache() async {
    if (clearError case final error?) {
      Error.throwWithStackTrace(error, failureStack);
    }
    await delegate.emptyCache();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const url = 'https://cdn.invalid/illustration.png';
  late Directory suiteRoot;
  late Directory root;
  late PathProviderPlatform originalPaths;
  late CacheManager manager;
  late NovelIllustrationCache cache;
  late List<CacheManager> openManagers;
  var calls = 0;

  Future<List<int>> load() async {
    calls++;
    return illustrationPng;
  }

  setUpAll(() async {
    originalPaths = PathProviderPlatform.instance;
    suiteRoot = await Directory.systemTemp.createTemp('novel_illustration_');
    PathProviderPlatform.instance = _TestPaths(suiteRoot.path);
    SharedPreferences.setMockInitialValues({});
    await AppLogger.instance.init();
    await AppLogger.instance.setLoggingEnabled(true);
  });

  tearDownAll(() async {
    await AppLogger.instance.setLoggingEnabled(false);
    PathProviderPlatform.instance = originalPaths;
    await suiteRoot.delete(recursive: true);
  });

  setUp(() async {
    setupSecureCredentialStoreForTest();
    root = await suiteRoot.createTemp('cache_');
    manager = createIllustrationTestManager(root.path);
    openManagers = [manager];
    cache = NovelIllustrationCache(cacheManager: manager);
    calls = 0;
    await AppLogger.instance.clear();
  });

  tearDown(() async {
    await AppLogger.instance.readEntries();
    // 让包自身的一次性清理先完成，再关闭磁盘索引。
    await Future<void>.delayed(const Duration(milliseconds: 5));
    for (final manager in openManagers) {
      await manager.dispose();
    }
    await root.delete(recursive: true);
    teardownSecureCredentialStoreForTest();
  });

  test('真实插图落盘，dispose 后重建服务与 manager 命中且不联网', () async {
    expect(await cache.loadBytes(url, load: load), illustrationPng);
    final info = await manager.getFileFromCache(url);
    expect(await info!.file.readAsBytes(), illustrationPng);
    final remaining = info.validTill.difference(DateTime.now());
    expect(remaining.inHours, inInclusiveRange(167, 168));
    expect(manager.config.maxNrOfCacheObjects, 300);
    expect(manager.config.stalePeriod, const Duration(days: 7));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await manager.dispose();
    openManagers.remove(manager);

    manager = createIllustrationTestManager(root.path);
    openManagers.add(manager);
    final recreated = NovelIllustrationCache(cacheManager: manager);
    expect(await recreated.loadBytes(url, load: load), illustrationPng);
    expect(calls, 1);
  });

  test('跨服务实例同 URL 共用在途请求，不同 URL 各自请求', () async {
    final other = NovelIllustrationCache(cacheManager: manager);
    final started = Completer<void>();
    final response = Completer<List<int>>();
    Future<List<int>> delayedLoad() {
      calls++;
      started.complete();
      return response.future;
    }

    final first = cache.loadBytes(url, load: delayedLoad);
    final second = other.loadBytes(url, load: load);
    expect(identical(first, second), isTrue);
    await started.future;
    expect(calls, 1);
    expect(await other.loadBytes('$url?other', load: load), illustrationPng);
    expect(calls, 2);
    response.complete(illustrationPng);
    expect(await first, illustrationPng);
    expect(await second, illustrationPng);
  });

  test('过期缓存重取，不使用陈旧内容', () async {
    await manager.putFile(
      url,
      illustrationPng,
      maxAge: const Duration(seconds: -1),
    );
    expect(await cache.loadBytes(url, load: load), illustrationPng);
    expect(calls, 1);
    expect(
      (await manager.getFileFromCache(url))!.validTill.isAfter(DateTime.now()),
      isTrue,
    );
  });

  test('磁盘文件缺失重新联网，不保留已完成字节', () async {
    await cache.loadBytes(url, load: load);
    final info = await manager.getFileFromCache(url);
    await info!.file.delete();
    expect(await cache.loadBytes(url, load: load), illustrationPng);
    expect(calls, 2);
  });

  test('磁盘坏图记录真实解码错误并删除，重新联网后缓存正常图片', () async {
    await manager.putFile(url, Uint8List.fromList(utf8.encode('not an image')));
    expect(await cache.loadBytes(url, load: load), illustrationPng);
    expect(await cache.loadBytes(url, load: load), illustrationPng);
    expect(calls, 1);
    final entries = await AppLogger.instance.readEntries();
    final read = entries.singleWhere(
      (entry) => entry.source == 'novel_illustration_cache.read',
    );
    expect(read.message, isNotEmpty);
    expect(read.stackTrace, isNotEmpty);
  });

  test('请求失败跨实例释放在途状态，原异常保留且下一次可以重试', () async {
    final started = Completer<void>();
    final response = Completer<List<int>>();
    final failure = StateError('image request failed');
    final other = NovelIllustrationCache(cacheManager: manager);
    final first = cache.loadBytes(
      url,
      load: () {
        started.complete();
        return response.future;
      },
    );
    final second = other.loadBytes(url, load: load);
    final expectations = Future.wait([
      expectLater(first, throwsA(same(failure))),
      expectLater(second, throwsA(same(failure))),
    ]);
    await started.future;
    response.completeError(failure);
    await expectations;
    expect(await other.loadBytes(url, load: load), illustrationPng);
    expect(calls, 1);
  });

  test('在线返回坏图不落盘，下一次重试重新请求', () async {
    await expectLater(
      cache.loadBytes(url, load: () async => utf8.encode('<html>error</html>')),
      throwsA(isA<Exception>()),
    );
    expect(await manager.getFileFromCache(url), isNull);
    expect(await cache.loadBytes(url, load: load), illustrationPng);
    expect(calls, 1);
    final entries = await AppLogger.instance.readEntries();
    expect(
      entries.where((entry) => entry.source.endsWith('.validate')),
      hasLength(1),
    );
  });

  test('磁盘写入失败不阻断在线阅读，并记录原始异常及堆栈', () async {
    final fault = _FaultCacheManager(manager)
      ..writeError = const FileSystemException('disk full');
    final failing = NovelIllustrationCache(cacheManager: fault);
    expect(await failing.loadBytes(url, load: load), illustrationPng);
    expect(await failing.loadBytes(url, load: load), illustrationPng);
    expect(calls, 2);
    expect(await manager.getFileFromCache(url), isNull);
    final entries = await AppLogger.instance.readEntries();
    final write = entries.firstWhere(
      (entry) => entry.source == 'novel_illustration_cache.write',
    );
    expect(write.message, fault.writeError.toString());
    expect(write.stackTrace, contains(fault.failureStack.toString()));
  });

  test('缓存读取与坏项删除失败仍能在线阅读，保留各自真实异常', () async {
    final fault = _FaultCacheManager(manager)
      ..readError = const FileSystemException('read denied')
      ..removeError = const FileSystemException('delete denied')
      ..writeError = const FileSystemException('write denied');
    final failing = NovelIllustrationCache(cacheManager: fault);
    expect(await failing.loadBytes(url, load: load), illustrationPng);
    expect(calls, 1);
    final entries = await AppLogger.instance.readEntries();
    for (final operation in ['read', 'remove', 'write']) {
      final entry = entries.singleWhere(
        (entry) => entry.source == 'novel_illustration_cache.$operation',
      );
      expect(entry.stackTrace, contains(fault.failureStack.toString()));
    }
    expect(
      entries.map((entry) => entry.message),
      containsAll([
        fault.readError.toString(),
        fault.removeError.toString(),
        fault.writeError.toString(),
      ]),
    );
  });

  test('clear 清除磁盘，再读同 URL 必须联网', () async {
    await cache.loadBytes(url, load: load);
    await NovelIllustrationCache(cacheManager: manager).clear();
    expect(await manager.getFileFromCache(url), isNull);
    expect(await cache.loadBytes(url, load: load), illustrationPng);
    expect(calls, 2);
    expect(NovelIllustrationCache.cacheKey, 'novelIllustrationCache');
  });

  test('clear 不让尚未完成的旧请求回写或被后续读取复用', () async {
    final started = Completer<void>();
    final response = Completer<List<int>>();
    final old = cache.loadBytes(
      url,
      load: () {
        started.complete();
        return response.future;
      },
    );
    await started.future;
    await cache.clear();
    response.complete(illustrationPng);
    expect(await old, illustrationPng);
    expect(await manager.getFileFromCache(url), isNull);
    expect(await cache.loadBytes(url, load: load), illustrationPng);
    expect(calls, 1);
  });

  test('clear 失败原样上抛并记录，不污染后续读取队列', () async {
    const failure = FileSystemException('clear denied');
    final fault = _FaultCacheManager(manager)
      ..clearError = failure
      ..writeError = const FileSystemException('write denied');
    final failing = NovelIllustrationCache(cacheManager: fault);
    await expectLater(failing.clear(), throwsA(same(failure)));
    expect(await failing.loadBytes(url, load: load), illustrationPng);
    final entries = await AppLogger.instance.readEntries();
    final clearing = entries.singleWhere(
      (entry) => entry.source == 'novel_illustration_cache.clear',
    );
    expect(clearing.message, failure.toString());
    expect(clearing.stackTrace, contains(fault.failureStack.toString()));
  });
}
