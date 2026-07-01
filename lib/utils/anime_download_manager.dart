import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../api/api_client.dart';
import '../models/anime.dart';
import 'app_dio.dart';

enum DownloadTaskStatus { pending, downloading, paused, failed }

class AnimeDownloadTaskInfo {
  final String pathWord;
  final String chapterUuid;
  final String chapterName;
  final String animeName;
  final String? cover;
  final DownloadTaskStatus status;
  final AnimeChapterDownloadProgress? progress;
  final String? errorMessage;

  const AnimeDownloadTaskInfo({
    required this.pathWord,
    required this.chapterUuid,
    required this.chapterName,
    required this.animeName,
    this.cover,
    required this.status,
    this.progress,
    this.errorMessage,
  });

  String get taskKey => '$pathWord|||$chapterUuid';
}

class AnimeDownloadManager extends ChangeNotifier {
  static final AnimeDownloadManager _instance = AnimeDownloadManager._();
  factory AnimeDownloadManager() => _instance;
  AnimeDownloadManager._();

  static const _manifestVersion = 1;
  static const _rootFolderName = 'anime_downloads';
  static const _manifestFileName = 'manifest.json';
  static const _animeMetaFileName = 'anime.json';
  static const _coverFileName = 'cover';
  static const _playlistFileName = 'playlist.m3u8';
  static const Duration _timeout = Duration(seconds: 30);

  final ApiClient _api = ApiClient();
  final Map<String, Map<String, DownloadedAnimeChapterSummary>> _manifest = {};
  final List<_AnimeDownloadTask> _tasks = [];
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  bool _initialized = false;
  bool _processing = false;
  Future<void>? _initFuture;
  Directory? _rootDirectory;
  CancelToken? _activeCancelToken;

  Stream<String> get onError => _errorController.stream;

  List<AnimeDownloadTaskInfo> get tasks {
    // 去重：同一个 chapter 只取最新状态的任务
    final seen = <String>{};
    final result = <AnimeDownloadTaskInfo>[];
    for (var i = _tasks.length - 1; i >= 0; i--) {
      final key = _tasks[i].taskKey;
      if (seen.add(key)) result.add(_tasks[i].toInfo());
    }
    return result.reversed.toList();
  }

  bool get isBusy => _tasks.any(
    (t) =>
        t.status == DownloadTaskStatus.pending ||
        t.status == DownloadTaskStatus.downloading,
  );

