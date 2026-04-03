import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../api/api_client.dart';
import '../models/chapter.dart';
import '../models/chapter_comment.dart';
import '../models/comic.dart';

class DownloadManager extends ChangeNotifier {
  static final DownloadManager _instance = DownloadManager._();
  factory DownloadManager() => _instance;
  DownloadManager._();

  static const _manifestVersion = 1;
  static const _rootFolderName = 'comic_downloads';
  static const _manifestFileName = 'manifest.json';
  static const _chapterMetaFileName = 'chapter.json';
  static const _comicMetaFileName = 'comic.json';
  static const _coverFileName = 'cover';
  static const Duration _timeout = Duration(seconds: 20);
  static const Map<String, String> _imageExtensions = {
    'image/jpeg': '.jpg',
    'image/png': '.png',
    'image/gif': '.gif',
    'image/webp': '.webp',
    'image/bmp': '.bmp',
    'image/svg+xml': '.svg',
    'image/tiff': '.tiff',
    'image/vnd.microsoft.icon': '.ico',
  };

  final ApiClient _api = ApiClient();
  final HttpClient _httpClient = HttpClient()..connectionTimeout = _timeout;
  final Map<String, Map<String, DownloadedChapterSummary>> _manifest = {};
  final List<_DownloadTask> _queue = [];
  final Set<String> _queuedKeys = {};

  bool _initialized = false;
  bool _processing = false;
  Future<void>? _initFuture;
  Directory? _rootDirectory;
  String? _activeKey;
  ChapterDownloadProgress? _activeProgress;

  bool get isBusy => _queuedKeys.isNotEmpty;

  Future<void> init() async {
    if (_initialized) return;
    _initFuture ??= _initialize();
    await _initFuture;
  }

  Set<String> downloadedChapterIds(String pathWord) =>
      _manifest[pathWord]?.keys.toSet() ?? const <String>{};

  List<LocalComicEntry> localComics() {
    final items = _manifest.entries
        .map((entry) {
          final lastSavedAt = entry.value.values.fold<DateTime>(
            DateTime.fromMillisecondsSinceEpoch(0),
            (current, item) =>
                item.savedAt.isAfter(current) ? item.savedAt : current,
          );
          final info =
              _readLocalComicInfo(entry.key) ??
              LocalComicInfo.fallback(entry.key, updatedAt: lastSavedAt);
          return LocalComicEntry(
            info: info,
            downloadedCount: entry.value.length,
          );
        })
        .whereType<LocalComicEntry>()
        .toList();
    items.sort((a, b) => b.info.updatedAt.compareTo(a.info.updatedAt));
    return items;
  }

  LocalComicInfo? getLocalComicInfo(String pathWord) {
    final info = _readLocalComicInfo(pathWord);
    if (info != null) return info;
    final chapters = _manifest[pathWord]?.values;
    if (chapters == null || chapters.isEmpty) return null;
    final lastSavedAt = chapters.fold<DateTime>(
      DateTime.fromMillisecondsSinceEpoch(0),
      (current, item) => item.savedAt.isAfter(current) ? item.savedAt : current,
    );
    return LocalComicInfo.fallback(pathWord, updatedAt: lastSavedAt);
  }

  List<DownloadedChapterSummary> downloadedChapters(String pathWord) {
    final chapters =
        _manifest[pathWord]?.values.toList() ?? <DownloadedChapterSummary>[];
    chapters.sort((a, b) {
      final orderCompare = a.sortOrder.compareTo(b.sortOrder);
      if (orderCompare != 0) return orderCompare;
      return a.savedAt.compareTo(b.savedAt);
    });
    return chapters;
  }

  bool isDownloaded(String pathWord, String chapterUuid) =>
      _manifest[pathWord]?.containsKey(chapterUuid) == true;

  bool isQueued(String pathWord, String chapterUuid) =>
      _queuedKeys.contains(_taskKey(pathWord, chapterUuid));

  bool isDownloading(String pathWord, String chapterUuid) =>
      _activeKey == _taskKey(pathWord, chapterUuid);

