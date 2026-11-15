import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/novel/novel_api.dart';
import '../models/download_activity_snapshot.dart';
import '../models/novel.dart';
import '../models/novel_download.dart';
import '../models/novel_volume_snapshot.dart';
import '../models/user_manager.dart';
import '../repositories/novel_repository.dart';
import 'app_logger.dart';
import 'app_platform.dart';
import 'download_manager.dart';
import 'json_helpers.dart';
import 'network_error.dart';
import 'novel_download_store.dart';

export '../models/novel_download.dart';

part 'novel_download_manager_parts/initialize.dart';
part 'novel_download_manager_parts/run_loop.dart';

typedef NovelSnapshotLoader =
    Future<NovelVolumeSnapshot> Function(
      String pathWord,
      String volumeId, {
      required CancelToken cancelToken,
    });
typedef NovelImageLoader =
    Future<List<int>> Function(String url, {required CancelToken cancelToken});

/// One queue for both provider and legacy callers. Reader access goes straight to
/// [store]; task cancellation never cancels a shared repository/reader request.
class NovelDownloadManager extends ChangeNotifier {
  static final NovelDownloadManager _instance = NovelDownloadManager._();
  factory NovelDownloadManager() => _instance;

  NovelDownloadManager._({
    NovelDownloadStore? store,
    NovelSnapshotLoader? snapshotLoader,
    NovelImageLoader? imageLoader,
    NovelDownloadIdentity Function()? identityProvider,
    String? Function(String?)? accountIdResolver,
    Object Function()? identityEpochProvider,
    Listenable? identityChanges,
    Future<SharedPreferences> Function()? preferences,
    Future<List<String>> Function()? protectedRoots,
    Future<String> Function()? defaultRoot,
    this.maxAttempts = 3,
    this.retryDelay = const Duration(seconds: 2),
  }) : store = store ?? NovelDownloadStore(),
       _snapshotLoader = snapshotLoader,
       _imageLoader = imageLoader,
       _identityProvider = identityProvider ?? _currentIdentity,
       _accountIdResolver =
           accountIdResolver ??
           ((id) => UserManager().copyAccount.resolveAccountId(id)),
       _identityEpochProvider = identityEpochProvider,
       _identityChanges = identityChanges,
       _preferences = preferences ?? SharedPreferences.getInstance,
       _protectedRoots = protectedRoots ?? _comicRoots,
       _defaultRoot = defaultRoot ?? store?.defaultRootPath ?? defaultRootPath;

  @visibleForTesting
  NovelDownloadManager.forTesting({
    required NovelDownloadStore store,
    required NovelSnapshotLoader snapshotLoader,
    required NovelImageLoader imageLoader,
    required NovelDownloadIdentity Function() identityProvider,
    String? Function(String?)? accountIdResolver,
    Object Function()? identityEpochProvider,
    Listenable? identityChanges,
    Future<SharedPreferences> Function()? preferences,
    Future<List<String>> Function()? protectedRoots,
    Future<String> Function()? defaultRoot,
    int maxAttempts = 3,
    Duration retryDelay = Duration.zero,
  }) : this._(
         store: store,
         snapshotLoader: snapshotLoader,
         imageLoader: imageLoader,
         identityProvider: identityProvider,
         // Fake identities must never consult the real account store.
         accountIdResolver: accountIdResolver ?? ((id) => id),
         identityEpochProvider: identityEpochProvider,
         identityChanges: identityChanges,
         preferences: preferences,
         protectedRoots: protectedRoots ?? (() async => []),
         defaultRoot: defaultRoot,
         maxAttempts: maxAttempts,
         retryDelay: retryDelay,
       );

