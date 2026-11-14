part of '../cache_management_page.dart';

extension _CacheSectionLoad on _CacheManagementPageState {
  /// 真正的图片缓存都走 flutter_cache_manager,存放在临时目录。
  Future<List<_FileCacheSection>> _loadImageCacheSections() async {
    final l10n = AppLocalizations.of(context)!;
    final tempDir = await getTemporaryDirectory();
    return [
      await _buildFileCacheSection(
        tempDir: tempDir,
        id: 'image:reader',
        cacheKey: _CacheManagementPageState._readerImageCacheKey,
        label: l10n.cacheReaderImageLabel,
        description: l10n.cacheReaderImageDesc,
        icon: Icons.menu_book_outlined,
      ),
      await _buildFileCacheSection(
        tempDir: tempDir,
        id: 'image:novel',
        cacheKey: NovelIllustrationCache.cacheKey,
        label: l10n.cacheNovelIllustrationLabel,
        description: l10n.cacheNovelIllustrationDesc,
        icon: Icons.collections_outlined,
      ),
      await _buildFileCacheSection(
        tempDir: tempDir,
        id: 'image:default',
        cacheKey: DefaultCacheManager.key,
        label: l10n.cacheDefaultImageLabel,
        description: l10n.cacheDefaultImageDesc,
        icon: Icons.image_outlined,
      ),
    ];
  }

  /// 轻小说正文是 application support 目录下的 JSON 文件,不走
  /// flutter_cache_manager,清理方式也不同,因此单独成节、单独清理。
  Future<_FileCacheSection> _loadNovelTextSection() async {
    final l10n = AppLocalizations.of(context)!;
    return _buildFileCacheSection(
      tempDir: await getApplicationSupportDirectory(),
      id: 'text:novel',
      cacheKey: FileNovelCacheStore.directoryName,
      label: l10n.cacheNovelTextLabel,
      description: l10n.cacheNovelTextDesc,
      icon: Icons.auto_stories_outlined,
    );
  }

  Future<_FontCacheSection?> _loadFontSection() async {
    final fontManager = FontManager();
    final downloaded = await fontManager.listDownloadedFonts();
    if (downloaded.isEmpty) return null;

    final fonts = <_FontCacheEntry>[];
    int totalBytes = 0;

    for (final name in downloaded) {
      final path = await fontManager.fontFilePath(name);
      final file = File(path);
      int sizeBytes = 0;
      if (await file.exists()) {
        try {
          sizeBytes = await file.length();
        } catch (e, stack) {
          unawaited(
            AppLogger.instance.recordWarning(
              e,
              stackTrace: stack,
              source: 'cache_management.scan_font_size',
            ),
          );
        }
      }
      totalBytes += sizeBytes;
      fonts.add(_FontCacheEntry(id: name, name: name, sizeBytes: sizeBytes));
    }

    if (fonts.isEmpty) return null;
    if (!mounted) return null;

    final l10n = AppLocalizations.of(context)!;
    return _FontCacheSection(
      id: _CacheManagementPageState._fontSectionId,
      label: l10n.cacheFontLabel,
      description: l10n.cacheFontDesc,
      fonts: fonts,
      sizeBytes: totalBytes,
    );
  }

  Future<_FileCacheSection> _buildFileCacheSection({
    required Directory tempDir,
    required String id,
    required String cacheKey,
    required String label,
    required String description,
    required IconData icon,
  }) async {
    final directory = _cacheDirectoryFor(tempDir, cacheKey);
    final stats = await _directoryStats(directory);
    return _FileCacheSection(
      id: id,
      cacheKey: cacheKey,
      label: label,
      description: description,
      directoryPath: directory.path,
      fileCount: stats.fileCount,
      sizeBytes: stats.sizeBytes,
      icon: icon,
    );
  }

  Directory _cacheDirectoryFor(Directory tempDir, String cacheKey) {
    return Directory('${tempDir.path}${Platform.pathSeparator}$cacheKey');
  }

  Future<_DirectoryStats> _directoryStats(Directory directory) async {
    if (!await directory.exists()) return const _DirectoryStats();

    var fileCount = 0;
    var sizeBytes = 0;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      fileCount += 1;
      try {
        sizeBytes += await entity.length();
      } catch (_) {
        // Ignore files that disappear while the cache manager is pruning.
      }
    }
    return _DirectoryStats(fileCount: fileCount, sizeBytes: sizeBytes);
  }

  Future<void> _clearImageCacheSection(_FileCacheSection section) async {
    if (section.cacheKey == NovelIllustrationCache.cacheKey) {
      await NovelIllustrationCache.instance.clear();
    } else if (section.cacheKey == DefaultCacheManager.key) {
      await DefaultCacheManager().emptyCache();
    } else {
      await CacheManager(Config(section.cacheKey)).emptyCache();
    }

    final directory = Directory(section.directoryPath);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  Future<void> _clearNovelTextSection(_FileCacheSection section) async {
    final directory = Directory(section.directoryPath);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}