  String _friendlyErrorMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '连接超时';
      case DioExceptionType.connectionError:
        return '建议开启代理后重试';
      default:
        return e.message ?? '建议开启代理后重试';
    }
  }

  Future<void> init() async {
    if (_initialized) return;
    _initFuture ??= _initialize();
    await _initFuture;
  }

  Set<String> downloadedChapterIds(String pathWord) =>
      _manifest[pathWord]?.keys.toSet() ?? const <String>{};

  List<LocalAnimeEntry> localAnimes() {
    final items = _manifest.entries
        .map((entry) {
          final lastSavedAt = entry.value.values.fold<DateTime>(
            DateTime.fromMillisecondsSinceEpoch(0),
            (current, item) =>
                item.savedAt.isAfter(current) ? item.savedAt : current,
          );
          final info =
              _readLocalAnimeInfo(entry.key) ??
              LocalAnimeInfo.fallback(entry.key, updatedAt: lastSavedAt);
          return LocalAnimeEntry(
            info: info,
            downloadedCount: entry.value.length,
          );
        })
        .whereType<LocalAnimeEntry>()
        .toList();
    items.sort((a, b) => b.info.updatedAt.compareTo(a.info.updatedAt));
    return items;
  }

  LocalAnimeInfo? getLocalAnimeInfo(String pathWord) {
    final info = _readLocalAnimeInfo(pathWord);
    if (info != null) return info;
    final chapters = _manifest[pathWord]?.values;
    if (chapters == null || chapters.isEmpty) return null;
    return LocalAnimeInfo.fallback(
      pathWord,
      updatedAt: chapters.fold<DateTime>(
        DateTime.fromMillisecondsSinceEpoch(0),
        (current, item) =>
            item.savedAt.isAfter(current) ? item.savedAt : current,
      ),
    );
  }

  List<DownloadedAnimeChapterSummary> downloadedChapters(String pathWord) {
    final chapters =
        _manifest[pathWord]?.values.toList() ??
        <DownloadedAnimeChapterSummary>[];
    chapters.sort((a, b) => a.savedAt.compareTo(b.savedAt));
    return chapters;
  }

  bool isDownloaded(String pathWord, String chapterUuid) =>
      _manifest[pathWord]?.containsKey(chapterUuid) == true;

  bool isInQueue(String pathWord, String chapterUuid) =>
      _findTask(pathWord, chapterUuid) != null;

  AnimeDownloadTaskInfo? taskInfo(String pathWord, String chapterUuid) {
    final task = _findTask(pathWord, chapterUuid);
    return task?.toInfo();
  }

  AnimeChapterDownloadProgress? progressOf(
    String pathWord,
    String chapterUuid,
  ) {
    final task = _findTask(pathWord, chapterUuid);
    if (task?.status != DownloadTaskStatus.downloading) return null;
    return task!.progress;
  }

  String? getLocalVideoPath(String pathWord, String chapterUuid) {
    if (!isDownloaded(pathWord, chapterUuid)) return null;
    final dir = _chapterDirectory(pathWord, chapterUuid);
    final playlistFile = File(_joinPath([dir.path, _playlistFileName]));
    if (playlistFile.existsSync()) return playlistFile.path;

    final videoFiles = dir.listSync().whereType<File>().where((f) {
      final ext = f.path.toLowerCase();
      return ext.endsWith('.mp4') ||
          ext.endsWith('.mkv') ||
          ext.endsWith('.webm') ||
          ext.endsWith('.ts');
    }).toList();
    if (videoFiles.isNotEmpty) return videoFiles.first.path;
    return null;
  }

  /// 批量添加下载任务
  Future<int> enqueueChapters({
    required String pathWord,
    required Anime anime,
    required List<AnimeChapter> chapters,
    required String line,
  }) async {
    await init();

    await _ensureAnimeStored(pathWord, anime);

    var added = 0;
    for (final chapter in chapters) {
      if (chapter.uuid.isEmpty || isDownloaded(pathWord, chapter.uuid)) {
        continue;
      }
      if (_findTask(pathWord, chapter.uuid) != null) continue;

      _tasks.add(
        _AnimeDownloadTask(
          pathWord: pathWord,
          chapter: chapter,
          line: line,
          animeName: anime.name,
          cover: anime.cover,
        ),
      );
      added++;
    }

    if (added > 0) {
      notifyListeners();
      unawaited(_processQueue());
    }

    return added;
  }

  /// 暂停任务
  void pauseTask(String pathWord, String chapterUuid) {
    final task = _findTask(pathWord, chapterUuid);
    if (task == null) return;

    if (task.status == DownloadTaskStatus.downloading) {
      _activeCancelToken?.cancel();
      _activeCancelToken = null;
      task.status = DownloadTaskStatus.paused;
    } else if (task.status == DownloadTaskStatus.pending) {
      task.status = DownloadTaskStatus.paused;
    }
    notifyListeners();
  }

  /// 恢复暂停/失败的任务
  void resumeTask(String pathWord, String chapterUuid) {
    final task = _findTask(pathWord, chapterUuid);
    if (task == null) return;
    if (task.status != DownloadTaskStatus.paused &&
        task.status != DownloadTaskStatus.failed) {
      return;
    }

    task.status = DownloadTaskStatus.pending;
    task.errorMessage = null;
    notifyListeners();
    unawaited(_processQueue());
  }

  /// 取消（移除）任务
  void cancelTask(String pathWord, String chapterUuid) {
    final task = _findTask(pathWord, chapterUuid);
    if (task == null) return;

    if (task.status == DownloadTaskStatus.downloading) {
      _activeCancelToken?.cancel();
      _activeCancelToken = null;
    }
    _tasks.remove(task);
    notifyListeners();
  }

  Future<void> deleteChapters(
    String pathWord,
    Iterable<String> chapterUuids,
  ) async {
    await init();
    for (final chapterUuid in chapterUuids.toSet()) {
      await _removeDownloadedChapter(pathWord, chapterUuid, deleteFiles: true);
    }
    if (_manifest[pathWord]?.isEmpty ?? true) {
      await _removeLocalAnime(pathWord);
    }
    notifyListeners();
  }

  Future<void> deleteLocalAnimes(Iterable<String> pathWords) async {
    await init();
    for (final pathWord in pathWords.toSet()) {
      _manifest.remove(pathWord);
      await _removeLocalAnime(pathWord);
    }
    await _persistManifest();
    notifyListeners();
  }

  // ── private ──

  _AnimeDownloadTask? _findTask(String pathWord, String chapterUuid) {
    final key = _taskKey(pathWord, chapterUuid);
    for (final task in _tasks) {
      if (task.taskKey == key) return task;
    }
    return null;
  }

  Future<void> _initialize() async {
    final docsDir = await getApplicationDocumentsDirectory();
    _rootDirectory = Directory(_joinPath([docsDir.path, _rootFolderName]));
    await _rootDirectory!.create(recursive: true);

    final manifestFile = _manifestFile;
    if (await manifestFile.exists()) {
      try {
        final raw = await manifestFile.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded['animes'] is Map) {
          final animes = Map<String, dynamic>.from(decoded['animes'] as Map);
          for (final animeEntry in animes.entries) {
            final chaptersRaw = animeEntry.value;
            if (chaptersRaw is! Map) continue;

            final summaries = <String, DownloadedAnimeChapterSummary>{};
            for (final chapterEntry in chaptersRaw.entries) {
              final summaryRaw = chapterEntry.value;
              if (summaryRaw is! Map) continue;
              summaries[chapterEntry.key
                  .toString()] = DownloadedAnimeChapterSummary.fromJson(
                Map<String, dynamic>.from(summaryRaw),
              );
            }

            if (summaries.isNotEmpty) {
              _manifest[animeEntry.key] = summaries;
            }
          }
        }
      } catch (e) {
        debugPrint('Load anime download manifest failed: $e');
      }
    }

    _initialized = true;
  }

  Future<void> _processQueue() async {
    if (_processing) return;
    _processing = true;

    try {
      while (_tasks.any((t) => t.status == DownloadTaskStatus.pending)) {
        // 取第一个 pending 任务
        final task = _tasks.firstWhere(
          (t) => t.status == DownloadTaskStatus.pending,
        );
        task.status = DownloadTaskStatus.downloading;
        task.progress = null;
        notifyListeners();

        try {
          await _downloadChapter(task);
          // 下载完成，从任务列表移除
          _tasks.remove(task);
          notifyListeners();
        } on DioException catch (e) {
          if (e.type == DioExceptionType.cancel) {
            // 用户主动取消，保持 paused 状态
            notifyListeners();
          } else {
            debugPrint(
              'Download anime chapter failed: ${task.pathWord}/${task.chapter.uuid} $e',
            );
            task.status = DownloadTaskStatus.failed;
            task.errorMessage = _friendlyErrorMessage(e);
            _errorController.add(
              '${task.chapterName} 下载失败：${task.errorMessage}',
            );
            notifyListeners();
          }
        } catch (e) {
          debugPrint(
            'Download anime chapter failed: ${task.pathWord}/${task.chapter.uuid} $e',
          );
          task.status = DownloadTaskStatus.failed;
          task.errorMessage = '未知错误';
          _errorController.add('${task.chapterName} 下载失败：$e');
          notifyListeners();
        }
      }
    } finally {
      _processing = false;
      notifyListeners();
    }
  }

  Future<void> _downloadChapter(_AnimeDownloadTask task) async {
    final chapterDir = _chapterDirectory(task.pathWord, task.chapter.uuid);

    try {
      await _resetDirectory(chapterDir);

      final playback = await _api.getAnimePlayback(
        task.pathWord,
        task.chapter.uuid,
        line: task.line,
      );

      final videoUrl = _resolveVideoUrl(playback.chapter);
      if (videoUrl.isEmpty) {
        throw const HttpException('视频链接为空');
      }

      final isHls = await _isHlsStream(videoUrl);

      if (isHls) {
        await _downloadHls(videoUrl, chapterDir);
      } else {
        await _downloadDirectVideo(videoUrl, chapterDir);
      }

      _manifest.putIfAbsent(task.pathWord, () => {});
      _manifest[task.pathWord]![task.chapter.uuid] =
          DownloadedAnimeChapterSummary(
            chapterUuid: task.chapter.uuid,
            chapterName: task.chapter.name,
            savedAt: DateTime.now(),
          );
      await _persistManifest();
      await _touchLocalAnime(task.pathWord);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      await _clearChapterDir(chapterDir);
      rethrow;
    } catch (_) {
      await _clearChapterDir(chapterDir);
      rethrow;
    }
  }

  String _resolveVideoUrl(AnimePlaybackChapter chapter) {
    if (chapter.video.isNotEmpty) return chapter.video;
    for (final url in chapter.videoList) {
      if (url.isNotEmpty) return url;
    }
    return '';
  }

  Future<bool> _isHlsStream(String url) async {
    final dio = AppDio.create(
      source: 'anime_download_probe',
      options: BaseOptions(
        responseType: ResponseType.plain,
        sendTimeout: _timeout,
        receiveTimeout: _timeout,
      ),
    );
    try {
      final response = await dio.get(url);
      final text = response.data?.toString() ?? '';
      return text.trim().startsWith('#EXTM3U');
    } catch (_) {
      return false;
    } finally {
      dio.close(force: true);
    }
  }

  Future<void> _downloadHls(String playlistUrl, Directory chapterDir) async {
    _activeCancelToken = CancelToken();
    final cancelToken = _activeCancelToken!;

    final dio = AppDio.create(
      source: 'anime_download_playlist',
      options: BaseOptions(
        responseType: ResponseType.plain,
        sendTimeout: _timeout,
        receiveTimeout: _timeout,
      ),
    );

    final segmentDio = AppDio.create(
      source: 'anime_download_segment',
      options: BaseOptions(
        responseType: ResponseType.bytes,
        sendTimeout: _timeout,
        receiveTimeout: const Duration(minutes: 5),
      ),
    );

    try {
      final resolved = await _resolveMediaPlaylist(
        dio,
        playlistUrl,
        cancelToken,
      );
      final playlistText = resolved.text;
      final baseUri = Uri.parse(resolved.url);

      final lines = playlistText.split(RegExp(r'\r?\n'));
      final segmentIndices = <int>[];
      final keyIndices = <int>[];
      final mapIndices = <int>[];

      for (var i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trim();
        if (trimmed.isEmpty) continue;
        if (trimmed.startsWith('#EXT-X-KEY')) {
          if (trimmed.contains('URI=')) keyIndices.add(i);
        } else if (trimmed.startsWith('#EXT-X-MAP')) {
          if (trimmed.contains('URI=')) mapIndices.add(i);
        } else if (!trimmed.startsWith('#')) {
          segmentIndices.add(i);
        }
      }

      if (segmentIndices.isEmpty) {
        throw const HttpException('m3u8 文件中没有找到视频片段');
      }

      final totalAssets =
          segmentIndices.length + keyIndices.length + mapIndices.length;
      var completed = 0;
      var segmentBytes = 0;
      var segmentsDownloaded = 0;
      var nonSegmentBytes = 0;
      _updateProgress(task: null, completed: 0, total: totalAssets);

      int? estimateTotalBytes() {
        if (segmentsDownloaded == 0) return null;
        final perSegment = segmentBytes / segmentsDownloaded;
        return (perSegment * segmentIndices.length).round() + nonSegmentBytes;
      }

      final tagReplacements = <int, String>{};

      // 1) 下载 EXT-X-KEY 引用的密钥文件
      for (var k = 0; k < keyIndices.length; k++) {
        final idx = keyIndices[k];
        final originalUri = _extractUriAttribute(lines[idx]);
        if (originalUri == null || originalUri.isEmpty) continue;
        final absUrl = baseUri.resolve(originalUri).toString();
        final localName = 'key_$k.bin';
        final savePath = _joinPath([chapterDir.path, localName]);
        await _downloadFile(
          segmentDio,
          absUrl,
          savePath,
          cancelToken: cancelToken,
        );
        nonSegmentBytes += await _fileSizeOrZero(savePath);
        tagReplacements[idx] = _replaceUriAttribute(lines[idx], localName);
        completed++;
        _updateProgress(
          task: null,
          completed: completed,
          total: totalAssets,
          estimatedTotalBytes: estimateTotalBytes(),
        );
      }

      // 2) 下载 EXT-X-MAP 引用的初始化分段（fMP4 必需）
      for (var m = 0; m < mapIndices.length; m++) {
        final idx = mapIndices[m];
        final originalUri = _extractUriAttribute(lines[idx]);
        if (originalUri == null || originalUri.isEmpty) continue;
        final absUrl = baseUri.resolve(originalUri).toString();
        final ext = _hlsExtFromUri(originalUri, '.mp4');
        final localName = 'init_$m$ext';
        final savePath = _joinPath([chapterDir.path, localName]);
        await _downloadFile(
          segmentDio,
          absUrl,
          savePath,
          cancelToken: cancelToken,
        );
        nonSegmentBytes += await _fileSizeOrZero(savePath);
        tagReplacements[idx] = _replaceUriAttribute(lines[idx], localName);
        completed++;
        _updateProgress(
          task: null,
          completed: completed,
          total: totalAssets,
          estimatedTotalBytes: estimateTotalBytes(),
        );
      }

      // 3) 下载视频分片，保留原始扩展名（.ts/.m4s/.aac 等）
      final segFileMap = <int, String>{};
      for (var j = 0; j < segmentIndices.length; j++) {
        final lineIdx = segmentIndices[j];
        final segUri = lines[lineIdx].trim();
        final segmentUrl = baseUri.resolve(segUri).toString();
        final ext = _hlsExtFromUri(segUri, '.ts');
        final segFileName = 'seg_${j.toString().padLeft(5, '0')}$ext';
        segFileMap[lineIdx] = segFileName;
        final savePath = _joinPath([chapterDir.path, segFileName]);
        await _downloadFile(
          segmentDio,
          segmentUrl,
          savePath,
          cancelToken: cancelToken,
        );
        segmentBytes += await _fileSizeOrZero(savePath);
        segmentsDownloaded++;
        completed++;
        _updateProgress(
          task: null,
          completed: completed,
          total: totalAssets,
          estimatedTotalBytes: estimateTotalBytes(),
        );
      }

      // 4) 重建本地 playlist，保留原始行内容（不再 trim 去掉格式）
      final localLines = <String>[];
      for (var i = 0; i < lines.length; i++) {
        if (segFileMap.containsKey(i)) {
          localLines.add(segFileMap[i]!);
        } else if (tagReplacements.containsKey(i)) {
          localLines.add(tagReplacements[i]!);
        } else {
          localLines.add(lines[i]);
        }
      }

      final localPlaylist = File(
        _joinPath([chapterDir.path, _playlistFileName]),
      );
      await localPlaylist.writeAsString(localLines.join('\n'));
    } finally {
      segmentDio.close(force: true);
      dio.close(force: true);
      _activeCancelToken = null;
    }
  }

  /// 如果 [url] 指向 master playlist（含 EXT-X-STREAM-INF），
  /// 选最高码率的子 playlist 并返回其 URL 与内容；否则返回原 URL 与内容。
  Future<_HlsPlaylistFetch> _resolveMediaPlaylist(
    Dio dio,
    String url,
    CancelToken cancelToken,
  ) async {
    final response = await dio.get(url, cancelToken: cancelToken);
    final text = response.data?.toString() ?? '';
    if (!text.trim().startsWith('#EXTM3U')) {
      throw const HttpException('不是有效的 m3u8 文件');
    }
    final lines = text.split(RegExp(r'\r?\n'));
    String? bestUri;
    var bestBandwidth = -1;
    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trim();
      if (!trimmed.startsWith('#EXT-X-STREAM-INF')) continue;
      final bwMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(trimmed);
      final bw = bwMatch == null ? 0 : int.tryParse(bwMatch.group(1)!) ?? 0;
      for (var j = i + 1; j < lines.length; j++) {
        final next = lines[j].trim();
        if (next.isEmpty || next.startsWith('#')) continue;
        if (bw > bestBandwidth) {
          bestBandwidth = bw;
          bestUri = next;
        }
        break;
      }
    }
    if (bestUri == null) return _HlsPlaylistFetch(url, text);
    final childUrl = Uri.parse(url).resolve(bestUri).toString();
    final childResponse = await dio.get(childUrl, cancelToken: cancelToken);
    final childText = childResponse.data?.toString() ?? '';
    if (!childText.trim().startsWith('#EXTM3U')) {
      throw const HttpException('子 m3u8 文件无效');
    }
    return _HlsPlaylistFetch(childUrl, childText);
  }

  String? _extractUriAttribute(String tagLine) {
    final match = RegExp(r'URI="([^"]*)"').firstMatch(tagLine);
    return match?.group(1);
  }

  String _replaceUriAttribute(String tagLine, String newUri) {
    return tagLine.replaceFirst(RegExp(r'URI="[^"]*"'), 'URI="$newUri"');
  }

  String _hlsExtFromUri(String uri, String fallback) {
    final qIdx = uri.indexOf('?');
    final path = qIdx >= 0 ? uri.substring(0, qIdx) : uri;
    final slashIdx = path.lastIndexOf('/');
    final last = slashIdx >= 0 ? path.substring(slashIdx + 1) : path;
    final dotIdx = last.lastIndexOf('.');
    if (dotIdx < 0) return fallback;
    final ext = last.substring(dotIdx).toLowerCase();
    if (RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(ext)) return ext;
    return fallback;
  }

  Future<void> _downloadDirectVideo(
    String videoUrl,
    Directory chapterDir,
  ) async {
    _activeCancelToken = CancelToken();
    final cancelToken = _activeCancelToken!;

    final uri = Uri.parse(videoUrl);
    var extension = '.mp4';
    final lastSegment = uri.pathSegments.isNotEmpty
        ? uri.pathSegments.last
        : uri.path;
    final dotIndex = lastSegment.lastIndexOf('.');
    if (dotIndex > 0) {
      final ext = lastSegment.substring(dotIndex).toLowerCase();
      if (RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(ext)) {
        extension = ext;
      }
    }

    final videoFile = File(_joinPath([chapterDir.path, 'video$extension']));

    _updateProgress(task: null, completed: 0, total: 1);

    final dio = AppDio.create(
      source: 'anime_download_video',
      options: BaseOptions(
        responseType: ResponseType.bytes,
        sendTimeout: _timeout,
        receiveTimeout: const Duration(hours: 2),
      ),
    );

    try {
      await dio.download(
        videoUrl,
        videoFile.path,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            _updateProgress(
              task: null,
              completed: 0,
              total: 1,
              estimatedTotalBytes: total,
            );
          }
        },
      );

      final finalSize = await _fileSizeOrZero(videoFile.path);
      _updateProgress(
        task: null,
        completed: 1,
        total: 1,
        estimatedTotalBytes: finalSize > 0 ? finalSize : null,
      );
    } finally {
      dio.close(force: true);
      _activeCancelToken = null;
    }
  }

  void _updateProgress({
    required _AnimeDownloadTask? task,
    required int completed,
    required int total,
    int? estimatedTotalBytes,
  }) {
    final t =
        task ??
        _tasks.firstWhere(
          (t) => t.status == DownloadTaskStatus.downloading,
          orElse: () => _placeholderTask,
        );
    if (t == _placeholderTask) return;
    t.progress = AnimeChapterDownloadProgress(
      completed: completed,
      total: total,
      estimatedTotalBytes: estimatedTotalBytes,
    );
    notifyListeners();
  }

  static final _placeholderTask = _AnimeDownloadTask(
    pathWord: '',
    chapter: const AnimeChapter(name: '', uuid: '', vCover: ''),
    line: '',
    animeName: '',
    cover: '',
  )..status = DownloadTaskStatus.downloading;

  Future<void> _downloadFile(
    Dio dio,
    String url,
    String savePath, {
    CancelToken? cancelToken,
  }) async {
    await dio.download(url, savePath, cancelToken: cancelToken);
  }

  Future<int> _fileSizeOrZero(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return 0;
      return await file.length();
    } catch (_) {
      return 0;
    }
  }

  Future<void> _persistManifest() async {
    final payload = <String, dynamic>{
      'version': _manifestVersion,
      'animes': _manifest.map(
        (pathWord, chapters) => MapEntry(
          pathWord,
          chapters.map(
            (chapterUuid, summary) => MapEntry(chapterUuid, summary.toJson()),
          ),
        ),
      ),
    };

    await _manifestFile.writeAsString(jsonEncode(payload));
  }

  Future<void> _removeDownloadedChapter(
    String pathWord,
    String chapterUuid, {
    required bool deleteFiles,
  }) async {
    final animeChapters = _manifest[pathWord];
    if (animeChapters != null) {
      animeChapters.remove(chapterUuid);
      if (animeChapters.isEmpty) {
        _manifest.remove(pathWord);
      } else {
        await _touchLocalAnime(pathWord);
      }
      await _persistManifest();
    }

    if (deleteFiles) {
      final dir = _chapterDirectory(pathWord, chapterUuid);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }
  }

  Future<void> _ensureAnimeStored(String pathWord, Anime anime) async {
    final stored = _readLocalAnimeInfo(pathWord);
    File? coverFile;
    try {
      if (stored == null ||
          stored.coverPath == null ||
          !await File(stored.coverPath!).exists()) {
        coverFile = await _downloadCoverIfNeeded(pathWord, anime.cover);
      }
    } catch (e) {
      debugPrint('Download anime cover failed: $e');
    }

    if (stored == null) {
      await _animeDirectory(pathWord).create(recursive: true);
      final info = LocalAnimeInfo(
        anime: anime,
        coverPath: coverFile?.path,
        updatedAt: DateTime.now(),
      );
      await _animeMetadataFile(
        pathWord,
      ).writeAsString(jsonEncode(info.toJson()));
      return;
    }

    final nextInfo = LocalAnimeInfo(
      anime: anime,
      coverPath: coverFile?.path ?? stored.coverPath,
      updatedAt: DateTime.now(),
    );
    await _animeMetadataFile(
      pathWord,
    ).writeAsString(jsonEncode(nextInfo.toJson()));
  }

  Future<File?> _downloadCoverIfNeeded(String pathWord, String coverUrl) async {
    if (coverUrl.isEmpty) return null;
    final animeDir = _animeDirectory(pathWord);
    await animeDir.create(recursive: true);
    final dio = AppDio.create(
      source: 'anime_download_cover',
      options: BaseOptions(
        responseType: ResponseType.bytes,
        sendTimeout: _timeout,
        receiveTimeout: _timeout,
      ),
    );
    final extension = _resolveExtension(Uri.parse(coverUrl));
    final file = File(_joinPath([animeDir.path, '$_coverFileName$extension']));
    try {
      await dio.download(coverUrl, file.path);
      return file;
    } finally {
      dio.close(force: true);
    }
  }

  Future<void> _touchLocalAnime(String pathWord) async {
    final info = _readLocalAnimeInfo(pathWord);
    if (info == null) return;
    final nextInfo = LocalAnimeInfo(
      anime: info.anime,
      coverPath: info.coverPath,
      updatedAt: DateTime.now(),
    );
    await _animeMetadataFile(
      pathWord,
    ).writeAsString(jsonEncode(nextInfo.toJson()));
  }

  Future<void> _removeLocalAnime(String pathWord) async {
    final dir = _animeDirectory(pathWord);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<void> _clearChapterDir(Directory dir) async {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  LocalAnimeInfo? _readLocalAnimeInfo(String pathWord) {
    final file = _animeMetadataFile(pathWord);
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return null;
      final info = LocalAnimeInfo.fromJson(Map<String, dynamic>.from(decoded));
      final coverPath = info.coverPath;
      if (coverPath != null &&
          coverPath.isNotEmpty &&
          !File(coverPath).existsSync()) {
        return LocalAnimeInfo(
          anime: info.anime,
          coverPath: null,
          updatedAt: info.updatedAt,
        );
      }
      return info;
    } catch (e) {
      debugPrint('Read local anime info failed: $e');
      return null;
    }
  }

  Future<void> _resetDirectory(Directory dir) async {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);
  }

  String _resolveExtension(Uri uri) {
    final lastSegment = uri.pathSegments.isNotEmpty
        ? uri.pathSegments.last
        : uri.path;
    final dotIndex = lastSegment.lastIndexOf('.');
    if (dotIndex > 0) {
      final ext = lastSegment.substring(dotIndex).toLowerCase();
      if (RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(ext)) return ext;
    }
    return '.jpg';
  }

  File get _manifestFile =>
      File(_joinPath([_rootDirectory!.path, _manifestFileName]));

  Directory _animeDirectory(String pathWord) {
    return Directory(
      _joinPath([_rootDirectory!.path, _safePathSegment(pathWord)]),
    );
  }

  File _animeMetadataFile(String pathWord) {
    return File(
      _joinPath([_animeDirectory(pathWord).path, _animeMetaFileName]),
    );
  }

  Directory _chapterDirectory(String pathWord, String chapterUuid) {
    return Directory(
      _joinPath([
        _animeDirectory(pathWord).path,
        _safePathSegment(chapterUuid),
      ]),
    );
  }

  String _joinPath(List<String> segments) => segments
      .where((segment) => segment.isNotEmpty)
      .join(Platform.pathSeparator);

  String _safePathSegment(String segment) {
    final sanitized = segment.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
    return sanitized.isEmpty ? 'unknown' : sanitized;
  }

  String _taskKey(String pathWord, String chapterUuid) =>
      '$pathWord|||$chapterUuid';
}