  static const queueStateKey = 'download_novel_queue_state_v1';
  static const concurrencyKey = 'download_novel_concurrency';
  static const saveDirectoryKey = 'download_novel_save_directory';
  final NovelDownloadStore store;
  final NovelSnapshotLoader? _snapshotLoader;
  final NovelImageLoader? _imageLoader;
  final NovelDownloadIdentity Function() _identityProvider;
  final String? Function(String?) _accountIdResolver;
  final Object Function()? _identityEpochProvider;
  final Listenable? _identityChanges;
  final Future<SharedPreferences> Function() _preferences;
  final Future<List<String>> Function() _protectedRoots;
  final Future<String> Function() _defaultRoot;
  final int maxAttempts;
  final Duration retryDelay;
  late final NovelRepository _repository = NovelRepository(
    api: ApiClient().novel,
  );
  final _tasks = <String, NovelDownloadTask>{};
  final _runs = <String, _NovelRun>{};
  final _epochs = <String, int>{};
  final _deleting = <String>{};
  final _deletingBooks = <String>{};
  Future<void> _queueTail = Future.value();
  Future<void>? _initializing;
  SharedPreferences? _prefs;
  Listenable? _listeningTo;
  NovelDownloadIdentity? _identity;
  Object? _identityEpoch;
  bool _initialized = false;
  bool _disposed = false;
  bool _paused = false;
  bool _relocating = false;
  int _concurrency = 2;
  String? _customSaveDirectory;
  String? persistenceError;
  String? directoryError;

  /// Unfinished work only; completed downloads remain in [store].
  List<NovelDownloadTask> get tasks => List.unmodifiable(_tasks.values);
  bool get paused => _paused;
  bool get isInitialized => _initialized;
  bool get isMigrating => _relocating || store.isMigrating;
  bool get isDownloading => _runs.isNotEmpty;
  int get activeCount => _runs.length;
  int get queuedCount =>
      _tasks.values.where((t) => t.status == NovelDownloadStatus.queued).length;
  int get concurrency => _concurrency;
  String? get rootPath => store.rootPath;
  String? get customSaveDirectory => _customSaveDirectory;
  List<LocalNovelInfo> get localNovels => store.localNovels;

  DownloadActivitySnapshot get activity {
    var active = 0;
    var pending = 0;
    var completed = 0;
    var total = 0;
    for (final task in _tasks.values) {
      switch (task.status) {
        case NovelDownloadStatus.downloading:
          active++;
        case NovelDownloadStatus.queued:
          pending++;
        case NovelDownloadStatus.paused:
        case NovelDownloadStatus.completed:
        case NovelDownloadStatus.partial:
        case NovelDownloadStatus.failed:
        case NovelDownloadStatus.unauthorized:
        case NovelDownloadStatus.locked:
        case NovelDownloadStatus.needsRepair:
          break;
      }
      if (task.status == NovelDownloadStatus.downloading ||
          task.status == NovelDownloadStatus.queued) {
        completed += task.completed;
        total += task.total;
      }
    }
    return DownloadActivitySnapshot(
      active: active,
      pending: pending,
      completed: completed,
      total: total,
    );
  }

  static NovelDownloadIdentity _currentIdentity() {
    final user = UserManager();
    return NovelDownloadIdentity(
      host: user.copyApiHost,
      accountId: user.copyAccount.session?.id ?? 'guest',
    );
  }

  /// Resolve only stable task ownership, never the identity/epoch of a live run.
  /// Keep the original source so deleting an alias also revokes queued work.
  bool _matchesSource(NovelDownloadIdentity source) {
    final current = _identityProvider();
    if (source.host != current.host) return false;
    if (source.accountId == 'guest' || current.accountId == 'guest') {
      return source.accountId == current.accountId;
    }
    final accountId = _accountIdResolver(source.accountId);
    return accountId != null &&
        accountId == _accountIdResolver(current.accountId);
  }

  Object _readEpoch() =>
      _identityEpochProvider?.call() ??
      (_snapshotLoader == null
          ? (UserManager().copyAccount.revision, UserManager().copyToken)
          : _identityProvider());

  static Future<String> defaultRootPath() async => p.join(
    (await getApplicationDocumentsDirectory()).path,
    NovelDownloadStore.directoryName,
  );

