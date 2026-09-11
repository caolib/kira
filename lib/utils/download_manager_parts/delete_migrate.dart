part of '../download_manager.dart';

extension DownloadManagerDeleteMigratePart on DownloadManager {
  Future<void> deleteChapters(
    String pathWord,
    Iterable<String> chapterUuids,
  ) async {
    await init();
    for (final chapterUuid in chapterUuids.toSet()) {
      await _removeDownloadedChapter(pathWord, chapterUuid, deleteFiles: true);
    }
    if (_manifest[pathWord]?.isEmpty ?? true) {
      await _removeLocalComic(pathWord);
    }
    _notifyListeners();
  }

  Future<void> deleteLocalComics(Iterable<String> pathWords) async {
    await init();
    for (final pathWord in pathWords.toSet()) {
      _manifest.remove(pathWord);
      await _removeLocalComic(pathWord);
    }
    await _persistManifest();
    _notifyListeners();
  }

  /// 变更下载根目录，并把已下载内容迁移过去。
  ///
  /// [path] 传 null 表示恢复默认内部目录。要求队列为空（无下载任务进行中）；
  /// 迁移逐漫画进行并通过 [onProgress] 上报。任一漫画迁移失败会尽力回滚
  /// 已迁移的部分并保持原设置不变（抛出原异常）。
  Future<void> setSaveDirectory(
    String? path, {
    void Function(DownloadMigrationProgress progress)? onProgress,
  }) async {
    await init();
    if (isBusy) {
      throw StateError('Download queue is busy');
    }
    final newCustom = DownloadManager.normalizeDirectoryPath(path);
    if ((newCustom ?? '') == (_customSaveDirectory ?? '')) return;

    final oldRoot = _rootDirectory;
    if (oldRoot == null) throw StateError('DownloadManager not initialized');

    final newRoot = await DownloadManager.resolveRootDirectory(
      customPath: newCustom,
      defaultParentPath: (await getApplicationDocumentsDirectory()).path,
    );
    final oldPath = DownloadManager.normalizeDirectoryPath(oldRoot.path)!;
    final newPath = DownloadManager.normalizeDirectoryPath(newRoot.path)!;
    if (newPath == oldPath) {
      // 目标与当前实际目录一致，仅更新设置（含清理失效的旧自定义值）。
      await _persistSaveDirectory(newCustom);
      _notifyListeners();
      return;
    }
    // 互为父子会导致目录搬进自身，直接拒绝。
    if (newPath.startsWith('$oldPath/') ||
        newPath.startsWith('$oldPath\\') ||
        oldPath.startsWith('$newPath/') ||
        oldPath.startsWith('$newPath\\')) {
      throw ArgumentError('New download directory overlaps the current one');
    }

    try {
      await _migrateRoot(oldRoot, newRoot, onProgress: onProgress);
    } catch (_) {
      // 失败时不落盘新设置，目录解析在下次启动仍会回到旧根。
      rethrow;
    }
    await _persistSaveDirectory(newCustom);
    _rootDirectory = newRoot;
    _notifyListeners();
    // 最后清理旧根的 manifest（尽力而为）：此时新设置已生效，中途崩溃
    // 最坏情况是旧根残留一个不再被读取的 manifest.json。
    final oldManifest = File(
      DownloadManager._joinPath([
        oldRoot.path,
        DownloadManager._manifestFileName,
      ]),
    );
    try {
      if (await oldManifest.exists()) await oldManifest.delete();
    } catch (e, st) {
      unawaited(AppLogger.instance.recordWarning(e, stackTrace: st));
    }
  }

  Future<void> _migrateRoot(
    Directory oldRoot,
    Directory newRoot, {
    void Function(DownloadMigrationProgress progress)? onProgress,
  }) async {
    await newRoot.create(recursive: true);

    final pathWords = _manifest.keys.toList();
    final total = pathWords.length;
    var moved = 0;

    for (final pathWord in pathWords) {
      final fromDir = Directory(
        DownloadManager._joinPath([
          oldRoot.path,
          DownloadManager._safePathSegment(pathWord),
        ]),
      );
      final toDir = Directory(
        DownloadManager._joinPath([
          newRoot.path,
          DownloadManager._safePathSegment(pathWord),
        ]),
      );
      try {
        await DownloadManager.moveDirectory(fromDir, toDir);
        await DownloadManager.rewriteStoredPaths(
          toDir,
          fromRoot: oldRoot.path,
          toRoot: newRoot.path,
        );
      } catch (e, st) {
        unawaited(
          AppLogger.instance.recordWarning(
            'Download migration failed at $pathWord: $e',
            stackTrace: st,
          ),
        );
        await _rollbackMigration(oldRoot, newRoot, pathWords.take(moved));
        rethrow;
      }
      moved++;
      onProgress?.call(
        DownloadMigrationProgress(
          current: moved,
          total: total,
          pathWord: pathWord,
        ),
      );
    }

    // manifest 只含相对标识（pathWord/uuid），整体写入新根即可。
    await File(
      DownloadManager._joinPath([
        newRoot.path,
        DownloadManager._manifestFileName,
      ]),
    ).writeAsString(jsonEncode(_manifestPayload()));
  }

  Future<void> _rollbackMigration(
    Directory oldRoot,
    Directory newRoot,
    Iterable<String> pathWords,
  ) async {
    for (final pathWord in pathWords) {
      try {
        final fromDir = Directory(
          DownloadManager._joinPath([
            newRoot.path,
            DownloadManager._safePathSegment(pathWord),
          ]),
        );
        final toDir = Directory(
          DownloadManager._joinPath([
            oldRoot.path,
            DownloadManager._safePathSegment(pathWord),
          ]),
        );
        await DownloadManager.moveDirectory(fromDir, toDir);
        await DownloadManager.rewriteStoredPaths(
          toDir,
          fromRoot: newRoot.path,
          toRoot: oldRoot.path,
        );
      } catch (e, st) {
        unawaited(
          AppLogger.instance.recordWarning(
            'Download migration rollback failed at $pathWord: $e',
            stackTrace: st,
          ),
        );
      }
    }
  }

  Future<void> _persistSaveDirectory(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(DownloadManager._keySaveDirectory);
    } else {
      await prefs.setString(DownloadManager._keySaveDirectory, value);
    }
    _customSaveDirectory = value;
  }
}
