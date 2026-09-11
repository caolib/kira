part of '../download_manager.dart';

extension DownloadManagerContentDownloadPart on DownloadManager {
  /// 从已存在的 chapter.json 读取评论（重试时复用，不重新拉取）。
  Future<({List<ChapterComment> list, int total})> _loadExistingComments(
    String pathWord,
    String chapterUuid,
  ) async {
    final file = _chapterMetadataFile(pathWord, chapterUuid);
    if (!await file.exists()) {
      return (list: const <ChapterComment>[], total: 0);
    }
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return (list: const <ChapterComment>[], total: 0);
      }
      final list =
          (decoded['comments'] as List?)
              ?.map(
                (item) => ChapterComment.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList() ??
          const <ChapterComment>[];
      final total = (decoded['comment_total'] as num?)?.toInt() ?? list.length;
      return (list: list, total: total);
    } catch (e, st) {
      unawaited(AppLogger.instance.recordWarning(e, stackTrace: st));
      return (list: const <ChapterComment>[], total: 0);
    }
  }

  /// 下载章节评论：默认仅取第一页（避免整章评论下载量过大、耗时过长）。
  Future<({List<ChapterComment> list, int total})> _downloadComments(
    String chapterUuid,
  ) async {
    final data = await _api.manga.getChapterComments(chapterUuid, limit: 100);
    return (list: data.list, total: data.total);
  }

  /// 并发下载一章内的所有图片，保留文件名顺序（001, 002, ...）。
  ///
  /// [existing] 中非空的项视为已下载，直接复用其路径并跳过下载；为 null 的项
  /// 才进入下载队列。任一图片重试耗尽后仍失败时记为 null（不抛错），整章以
  /// partial 状态返回，由调用方决定是否持久化失败索引。
  /// 进度通过 [_activeProgress] 实时上报。
  Future<List<String?>> _downloadImages(
    List<String> imageUrls,
    Directory chapterDir, {
    List<String?> existing = const [],
  }) async {
    final total = imageUrls.length;
    final result = List<String?>.filled(total, null);

    var completed = 0;
    var failed = 0;
    // 仅下载 existing 中为 null（未下载）的页。
    final pending = <int>[];
    for (var i = 0; i < total; i++) {
      final existingPath = i < existing.length ? existing[i] : null;
      if (existingPath != null && existingPath.isNotEmpty) {
        result[i] = existingPath;
        completed++;
      } else {
        pending.add(i);
      }
    }

    var next = 0; // 下一个待分配的 pending 位置

    // worker 协程：循环领取并下载尚未处理的图片，直到全部派发完。
    Future<void> worker() async {
      while (true) {
        final pos = next;
        next++;
        if (pos >= pending.length) return;
        final index = pending[pos];
        try {
          final file = await _downloadImage(
            imageUrls[index],
            chapterDir,
            index + 1,
          );
          result[index] = file.path;
          completed++;
        } catch (e, st) {
          // 单张失败不中断整章；记为 null，由调用方收集为 failedIndices。
          failed++;
          unawaited(
            AppLogger.instance.recordWarning(
              'Image #$index download failed: $e',
              stackTrace: st,
            ),
          );
        }
        _activeProgress = ChapterDownloadProgress(
          completed: completed,
          total: total,
          failed: failed,
        );
        _notifyListeners();
      }
    }

    final workerCount = _imageDownloadConcurrency.clamp(
      1,
      pending.isNotEmpty ? pending.length : 1,
    );
    final workers = List.generate(workerCount, (_) => worker());
    await Future.wait(workers);
    return result;
  }

  Future<File> _downloadImage(
    String imageUrl,
    Directory chapterDir,
    int index,
  ) async {
    Object? lastError;
    for (
      var attempt = 0;
      attempt <= DownloadManager._imageMaxRetries;
      attempt++
    ) {
      try {
        return await _downloadImageOnce(imageUrl, chapterDir, index);
      } catch (e) {
        lastError = e;
        // 写到一半的文件可能不完整，删除后重试。
        final ext = _guessExtensionFromUrl(imageUrl);
        final partial = File(
          DownloadManager._joinPath([
            chapterDir.path,
            '${index.toString().padLeft(3, '0')}$ext',
          ]),
        );
        try {
          if (await partial.exists()) await partial.delete();
        } catch (e, st) {
          unawaited(AppLogger.instance.recordWarning(e, stackTrace: st));
        }
      }
    }
    throw HttpException('Image download failed after retries: $lastError');
  }

  String _guessExtensionFromUrl(String imageUrl) {
    final uri = Uri.parse(imageUrl);
    final lastSegment = uri.pathSegments.isNotEmpty
        ? uri.pathSegments.last
        : uri.path;
    final dotIndex = lastSegment.lastIndexOf('.');
    if (dotIndex > 0) {
      final ext = lastSegment.substring(dotIndex).toLowerCase();
      if (RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(ext)) return ext;
    }
    return '.jpg';
  }

  Future<File> _downloadImageOnce(
    String imageUrl,
    Directory chapterDir,
    int index,
  ) async {
    final uri = Uri.parse(imageUrl);
    final request = await _httpClient
        .getUrl(uri)
        .timeout(DownloadManager._timeout);
    final response = await request.close().timeout(DownloadManager._timeout);

    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Image download failed (${response.statusCode})',
        uri: uri,
      );
    }

    final extension = _resolveImageExtension(uri, response);
    final file = File(
      DownloadManager._joinPath([
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

  String _resolveImageExtension(Uri uri, HttpClientResponse response) {
    final mimeType = response.headers.contentType?.mimeType.toLowerCase();
    if (mimeType != null &&
        DownloadManager._imageExtensions.containsKey(mimeType)) {
      return DownloadManager._imageExtensions[mimeType]!;
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
}