  static Future<List<String>> _comicRoots() async {
    final prefs = await SharedPreferences.getInstance();
    return [
      p.join(
        (await getApplicationDocumentsDirectory()).path,
        'comic_downloads',
      ),
      ?DownloadManager().rootPath,
      if (prefs.getString('download_save_directory') case final path?)
        if (path.trim().isNotEmpty) path,
    ];
  }

  /// Default and effective roots for the comic directory's reciprocal protection.
  Future<List<String>> protectedRootPaths() async => [
    await _defaultRoot(),
    ?rootPath,
    ?_customSaveDirectory,
  ];

  Future<void> init() {
    if (_initialized) return Future.value();
    return _initializing ??= _initialize().whenComplete(
      () => _initializing = null,
    );
  }

  NovelDownloadTask? taskFor(String pathWord, String volumeId) =>
      _tasks[_key(pathWord, volumeId)];
  NovelDownloadStatus? statusOf(String pathWord, String volumeId) =>
      taskFor(pathWord, volumeId)?.status ??
      store.getLocalNovelInfo(pathWord)?.downloaded[volumeId]?.status;
  bool isVolumeDownloaded(String pathWord, String volumeId) =>
      store.downloadedVolumes(pathWord).contains(volumeId);
  bool isVolumeQueued(String pathWord, String volumeId) =>
      switch (taskFor(pathWord, volumeId)?.status) {
        NovelDownloadStatus.queued ||
        NovelDownloadStatus.downloading ||
        NovelDownloadStatus.paused => true,
        _ => false,
      };
  bool isVolumePaused(String pathWord, String volumeId) =>
      taskFor(pathWord, volumeId)?.status == NovelDownloadStatus.paused;

  /// 本机已保存（含待修复）的卷 id；本地详情页据此判断是否已被整体删除。
  Set<String> localVolumeIds(String pathWord) =>
      store.getLocalNovelInfo(pathWord)?.downloaded.keys.toSet() ?? const {};

  /// 单本本机小说信息（离线目录 + 已下载分卷）。
  LocalNovelInfo? localInfo(String pathWord) =>
      store.getLocalNovelInfo(pathWord);

  /// 按原目录正序展示可阅读（完整或部分完成）与待修复的本地卷。
  List<NovelVolume> localVolumes(String pathWord) {
    final info = store.getLocalNovelInfo(pathWord);
    if (info == null) return const [];
    // 目录可能更新并移除旧卷，仍保留这些已经下载的内容。
    final orderedIds = {
      for (final volume in info.volumes) volume.id,
      ...info.downloaded.keys,
    };
    return [
      for (final id in orderedIds)
        if (info.downloaded[id] case final entry?)
          if (entry.isReadable || entry.needsRepair) entry.volume,
    ];
  }

  LocalNovelVolumeInfo? localVolumeInfo(String pathWord, String volumeId) =>
      store.getLocalNovelInfo(pathWord)?.downloaded[volumeId];

  /// 重新下载一个本机已有（但损坏或缺少插图）的卷。
  ///
  /// 与 [retry] 不同，这里不依赖队列里仍存在任务：本地详情页在应用重启后
  /// 只能看到磁盘上的记录，需要按卷重新入队。
  Future<void> requeueVolume(String pathWord, String volumeId) async {
    await init();
    _checkAvailable();
    final info = store.getLocalNovelInfo(pathWord);
    final volume = info?.downloaded[volumeId]?.volume;
    if (info == null || volume == null) {
      throw ArgumentError.value(pathWord, 'pathWord', '本地小说或分卷不存在');
    }
    // 服务端不提供字节范围续传，整卷重下：先丢弃本机文件与旧任务，
    // 避免旧记录让 enqueueVolumes 判为已下载而跳过。
    await deleteVolume(pathWord, volumeId);
    await enqueueVolumes(
      book: info.book,
      volumes: info.volumes,
      selected: [volume],
    );
  }

