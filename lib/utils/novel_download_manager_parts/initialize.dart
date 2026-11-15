part of '../novel_download_manager.dart';

extension NovelDownloadManagerInitializePart on NovelDownloadManager {
  Future<void> _initialize() async {
    if (maxAttempts < 1) throw ArgumentError.value(maxAttempts, 'maxAttempts');
    _prefs = await _preferences();
    _concurrency = (_prefs!.getInt(NovelDownloadManager.concurrencyKey) ?? 2)
        .clamp(1, 32);
    _customSaveDirectory = AppPlatform.supportsCustomDownloadDirectory
        ? _prefs!
              .getString(NovelDownloadManager.saveDirectoryKey)
              ?.trim()
              .nullIfEmpty()
        : null;
    if (_customSaveDirectory case final custom?) {
      try {
        final canonical = await _validateRoot(custom);
        await NovelDownloadStore.probeDirectory(canonical);
        await store.init(rootPath: canonical);
      } catch (error, stack) {
        directoryError = '小说下载目录不可用，已回退默认目录';
        NovelDownloadManager._log(error, stack);
        await store.init(rootPath: await _validateRoot(await _defaultRoot()));
      }
    } else {
      await store.init(rootPath: await _validateRoot(await _defaultRoot()));
    }
    _identity = _identityProvider();
    _identityEpoch = _readEpoch();
    _listeningTo =
        _identityChanges ?? (_snapshotLoader == null ? UserManager() : null);
    _listeningTo?.addListener(refreshIdentity);
    final raw = _prefs!.getString(NovelDownloadManager.queueStateKey);
    var queueReconciled = false;
    if (raw != null) {
      try {
        final json = jsonMap({'v': jsonDecode(raw)}, 'v');
        if (json == null ||
            jsonInt(json, 'version') != 1 ||
            json['tasks'] is! List) {
          throw const FormatException('小说下载队列无效');
        }
        _paused = jsonBool(json, 'paused');
        for (final rawTask in jsonList(json, 'tasks')) {
          try {
            final json = jsonMap({'v': rawTask}, 'v');
            if (json == null) throw const FormatException('小说下载任务无效');
            final task = NovelDownloadTask.fromJson(json);
            final local = store
                .getLocalNovelInfo(task.pathWord)
                ?.downloaded[task.volumeId];
            if (local?.isDownloaded == true) {
              // Store.init has verified the files. Drop legacy completed tasks
              // and stale queue entries left between saving files and dequeueing.
              queueReconciled = true;
              continue;
            } else if (task.status == NovelDownloadStatus.completed) {
              task.status = NovelDownloadStatus.needsRepair;
              queueReconciled = true;
            } else if (!_matchesSource(task.source)) {
              task.status = NovelDownloadStatus.paused;
            } else if (task.status == NovelDownloadStatus.downloading ||
                task.status == NovelDownloadStatus.queued) {
              task.status = task.attempts >= maxAttempts
                  ? (local?.isReadable == true
                        ? NovelDownloadStatus.partial
                        : NovelDownloadStatus.failed)
                  : (_paused
                        ? NovelDownloadStatus.paused
                        : NovelDownloadStatus.queued);
            }
            _tasks.putIfAbsent(task.id, () => task);
          } catch (error, stack) {
            persistenceError = '部分小说下载任务损坏，已忽略';
            NovelDownloadManager._log(error, stack);
          }
        }
      } catch (error, stack) {
        persistenceError = '小说下载队列损坏，本地下载文件已保留';
        NovelDownloadManager._log(error, stack);
      }
    }
    if (queueReconciled) {
      // A paused queue never reaches _pump's persistence path.
      await _persist().catchError((Object error, StackTrace stack) {
        NovelDownloadManager._log(error, stack);
      });
    }
    _initialized = true;
    _notify();
    _pump();
  }
}