  ChapterDownloadProgress? progressOf(String pathWord, String chapterUuid) =>
      isDownloading(pathWord, chapterUuid) ? _activeProgress : null;

  int pendingCountForComic(String pathWord) {
    var count = 0;
    for (final key in _queuedKeys) {
      if (_decodeTaskKey(key).pathWord == pathWord) {
        count++;
      }
    }
    return count;
  }

  Future<int> enqueueChapters({
    required String pathWord,
    required Comic comic,
    required Iterable<Chapter> chapters,
  }) async {
    await init();

    await _ensureComicStored(pathWord, comic);

    var added = 0;
    for (final chapter in chapters) {
      if (chapter.uuid.isEmpty || isDownloaded(pathWord, chapter.uuid)) {
        continue;
      }

      final key = _taskKey(pathWord, chapter.uuid);
      if (_queuedKeys.contains(key)) continue;

      _queue.add(_DownloadTask(pathWord: pathWord, chapter: chapter));
      _queuedKeys.add(key);
      added++;
    }

    if (added > 0) {
      notifyListeners();
      unawaited(_processQueue());
    }

    return added;
  }

  Future<ChapterDetail?> getDownloadedChapterDetail(
    String pathWord,
    String chapterUuid,
  ) async {
    await init();
    if (!isDownloaded(pathWord, chapterUuid)) return null;

    final metadataFile = _chapterMetadataFile(pathWord, chapterUuid);
    if (!await metadataFile.exists()) {
      await _removeDownloadedChapter(pathWord, chapterUuid, deleteFiles: true);
      return null;
    }

    try {
      final raw = await metadataFile.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        await _removeDownloadedChapter(
          pathWord,
          chapterUuid,
          deleteFiles: true,
        );
        return null;
      }

      final detail = ChapterDetail.fromDownloadedJson(
        Map<String, dynamic>.from(decoded),
      );
      final allFilesExist = await _allFilesExist(detail.contents);
      if (!allFilesExist) {
        await _removeDownloadedChapter(
          pathWord,
          chapterUuid,
          deleteFiles: true,
        );
        return null;
      }
      return detail;
    } catch (e) {
      debugPrint('Read downloaded chapter failed: $e');
      await _removeDownloadedChapter(pathWord, chapterUuid, deleteFiles: true);
      return null;
    }
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
        if (decoded is Map && decoded['comics'] is Map) {
          final comics = Map<String, dynamic>.from(decoded['comics'] as Map);
          for (final comicEntry in comics.entries) {
            final chaptersRaw = comicEntry.value;
            if (chaptersRaw is! Map) continue;

            final summaries = <String, DownloadedChapterSummary>{};
            for (final chapterEntry in chaptersRaw.entries) {
              final summaryRaw = chapterEntry.value;
              if (summaryRaw is! Map) continue;
              summaries[chapterEntry.key
                  .toString()] = DownloadedChapterSummary.fromJson(
                Map<String, dynamic>.from(summaryRaw),
              );
            }

            if (summaries.isNotEmpty) {
              _manifest[comicEntry.key] = summaries;
            }
          }
        }
      } catch (e) {
        debugPrint('Load download manifest failed: $e');
      }
    }

    _initialized = true;
  }

  Future<void> deleteChapters(
    String pathWord,
    Iterable<String> chapterUuids,
  ) async {
    await init();
    for (final chapterUuid in chapterUuids.toSet()) {
      await _removeDownloadedChapter(pathWord, chapterUuid, deleteFiles: true);
    }
    if ((_manifest[pathWord]?.isEmpty ?? true)) {
      await _removeLocalComic(pathWord);
    }
    notifyListeners();
  }

  Future<void> deleteLocalComics(Iterable<String> pathWords) async {
    await init();
    for (final pathWord in pathWords.toSet()) {
      _manifest.remove(pathWord);
      await _removeLocalComic(pathWord);
    }
    await _persistManifest();
    notifyListeners();
  }

  Future<void> _processQueue() async {
    if (_processing) return;
    _processing = true;

    try {
      while (_queue.isNotEmpty) {
        final task = _queue.removeAt(0);
        final key = _taskKey(task.pathWord, task.chapter.uuid);
        _activeKey = key;
        _activeProgress = null;
        notifyListeners();

        try {
          await _downloadChapter(task);
        } catch (e) {
          debugPrint(
            'Download chapter failed: ${task.pathWord}/${task.chapter.uuid} $e',
          );
        } finally {
          _queuedKeys.remove(key);
          _activeKey = null;
          _activeProgress = null;
          notifyListeners();
        }
      }
    } finally {
      _processing = false;
      notifyListeners();
    }
  }

  Future<void> _downloadChapter(_DownloadTask task) async {
    final chapterDir = _chapterDirectory(task.pathWord, task.chapter.uuid);

    try {
      await _resetDirectory(chapterDir);

      final detail = await _api.getChapterDetail(
        task.pathWord,
        task.chapter.uuid,
      );
      if (detail.contents.isEmpty) {
        throw const HttpException('Chapter has no images');
      }

      final comments = await _downloadComments(task.chapter.uuid);

      _activeProgress = ChapterDownloadProgress(
        completed: 0,
        total: detail.contents.length,
      );
      notifyListeners();

      final localPaths = <String>[];
      for (var i = 0; i < detail.contents.length; i++) {
        final savedFile = await _downloadImage(
          detail.contents[i],
          chapterDir,
          i + 1,
        );
        localPaths.add(savedFile.path);
        _activeProgress = ChapterDownloadProgress(
          completed: i + 1,
          total: detail.contents.length,
        );
        notifyListeners();
      }

      final localDetail = detail.copyWith(
        contents: localPaths,
        isDownloaded: true,
        comments: comments.list,
        commentTotal: comments.total,
      );
      await _chapterMetadataFile(
        task.pathWord,
        task.chapter.uuid,
      ).writeAsString(jsonEncode(localDetail.toDownloadJson()));

      _manifest.putIfAbsent(task.pathWord, () => {});
      _manifest[task.pathWord]![task.chapter.uuid] = DownloadedChapterSummary(
        chapterUuid: task.chapter.uuid,
        chapterName: task.chapter.name,
        chapterIndex: task.chapter.index,
        chapterOrder: task.chapter.ordered,
        pageCount: localPaths.length,
        savedAt: DateTime.now(),
      );
      await _persistManifest();
      await _touchLocalComic(task.pathWord);
    } catch (_) {
      await _removeDownloadedChapter(
        task.pathWord,
        task.chapter.uuid,
        deleteFiles: true,
      );
      rethrow;
    }
  }

  Future<({List<ChapterComment> list, int total})> _downloadComments(
    String chapterUuid,
  ) async {
    final comments = <ChapterComment>[];
    var offset = 0;
    var total = 0;

    while (true) {
      final data = await _api.getChapterComments(
        chapterUuid,
        limit: 100,
        offset: offset,
      );
      comments.addAll(data.list);
      total = data.total;
      offset = comments.length;
      if (data.list.isEmpty || offset >= total) {
        break;
      }
    }

    return (list: comments, total: total);
  }

  Future<File> _downloadImage(
    String imageUrl,
    Directory chapterDir,
    int index,
  ) async {
    final uri = Uri.parse(imageUrl);
    final request = await _httpClient.getUrl(uri).timeout(_timeout);
    final response = await request.close().timeout(_timeout);

    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Image download failed (${response.statusCode})',
        uri: uri,
      );
    }

    final extension = _resolveImageExtension(uri, response);
    final file = File(
      _joinPath([
        chapterDir.path,
        '${index.toString().padLeft(3, '0')}$extension',
      ]),
    );
    final sink = file.openWrite();
    try {
      await sink.addStream(response);
    } finally {
      await sink.close();
    }
    return file;
  }

  Future<void> _persistManifest() async {
    final payload = <String, dynamic>{
      'version': _manifestVersion,
      'comics': _manifest.map(
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
    final comicChapters = _manifest[pathWord];
    if (comicChapters != null) {
      comicChapters.remove(chapterUuid);
      if (comicChapters.isEmpty) {
        _manifest.remove(pathWord);
      } else {
        await _touchLocalComic(pathWord);
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

  Future<void> _ensureComicStored(String pathWord, Comic comic) async {
    final stored = _readLocalComicInfo(pathWord);
    File? coverFile;
    try {
      if (stored == null ||
          stored.coverPath == null ||
          !await File(stored.coverPath!).exists()) {
        coverFile = await _downloadCoverIfNeeded(pathWord, comic.cover);
      }
    } catch (e) {
      debugPrint('Download comic cover failed: $e');
    }

    if (stored == null) {
      await _comicDirectory(pathWord).create(recursive: true);
      final info = LocalComicInfo(
        comic: comic.copyWith(cover: coverFile?.path ?? comic.cover),
        coverPath: coverFile?.path,
        updatedAt: DateTime.now(),
      );
      await _comicMetadataFile(
        pathWord,
      ).writeAsString(jsonEncode(info.toJson()));
      return;
    }

    final nextInfo = LocalComicInfo(
      comic: comic.copyWith(
        cover: coverFile?.path ?? stored.coverPath ?? stored.comic.cover,
      ),
      coverPath: coverFile?.path ?? stored.coverPath,
      updatedAt: DateTime.now(),
    );
    await _comicMetadataFile(
      pathWord,
    ).writeAsString(jsonEncode(nextInfo.toJson()));
  }

  Future<File?> _downloadCoverIfNeeded(String pathWord, String coverUrl) async {
    if (coverUrl.isEmpty) return null;
    final comicDir = _comicDirectory(pathWord);
    await comicDir.create(recursive: true);
    final uri = Uri.parse(coverUrl);
    final request = await _httpClient.getUrl(uri).timeout(_timeout);
    final response = await request.close().timeout(_timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Cover download failed (${response.statusCode})',
        uri: uri,
      );
    }
    final extension = _resolveImageExtension(uri, response);
    final file = File(_joinPath([comicDir.path, '$_coverFileName$extension']));
    final sink = file.openWrite();
    try {
      await sink.addStream(response);
    } finally {
      await sink.close();
    }
    return file;
  }

  Future<void> _touchLocalComic(String pathWord) async {
    final info = _readLocalComicInfo(pathWord);
    if (info == null) return;
    final nextInfo = LocalComicInfo(
      comic: info.comic,
      coverPath: info.coverPath,
      updatedAt: DateTime.now(),
    );
    await _comicMetadataFile(
      pathWord,
    ).writeAsString(jsonEncode(nextInfo.toJson()));
  }

  Future<void> _removeLocalComic(String pathWord) async {
    final dir = _comicDirectory(pathWord);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  LocalComicInfo? _readLocalComicInfo(String pathWord) {
    final file = _comicMetadataFile(pathWord);
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return null;
      final info = LocalComicInfo.fromJson(Map<String, dynamic>.from(decoded));
      final coverPath = info.coverPath;
      if (coverPath != null &&
          coverPath.isNotEmpty &&
          !File(coverPath).existsSync()) {
        return LocalComicInfo(
          comic: info.comic,
          coverPath: null,
          updatedAt: info.updatedAt,
        );
      }
      return info;
    } catch (e) {
      debugPrint('Read local comic info failed: $e');
      return null;
    }
  }

  Future<void> _resetDirectory(Directory dir) async {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);
  }

  Future<bool> _allFilesExist(List<String> paths) async {
    for (final path in paths) {
      if (!await File(path).exists()) {
        return false;
      }
    }
    return true;
  }

  File get _manifestFile =>
      File(_joinPath([_rootDirectory!.path, _manifestFileName]));

  Directory _comicDirectory(String pathWord) {
    return Directory(
      _joinPath([_rootDirectory!.path, _safePathSegment(pathWord)]),
    );
  }

  File _comicMetadataFile(String pathWord) {
    return File(
      _joinPath([_comicDirectory(pathWord).path, _comicMetaFileName]),
    );
  }

  Directory _chapterDirectory(String pathWord, String chapterUuid) {
    return Directory(
      _joinPath([
        _comicDirectory(pathWord).path,
        _safePathSegment(chapterUuid),
      ]),
    );
  }

  File _chapterMetadataFile(String pathWord, String chapterUuid) {
    return File(
      _joinPath([
        _chapterDirectory(pathWord, chapterUuid).path,
        _chapterMetaFileName,
      ]),
    );
  }

  String _resolveImageExtension(Uri uri, HttpClientResponse response) {
    final mimeType = response.headers.contentType?.mimeType.toLowerCase();
    if (mimeType != null && _imageExtensions.containsKey(mimeType)) {
      return _imageExtensions[mimeType]!;
    }

    final lastSegment = uri.pathSegments.isNotEmpty
        ? uri.pathSegments.last
        : uri.path;
    final dotIndex = lastSegment.lastIndexOf('.');
    if (dotIndex > 0) {
      final ext = lastSegment.substring(dotIndex).toLowerCase();
      if (RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(ext)) {
        return ext;
      }
    }

    return '.jpg';
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

  ({String pathWord, String chapterUuid}) _decodeTaskKey(String key) {
    final parts = key.split('|||');
    return (
      pathWord: parts.isNotEmpty ? parts.first : '',
      chapterUuid: parts.length > 1 ? parts.last : '',
    );
  }
}

class DownloadedChapterSummary {
  final String chapterUuid;
  final String chapterName;
  final int chapterIndex;
  final int chapterOrder;
  final int pageCount;
  final DateTime savedAt;

  const DownloadedChapterSummary({
    required this.chapterUuid,
    required this.chapterName,
    this.chapterIndex = 0,
    this.chapterOrder = 0,
    required this.pageCount,
    required this.savedAt,
  });

  int get sortOrder => chapterOrder > 0 ? chapterOrder : chapterIndex;

  factory DownloadedChapterSummary.fromJson(Map<String, dynamic> json) =>
      DownloadedChapterSummary(
        chapterUuid: json['chapter_uuid']?.toString() ?? '',
        chapterName: json['chapter_name']?.toString() ?? '',
        chapterIndex: json['chapter_index'] is int
            ? json['chapter_index'] as int
            : int.tryParse(json['chapter_index']?.toString() ?? '') ?? 0,
        chapterOrder: json['chapter_order'] is int
            ? json['chapter_order'] as int
            : int.tryParse(json['chapter_order']?.toString() ?? '') ?? 0,
        pageCount: json['page_count'] is int
            ? json['page_count'] as int
            : int.tryParse(json['page_count']?.toString() ?? '') ?? 0,
        savedAt:
            DateTime.tryParse(json['saved_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  Map<String, dynamic> toJson() => {
    'chapter_uuid': chapterUuid,
    'chapter_name': chapterName,
    'chapter_index': chapterIndex,
    'chapter_order': chapterOrder,
    'page_count': pageCount,
    'saved_at': savedAt.toIso8601String(),
  };
}

class ChapterDownloadProgress {
  final int completed;
  final int total;

  const ChapterDownloadProgress({required this.completed, required this.total});

  double get ratio => total <= 0 ? 0 : completed / total;
}

class _DownloadTask {
  final String pathWord;
  final Chapter chapter;

  const _DownloadTask({required this.pathWord, required this.chapter});
}

class LocalComicInfo {
  final Comic comic;
  final String? coverPath;
  final DateTime updatedAt;

  const LocalComicInfo({
    required this.comic,
    required this.coverPath,
    required this.updatedAt,
  });

  factory LocalComicInfo.fallback(String pathWord, {DateTime? updatedAt}) =>
      LocalComicInfo(
        comic: Comic(name: pathWord, pathWord: pathWord, cover: ''),
        coverPath: null,
        updatedAt: updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      );

  factory LocalComicInfo.fromJson(Map<String, dynamic> json) => LocalComicInfo(
    comic: Comic.fromJson(Map<String, dynamic>.from(json['comic'] as Map)),
    coverPath: json['cover_path']?.toString(),
    updatedAt:
        DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );

  Map<String, dynamic> toJson() => {
    'comic': comic.toJson(),
    'cover_path': coverPath,
    'updated_at': updatedAt.toIso8601String(),
  };
}

class LocalComicEntry {
  final LocalComicInfo info;
  final int downloadedCount;

  const LocalComicEntry({required this.info, required this.downloadedCount});
}
