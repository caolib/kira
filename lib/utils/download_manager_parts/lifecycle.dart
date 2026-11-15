part of '../download_manager.dart';

extension DownloadManagerLifecyclePart on DownloadManager {
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
    await _loadFromPrefs(prefs);
    _initialized = true;

    // 重启后续传:恢复的队列立即继续下载(此前已暂停则保持暂停)。
    _ensureProcessing();
  }

  /// 从 prefs 重建根目录、清单与队列,等价于一次冷启动的加载。
  ///
  /// 冷启动([_initialize])与导入备份后的重载([reloadFromPrefs])共用同一
  /// 条路径:两者都必须把内存态当成空的重新填充,否则旧数据会残留。
  Future<void> _loadFromPrefs(SharedPreferences prefs) async {
    // 等待在途的持久化写入落盘,避免旧快照晚于本次重载写入。
    await _queueStateWriteTail;
    await _manifestWriteTail;

    _customSaveDirectory = AppPlatform.supportsCustomDownloadDirectory
        ? DownloadManager.normalizeDirectoryPath(
            prefs.getString(DownloadManager._keySaveDirectory),
          )
        : null;
    _rootDirectory = _rootDirectoryProvider == null
        ? await DownloadManager.resolveRootDirectory(
            customPath: _customSaveDirectory,
            defaultParentPath: (await getApplicationDocumentsDirectory()).path,
          )
        : await _rootDirectoryProvider();
    await _rootDirectory!.create(recursive: true);

    _applyScalarSettings(prefs);

    // 清空内存态:重载时必须从空的 manifest/队列重新填充,否则会与
    // 导入进来的新数据混合。
    _manifest.clear();
    _queue.clear();
    _queuedKeys.clear();
    _pausedTaskKeys.clear();
    _cancelledTaskKeys.clear();
    _paused = false;
    _batchRunFailures = [];
    _batchFailures = const [];
    _lastBatchSummary = null;
    _batchSucceeded = 0;

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
  }
}
