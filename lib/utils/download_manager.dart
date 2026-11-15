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
import 'app_platform.dart';
import 'downloaded_file_path.dart';
import 'json_helpers.dart';

part 'download_manager_parts/models.dart';
part 'download_manager_parts/task_control.dart';
part 'download_manager_parts/queue_state.dart';
part 'download_manager_parts/lifecycle.dart';
part 'download_manager_parts/queue_runner.dart';
part 'download_manager_parts/image_pipeline.dart';
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

  /// 是否已全局暂停下载。暂停状态随队列快照保存，重启后可继续。
  bool get paused => _paused;

  /// 暂停全部下载：在飞的图片请求自然完成后停止领取新任务。
  void pauseDownloads() {
    if (_paused) return;
    _paused = true;
    _signalScheduler();
    _notifyListeners();
    unawaited(_persistQueueState());
  }

  /// 恢复全部下载。
  void resumeDownloads() {
    if (!_paused) return;
    _paused = false;
    _signalScheduler();
    _wakeImageWorkers();
    _notifyListeners();
    unawaited(_persistQueueState());
    _ensureProcessing();
  }

  /// 单个章节是否被暂停。
  bool isChapterPaused(String pathWord, String chapterUuid) =>
      _pausedTaskKeys.contains(_taskKey(pathWord, chapterUuid));

  /// 暂停单个章节：在飞的图片请求自然完成后停止领取新任务。
  void pauseChapter(String pathWord, String chapterUuid) {
    if (!_pausedTaskKeys.add(_taskKey(pathWord, chapterUuid))) return;
    _notifyListeners();
    unawaited(_persistQueueState());
  }

  /// 恢复单个章节。
  void resumeChapter(String pathWord, String chapterUuid) {
    final key = _taskKey(pathWord, chapterUuid);
    if (!_pausedTaskKeys.remove(key)) return;
    _signalScheduler();
    _wakeImageWorkers();
    _notifyListeners();
    unawaited(_persistQueueState());
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
    _notifyListeners();
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
    _notifyListeners();
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
    _notifyListeners();
    unawaited(_persistQueueState());
  }

  Future<void> init() async {
    if (_initialized) return;
    _initFuture ??= _initialize();
    await _initFuture;
  }

  /// 图片并发下载数量（全局 worker 池，跨章节共享），
  /// 范围 [_minImageConcurrency]~[_maxImageConcurrency]。
  int get imageDownloadConcurrency => _imageDownloadConcurrency;

  /// 重新从 SharedPreferences 读取下载设置(导入备份 / 清除数据后调用)。
  ///
  /// 未初始化时等价于 [init]。队列有任务在飞时只刷新标量设置(并发数量、
  /// 章节评论):此时重算根目录或替换队列会与运行中的 worker 争用文件路径,
  /// 那部分交由下次启动生效。空闲时则做与冷启动等价的完整重载——根目录、
  /// 清单、队列一起从 prefs 重建。
  Future<void> reloadFromPrefs() async {
    if (!_initialized) {
      await init();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (_processing || isBusy) {
      _applyScalarSettings(prefs);
      notifyListeners();
      return;
    }
    await _loadFromPrefs(prefs);
    notifyListeners();
    _ensureProcessing();
  }

  /// Portable backups never replace paths or queues. Avoid restarting workers
  /// or touching local manifests when applying just the two scalar preferences.
  Future<void> reloadScalarSettings() async {
    _applyScalarSettings(await SharedPreferences.getInstance());
    notifyListeners();
  }

  /// 应用与运行态无关的标量设置,任何时刻都安全。
  void _applyScalarSettings(SharedPreferences prefs) {
    _imageDownloadConcurrency = _clampConcurrency(
      prefs.getInt(_keyImageConcurrency),
    );
    _downloadCommentsEnabled = prefs.getBool(_keyDownloadComments) ?? true;
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
      final decoded = jsonMap({'value': jsonDecode(raw)}, 'value');
      if (decoded == null) return List<String?>.filled(total, null);
      final contents = jsonList(decoded, 'contents');
      final result = List<String?>.filled(total, null);
      for (var i = 0; i < total && i < contents.length; i++) {
        final stored = contents[i]?.toString() ?? '';
        final resolved = DownloadedFilePath.resolve(
          stored,
          rootPath: _rootDirectory!.path,
          directoryPath: _chapterDirectory(pathWord, chapterUuid).path,
          relocateIOSContainer: AppPlatform.isIOS,
        );
        if (resolved != null && await File(resolved).exists()) {
          result[i] = resolved;
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
