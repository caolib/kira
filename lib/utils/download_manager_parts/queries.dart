part of '../download_manager.dart';

extension DownloadManagerQueriesPart on DownloadManager {
  /// 用户自定义的下载根目录；null 表示使用应用内部默认目录。
  String? get customSaveDirectory => _customSaveDirectory;

  /// 当前生效的下载根目录路径；初始化完成前为 null。
  String? get rootPath => _rootDirectory?.path;

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

  /// 按下载时记录的分组返回章节列表，用于本地详情页分区展示。
  /// 每个元素是一组：`(group, chapters)`，组内排序同 [downloadedChapters]。
  List<({String group, List<DownloadedChapterSummary> chapters})>
  downloadedChaptersGrouped(String pathWord) {
    final all = downloadedChapters(pathWord);
    final grouped = <String, List<DownloadedChapterSummary>>{};
    for (final chapter in all) {
      grouped.putIfAbsent(chapter.chapterGroup, () => []).add(chapter);
    }
    return grouped.entries
        .map((e) => (group: e.key, chapters: e.value))
        .toList();
  }

  bool isDownloaded(String pathWord, String chapterUuid) =>
      _manifest[pathWord]?.containsKey(chapterUuid) == true;

  bool isQueued(String pathWord, String chapterUuid) =>
      _queuedKeys.contains(_taskKey(pathWord, chapterUuid));

  bool isDownloading(String pathWord, String chapterUuid) =>
      _activeKeys.contains(_taskKey(pathWord, chapterUuid));

  ChapterDownloadProgress? progressOf(String pathWord, String chapterUuid) =>
      _activeProgress[_taskKey(pathWord, chapterUuid)];

  /// 该章节是否为部分下载（仍有未下载页，可重试补全）。
  bool isPartial(String pathWord, String chapterUuid) =>
      _manifest[pathWord]?[chapterUuid]?.isPartial ?? false;

  /// 获取指定章节的部分失败页数；未下载或完整下载返回 0。
  int failedCountOf(String pathWord, String chapterUuid) =>
      _manifest[pathWord]?[chapterUuid]?.failedIndices.length ?? 0;

  /// 重试补全已部分下载章节的失败页：仅下载失败的那几页，成功页直接复用。
  ///
  /// 返回 true 表示已入队；false 表示无记录、已是完整下载或在队列中。
  Future<bool> retryChapter(String pathWord, String chapterUuid) async {
    await init();
    final summary = _manifest[pathWord]?[chapterUuid];
    if (summary == null || !summary.isPartial) return false;

    final key = _taskKey(pathWord, chapterUuid);
    if (_queuedKeys.contains(key) || _deletingTaskKeys.contains(key)) {
      return false;
    }

    final chapter = Chapter(
      uuid: summary.chapterUuid,
      index: summary.chapterIndex,
      name: summary.chapterName,
      ordered: summary.chapterOrder,
    );
    _queue.add(
      _DownloadTask(
        pathWord: pathWord,
        group: summary.chapterGroup,
        chapter: chapter,
        isRetry: true,
      ),
    );
    _queuedKeys.add(key);
    _notifyListeners();
    unawaited(_persistQueueState());
    _signalScheduler();
    _ensureProcessing();
    return true;
  }

  int pendingCountForComic(String pathWord) {
    var count = 0;
    for (final key in _queuedKeys) {
      if (_decodeTaskKey(key).pathWord == pathWord) {
        count++;
      }
    }
    return count;
  }

  /// 该章节目录下已下载的图片文件数（用于删除任务前提示）。
  /// 队列中未开始的任务返回 0。
  Future<int> downloadedFileCountOf(String pathWord, String chapterUuid) async {
    await init();
    final dir = _chapterDirectory(pathWord, chapterUuid);
    if (!await dir.exists()) return 0;
    var count = 0;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last.toLowerCase();
      if (name == DownloadManager._chapterMetaFileName) continue;
      final dot = name.lastIndexOf('.');
      if (dot > 0 &&
          DownloadManager._imageExtensions.values.contains(
            name.substring(dot),
          )) {
        count++;
      }
    }
    return count;
  }

  /// 一键重试上一批次的失败章节：全部重新入队并重置尝试次数。
  ///
  /// 返回成功入队的数量；原失败汇总随之清除。
  Future<int> retryFailedBatch() async {
    await init();
    if (_batchFailures.isEmpty) return 0;

    var added = 0;
    for (final failure in _batchFailures) {
      final task = failure.task;
      final key = _taskKey(task.pathWord, task.chapter.uuid);
      if (_queuedKeys.contains(key) || _deletingTaskKeys.contains(key)) {
        continue;
      }
      if (!task.isRetry && isDownloaded(task.pathWord, task.chapter.uuid)) {
        continue;
      }
      _queue.add(
        _DownloadTask(
          pathWord: task.pathWord,
          group: task.group,
          chapter: task.chapter,
          isRetry: task.isRetry,
        ),
      );
      _queuedKeys.add(key);
      added++;
    }

    // 失败章节已重新入队或均已无效，原汇总不再展示。
    _batchFailures = const [];
    _lastBatchSummary = null;
    _notifyListeners();
    unawaited(_persistQueueState());
    if (added > 0) {
      _signalScheduler();
      _ensureProcessing();
    }
    return added;
  }

  Future<int> enqueueChapters({
    required String pathWord,
    required Comic comic,
    required Iterable<Chapter> chapters,
    String group = 'default',
  }) async {
    await init();

    // 按话数升序入队：无论列表当前正序还是逆序展示，先下载靠前的章节。
    final ordered = chapters.toList()
      ..sort(DownloadManager.chapterDownloadOrder);

    var added = 0;
    for (final chapter in ordered) {
      if (chapter.uuid.isEmpty || isDownloaded(pathWord, chapter.uuid)) {
        continue;
      }

      final key = _taskKey(pathWord, chapter.uuid);
      if (_queuedKeys.contains(key) || _deletingTaskKeys.contains(key)) {
        continue;
      }

      _queue.add(
        _DownloadTask(pathWord: pathWord, group: group, chapter: chapter),
      );
      _queuedKeys.add(key);
      added++;
    }

    if (added > 0) {
      _batchFailures = const [];
      _lastBatchSummary = null;
      // 章节先入队并立刻通知 UI，漫画元数据/封面在后台准备，
      // 避免点击下载后因等待封面等网络请求产生停顿。
      _notifyListeners();
      unawaited(_persistQueueState());
      _signalScheduler();
      _ensureProcessing();
      _scheduleComicPrepare(pathWord, comic);
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
      // 部分下载章节：失败页的 contents 为空串、文件不存在，属正常；
      // 但 manifest 标记为已下载的页若文件丢失则视为损坏，清理。
      final failed =
          _manifest[pathWord]?[chapterUuid]?.failedIndices.toSet() ??
          const <int>{};
      for (var i = 0; i < detail.contents.length; i++) {
        if (failed.contains(i)) continue;
        final p = detail.contents[i];
        if (p.isEmpty || !await File(p).exists()) {
          await _removeDownloadedChapter(
            pathWord,
            chapterUuid,
            deleteFiles: true,
          );
          return null;
        }
      }
      return detail;
    } catch (e) {
      debugPrint('Read downloaded chapter failed: $e');
      await _removeDownloadedChapter(pathWord, chapterUuid, deleteFiles: true);
      return null;
    }
  }
}
