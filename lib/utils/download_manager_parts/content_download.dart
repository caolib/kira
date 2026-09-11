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
      if (attempt > 0) {
        // 退避后重试；上次因 429 被限流时加倍等待。
        await Future<void>.delayed(
          DownloadManager.imageRetryDelay(
            attempt,
            rateLimited:
                lastError is _ImageStatusException &&
                lastError.statusCode == HttpStatus.tooManyRequests,
          ),
        );
      }
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
      throw _ImageStatusException(response.statusCode, uri);
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

/// 图片响应非 200：携带状态码，供重试时识别 429 限流并延长退避。
class _ImageStatusException implements Exception {
  final int statusCode;
  final Uri uri;

  const _ImageStatusException(this.statusCode, this.uri);

  @override
  String toString() => 'Image download failed ($statusCode): $uri';
}
