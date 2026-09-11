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

  DownloadManager._({
    Future<Directory> Function()? rootDirectoryProvider,
    Future<ChapterDetail> Function(String pathWord, String chapterUuid)?
    chapterDetailLoader,
    Future<({List<ChapterComment> list, int total})> Function(
      String chapterUuid,
    )?
    chapterCommentsLoader,
    Future<File> Function(String imageUrl, Directory chapterDir, int index)?
    imageDownloader,
  }) : _rootDirectoryProvider = rootDirectoryProvider,
       _chapterDetailLoader = chapterDetailLoader,
       _chapterCommentsLoader = chapterCommentsLoader,
       _imageDownloader = imageDownloader,
       _api = ApiClient(),
       _httpClient = HttpClient()..connectionTimeout = _timeout;

  /// Creates an isolated manager with injectable I/O for state-machine tests.
  @visibleForTesting
  DownloadManager.forTesting({
    required Directory rootDirectory,
    Future<ChapterDetail> Function(String pathWord, String chapterUuid)?
    chapterDetailLoader,
    Future<({List<ChapterComment> list, int total})> Function(
      String chapterUuid,
    )?
    chapterCommentsLoader,
    Future<File> Function(String imageUrl, Directory chapterDir, int index)?
    imageDownloader,
  }) : this._(
         rootDirectoryProvider: () async => rootDirectory,
         chapterDetailLoader: chapterDetailLoader,
         chapterCommentsLoader: chapterCommentsLoader,
         imageDownloader: imageDownloader,
       );

  static const _manifestVersion = 1;
  static const _rootFolderName = 'comic_downloads';
  static const _manifestFileName = 'manifest.json';
  static const _chapterMetaFileName = 'chapter.json';
  static const _comicMetaFileName = 'comic.json';
  static const _coverFileName = 'cover';
  static const Duration _timeout = Duration(seconds: 20);

  /// 单张图片下载失败时的最大重试次数（不含首次）。
  static const int _imageMaxRetries = 2;

  /// 单图重试的基础退避时长（第 1/2 次重试前）；遇 429 限流加倍。
  static const List<Duration> _imageRetryBaseDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
  ];

  /// 整章下载失败的最大尝试次数（含首次，超出后放弃并记入批次失败）。
  static const int _chapterMaxAttempts = 4;

  /// 整章自动重试的退避时长：第 1/2/3 次重试前各等一档。
  static const List<Duration> _chapterRetryDelays = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
  ];

  /// 并发下载数量的持久化键。
  static const _keyImageConcurrency = 'download_image_concurrency';

  /// 并发下载数量默认值。
  static const int _defaultImageConcurrency = 8;

  /// 并发下载数量允许范围。
  static const int _minImageConcurrency = 1;
  static const int _maxImageConcurrency = 32;

  /// 在飞章节数上限。页任务按章节顺序进入全局队列：前面的章节优先
  /// 占用 worker，有剩余立刻派发给后面的章节，不闲置并发额度；
  /// 多持有 1 个在飞章节用于预取详情，消除章节间的请求空窗。
  static const int _maxChaptersInFlight = 2;

  /// 是否下载章节评论的持久化键。
  static const _keyDownloadComments = 'download_chapter_comments';

  /// 自定义下载根目录的持久化键；缺省/置空表示使用应用内部默认目录。
  static const _keySaveDirectory = 'download_save_directory';

  /// 下载队列的持久化键：重启后恢复队列继续下载（含暂停状态与批次失败）。
  static const _keyQueueState = 'download_queue_state_v1';

  /// 队列持久化载荷结构版本，结构变更时递增使旧数据失效。
  static const _queueStateVersion = 1;

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

  final ApiClient _api;
  final HttpClient _httpClient;
  final Future<Directory> Function()? _rootDirectoryProvider;
  final Future<ChapterDetail> Function(String pathWord, String chapterUuid)?
  _chapterDetailLoader;
  final Future<({List<ChapterComment> list, int total})> Function(
    String chapterUuid,
  )?
  _chapterCommentsLoader;
  final Future<File> Function(String imageUrl, Directory chapterDir, int index)?
  _imageDownloader;
  final Map<String, Map<String, DownloadedChapterSummary>> _manifest = {};
  final List<_DownloadTask> _queue = [];
  final Set<String> _queuedKeys = {};

  bool _initialized = false;
  bool _processing = false;
  Future<void>? _initFuture;
  Directory? _rootDirectory;

  // 正在下载（详情拉取中或图片在飞）的章节任务 key。
  final Set<String> _activeKeys = {};

  // 正在下载章节的实时进度，key 同 [_activeKeys]。
  final Map<String, ChapterDownloadProgress> _activeProgress = {};

  // 在飞章节运行态，最多 [_maxChaptersInFlight] 个。
  final Map<String, _ChapterRun> _activeRuns = {};

  // 用户单独暂停的章节任务 key。
  final Set<String> _pausedTaskKeys = {};

  // 用户请求取消（删除）的章节任务 key；在飞任务在下个阶段边界退出。
  final Set<String> _cancelledTaskKeys = {};

  // 删除尚未完成时禁止同 key 重新入队，避免旧删除流程误删新任务文件。
  final Set<String> _deletingTaskKeys = {};

  // 全局暂停：不领取新任务，在飞的图片请求自然完成后停住。
  bool _paused = false;

  // 全局图片任务队列，跨章节共享 worker 池，章节尾部不再闲置并发额度。
  final List<_ImageJob> _imageJobs = [];
  Completer<void>? _jobWake;

  // 章节调度器的等待点集合；任何章节完成/失败/新任务入队都会唤醒。
  final List<Completer<void>> _schedulerWaits = [];
  bool _schedulerDone = false;

  // 持久化写入尾链，保证旧快照不会在新快照之后完成并覆盖新状态。
  Future<void> _queueStateWriteTail = Future.value();
  Future<void> _manifestWriteTail = Future.value();
  Future<void> _deleteWriteTail = Future.value();
  final Map<String, Future<void>> _comicMetadataWriteTails = {};
  final Map<String, Future<void>> _chapterMetadataWriteTails = {};

  int _batchSucceeded = 0;

  /// 当前批次的整章失败累积，队列排空时写入 [_batchFailures]。
  List<_BatchChapterFailure> _batchRunFailures = [];

  /// 当前批次的整章失败记录，保留原任务供"重试失败章节"重新入队。
  List<_BatchChapterFailure> _batchFailures = const [];

  /// 最近一次队列清空后的批次汇总；无失败章节或已被清除时为 null。
  DownloadBatchSummary? _lastBatchSummary;

  /// 最近一次批量下载的失败汇总；无失败或已被清除/替换时为 null。
  DownloadBatchSummary? get lastBatchSummary => _lastBatchSummary;

  /// 清除批次失败汇总（用户关闭提示条后调用）。
  void clearBatchSummary() {
    if (_lastBatchSummary == null &&
        _batchFailures.isEmpty &&
        _batchRunFailures.isEmpty) {
      return;
    }
    _batchFailures = const [];
    _batchRunFailures = [];
    _lastBatchSummary = null;
    notifyListeners();
    unawaited(_persistQueueState());
  }

  /// 是否已全局暂停下载。暂停状态随队列快照保存，重启后可继续。
  bool get paused => _paused;

  /// 暂停全部下载：在飞的图片请求自然完成后停止领取新任务。
  void pauseDownloads() {
    if (_paused) return;
    _paused = true;
    _signalScheduler();
    notifyListeners();
    unawaited(_persistQueueState());
  }

  /// 恢复全部下载。
  void resumeDownloads() {
    if (!_paused) return;
    _paused = false;
    _signalScheduler();
    _wakeImageWorkers();
    notifyListeners();
    unawaited(_persistQueueState());
    _ensureProcessing();
  }

  /// 单个章节是否被暂停。
  bool isChapterPaused(String pathWord, String chapterUuid) =>
      _pausedTaskKeys.contains(_taskKey(pathWord, chapterUuid));

  /// 暂停单个章节：在飞的图片请求自然完成后停止领取新任务。
  void pauseChapter(String pathWord, String chapterUuid) {
    if (!_pausedTaskKeys.add(_taskKey(pathWord, chapterUuid))) return;
    notifyListeners();
    unawaited(_persistQueueState());
  }

  /// 恢复单个章节。
  void resumeChapter(String pathWord, String chapterUuid) {
    final key = _taskKey(pathWord, chapterUuid);
    if (!_pausedTaskKeys.remove(key)) return;
    _signalScheduler();
    _wakeImageWorkers();
    notifyListeners();
    unawaited(_persistQueueState());
  }

  /// 从队列删除一个任务，并删除该章节已下载到本地的文件。
  ///
  /// 任务在队列中等待：直接移除。任务正在下载：图片请求自然完成后不再
  /// 收尾保存，已下载的部分文件一并删除。任务不在队列（如批次失败记录）：
  /// 仅清理对应记录。
  Future<void> deleteQueuedChapter(String pathWord, String chapterUuid) async {
    if (!_initialized) await init();
    final key = _taskKey(pathWord, chapterUuid);
    if (!_deletingTaskKeys.add(key)) return;
    final previous = _deleteWriteTail;
    final completed = Completer<void>();
    _deleteWriteTail = completed.future;
    try {
      await _deleteQueuedChapter(
        pathWord,
        chapterUuid,
        key,
        previous: previous,
      );
    } finally {
      _deletingTaskKeys.remove(key);
      if (!completed.isCompleted) completed.complete();
    }
  }

  Future<void> _deleteQueuedChapter(
    String pathWord,
    String chapterUuid,
    String key, {
    required Future<void> previous,
  }) async {
    final run = _activeRuns[key];

    _pausedTaskKeys.remove(key);
    // 先从 UI 队列移除；活动 run 保留 queued key，阻止删除完成前同 key 重入。
    _queue.removeWhere(
      (task) => _taskKey(task.pathWord, task.chapter.uuid) == key,
    );
    if (run != null) {
      // 在飞：标记取消并丢弃尚未领取的页任务；删除流程会等待 run 终止。
      _cancelledTaskKeys.add(key);
      run.cancelled = true;
      final removedJobs = _imageJobs
          .where((job) => identical(job.run, run))
          .length;
      if (removedJobs > 0) {
        _imageJobs.removeWhere((job) => identical(job.run, run));
        run.remaining -= removedJobs;
        if (run.remaining < 0) run.remaining = 0;
      }
      if (run.imageJobsDispatched && run.remaining <= 0 && !run.finalizing) {
        _completeCancelledRun(run);
      }
    } else {
      _queuedKeys.remove(key);
    }

    _batchFailures = _batchFailures
        .where((f) => _taskKey(f.task.pathWord, f.task.chapter.uuid) != key)
        .toList();
    _batchRunFailures = _batchRunFailures
        .where((f) => _taskKey(f.task.pathWord, f.task.chapter.uuid) != key)
        .toList();
    final summary = _lastBatchSummary;
    if (summary != null &&
        summary.failures.any(
          (f) => f.pathWord == pathWord && f.chapterUuid == chapterUuid,
        )) {
      final remaining = summary.failures
          .where(
            (f) => !(f.pathWord == pathWord && f.chapterUuid == chapterUuid),
          )
          .toList();
      _lastBatchSummary = remaining.isEmpty
          ? null
          : DownloadBatchSummary(
              succeeded: summary.succeeded,
              finishedAt: summary.finishedAt,
              failures: remaining,
            );
    }

    // 先落盘不含该任务的快照，避免进程在等待活动请求时把任务恢复回来。
    notifyListeners();
    await _persistQueueState();

    if (run != null && !run.terminated) {
      await run.done;
    }

    // 文件和 manifest 的清理按删除请求顺序执行；队列状态已经在上面立即反映。
    await previous;

    // 删除该章节已下载的文件与清单记录（无记录时不报错）。
    await _removeDownloadedChapter(pathWord, chapterUuid, deleteFiles: true);
    if (!_hasQueuedOrActiveTaskForComic(pathWord, excludingKey: key) &&
        (_manifest[pathWord]?.isEmpty ?? true)) {
      final prepare = _comicPrepares[pathWord];
      if (prepare != null) {
        try {
          await prepare;
        } catch (e, st) {
          unawaited(AppLogger.instance.recordWarning(e, stackTrace: st));
        }
      }
      if (!_hasQueuedOrActiveTaskForComic(pathWord, excludingKey: key) &&
          (_manifest[pathWord]?.isEmpty ?? true)) {
        await _removeLocalComic(pathWord);
      }
    }
    await _persistQueueState();
    notifyListeners();
    _signalScheduler();
    _wakeImageWorkers();
  }

  /// 批量暂停多个章节任务。已在飞的任务在下个阶段边界停住。
  void pauseChapters(Iterable<({String pathWord, String chapterUuid})> keys) {
    var changed = false;
    for (final key in keys) {
      if (_pausedTaskKeys.add(_taskKey(key.pathWord, key.chapterUuid))) {
        changed = true;
      }
    }
    if (!changed) return;
    notifyListeners();
    unawaited(_persistQueueState());
  }

  /// 批量恢复多个章节任务。
  void resumeChapters(Iterable<({String pathWord, String chapterUuid})> keys) {
    var changed = false;
    for (final key in keys) {
      if (_pausedTaskKeys.remove(_taskKey(key.pathWord, key.chapterUuid))) {
        changed = true;
      }
    }
    if (!changed) return;
    _signalScheduler();
    _wakeImageWorkers();
    notifyListeners();
    unawaited(_persistQueueState());
  }

  /// 批量删除队列任务并删除已下载文件，内部逐个调用 [deleteQueuedChapter]。
  ///
  /// [onProgress] 在每个任务删除完成后回调（已完成数, 总数）。
  Future<void> deleteQueuedChapters(
    Iterable<({String pathWord, String chapterUuid})> keys, {
    void Function(int completed, int total)? onProgress,
  }) async {
    final list = <({String pathWord, String chapterUuid})>[];
    final seen = <String>{};
    for (final key in keys) {
      final id = '${key.pathWord}|||${key.chapterUuid}';
      if (seen.add(id)) list.add(key);
    }
    var completed = 0;
    Object? firstError;
    StackTrace? firstStack;
    for (final key in list) {
      try {
        await deleteQueuedChapter(key.pathWord, key.chapterUuid);
      } catch (e, st) {
        firstError ??= e;
        firstStack ??= st;
        unawaited(
          AppLogger.instance.recordWarning(
            'Delete queued chapter failed: ${key.pathWord}/${key.chapterUuid}',
            stackTrace: st,
          ),
        );
      }
      completed++;
      onProgress?.call(completed, list.length);
    }
    if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
  }

  /// 当前队列状态快照：任务、全局/单独暂停状态与批次失败记录。
  Map<String, dynamic> _encodeQueueState() => {
    'version': _queueStateVersion,
    'paused': _paused,
    'paused_tasks': _pausedTaskKeys.toList(),
    'tasks': [for (final task in _queue) _encodeTask(task)],
    'succeeded': _batchSucceeded,
    'batch_failures': [
      for (final failure
          in (_batchRunFailures.isNotEmpty
              ? _batchRunFailures
              : _batchFailures))
        {
          ..._encodeTask(failure.task),
          'comic_name': failure.comicName,
          'cover': failure.cover,
        },
    ],
  };

  /// 将队列快照写入 SharedPreferences。快照同步生成、写入异步，
  /// 各状态变更点触发，最后一次写入生效。
  Future<void> _persistQueueState() {
    final payload = jsonEncode(_encodeQueueState());
    final previous = _queueStateWriteTail;
    final completed = Completer<void>();
    _queueStateWriteTail = completed.future;
    return () async {
      try {
        await previous;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyQueueState, payload);
      } catch (e, st) {
        unawaited(
          AppLogger.instance.recordWarning(
            'Persist download queue failed: $e',
            stackTrace: st,
          ),
        );
      } finally {
        if (!completed.isCompleted) completed.complete();
      }
    }();
  }

  /// 从持久化恢复队列、暂停状态与批次失败记录（App 重启后续传）。
  Future<void> _restoreQueueState(SharedPreferences prefs) async {
    final raw = prefs.getString(_keyQueueState);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final version = decoded['version'];
      if (version is int && version != _queueStateVersion) return;

      _paused = decoded['paused'] == true;
      final pausedTasks = decoded['paused_tasks'];
      if (pausedTasks is List) {
        _pausedTaskKeys.addAll(pausedTasks.map((e) => e.toString()));
      }

      final tasks = decoded['tasks'];
      if (tasks is List) {
        for (final item in tasks) {
          final restored = decodeQueueTaskJson(item);
          if (restored == null) continue;
          // 崩溃窗口内可能已完成下载：清单中已完整存在的全新任务不再重下。
          final summary = _manifest[restored.pathWord]?[restored.chapter.uuid];
          if (summary != null && !summary.isPartial && !restored.isRetry) {
            continue;
          }
          final task = _taskFromRestored(
            restored,
            isRetry:
                restored.isRetry ||
                (_manifest[restored.pathWord]?[restored.chapter.uuid]
                        ?.isPartial ??
                    false),
          );
          final key = _taskKey(task.pathWord, task.chapter.uuid);
          if (_queuedKeys.contains(key)) continue;
          _queue.add(task);
          _queuedKeys.add(key);
        }
      }

      _pausedTaskKeys.removeWhere((key) => !_queuedKeys.contains(key));
      _batchSucceeded = decoded['succeeded'] is int
          ? decoded['succeeded'] as int
          : 0;

      final failures = decoded['batch_failures'];
      final restoredFailures = <_BatchChapterFailure>[];
      if (failures is List) {
        for (final item in failures) {
          if (item is! Map) continue;
          final restored = decodeQueueTaskJson(item);
          if (restored == null) continue;
          restoredFailures.add(
            _BatchChapterFailure(
              task: _taskFromRestored(restored),
              comicName: item['comic_name']?.toString() ?? restored.pathWord,
              cover: item['cover']?.toString(),
            ),
          );
        }
      }
      if (restoredFailures.isNotEmpty) {
        _batchFailures = restoredFailures;
        _lastBatchSummary = DownloadBatchSummary(
          succeeded: decoded['succeeded'] is int
              ? decoded['succeeded'] as int
              : 0,
          finishedAt: DateTime.now(),
          failures: [
            for (final failure in restoredFailures)
              DownloadBatchFailure(
                pathWord: failure.task.pathWord,
                chapterUuid: failure.task.chapter.uuid,
                chapterName: failure.task.chapter.name,
                comicName: failure.comicName,
                cover: failure.cover,
                isRetry: failure.task.isRetry,
              ),
          ],
        );
      }
    } catch (e, st) {
      unawaited(
        AppLogger.instance.recordWarning(
          'Restore download queue failed: $e',
          stackTrace: st,
        ),
      );
    }
  }

  /// extension part 文件里的成员不是 DownloadManager 自身的成员，不能直接调用受
  /// 保护的 [notifyListeners]，统一经由这个转发方法。
  void _notifyListeners() => notifyListeners();

  bool get isBusy =>
      _queuedKeys.isNotEmpty ||
      _activeRuns.isNotEmpty ||
      _comicPrepares.isNotEmpty ||
      _deletingTaskKeys.isNotEmpty;

  void _ensureProcessing() {
    if (_initialized && !_paused && _queue.isNotEmpty && !_processing) {
      unawaited(_processQueue());
    }
  }

  bool _hasQueuedOrActiveTaskForComic(String pathWord, {String? excludingKey}) {
    bool include(String key) => key != excludingKey;
    return _queue.any(
          (task) =>
              task.pathWord == pathWord &&
              include(_taskKey(task.pathWord, task.chapter.uuid)),
        ) ||
        _activeRuns.values.any(
          (run) => run.task.pathWord == pathWord && include(run.key),
        ) ||
        _deletingTaskKeys.any((key) {
          final decoded = _decodeTaskKey(key);
          return decoded.pathWord == pathWord && include(key);
        });
  }

  bool _isCancelledRun(_ChapterRun run) =>
      run.cancelled || _cancelledTaskKeys.contains(run.key);

  void _completeCancelledRun(_ChapterRun run) {
    if (run.terminated) return;
    _imageJobs.removeWhere((job) => identical(job.run, run));
    _queue.removeWhere(
      (task) => _taskKey(task.pathWord, task.chapter.uuid) == run.key,
    );
    _queuedKeys.remove(run.key);
    _cancelledTaskKeys.remove(run.key);
    if (identical(_activeRuns[run.key], run)) _activeRuns.remove(run.key);
    _activeKeys.remove(run.key);
    _activeProgress.remove(run.key);
    run.terminated = true;
    run.complete();
    unawaited(_persistQueueState());
    notifyListeners();
    _signalScheduler();
    _wakeImageWorkers();
  }

  void _completeRun(_ChapterRun run) {
    if (run.terminated) return;
    if (identical(_activeRuns[run.key], run)) _activeRuns.remove(run.key);
    _activeKeys.remove(run.key);
    _activeProgress.remove(run.key);
    run.terminated = true;
    run.complete();
    notifyListeners();
    _signalScheduler();
  }

  /// 当前下载队列的任务信息列表，可供 UI 展示。
  List<ComicDownloadTaskInfo> get tasks {
    final result = <ComicDownloadTaskInfo>[];
    for (final task in _queue) {
      final key = _taskKey(task.pathWord, task.chapter.uuid);
      final status = _paused || _pausedTaskKeys.contains(key)
          ? ComicDownloadTaskStatus.paused
          : _activeKeys.contains(key)
          ? ComicDownloadTaskStatus.downloading
          : ComicDownloadTaskStatus.pending;
      final info = getLocalComicInfo(task.pathWord);
      result.add(
        ComicDownloadTaskInfo(
          pathWord: task.pathWord,
          chapterUuid: task.chapter.uuid,
          chapterName: task.chapter.name,
          comicName: info?.comic.name ?? task.pathWord,
          cover: info?.comic.cover,
          status: status,
          progress: _activeProgress[key],
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

  /// 图片并发下载数量（全局 worker 池，跨章节共享），
  /// 范围 [_minImageConcurrency]~[_maxImageConcurrency]。
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

  /// 单图第 [retryIndex]（从 1 起）次重试前的等待时长；[rateLimited] 为
  /// true（429 限流）时加倍。
  static Duration imageRetryDelay(int retryIndex, {bool rateLimited = false}) {
    final base =
        _imageRetryBaseDelays[(retryIndex - 1).clamp(
          0,
          _imageRetryBaseDelays.length - 1,
        )];
    return rateLimited ? base * 4 : base;
  }

  /// 整章第 [retryIndex]（从 1 起）次自动重试前的退避时长。
  static Duration chapterRetryDelay(int retryIndex) =>
      _chapterRetryDelays[(retryIndex - 1).clamp(
        0,
        _chapterRetryDelays.length - 1,
      )];

  /// 章节下载顺序比较器：ordered > 0 时按 ordered 升序，否则按 index；
  /// 同序时按 uuid 决出稳定次序（Dart 的 sort 不保证稳定）。
  static int chapterDownloadOrder(Chapter a, Chapter b) {
    final orderA = a.ordered > 0 ? a.ordered : a.index;
    final orderB = b.ordered > 0 ? b.ordered : b.index;
    if (orderA != orderB) return orderA.compareTo(orderB);
    return a.uuid.compareTo(b.uuid);
  }

  /// 队列任务持久化编码（公开供单测覆盖编解码往返）。
  @visibleForTesting
  static Map<String, dynamic> encodeQueueTaskJson({
    required String pathWord,
    required String group,
    required Chapter chapter,
    required bool isRetry,
    required int attempt,
    DateTime? notBefore,
  }) => {
    'path_word': pathWord,
    'group': group,
    'chapter_uuid': chapter.uuid,
    'chapter_index': chapter.index,
    'chapter_name': chapter.name,
    'chapter_order': chapter.ordered,
    'is_retry': isRetry,
    'attempt': attempt,
    'not_before': notBefore?.toIso8601String(),
  };

  /// 解析持久化的队列任务；载荷非法或关键字段缺失时返回 null。
  @visibleForTesting
  static ({
    String pathWord,
    String group,
    Chapter chapter,
    bool isRetry,
    int attempt,
    DateTime? notBefore,
  })?
  decodeQueueTaskJson(Object? raw) {
    if (raw is! Map) return null;
    final pathWord = raw['path_word']?.toString() ?? '';
    final chapterUuid = raw['chapter_uuid']?.toString() ?? '';
    if (pathWord.isEmpty || chapterUuid.isEmpty) return null;
    final chapterIndex = raw['chapter_index'] is int
        ? raw['chapter_index'] as int
        : int.tryParse('${raw['chapter_index']}') ?? 0;
    final chapterOrder = raw['chapter_order'] is int
        ? raw['chapter_order'] as int
        : int.tryParse('${raw['chapter_order']}') ?? 0;
    return (
      pathWord: pathWord,
      group: raw['group']?.toString().trim().isEmpty ?? true
          ? 'default'
          : raw['group'].toString(),
      chapter: Chapter(
        uuid: chapterUuid,
        index: chapterIndex,
        name: raw['chapter_name']?.toString() ?? '',
        ordered: chapterOrder,
      ),
      isRetry: raw['is_retry'] == true,
      attempt: raw['attempt'] is int
          ? raw['attempt'] as int
          : int.tryParse('${raw['attempt']}') ?? 1,
      notBefore: DateTime.tryParse(raw['not_before']?.toString() ?? ''),
    );
  }

  static Map<String, dynamic> _encodeTask(_DownloadTask task) =>
      encodeQueueTaskJson(
        pathWord: task.pathWord,
        group: task.group,
        chapter: task.chapter,
        isRetry: task.isRetry,
        attempt: task.attempt,
        notBefore: task.notBefore,
      );

  static _DownloadTask _taskFromRestored(
    ({
      String pathWord,
      String group,
      Chapter chapter,
      bool isRetry,
      int attempt,
      DateTime? notBefore,
    })
    restored, {
    bool? isRetry,
  }) => _DownloadTask(
    pathWord: restored.pathWord,
    group: restored.group,
    chapter: restored.chapter,
    isRetry: isRetry ?? restored.isRetry,
    attempt: restored.attempt,
    notBefore: restored.notBefore,
  );

  final Map<String, Future<void>> _comicPrepares = {};

  void _scheduleComicPrepare(String pathWord, Comic comic) {
    final previous = _comicPrepares[pathWord] ?? Future.value();
    final task = () async {
      try {
        await previous;
      } catch (e, st) {
        unawaited(AppLogger.instance.recordWarning(e, stackTrace: st));
      }
      try {
        await _ensureComicStored(pathWord, comic);
      } catch (e, st) {
        unawaited(AppLogger.instance.recordWarning(e, stackTrace: st));
      }
    }();
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
    _rootDirectory = _rootDirectoryProvider == null
        ? await resolveRootDirectory(
            customPath: _customSaveDirectory,
            defaultParentPath: (await getApplicationDocumentsDirectory()).path,
          )
        : await _rootDirectoryProvider();
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

    await _restoreQueueState(prefs);

    _initialized = true;

    // 重启后续传：恢复的队列立即继续下载（此前已暂停则保持暂停）。
    _ensureProcessing();
  }

  /// 队列主循环：启动全局图片 worker 池与章节流水线调度，直到队列排空。
  Future<void> _processQueue() async {
    if (_processing) return;
    _processing = true;
    _batchSucceeded = 0;
    _batchRunFailures = [];

    try {
      _schedulerDone = false;
      final workers = List.generate(
        _imageDownloadConcurrency,
        (_) => _imageWorker(),
      );
      await _runChapterScheduler();
      _schedulerDone = true;
      _wakeImageWorkers();
      await Future.wait(workers);

      if (_batchRunFailures.isNotEmpty) {
        final failures = List<_BatchChapterFailure>.of(_batchRunFailures);
        _batchFailures = failures;
        _lastBatchSummary = DownloadBatchSummary(
          succeeded: _batchSucceeded,
          finishedAt: DateTime.now(),
          failures: [
            for (final failure in failures)
              DownloadBatchFailure(
                pathWord: failure.task.pathWord,
                chapterUuid: failure.task.chapter.uuid,
                chapterName: failure.task.chapter.name,
                comicName: failure.comicName,
                cover: failure.cover,
                isRetry: failure.task.isRetry,
              ),
          ],
        );
      }
      _batchRunFailures = [];
      await _persistQueueState();
    } finally {
      _processing = false;
      notifyListeners();
      // 新任务可能在 scheduler/worker 收尾窗口内入队；启动一个新的处理器，
      // 避免入队调用恰好撞上旧处理器仍标记为 busy 而被吞掉。
      _ensureProcessing();
    }
  }

  /// 章节流水线调度：维持最多 [_maxChaptersInFlight] 个在飞章节。
  /// 任务在下载期间保留在队列中供 UI 展示；全局或单独暂停的章节不会被领取。
  Future<void> _runChapterScheduler() async {
    while (true) {
      // 领取新任务，跳过已在飞、已暂停与未出退避窗口的任务。
      while (!_paused && _activeRuns.length < _maxChaptersInFlight) {
        final now = DateTime.now();
        final index = _queue.indexWhere((task) {
          if (!task.isEligibleAt(now)) return false;
          final key = _taskKey(task.pathWord, task.chapter.uuid);
          return !_activeRuns.containsKey(key) &&
              !_pausedTaskKeys.contains(key);
        });
        if (index < 0) break;

        final task = _queue[index];
        final key = _taskKey(task.pathWord, task.chapter.uuid);
        _cancelledTaskKeys.remove(key);
        final run = _ChapterRun(task: task, key: key);
        _activeRuns[key] = run;
        _activeKeys.add(key);
        notifyListeners();
        unawaited(_startChapter(run));
      }

      if (_activeRuns.isEmpty) {
        if (_queue.isEmpty) return;
        // 剩余任务均不可领取（全局暂停、单独暂停或退避窗口内）：挂起等待。
        await _waitForNextEligible();
        continue;
      }

      // 等待任一章节完成（收尾或失败处理后唤醒）。
      final wake = _newSchedulerWait();
      try {
        await wake.future;
      } finally {
        _schedulerWaits.remove(wake);
      }
    }
  }

  /// 启动单个在飞章节：拉取详情 → 准备目录/复用已下载页 →
  /// 把待下载页推入全局图片队列。详情或准备阶段失败转入失败路径。
  Future<void> _startChapter(_ChapterRun run) async {
    final task = run.task;
    try {
      if (_isCancelledRun(run)) {
        run.cancelled = true;
        return;
      }
      final detail = _chapterDetailLoader == null
          ? await _api.manga.getChapterDetail(task.pathWord, task.chapter.uuid)
          : await _chapterDetailLoader(task.pathWord, task.chapter.uuid);
      if (_isCancelledRun(run)) return;
      if (detail.contents.isEmpty) {
        throw const HttpException('Chapter has no images');
      }
      run.detail = detail;
      run.total = detail.contents.length;
      run.result = List<String?>.filled(run.total, null);

      final chapterDir = _chapterDirectory(task.pathWord, task.chapter.uuid);
      // 重试时保留已下载的文件，仅补全失败页；全新下载则清空目录。
      if (!task.isRetry) {
        await _resetDirectory(chapterDir);
      }
      if (_isCancelledRun(run)) return;

      // 复用已下载页的本地路径，避免重复下载成功页（重试或崩溃恢复）。
      final existing = await _loadExistingPaths(
        task.pathWord,
        task.chapter.uuid,
        run.total,
      );
      if (_isCancelledRun(run)) return;

      // 重试时复用已保存的评论；全新下载且开关开启时才拉取评论。
      // 评论与图片互不依赖，与图片下载并行执行，避免拖慢进度显示。
      run.commentsFuture = (task.isRetry || !_downloadCommentsEnabled)
          ? _loadExistingComments(task.pathWord, task.chapter.uuid)
          : _downloadComments(task.chapter.uuid);

      for (var i = 0; i < run.total; i++) {
        final existingPath = i < existing.length ? existing[i] : null;
        if (existingPath != null && existingPath.isNotEmpty) {
          run.result[i] = existingPath;
          run.completed++;
        }
      }
      run.remaining = run.total - run.completed;
      _activeProgress[run.key] = ChapterDownloadProgress(
        completed: run.completed,
        total: run.total,
      );
      notifyListeners();

      if (run.remaining == 0) {
        await _finalizeChapter(run);
        return;
      }

      // 页任务按章节顺序进入全局队列：前面的章节优先占用 worker，
      // 有剩余的 worker 立即领取后面章节的页，不闲置并发额度。
      if (_isCancelledRun(run)) return;
      run.imageJobsDispatched = true;
      for (var i = 0; i < run.total; i++) {
        if (run.result[i] != null) continue;
        _imageJobs.add(_ImageJob(run: run, index: i, url: detail.contents[i]));
      }
      _wakeImageWorkers();
    } catch (e, st) {
      if (_isCancelledRun(run)) {
        _completeCancelledRun(run);
      } else {
        await _handleChapterFailure(run, e, st);
      }
    } finally {
      // 详情/准备阶段可能在取消后才返回，确保没有 image job 时也能释放 run。
      if (_isCancelledRun(run) && !run.imageJobsDispatched && !run.finalizing) {
        _completeCancelledRun(run);
      }
    }
  }

  /// 章节收尾：等评论结果（失败降级）、写 chapter.json 与 manifest。
  /// 全部页成功则记成功；写盘失败转入失败路径。任务被删除（取消）时
  /// 跳过保存，由删除流程清理文件。
  Future<void> _finalizeChapter(_ChapterRun run) async {
    final task = run.task;
    if (run.terminated || run.finalizing) return;
    run.finalizing = true;
    try {
      if (_isCancelledRun(run)) return;
      // 评论拉取失败不连累整章：降级为已有评论或空评论，图片照常保存。
      var comments = (list: const <ChapterComment>[], total: 0);
      try {
        comments = await run.commentsFuture;
      } catch (e, st) {
        unawaited(
          AppLogger.instance.recordWarning(
            'Download chapter comments failed: ${task.chapter.uuid}: $e',
            stackTrace: st,
          ),
        );
        comments = await _loadExistingComments(
          task.pathWord,
          task.chapter.uuid,
        );
      }
      if (_isCancelledRun(run)) return;

      // 处理结果：失败页记为空串，收集失败索引。
      final failedIndices = <int>[];
      final completedPaths = List<String>.filled(run.total, '');
      for (var i = 0; i < run.total; i++) {
        final path = run.result[i];
        if (path == null) {
          failedIndices.add(i);
        } else {
          completedPaths[i] = path;
        }
      }

      final localDetail = run.detail!.copyWith(
        contents: completedPaths,
        isDownloaded: true,
        comments: comments.list,
        commentTotal: comments.total,
      );
      await _writeChapterMetadata(
        task.pathWord,
        task.chapter.uuid,
        localDetail,
      );
      if (_isCancelledRun(run)) return;

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
      if (_isCancelledRun(run)) return;
      await _touchLocalComic(task.pathWord);
      if (_isCancelledRun(run)) return;
      // 注意：部分图片失败不抛错，章节以 partial 状态持久化，用户可重试补全。

      _queue.remove(task);
      _queuedKeys.remove(run.key);
      _batchSucceeded++;
      await _persistQueueState();
    } catch (e, st) {
      if (_isCancelledRun(run)) {
        _completeCancelledRun(run);
      } else {
        await _handleChapterFailure(run, e, st);
      }
    } finally {
      run.finalizing = false;
      if (_isCancelledRun(run)) {
        _completeCancelledRun(run);
      } else {
        _completeRun(run);
      }
    }
  }

  /// 整章失败处理：尝试次数未耗尽则带退避重新入队（排到队尾，先放行
  /// 后续章节）；耗尽后全新下载清理目录、记入批次失败。任务被删除
  /// （取消）时直接退出，由删除流程清理文件。
  Future<void> _handleChapterFailure(
    _ChapterRun run,
    Object error,
    StackTrace st,
  ) async {
    if (_isCancelledRun(run)) {
      _completeCancelledRun(run);
      return;
    }

    unawaited(
      AppLogger.instance.recordWarning(
        'Download chapter failed (attempt ${run.task.attempt}): '
        '${run.task.pathWord}/${run.task.chapter.uuid}: $error',
        stackTrace: st,
      ),
    );

    _queue.remove(run.task);
    notifyListeners();

    var requeued = false;
    try {
      if (run.task.attempt < _chapterMaxAttempts) {
        final retryAt = DateTime.now().add(chapterRetryDelay(run.task.attempt));
        if (_isCancelledRun(run)) return;
        _queue.add(run.task.copyWithRetry(retryAt));
        _queuedKeys.add(run.key);
        requeued = true;
        notifyListeners();
      } else {
        // 手动补全(isRetry)失败保留 partial 记录，全新下载失败才清理。
        if (!run.task.isRetry) {
          await _removeDownloadedChapter(
            run.task.pathWord,
            run.task.chapter.uuid,
            deleteFiles: true,
          );
        }
        if (_isCancelledRun(run)) return;
        final info = getLocalComicInfo(run.task.pathWord);
        _batchRunFailures.add(
          _BatchChapterFailure(
            task: run.task,
            comicName: info?.comic.name ?? run.task.pathWord,
            cover: info?.comic.cover,
          ),
        );
      }
      await _persistQueueState();
    } finally {
      if (_isCancelledRun(run)) {
        _completeCancelledRun(run);
      } else {
        if (!requeued) _queuedKeys.remove(run.key);
        _completeRun(run);
      }
    }
  }

  /// 全局图片 worker：跨章节领取页任务；队列排空且调度器收尾后退出。
  /// 暂停（全局或所属章节）的任务留在队列中，恢复后继续。
  Future<void> _imageWorker() async {
    while (true) {
      final job = _nextImageJob();
      if (job != null) {
        try {
          await _processImageJob(job);
        } catch (e, st) {
          if (_isCancelledRun(job.run)) {
            _completeCancelledRun(job.run);
          } else {
            await _handleChapterFailure(job.run, e, st);
          }
        }
        continue;
      }
      if (_schedulerDone) return;
      // 队列无可领取任务（已排空、全局暂停或章节暂停）：等待唤醒。
      final wake = _jobWake ??= Completer<void>();
      await wake.future;
      continue;
    }
  }

  /// 取出下一个可领取的页任务；全局暂停或所属章节被暂停时返回 null。
  _ImageJob? _nextImageJob() {
    if (_paused) return null;
    for (var i = 0; i < _imageJobs.length; i++) {
      if (_pausedTaskKeys.contains(_imageJobs[i].run.key)) continue;
      return _imageJobs.removeAt(i);
    }
    return null;
  }

  void _wakeImageWorkers() {
    final wake = _jobWake;
    if (wake != null && !wake.isCompleted) wake.complete();
    _jobWake = null;
  }

  /// 处理单个页任务：下载并记录结果与进度；章节最后一页完成时触发收尾。
  /// 任务被删除（取消）时跳过收尾，由删除流程清理文件。
  Future<void> _processImageJob(_ImageJob job) async {
    final run = job.run;
    if (_isCancelledRun(run)) {
      run.cancelled = true;
      run.remaining--;
      if (run.remaining <= 0 && !run.finalizing) _completeCancelledRun(run);
      return;
    }
    String? path;
    try {
      final file = await _downloadImage(
        job.url,
        _chapterDirectory(run.task.pathWord, run.task.chapter.uuid),
        job.index + 1,
      );
      path = file.path;
      run.completed++;
    } catch (e, st) {
      // 单张失败不中断整章；记为 null，由收尾阶段收集为 failedIndices。
      run.failed++;
      unawaited(
        AppLogger.instance.recordWarning(
          'Image #${job.index} download failed: $e',
          stackTrace: st,
        ),
      );
    }
    if (_isCancelledRun(run)) {
      run.cancelled = true;
      run.remaining--;
      if (run.remaining <= 0 && !run.finalizing) _completeCancelledRun(run);
      return;
    }
    run.result[job.index] = path;
    run.remaining--;
    _activeProgress[run.key] = ChapterDownloadProgress(
      completed: run.completed,
      total: run.total,
      failed: run.failed,
    );
    _notifyListeners();
    if (run.remaining <= 0) {
      await _finalizeChapter(run);
    }
  }

  /// 注册一个调度器等待点；[_signalScheduler] 唤醒所有等待点。
  Completer<void> _newSchedulerWait() {
    final wake = Completer<void>();
    _schedulerWaits.add(wake);
    return wake;
  }

  /// 唤醒章节调度器（章节完成、失败或新任务入队时调用）。
  void _signalScheduler() {
    if (_schedulerWaits.isEmpty) return;
    final waits = List.of(_schedulerWaits);
    _schedulerWaits.clear();
    for (final wake in waits) {
      if (!wake.isCompleted) wake.complete();
    }
  }

  /// 队列剩余任务均不可领取（处于退避窗口、被单独暂停或全局暂停）时
  /// 挂起等待；最早退避到期、恢复下载或新任务入队时返回。
  Future<void> _waitForNextEligible() async {
    final now = DateTime.now();
    DateTime? earliest;
    for (final task in _queue) {
      if (_pausedTaskKeys.contains(
        _taskKey(task.pathWord, task.chapter.uuid),
      )) {
        continue;
      }
      final notBefore = task.notBefore;
      if (notBefore == null || !notBefore.isAfter(now)) return;
      if (earliest == null || notBefore.isBefore(earliest)) {
        earliest = notBefore;
      }
    }

    // 全局暂停：无超时等待，恢复或新任务入队时唤醒。
    final wait = _paused ? null : earliest?.difference(now);
    if (wait != null && wait <= Duration.zero) return;

    final wake = _newSchedulerWait();
    try {
      if (wait == null) {
        await wake.future;
      } else {
        await Future.any<void>([wake.future, Future<void>.delayed(wait)]);
      }
    } finally {
      _schedulerWaits.remove(wake);
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

  Future<void> _writeTextFileAtomically(File file, String contents) async {
    await file.parent.create(recursive: true);
    final temporary = File(
      '${file.path}.tmp.${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temporary.writeAsString(contents, flush: true);
      try {
        await temporary.rename(file.path);
      } on FileSystemException {
        // Some Windows file systems do not replace an existing target on
        // rename. Keep the temporary write, then use the portable fallback.
        if (await file.exists()) await file.delete();
        await temporary.rename(file.path);
      }
    } finally {
      try {
        if (await temporary.exists()) await temporary.delete();
      } catch (e, st) {
        unawaited(AppLogger.instance.recordWarning(e, stackTrace: st));
      }
    }
  }

  Future<void> _writeSerializedText(
    Map<String, Future<void>> tails,
    String key,
    File file,
    String contents,
  ) {
    final previous = tails[key] ?? Future.value();
    final completed = Completer<void>();
    tails[key] = completed.future;
    return () async {
      try {
        try {
          await previous;
        } catch (e, st) {
          // A failed older write must not prevent a later state snapshot from
          // being attempted.
          unawaited(AppLogger.instance.recordWarning(e, stackTrace: st));
        }
        await _writeTextFileAtomically(file, contents);
      } finally {
        if (identical(tails[key], completed.future)) {
          unawaited(tails.remove(key));
        }
        if (!completed.isCompleted) completed.complete();
      }
    }();
  }

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
  // 已执行的尝试次数（含当前，从 1 起）；用于整章失败后的自动重试退避。
  final int attempt;
  // 自动重试的退避到期时间；早于该时刻的任务不会被领取。
  final DateTime? notBefore;

  const _DownloadTask({
    required this.pathWord,
    required this.group,
    required this.chapter,
    this.isRetry = false,
    this.attempt = 1,
    this.notBefore,
  });

  /// 是否已到可领取时间（自动重试退避窗口已过）。
  bool isEligibleAt(DateTime now) =>
      notBefore == null || !notBefore!.isAfter(now);

  /// 生成下一次自动重试的任务副本：尝试次数 +1、退避到期时间为 [retryAt]。
  _DownloadTask copyWithRetry(DateTime retryAt) => _DownloadTask(
    pathWord: pathWord,
    group: group,
    chapter: chapter,
    isRetry: isRetry,
    attempt: attempt + 1,
    notBefore: retryAt,
  );
}

/// 在飞章节的运行态：详情拉取、页结果收集与进度上报。
class _ChapterRun {
  final _DownloadTask task;
  final String key;

  ChapterDetail? detail;

  // 各页本地路径；null 表示该页未下载成功（含尚未处理）。
  List<String?> result = const [];

  int total = 0;

  // 成功页数（含复用的已下载页）。
  int completed = 0;
  int failed = 0;

  // 尚未完成的页任务数；归零时触发章节收尾。
  int remaining = 0;

  // 用户删除了该任务：不再收尾保存，等待清理。
  bool cancelled = false;

  // 图片任务已经全部放入全局队列；之后的取消由 worker/删除流程收尾。
  bool imageJobsDispatched = false;

  // 章节正在等待评论或写入本地文件。
  bool finalizing = false;

  // run 已经从管理器的活动集合中终结。
  bool terminated = false;

  final Completer<void> _done = Completer<void>();

  Future<void> get done => _done.future;

  void complete() {
    if (!_done.isCompleted) _done.complete();
  }

  Future<({List<ChapterComment> list, int total})> commentsFuture =
      Future.value((list: const <ChapterComment>[], total: 0));

  _ChapterRun({required this.task, required this.key});
}

/// 全局图片队列的单元：跨章节共享 worker 池，章节尾部不再闲置并发额度。
class _ImageJob {
  final _ChapterRun run;
  final int index;
  final String url;

  const _ImageJob({required this.run, required this.index, required this.url});
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

  /// 已暂停（全局暂停或单独暂停）
  paused,
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

/// 批次内单章失败记录，保留原任务以便"重试失败章节"重新入队。
class _BatchChapterFailure {
  final _DownloadTask task;
  final String comicName;
  final String? cover;

  const _BatchChapterFailure({
    required this.task,
    required this.comicName,
    this.cover,
  });
}

/// 批量下载中单章失败的记录，供 UI 展示。
class DownloadBatchFailure {
  final String pathWord;
  final String chapterUuid;
  final String chapterName;
  final String comicName;
  final String? cover;

  /// 是否为手动补全（partial 重试）失败；false 表示全新下载失败。
  final bool isRetry;

  const DownloadBatchFailure({
    required this.pathWord,
    required this.chapterUuid,
    required this.chapterName,
    required this.comicName,
    this.cover,
    this.isRetry = false,
  });
}

/// 队列清空后的批次下载汇总：成功章数与失败章清单。
class DownloadBatchSummary {
  final int succeeded;
  final List<DownloadBatchFailure> failures;
  final DateTime finishedAt;

  const DownloadBatchSummary({
    required this.succeeded,
    required this.failures,
    required this.finishedAt,
  });
}