  Future<void> enqueueVolumes({
    required NovelBook book,
    required List<NovelVolume> volumes,
    required Iterable<NovelVolume> selected,
  }) async {
    await init();
    _checkAvailable();
    refreshIdentity();
    if (book.pathWord.isEmpty || volumes.any((v) => v.id.isEmpty)) {
      throw ArgumentError('小说书籍或卷标识为空');
    }
    final source = _identityProvider();
    final sourceEpoch = _readEpoch();
    final selectedIds = selected.map((v) => v.id).toSet();
    for (final volume in volumes) {
      if (!selectedIds.contains(volume.id) ||
          _deletingBooks.contains(book.pathWord)) {
        continue;
      }
      final key = _key(book.pathWord, volume.id);
      if (_deleting.contains(key) || isVolumeQueued(book.pathWord, volume.id)) {
        continue;
      }
      // Revalidate disk, rather than trusting a stale completion badge.
      await store.readVolumeSnapshot(book.pathWord, volume.id);
      _checkAvailable();
      if (source != _identityProvider() || sourceEpoch != _readEpoch()) {
        refreshIdentity();
        throw const NovelIdentityChangedException();
      }
      if (_deleting.contains(key) ||
          _deletingBooks.contains(book.pathWord) ||
          isVolumeQueued(book.pathWord, volume.id)) {
        continue;
      }
      if (store.downloadedVolumes(book.pathWord).contains(volume.id)) continue;
      _tasks[key] = NovelDownloadTask(
        book: book,
        volume: volume,
        volumes: List.unmodifiable(volumes),
        source: _identityProvider(),
        status: _paused
            ? NovelDownloadStatus.paused
            : NovelDownloadStatus.queued,
      );
    }
    await _persist();
    _notify();
    _pump();
  }

  /// A revision change pauses unfinished work, even after A -> B -> A. A later
  /// explicit resume may use a refreshed token belonging to the same stable ID.
  void refreshIdentity() {
    if (!_initialized || _disposed) return;
    final identity = _identityProvider();
    final epoch = _readEpoch();
    if (identity == _identity && epoch == _identityEpoch) return;
    _identity = identity;
    _identityEpoch = epoch;
    for (final task in _tasks.values) {
      if (task.isComplete) continue;
      _invalidate(task.id);
      task.status = NovelDownloadStatus.paused;
      task.error = '拷贝账号或线路已变更，请使用原来源恢复下载';
    }
    _changed();
  }

  Future<void> pauseVolume(String pathWord, String volumeId) async {
    await init();
    final task = taskFor(pathWord, volumeId);
    if (task == null || task.isComplete) return;
    _invalidate(task.id);
    task.status = NovelDownloadStatus.paused;
    _changed();
    await store.waitForWrites();
    await _queueTail;
  }

  Future<void> resumeVolume(String pathWord, String volumeId) async {
    await init();
    _checkAvailable();
    refreshIdentity();
    final task = taskFor(pathWord, volumeId);
    if (task == null || task.isComplete || task.isActive) return;
    if (!_matchesSource(task.source)) {
      task.status = NovelDownloadStatus.paused;
      task.error = '请切回此任务的拷贝账号及线路';
    } else {
      task.status = NovelDownloadStatus.queued;
      task.attempts = 0;
      task.error = null;
    }
    await _persist();
    _notify();
    _pump();
  }

  Future<void> pauseVolumes(String pathWord, Iterable<String> volumeIds) async {
    await Future.wait([for (final id in volumeIds) pauseVolume(pathWord, id)]);
  }

  Future<void> resumeVolumes(
    String pathWord,
    Iterable<String> volumeIds,
  ) async {
    for (final id in volumeIds) {
      await resumeVolume(pathWord, id);
    }
  }

  Future<void> pauseDownloads() async {
    await init();
    _paused = true;
    for (final task in _tasks.values) {
      if (task.isComplete) continue;
      _invalidate(task.id);
      task.status = NovelDownloadStatus.paused;
    }
    _changed();
    await store.waitForWrites();
    await _queueTail;
  }

