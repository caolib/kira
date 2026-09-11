import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../models/chapter.dart';
import '../models/chapter_comment.dart';
import '../models/comic.dart';
import 'app_logger.dart';
part 'download_manager_parts/comic_store.dart';
part 'download_manager_parts/content_download.dart';
part 'download_manager_parts/delete_migrate.dart';
part 'download_manager_parts/queries.dart';


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

  /// 单张图片下载失败时的最大重试次数（不含首次）。
  static const int _imageMaxRetries = 2;

  /// 并发下载数量的持久化键。
  static const _keyImageConcurrency = 'download_image_concurrency';

  /// 并发下载数量默认值。
  static const int _defaultImageConcurrency = 5;

  /// 并发下载数量允许范围。
  static const int _minImageConcurrency = 1;
  static const int _maxImageConcurrency = 10;

  /// 是否下载章节评论的持久化键。
  static const _keyDownloadComments = 'download_chapter_comments';

  /// 自定义下载根目录的持久化键；缺省/置空表示使用应用内部默认目录。
  static const _keySaveDirectory = 'download_save_directory';

  int _imageDownloadConcurrency = _defaultImageConcurrency;
  bool _downloadCommentsEnabled = true;
  String? _customSaveDirectory;
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

  /// extension part 文件里的成员不是 DownloadManager 自身的成员，不能直接调用受
  /// 保护的 [notifyListeners]，统一经由这个转发方法。
  void _notifyListeners() => notifyListeners();

  bool get isBusy => _queuedKeys.isNotEmpty;

  /// 当前下载队列的任务信息列表，可供 UI 展示。
  List<ComicDownloadTaskInfo> get tasks {
    final result = <ComicDownloadTaskInfo>[];
    for (final task in _queue) {
      final key = _taskKey(task.pathWord, task.chapter.uuid);
      final isActive = _activeKey == key;
      final info = getLocalComicInfo(task.pathWord);
      result.add(
        ComicDownloadTaskInfo(
          pathWord: task.pathWord,
          chapterUuid: task.chapter.uuid,
          chapterName: task.chapter.name,
          comicName: info?.comic.name ?? task.pathWord,
          cover: info?.comic.cover,
          status: isActive
              ? ComicDownloadTaskStatus.downloading
              : ComicDownloadTaskStatus.pending,
          progress: isActive ? _activeProgress : null,
        ),
      );
    }
    return result;
  }

  Future<void> init() async {
    if (_initialized) return;
    _initFuture ??= _initialize();
    await _initFuture;
  }

  /// 单章图片并发下载数量，范围 [_minImageConcurrency]~[_maxImageConcurrency]。
  int get imageDownloadConcurrency => _imageDownloadConcurrency;

  /// 加载持久化的并发下载数量（若未初始化则从 SharedPreferences 读取）。
  Future<void> loadImageDownloadConcurrency() async {
    final prefs = await SharedPreferences.getInstance();
    _imageDownloadConcurrency = _clampConcurrency(
      prefs.getInt(_keyImageConcurrency),
    );
  }

  /// 是否在下载章节时一并下载评论，默认开启。
  bool get downloadCommentsEnabled => _downloadCommentsEnabled;

  /// 设置并持久化是否下载章节评论。
  Future<void> setDownloadCommentsEnabled(bool value) async {
    if (_downloadCommentsEnabled == value) return;
    _downloadCommentsEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDownloadComments, value);
  }

  /// 设置并持久化并发下载数量，返回归一化后的实际值。
  Future<int> setImageDownloadConcurrency(int value) async {
    final clamped = _clampConcurrency(value);
    if (_imageDownloadConcurrency == clamped) return clamped;
    _imageDownloadConcurrency = clamped;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyImageConcurrency, clamped);
    return clamped;
  }

  static int _clampConcurrency(int? value) {
    if (value == null || value < _minImageConcurrency) {
      return _defaultImageConcurrency;
    }
    if (value > _maxImageConcurrency) return _maxImageConcurrency;
    return value;
  }

  final Map<String, Future<void>> _comicPrepares = {};

  void _scheduleComicPrepare(String pathWord, Comic comic) {
    final previous = _comicPrepares[pathWord] ?? Future.value();
    final task = previous.whenComplete(() {
      return _ensureComicStored(pathWord, comic);
    });
    _comicPrepares[pathWord] = task;
    unawaited(
      task.whenComplete(() {
        if (identical(_comicPrepares[pathWord], task)) {
          _comicPrepares.remove(pathWord);
        }
      }),
    );
  }

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _customSaveDirectory = normalizeDirectoryPath(
      prefs.getString(_keySaveDirectory),
    );
    _rootDirectory = await resolveRootDirectory(
      customPath: _customSaveDirectory,
      defaultParentPath: (await getApplicationDocumentsDirectory()).path,
    );
    await _rootDirectory!.create(recursive: true);

    await loadImageDownloadConcurrency();
    final prefsForComments = await SharedPreferences.getInstance();
    _downloadCommentsEnabled =
        prefsForComments.getBool(_keyDownloadComments) ?? true;

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

  Future<void> _processQueue() async {
    if (_processing) return;
    _processing = true;

    try {
      while (_queue.isNotEmpty) {
        // 取队首任务但暂不移除，使其在下载期间仍显示在队列中。
        final task = _queue.first;
        final key = _taskKey(task.pathWord, task.chapter.uuid);
        _activeKey = key;
        _activeProgress = null;
        notifyListeners();

        try {
          await _downloadChapter(task, isRetry: task.isRetry);
        } catch (e) {
          debugPrint(
            'Download chapter failed: ${task.pathWord}/${task.chapter.uuid} $e',
          );
        } finally {
          _queue.remove(task);
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

  Future<void> _downloadChapter(
    _DownloadTask task, {
    bool isRetry = false,
  }) async {
    final chapterDir = _chapterDirectory(task.pathWord, task.chapter.uuid);

    try {
      // 重试时保留已下载的文件，仅补全失败页；全新下载则清空目录。
      if (!isRetry) {
        await _resetDirectory(chapterDir);
      }

      final detail = await _api.manga.getChapterDetail(
        task.pathWord,
        task.chapter.uuid,
      );
      if (detail.contents.isEmpty) {
        throw const HttpException('Chapter has no images');
      }

      final total = detail.contents.length;

      // 复用已下载页的本地路径，避免重复下载成功页（重试或崩溃恢复）。
      final existing = await _loadExistingPaths(
        task.pathWord,
        task.chapter.uuid,
        total,
      );
      final completedStart = existing.where((e) => e != null).length;

      // 重试时复用已保存的评论；全新下载且开关开启时才拉取评论。
      // 评论与图片互不依赖，与图片下载并行执行，避免拖慢进度显示。
      final commentsFuture = (isRetry || !_downloadCommentsEnabled)
          ? _loadExistingComments(task.pathWord, task.chapter.uuid)
          : _downloadComments(task.chapter.uuid);

      _activeProgress = ChapterDownloadProgress(
        completed: completedStart,
        total: total,
      );
      notifyListeners();

      final result = await _downloadImages(
        detail.contents,
        chapterDir,
        existing: existing,
      );
      final comments = await commentsFuture;

      // 处理结果：失败页记为空串，收集失败索引。
      final failedIndices = <int>[];
      final completedPaths = List<String>.filled(total, '');
      for (var i = 0; i < total; i++) {
        if (result[i] == null) {
          failedIndices.add(i);
        } else {
          completedPaths[i] = result[i]!;
        }
      }

      final localDetail = detail.copyWith(
        contents: completedPaths,
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
        chapterGroup: task.group,
        chapterIndex: task.chapter.index,
        chapterOrder: task.chapter.ordered,
        pageCount: completedPaths.length,
        savedAt: DateTime.now(),
        failedIndices: failedIndices,
      );
      await _persistManifest();
      await _touchLocalComic(task.pathWord);
      // 注意：部分图片失败不抛错，章节以 partial 状态持久化，用户可重试补全。
    } on Exception catch (_) {
      // 仅整章级失败（如 API 错误）才清理。部分页失败已写入 manifest，保留。
      if (!isRetry) {
        await _removeDownloadedChapter(
          task.pathWord,
          task.chapter.uuid,
          deleteFiles: true,
        );
      }
      rethrow;
    }
  }

  /// 从已存在的 chapter.json 读取各页本地路径，未下载的页返回 null。
  Future<List<String?>> _loadExistingPaths(
    String pathWord,
    String chapterUuid,
    int total,
  ) async {
    final file = _chapterMetadataFile(pathWord, chapterUuid);
    if (!await file.exists()) {
      return List<String?>.filled(total, null);
    }
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return List<String?>.filled(total, null);
      final contents = (decoded['contents'] as List?)?.toList() ?? const [];
      final result = List<String?>.filled(total, null);
      for (var i = 0; i < total && i < contents.length; i++) {
        final p = contents[i]?.toString() ?? '';
        if (p.isNotEmpty && await File(p).exists()) {
          result[i] = p;
        }
      }
      return result;
    } catch (e, st) {
      unawaited(AppLogger.instance.recordWarning(e, stackTrace: st));
      return List<String?>.filled(total, null);
    }
  }

  static String _joinPath(List<String> segments) => segments
      .where((segment) => segment.isNotEmpty)
      .join(Platform.pathSeparator);

  static String _safePathSegment(String segment) {
    final sanitized = segment.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
    return sanitized.isEmpty ? 'unknown' : sanitized;
  }

  /// 规范化目录路径：去首尾空白与末尾分隔符；空串返回 null。
  static String? normalizeDirectoryPath(String? path) {
    if (path == null) return null;
    final p = _stripTrailingSeparators(path);
    return p.isEmpty ? null : p;
  }

  static String _stripTrailingSeparators(String path) {
    var p = path.trim();
    while (p.length > 1 && (p.endsWith('/') || p.endsWith('\\'))) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  /// 可写探测：在 [dir] 内创建并删除一个临时探针文件。
  static Future<bool> isDirectoryWritable(Directory dir) async {
    final probe = File(_joinPath([dir.path, '.kira_write_probe']));
    try {
      await probe.writeAsString('');
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        if (await probe.exists()) await probe.delete();
      } catch (e, st) {
        unawaited(AppLogger.instance.recordWarning(e, stackTrace: st));
      }
    }
  }

  /// 解析下载根目录：自定义目录存在/可创建且可写时使用之，否则回退
  /// `defaultParentPath` 下的默认目录并记录警告。
  static Future<Directory> resolveRootDirectory({
    required String? customPath,
    required String defaultParentPath,
  }) async {
    final defaultDir = Directory(
      _joinPath([defaultParentPath, _rootFolderName]),
    );
    if (customPath == null || customPath.isEmpty) return defaultDir;

    final dir = Directory(customPath);
    try {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      if (await isDirectoryWritable(dir)) return dir;
      unawaited(
        AppLogger.instance.recordWarning(
          'Custom download directory not writable: $customPath',
        ),
      );
    } catch (e, st) {
      unawaited(
        AppLogger.instance.recordWarning(
          'Custom download directory unavailable: $customPath ($e)',
          stackTrace: st,
        ),
      );
    }
    return defaultDir;
  }

  /// 将 [from] 目录整体搬到 [to]。同卷直接 rename；跨卷退化为复制+删除。
  /// [from] 不存在时静默返回（manifest 记录可能已被外部清理）。
  static Future<void> moveDirectory(Directory from, Directory to) async {
    if (!await from.exists()) return;
    if (await to.exists()) {
      await to.delete(recursive: true);
    }
    try {
      await from.rename(to.path);
    } on FileSystemException {
      await to.create(recursive: true);
      try {
        await _copyDirectoryContents(from, to);
      } catch (e) {
        // 清理复制到一半的目标目录，避免残留半成品。
        try {
          if (await to.exists()) await to.delete(recursive: true);
        } catch (cleanupError, cleanupSt) {
          unawaited(
            AppLogger.instance.recordWarning(
              cleanupError,
              stackTrace: cleanupSt,
            ),
          );
        }
        rethrow;
      }
      await from.delete(recursive: true);
    }
  }

  static Future<void> _copyDirectoryContents(
    Directory from,
    Directory to,
  ) async {
    await for (final entity in from.list()) {
      final name = entity.path.split(Platform.pathSeparator).last;
      final targetPath = _joinPath([to.path, name]);
      if (entity is Directory) {
        final target = Directory(targetPath);
        await target.create(recursive: true);
        await _copyDirectoryContents(entity, target);
      } else if (entity is File) {
        await entity.copy(targetPath);
      }
    }
  }

  /// 重写 [comicDir] 内持久化元数据中的绝对路径前缀：chapter.json 的
  /// `contents` 与 comic.json 的 `cover_path`/`comic.cover`，从 [fromRoot]
  /// 改写到 [toRoot]。仅处理确实位于旧根下的路径；comicDir 不存在时跳过。
  static Future<void> rewriteStoredPaths(
    Directory comicDir, {
    required String fromRoot,
    required String toRoot,
  }) async {
    if (!await comicDir.exists()) return;

    final comicFile = File(_joinPath([comicDir.path, _comicMetaFileName]));
    if (await comicFile.exists()) {
      try {
        final decoded = jsonDecode(await comicFile.readAsString());
        if (decoded is Map) {
          final map = Map<String, dynamic>.from(decoded);
          var changed = false;

          final coverPath = map['cover_path'];
          if (coverPath is String) {
            final rewritten = rewritePathPrefix(coverPath, fromRoot, toRoot);
            if (rewritten != null) {
              map['cover_path'] = rewritten;
              changed = true;
            }
          }
          final comic = map['comic'];
          if (comic is Map) {
            final comicMap = Map<String, dynamic>.from(comic);
            final cover = comicMap['cover'];
            if (cover is String) {
              final rewritten = rewritePathPrefix(cover, fromRoot, toRoot);
              if (rewritten != null) {
                comicMap['cover'] = rewritten;
                changed = true;
              }
            }
            map['comic'] = comicMap;
          }
          if (changed) {
            await comicFile.writeAsString(jsonEncode(map));
          }
        }
      } catch (e, st) {
        unawaited(AppLogger.instance.recordWarning(e, stackTrace: st));
      }
    }

    await for (final entity in comicDir.list()) {
      if (entity is! Directory) continue;
      final chapterFile = File(_joinPath([entity.path, _chapterMetaFileName]));
      if (!await chapterFile.exists()) continue;
      try {
        final decoded = jsonDecode(await chapterFile.readAsString());
        if (decoded is! Map) continue;
        final contents = decoded['contents'];
        if (contents is! List) continue;
        var changed = false;
        final rewrittenContents = <String>[];
        for (final item in contents) {
          var value = item?.toString() ?? '';
          final rewritten = rewritePathPrefix(value, fromRoot, toRoot);
          if (rewritten != null) {
            value = rewritten;
            changed = true;
          }
          rewrittenContents.add(value);
        }
        if (changed) {
          final map = Map<String, dynamic>.from(decoded);
          map['contents'] = rewrittenContents;
          await chapterFile.writeAsString(jsonEncode(map));
        }
      } catch (e, st) {
        unawaited(AppLogger.instance.recordWarning(e, stackTrace: st));
      }
    }
  }

  /// 若 [path] 位于 [fromRoot] 之下，把前缀替换为 [toRoot] 后返回新路径；
  /// 否则返回 null。路径不存在于旧根下（如空串、外部路径）时不改写。
  static String? rewritePathPrefix(
    String path,
    String fromRoot,
    String toRoot,
  ) {
    if (path.isEmpty || fromRoot.isEmpty || toRoot.isEmpty) return null;
    final root = _stripTrailingSeparators(fromRoot);
    final p = _stripTrailingSeparators(path);
    if (p == root) return null;
    if (!p.startsWith('$root/') && !p.startsWith('$root\\')) return null;
    // 历史数据可能混用两种分隔符，统一改为当前平台的分隔符。
    final rest = p
        .substring(root.length + 1)
        .replaceAll('/', Platform.pathSeparator)
        .replaceAll('\\', Platform.pathSeparator);
    return _joinPath([_stripTrailingSeparators(toRoot), rest]);
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
  final String chapterGroup;
  final int chapterIndex;
  final int chapterOrder;
  final int pageCount;
  final DateTime savedAt;
  // 0-based 页索引：下载失败的页。空表示完整下载。
  final List<int> failedIndices;

  const DownloadedChapterSummary({
    required this.chapterUuid,
    required this.chapterName,
    this.chapterGroup = 'default',
    this.chapterIndex = 0,
    this.chapterOrder = 0,
    required this.pageCount,
    required this.savedAt,
    this.failedIndices = const [],
  });

  int get sortOrder => chapterOrder > 0 ? chapterOrder : chapterIndex;

  /// 是否为部分失败（仍有未下载页）。
  bool get isPartial => failedIndices.isNotEmpty;

  factory DownloadedChapterSummary.fromJson(Map<String, dynamic> json) =>
      DownloadedChapterSummary(
        chapterUuid: json['chapter_uuid']?.toString() ?? '',
        chapterName: json['chapter_name']?.toString() ?? '',
        chapterGroup: json['chapter_group']?.toString().trim().isEmpty ?? true
            ? 'default'
            : json['chapter_group'].toString(),
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
        failedIndices:
            (json['failed_indices'] as List?)
                ?.map((e) => int.tryParse(e.toString()) ?? 0)
                .where((v) => v >= 0)
                .toList() ??
            const [],
      );

  Map<String, dynamic> toJson() => {
    'chapter_uuid': chapterUuid,
    'chapter_name': chapterName,
    'chapter_group': chapterGroup,
    'chapter_index': chapterIndex,
    'chapter_order': chapterOrder,
    'page_count': pageCount,
    'saved_at': savedAt.toIso8601String(),
    'failed_indices': failedIndices,
  };
}

class ChapterDownloadProgress {
  final int completed;
  final int total;
  final int failed;

  const ChapterDownloadProgress({
    required this.completed,
    required this.total,
    this.failed = 0,
  });

  double get ratio => total <= 0 ? 0 : completed / total;
}

/// 下载目录迁移进度：已迁移 [current] / 共 [total] 部漫画。
class DownloadMigrationProgress {
  final int current;
  final int total;

  /// 刚完成迁移的漫画 pathWord。
  final String pathWord;

  const DownloadMigrationProgress({
    required this.current,
    required this.total,
    required this.pathWord,
  });

  double get ratio => total <= 0 ? 0 : current / total;
}

class _DownloadTask {
  final String pathWord;
  final String group;
  final Chapter chapter;
  // true 表示这是对已有部分下载的"补全重试"：不清空目录、不重复下载成功页。
  final bool isRetry;

  const _DownloadTask({
    required this.pathWord,
    required this.group,
    required this.chapter,
    this.isRetry = false,
  });
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

/// 漫画下载队列任务状态
enum ComicDownloadTaskStatus {
  /// 下载中
  downloading,

  /// 等待中
  pending,
}

/// 漫画下载队列中的任务信息，供 UI 展示。
class ComicDownloadTaskInfo {
  final String pathWord;
  final String chapterUuid;
  final String chapterName;
  final String comicName;
  final String? cover;
  final ComicDownloadTaskStatus status;
  final ChapterDownloadProgress? progress;

  const ComicDownloadTaskInfo({
    required this.pathWord,
    required this.chapterUuid,
    required this.chapterName,
    required this.comicName,
    this.cover,
    required this.status,
    this.progress,
  });
}
