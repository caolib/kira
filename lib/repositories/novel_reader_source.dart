import 'dart:async';

import '../models/novel.dart';
import '../utils/app_logger.dart';
import '../utils/novel_download_store.dart';
import 'novel_repository.dart';

/// 阅读器和目录弹层共用同一个来源，保持正文、目录与插图的加载策略一致。
abstract interface class NovelReaderSource {
  bool get localOnly;

  Future<List<NovelVolume>> loadVolumes(String pathWord);

  Future<NovelVolumeDetail> loadVolumeDetail(String pathWord, String volumeId);

  Future<NovelVolumeContent?> loadContent(
    String pathWord,
    String volumeId, {
    bool refresh = false,
    bool cachedOnly = false,
  });

  Future<List<int>> loadImageBytes(
    String pathWord,
    String volumeId,
    String url,
  );
}

class RepositoryNovelReaderSource implements NovelReaderSource {
  const RepositoryNovelReaderSource(this.repository);

  final NovelRepository repository;

  @override
  bool get localOnly => false;

  @override
  Future<List<NovelVolume>> loadVolumes(String pathWord) =>
      repository.loadVolumes(pathWord);

  @override
  Future<NovelVolumeDetail> loadVolumeDetail(
    String pathWord,
    String volumeId,
  ) => repository.loadVolumeDetail(pathWord, volumeId);

  @override
  Future<NovelVolumeContent?> loadContent(
    String pathWord,
    String volumeId, {
    bool refresh = false,
    bool cachedOnly = false,
  }) => cachedOnly
      ? repository.getCachedVolumeContent(pathWord, volumeId)
      : repository.loadVolumeContent(pathWord, volumeId, refresh: refresh);

  @override
  Future<List<int>> loadImageBytes(
    String pathWord,
    String volumeId,
    String url,
  ) => repository.api.getContentBytes(url);
}

/// 按卷优先读取永久下载，缺失或损坏时使用在线来源；只读缓存预取不联网。
class DownloadFirstNovelReaderSource implements NovelReaderSource {
  const DownloadFirstNovelReaderSource(this.store, this.fallback);

  final NovelDownloadStore store;
  final NovelReaderSource fallback;

  @override
  bool get localOnly => false;

  Future<T?> _readDownload<T>(Future<T?> Function() read) async {
    // 下载目录由启动流程或本地入口初始化，普通在线入口不额外触发平台 I/O。
    if (store.rootPath == null) return null;
    try {
      return await read();
    } catch (error, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          error,
          stackTrace: stack,
          source: 'novel_reader.downloads',
        ),
      );
      return null;
    }
  }

  @override
  Future<List<NovelVolume>> loadVolumes(String pathWord) async {
    final volumes = store.getLocalNovelInfo(pathWord)?.volumes;
    if (volumes != null && volumes.isNotEmpty) return volumes;
    return fallback.loadVolumes(pathWord);
  }

  @override
  Future<NovelVolumeDetail> loadVolumeDetail(
    String pathWord,
    String volumeId,
  ) async {
    final snapshot = await _readDownload(
      () => store.readVolumeSnapshot(pathWord, volumeId),
    );
    return snapshot?.detail ??
        await fallback.loadVolumeDetail(pathWord, volumeId);
  }

  @override
  Future<NovelVolumeContent?> loadContent(
    String pathWord,
    String volumeId, {
    bool refresh = false,
    bool cachedOnly = false,
  }) async {
    final snapshot = await _readDownload(
      () => store.readVolumeSnapshot(pathWord, volumeId),
    );
    return snapshot?.content ??
        await fallback.loadContent(
          pathWord,
          volumeId,
          refresh: refresh,
          cachedOnly: cachedOnly,
        );
  }

  @override
  Future<List<int>> loadImageBytes(
    String pathWord,
    String volumeId,
    String url,
  ) async {
    final bytes = await _readDownload(
      () => store.readImageBytes(pathWord, volumeId, url),
    );
    return bytes ?? await fallback.loadImageBytes(pathWord, volumeId, url);
  }
}

class NovelDownloadUnavailableException implements Exception {
  const NovelDownloadUnavailableException();

  @override
  String toString() => 'The downloaded novel volume or asset is unavailable';
}

/// 显式本地来源没有任何网络回退，退出账号或清理阅读缓存也不影响它。
class DownloadedNovelReaderSource implements NovelReaderSource {
  const DownloadedNovelReaderSource(this.store);

  final NovelDownloadStore store;

  @override
  bool get localOnly => true;

  @override
  Future<List<NovelVolume>> loadVolumes(String pathWord) async {
    await store.init();
    return store.getLocalNovelInfo(pathWord)?.volumes ?? const [];
  }

  @override
  Future<NovelVolumeDetail> loadVolumeDetail(
    String pathWord,
    String volumeId,
  ) async {
    await store.init();
    final snapshot = await store.readVolumeSnapshot(pathWord, volumeId);
    if (snapshot == null) throw const NovelDownloadUnavailableException();
    return snapshot.detail;
  }

  @override
  Future<NovelVolumeContent?> loadContent(
    String pathWord,
    String volumeId, {
    bool refresh = false,
    bool cachedOnly = false,
  }) async {
    await store.init();
    final snapshot = await store.readVolumeSnapshot(pathWord, volumeId);
    if (snapshot == null) throw const NovelDownloadUnavailableException();
    return snapshot.content;
  }

  @override
  Future<List<int>> loadImageBytes(
    String pathWord,
    String volumeId,
    String url,
  ) async {
    final bytes = await store.readImageBytes(pathWord, volumeId, url);
    if (bytes == null) throw const NovelDownloadUnavailableException();
    return bytes;
  }
}