  Future<void> resumeDownloads() async {
    await init();
    _checkAvailable();
    refreshIdentity();
    _paused = false;
    for (final task in _tasks.values) {
      if (task.status == NovelDownloadStatus.paused &&
          _matchesSource(task.source)) {
        task.status = NovelDownloadStatus.queued;
        task.attempts = 0;
        task.error = null;
      }
    }
    await _persist();
    _notify();
    _pump();
  }

  Future<void> retry(String pathWord, String volumeId) =>
      resumeVolume(pathWord, volumeId);
  Future<void> retryFailed() async {
    for (final task in tasks) {
      if ({
        NovelDownloadStatus.failed,
        NovelDownloadStatus.partial,
        NovelDownloadStatus.needsRepair,
        NovelDownloadStatus.unauthorized,
        NovelDownloadStatus.locked,
      }.contains(task.status)) {
        await retry(task.pathWord, task.volumeId);
      }
    }
  }

  Future<void> deleteVolume(String pathWord, String volumeId) async {
    await init();
    _checkAvailable();
    final key = _key(pathWord, volumeId);
    if (!_deleting.add(key)) return;
    try {
      _invalidate(key);
      _tasks.remove(key);
      _changed();
      await store.waitForWrites();
      await store.deleteVolume(pathWord, volumeId);
      await _persist();
      // 删掉最后一卷后书条目会变成"0 卷空壳"：下载中心仍显示卡片，
      // 点进本地详情会永远转圈——没有本地卷且没有任务时移除书条目。
      // 重新下载时 saveSnapshot 会 putIfAbsent 重建条目。
      final hasLocalVolumes =
          store.getLocalNovelInfo(pathWord)?.downloaded.isNotEmpty ?? false;
      final hasBookTasks = _tasks.values.any(
        (task) => task.pathWord == pathWord,
      );
      if (!hasLocalVolumes && !hasBookTasks) {
        await store.deleteNovel(pathWord);
      }
    } finally {
      _deleting.remove(key);
      _notify();
      _pump();
    }
  }

  Future<void> deleteVolumes(
    String pathWord,
    Iterable<String> volumeIds,
  ) async {
    for (final id in volumeIds.toList()) {
      await deleteVolume(pathWord, id);
    }
  }

  Future<void> deleteNovel(String pathWord) async {
    await init();
    _checkAvailable();
    if (!_deletingBooks.add(pathWord)) return;
    try {
      final ids = <String>{
        ...?store.getLocalNovelInfo(pathWord)?.downloaded.keys,
        for (final task in tasks)
          if (task.pathWord == pathWord) task.volumeId,
      };
      await deleteVolumes(pathWord, ids);
      await store.deleteNovel(pathWord);
    } finally {
      _deletingBooks.remove(pathWord);
      _notify();
    }
  }

  Future<void> deleteAll() async {
    final books = <String>{
      for (final task in tasks) task.pathWord,
      for (final book in localNovels) book.pathWord,
    };
    for (final book in books) {
      await deleteNovel(book);
    }
  }

  Future<void> reloadScalarSettings() async {
    final prefs = await _preferences();
    _concurrency = (prefs.getInt(concurrencyKey) ?? 2).clamp(1, 32);
    _notify();
    _pump();
  }

  Future<int> setConcurrency(int value) async {
    await init();
    final next = value.clamp(1, 32);
    if (!await _prefs!.setInt(concurrencyKey, next)) {
      throw StateError('小说下载设置保存失败');
    }
    _concurrency = next;
    _notify();
    _pump();
    return next;
  }

  Future<String> _validateRoot(String path) async {
    final target = await NovelDownloadStore.canonicalDirectory(path);
    for (final root in await _protectedRoots()) {
      if (NovelDownloadStore.pathsOverlap(
        target,
        await NovelDownloadStore.canonicalDirectory(root),
      )) {
        throw ArgumentError('小说与漫画下载目录不能相同或互相包含');
      }
    }
    return target;
  }

