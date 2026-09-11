part of '../download_manager.dart';

extension DownloadManagerComicStorePart on DownloadManager {
  Map<String, dynamic> _manifestPayload() => {
    'version': DownloadManager._manifestVersion,
    'comics': _manifest.map(
      (pathWord, chapters) => MapEntry(
        pathWord,
        chapters.map(
          (chapterUuid, summary) => MapEntry(chapterUuid, summary.toJson()),
        ),
      ),
    ),
  };

  Future<void> _persistManifest() async {
    await _manifestFile.writeAsString(jsonEncode(_manifestPayload()));
  }

  Future<void> _removeDownloadedChapter(
    String pathWord,
    String chapterUuid, {
    required bool deleteFiles,
  }) async {
    final comicChapters = _manifest[pathWord];
    if (comicChapters != null) {
      comicChapters.remove(chapterUuid);
      if (comicChapters.isEmpty) {
        _manifest.remove(pathWord);
      } else {
        await _touchLocalComic(pathWord);
      }
      await _persistManifest();
    }

    if (deleteFiles) {
      final dir = _chapterDirectory(pathWord, chapterUuid);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }
  }

  /// 准备漫画元数据与封面。
  ///
  /// 先落盘 comic.json（尚无本地封面时封面暂用远程 URL），让下载队列立即
  /// 能显示漫画名；封面文件随后在后台下载，完成后回填本地路径。
  Future<void> _ensureComicStored(String pathWord, Comic comic) async {
    final stored = _readLocalComicInfo(pathWord);
    // _readLocalComicInfo 在封面文件缺失时会将 coverPath 置 null，
    // 因此 coverPath 非空即代表本地封面可用。
    final hasLocalCover = stored?.coverPath?.isNotEmpty ?? false;

    await _comicDirectory(pathWord).create(recursive: true);
    await _comicMetadataFile(pathWord).writeAsString(
      jsonEncode(
        LocalComicInfo(
          comic: comic.copyWith(
            cover: hasLocalCover ? stored!.coverPath : comic.cover,
          ),
          coverPath: hasLocalCover ? stored!.coverPath : null,
          updatedAt: DateTime.now(),
        ).toJson(),
      ),
    );
    _notifyListeners();

    if (hasLocalCover) return;

    File? coverFile;
    try {
      coverFile = await _downloadCoverIfNeeded(pathWord, comic.cover);
    } catch (e) {
      debugPrint('Download comic cover failed: $e');
      return;
    }
    if (coverFile == null) return;

    // 回填前重读元数据，避免覆盖期间 _touchLocalComic 刷新的 updatedAt。
    final refreshed = _readLocalComicInfo(pathWord);
    if (refreshed == null) return;
    await _comicMetadataFile(pathWord).writeAsString(
      jsonEncode(
        LocalComicInfo(
          comic: refreshed.comic.copyWith(cover: coverFile.path),
          coverPath: coverFile.path,
          updatedAt: refreshed.updatedAt,
        ).toJson(),
      ),
    );
    _notifyListeners();
  }

  Future<File?> _downloadCoverIfNeeded(String pathWord, String coverUrl) async {
    if (coverUrl.isEmpty) return null;
    final comicDir = _comicDirectory(pathWord);
    await comicDir.create(recursive: true);
    final uri = Uri.parse(coverUrl);
    final request = await _httpClient
        .getUrl(uri)
        .timeout(DownloadManager._timeout);
    final response = await request.close().timeout(DownloadManager._timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Cover download failed (${response.statusCode})',
        uri: uri,
      );
    }
    final extension = _resolveImageExtension(uri, response);
    final file = File(
      DownloadManager._joinPath([
        comicDir.path,
        '${DownloadManager._coverFileName}$extension',
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

  Future<void> _touchLocalComic(String pathWord) async {
    final info = _readLocalComicInfo(pathWord);
    if (info == null) return;
    final nextInfo = LocalComicInfo(
      comic: info.comic,
      coverPath: info.coverPath,
      updatedAt: DateTime.now(),
    );
    await _comicMetadataFile(
      pathWord,
    ).writeAsString(jsonEncode(nextInfo.toJson()));
  }

  Future<void> _removeLocalComic(String pathWord) async {
    final dir = _comicDirectory(pathWord);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  LocalComicInfo? _readLocalComicInfo(String pathWord) {
    final file = _comicMetadataFile(pathWord);
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return null;
      final info = LocalComicInfo.fromJson(Map<String, dynamic>.from(decoded));
      final coverPath = info.coverPath;
      if (coverPath != null &&
          coverPath.isNotEmpty &&
          !File(coverPath).existsSync()) {
        return LocalComicInfo(
          comic: info.comic,
          coverPath: null,
          updatedAt: info.updatedAt,
        );
      }
      return info;
    } catch (e) {
      debugPrint('Read local comic info failed: $e');
      return null;
    }
  }

  Future<void> _resetDirectory(Directory dir) async {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);
  }

  File get _manifestFile => File(
    DownloadManager._joinPath([
      _rootDirectory!.path,
      DownloadManager._manifestFileName,
    ]),
  );

  Directory _comicDirectory(String pathWord) {
    return Directory(
      DownloadManager._joinPath([
        _rootDirectory!.path,
        DownloadManager._safePathSegment(pathWord),
      ]),
    );
  }

  File _comicMetadataFile(String pathWord) {
    return File(
      DownloadManager._joinPath([
        _comicDirectory(pathWord).path,
        DownloadManager._comicMetaFileName,
      ]),
    );
  }

  Directory _chapterDirectory(String pathWord, String chapterUuid) {
    return Directory(
      DownloadManager._joinPath([
        _comicDirectory(pathWord).path,
        DownloadManager._safePathSegment(chapterUuid),
      ]),
    );
  }

  File _chapterMetadataFile(String pathWord, String chapterUuid) {
    return File(
      DownloadManager._joinPath([
        _chapterDirectory(pathWord, chapterUuid).path,
        DownloadManager._chapterMetaFileName,
      ]),
    );
  }
}
