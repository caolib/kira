import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/novel.dart';
import 'package:kira/models/novel_download.dart';
import 'package:kira/repositories/novel_reader_source.dart';
import 'package:kira/utils/novel_download_store.dart';

import '../utils/novel_download_store_test.dart'
    show downloadSnapshot, downloadVolume, saveFixture;

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late NovelDownloadStore store;
  late _OnlineSource online;
  late DownloadFirstNovelReaderSource source;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('novel_reader_source_');
    store = NovelDownloadStore.forTesting(rootDirectory: root);
    await store.init();
    await saveFixture(store, complete: true);
    online = _OnlineSource();
    source = DownloadFirstNovelReaderSource(store, online);
  });

  tearDown(() async => root.delete(recursive: true));

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
}