  Future<void> setSaveDirectory(
    String? path, {
    void Function(NovelDownloadMigrationProgress progress)? onProgress,
  }) async {
    if (!AppPlatform.supportsCustomDownloadDirectory &&
        path?.trim().nullIfEmpty() != null) {
      throw UnsupportedError('iOS downloads use the application directory');
    }
    await init();
    _checkAvailable();
    if (_runs.isNotEmpty ||
        _deleting.isNotEmpty ||
        _deletingBooks.isNotEmpty ||
        queuedCount > 0) {
      throw StateError('请暂停下载并等待当前写入完成后再迁移目录');
    }
    _relocating = true;
    _notify();
    try {
      final custom = path?.trim().nullIfEmpty();
      final destination = await _validateRoot(custom ?? await _defaultRoot());
      final previous = _prefs!.getString(saveDirectoryKey);
      Future<void> commit(String canonical) async {
        try {
          final saved = custom == null
              ? await _prefs!.remove(saveDirectoryKey)
              : await _prefs!.setString(saveDirectoryKey, canonical);
          if (!saved) throw StateError('小说下载目录设置保存失败');
        } catch (error, stack) {
          try {
            final restored = previous == null
                ? await _prefs!.remove(saveDirectoryKey)
                : await _prefs!.setString(saveDirectoryKey, previous);
            if (!restored) throw StateError('小说下载目录设置回滚失败');
          } catch (rollbackError, rollbackStack) {
            _log(rollbackError, rollbackStack);
          }
          Error.throwWithStackTrace(error, stack);
        }
      }

      if (rootPath != null &&
          p.equals(
            await NovelDownloadStore.canonicalDirectory(rootPath!),
            destination,
          )) {
        await commit(destination);
      } else {
        await store.migrateTo(
          destination,
          commit: commit,
          onProgress: onProgress,
        );
      }
      _customSaveDirectory = custom == null ? null : destination;
      directoryError = null;
    } finally {
      _relocating = false;
      _notify();
      _pump();
    }
  }

  @visibleForTesting
  Future<void> waitForIdle() async {
    while (_runs.isNotEmpty ||
        (!_disposed && !_paused && queuedCount > 0 && !isMigrating)) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await store.waitForWrites();
    await _queueTail;
  }

  Future<void> _persist() {
    final next = _queueTail.then((_) async {
      if (_prefs == null) return;
      final data = jsonEncode({
        'version': 1,
        'paused': _paused,
        'tasks': _tasks.values.map((t) => t.toJson()).toList(),
      });
      if (!await _prefs!.setString(queueStateKey, data)) {
        throw StateError('小说下载队列保存失败');
      }
    });
    _queueTail = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        persistenceError = '小说下载队列保存失败';
        _log(error, stack);
      },
    );
    return next;
  }

  void _changed() {
    _notify();
    unawaited(
      _persist().catchError((Object error, StackTrace stack) {
        _log(error, stack);
      }),
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _checkAvailable() {
    if (_disposed) throw StateError('小说下载管理器已关闭');
    if (isMigrating) throw StateError('小说下载目录正在迁移');
    if (store.hasManifestError) throw StateError(store.manifestError!);
  }

  static String _key(String pathWord, String volumeId) =>
      '$pathWord\n$volumeId';
  static void _log(Object error, StackTrace stack) {
    unawaited(
      AppLogger.instance.recordWarning(
        error,
        stackTrace: stack,
        source: 'novel_download',
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _listeningTo?.removeListener(refreshIdentity);
    for (final run in _runs.values) {
      run.cancel();
    }
    super.dispose();
  }
}

class _NovelRun {
  final int epoch;
  final Object identityEpoch;
  final CancelToken cancelToken = CancelToken();
  final cancelled = Completer<void>();
  _NovelRun(this.epoch, this.identityEpoch);
  void cancel() {
    cancelToken.cancel('novel_task_cancelled');
    if (!cancelled.isCompleted) cancelled.complete();
  }
}