class DownloadedAnimeChapterSummary {
  final String chapterUuid;
  final String chapterName;
  final DateTime savedAt;

  const DownloadedAnimeChapterSummary({
    required this.chapterUuid,
    required this.chapterName,
    required this.savedAt,
  });

  factory DownloadedAnimeChapterSummary.fromJson(Map<String, dynamic> json) =>
      DownloadedAnimeChapterSummary(
        chapterUuid: json['chapter_uuid']?.toString() ?? '',
        chapterName: json['chapter_name']?.toString() ?? '',
        savedAt:
            DateTime.tryParse(json['saved_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  Map<String, dynamic> toJson() => {
    'chapter_uuid': chapterUuid,
    'chapter_name': chapterName,
    'saved_at': savedAt.toIso8601String(),
  };
}

class AnimeChapterDownloadProgress {
  final int completed;
  final int total;
  final int? estimatedTotalBytes;

  const AnimeChapterDownloadProgress({
    required this.completed,
    required this.total,
    this.estimatedTotalBytes,
  });

  double get ratio => total <= 0 ? 0 : completed / total;
}

class _HlsPlaylistFetch {
  final String url;
  final String text;
  const _HlsPlaylistFetch(this.url, this.text);
}

class _AnimeDownloadTask {
  final String pathWord;
  final AnimeChapter chapter;
  final String line;
  final String animeName;
  final String cover;
  DownloadTaskStatus status = DownloadTaskStatus.pending;
  AnimeChapterDownloadProgress? progress;
  String? errorMessage;

  _AnimeDownloadTask({
    required this.pathWord,
    required this.chapter,
    required this.line,
    required this.animeName,
    required this.cover,
  });

  String get chapterUuid => chapter.uuid;
  String get chapterName => chapter.name;
  String get taskKey => '$pathWord|||${chapter.uuid}';

  AnimeDownloadTaskInfo toInfo() => AnimeDownloadTaskInfo(
    pathWord: pathWord,
    chapterUuid: chapter.uuid,
    chapterName: chapter.name,
    animeName: animeName,
    cover: cover,
    status: status,
    progress: progress,
    errorMessage: errorMessage,
  );
}

class LocalAnimeInfo {
  final Anime anime;
  final String? coverPath;
  final DateTime updatedAt;

  const LocalAnimeInfo({
    required this.anime,
    required this.coverPath,
    required this.updatedAt,
  });

  factory LocalAnimeInfo.fallback(String pathWord, {DateTime? updatedAt}) =>
      LocalAnimeInfo(
        anime: Anime(name: pathWord, pathWord: pathWord, cover: ''),
        coverPath: null,
        updatedAt: updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      );

  factory LocalAnimeInfo.fromJson(Map<String, dynamic> json) => LocalAnimeInfo(
    anime: Anime.fromJson(Map<String, dynamic>.from(json['anime'] as Map)),
    coverPath: json['cover_path']?.toString(),
    updatedAt:
        DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );

  Map<String, dynamic> toJson() => {
    'anime': anime.toJson(),
    'cover_path': coverPath,
    'updated_at': updatedAt.toIso8601String(),
  };
}

class LocalAnimeEntry {
  final LocalAnimeInfo info;
  final int downloadedCount;

  const LocalAnimeEntry({required this.info, required this.downloadedCount});
}
