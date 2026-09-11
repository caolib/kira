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

  /// 在飞章节数：1 章下载图片 + 1 章预取详情。图片任务严格按章节顺序
  /// 派发（当前章全部页结束后下一章才开始传图），让最早的话尽快完整
  /// 可读；详情预取只提前发 API 请求，不提前下载下一章的图片。
  static const int _maxChaptersInFlight = 2;

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

  // 正在下载（详情拉取中或图片在飞）的章节任务 key。
  final Set<String> _activeKeys = {};

  // 正在下载章节的实时进度，key 同 [_activeKeys]。
  final Map<String, ChapterDownloadProgress> _activeProgress = {};

  // 在飞章节运行态，最多 [_maxChaptersInFlight] 个（1 传图 + 1 预取详情）。
  final Map<String, _ChapterRun> _activeRuns = {};

  // 当前持有传图权的章节 key；图片任务严格按章节串行派发。
  String? _downloadingKey;

  // 全局图片任务队列，跨章节共享 worker 池，章节尾部不再闲置并发额度。
  final List<_ImageJob> _imageJobs = [];
  Completer<void>? _jobWake;

  // 章节调度器的等待点集合；任何章节完成/失败/新任务入队都会唤醒。
  final List<Completer<void>> _schedulerWaits = [];
  bool _schedulerDone = false;

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
    if (_lastBatchSummary == null && _batchFailures.isEmpty) return;
    _batchFailures = const [];
    _lastBatchSummary = null;
    notifyListeners();
  }

  /// extension part 文件里的成员不是 DownloadManager 自身的成员，不能直接调用受
  /// 保护的 [notifyListeners]，统一经由这个转发方法。
  void _notifyListeners() => notifyListeners();

  bool get isBusy => _queuedKeys.isNotEmpty;

  /// 当前下载队列的任务信息列表，可供 UI 展示。
  List<ComicDownloadTaskInfo> get tasks {
    final result = <ComicDownloadTaskInfo>[];
    for (final task in _queue) {
      final key = _taskKey(task.pathWord, task.chapter.uuid);
      final isActive = _activeKeys.contains(key);
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
        _batchFailures = _batchRunFailures;
        _lastBatchSummary = DownloadBatchSummary(
          succeeded: _batchSucceeded,
          finishedAt: DateTime.now(),
          failures: [
            for (final failure in _batchRunFailures)
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
    } finally {
      _processing = false;
      notifyListeners();
    }
  }

  /// 章节流水线调度：维持最多 [_maxChaptersInFlight] 个在飞章节——
  /// 1 个在传图，1 个在预取详情。图片任务严格按章节顺序派发，
  /// 让最早的话尽快完整可读；任务在下载期间保留在队列中供 UI 展示。
  Future<void> _runChapterScheduler() async {
    while (true) {
      // 领取新任务，跳过已在飞的任务与未出退避窗口的自动重试。
      while (_activeRuns.length < _maxChaptersInFlight) {
        final now = DateTime.now();
        final index = _queue.indexWhere((task) {
          if (!task.isEligibleAt(now)) return false;
          return !_activeRuns.containsKey(
            _taskKey(task.pathWord, task.chapter.uuid),
          );
        });
        if (index < 0) break;

        final task = _queue[index];
        final key = _taskKey(task.pathWord, task.chapter.uuid);
        final run = _ChapterRun(task: task, key: key);
        _activeRuns[key] = run;
        _activeKeys.add(key);
        notifyListeners();
        unawaited(_startChapter(run));
      }

      if (_activeRuns.isEmpty) {
        if (_queue.isEmpty) return;
        // 剩余任务都在自动重试退避窗口内：等到最早到期或新任务入队。
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
      final detail = await _api.manga.getChapterDetail(
        task.pathWord,
        task.chapter.uuid,
      );
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

      // 复用已下载页的本地路径，避免重复下载成功页（重试或崩溃恢复）。
      final existing = await _loadExistingPaths(
        task.pathWord,
        task.chapter.uuid,
        run.total,
      );

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

      // 图片任务严格串章：当前已有章节在传图时只标记就绪，等它完成后
      // 再派发（详情已就绪，无空窗）。
      run.readyToDispatch = true;
      _dispatchNextReadyChapter();
    } catch (e, st) {
      await _handleChapterFailure(run, e, st);
    }
  }

  /// 派发下一个就绪章节的图片任务（当前无章节在传图时）。
  void _dispatchNextReadyChapter() {
    if (_downloadingKey != null) return;
    for (final run in _activeRuns.values) {
      if (!run.readyToDispatch || run.remaining <= 0) continue;
      _downloadingKey = run.key;
      for (var i = 0; i < run.total; i++) {
        if (run.result[i] != null) continue;
        _imageJobs.add(
          _ImageJob(run: run, index: i, url: run.detail!.contents[i]),
        );
      }
      _wakeImageWorkers();
      return;
    }
  }

  /// 章节结束传图（完成或失败）后释放传图权，并尝试派发下一章。
  void _releaseImageSlot(_ChapterRun run) {
    if (_downloadingKey == run.key) {
      _downloadingKey = null;
    }
    _dispatchNextReadyChapter();
  }

  /// 章节收尾：等评论结果（失败降级）、写 chapter.json 与 manifest。
  /// 全部页成功则记成功；写盘失败转入失败路径。
  Future<void> _finalizeChapter(_ChapterRun run) async {
    final task = run.task;
    var failed = false;
    try {
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

      _queue.remove(task);
      _queuedKeys.remove(run.key);
      _batchSucceeded++;
    } catch (e, st) {
      failed = true;
      await _handleChapterFailure(run, e, st);
    } finally {
      _activeRuns.remove(run.key);
      _activeKeys.remove(run.key);
      _activeProgress.remove(run.key);
      _releaseImageSlot(run);
      notifyListeners();
    }
    if (!failed) _signalScheduler();
  }

  /// 整章失败处理：尝试次数未耗尽则带退避重新入队（排到队尾，先放行
  /// 后续章节）；耗尽后全新下载清理目录、记入批次失败。
  Future<void> _handleChapterFailure(
    _ChapterRun run,
    Object error,
    StackTrace st,
  ) async {
    unawaited(
      AppLogger.instance.recordWarning(
        'Download chapter failed (attempt ${run.task.attempt}): '
        '${run.task.pathWord}/${run.task.chapter.uuid}: $error',
        stackTrace: st,
      ),
    );

    _activeRuns.remove(run.key);
    _activeKeys.remove(run.key);
    _activeProgress.remove(run.key);
    _releaseImageSlot(run);
    _queue.remove(run.task);
    _queuedKeys.remove(run.key);
    notifyListeners();

    if (run.task.attempt < _chapterMaxAttempts) {
      final retryAt = DateTime.now().add(chapterRetryDelay(run.task.attempt));
      _queue.add(run.task.copyWithRetry(retryAt));
      _queuedKeys.add(run.key);
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
      final info = getLocalComicInfo(run.task.pathWord);
      _batchRunFailures.add(
        _BatchChapterFailure(
          task: run.task,
          comicName: info?.comic.name ?? run.task.pathWord,
          cover: info?.comic.cover,
        ),
      );
    }
    _signalScheduler();
  }

  /// 全局图片 worker：跨章节领取页任务；队列排空且调度器收尾后退出。
  Future<void> _imageWorker() async {
    while (true) {
      if (_imageJobs.isEmpty) {
        if (_schedulerDone) return;
        final wake = _jobWake ??= Completer<void>();
        await wake.future;
        continue;
      }
      final job = _imageJobs.removeAt(0);
      await _processImageJob(job);
    }
  }

  void _wakeImageWorkers() {
    final wake = _jobWake;
    if (wake != null && !wake.isCompleted) wake.complete();
    _jobWake = null;
  }

  /// 处理单个页任务：下载并记录结果与进度；章节最后一页完成时触发收尾。
  Future<void> _processImageJob(_ImageJob job) async {
    final run = job.run;
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

  /// 队列剩余任务全部处于自动重试退避窗口内时，等待最早到期时间；
  /// 期间新任务入队（[_signalScheduler]）则提前返回。
  Future<void> _waitForNextEligible() async {
    final now = DateTime.now();
    DateTime? earliest;
    for (final task in _queue) {
      final notBefore = task.notBefore;
      if (notBefore == null || !notBefore.isAfter(now)) return;
      if (earliest == null || notBefore.isBefore(earliest)) {
        earliest = notBefore;
      }
    }
    final wait = earliest?.difference(now);
    if (wait == null || wait <= Duration.zero) return;

    final wake = _newSchedulerWait();
    try {
      await Future.any<void>([wake.future, Future<void>.delayed(wait)]);
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

  // 详情已就绪、待派发图片任务；图片任务严格串章派发。
  bool readyToDispatch = false;

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
