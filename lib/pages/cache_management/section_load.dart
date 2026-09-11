part of '../cache_management_page.dart';

extension _CacheSectionLoad on _CacheManagementPageState {
  Future<List<_ImageCacheSection>> _loadImageCacheSections() async {
    final l10n = AppLocalizations.of(context)!;
    final tempDir = await getTemporaryDirectory();
    return [
      await _buildImageCacheSection(
        tempDir: tempDir,
        id: 'image:reader',
        cacheKey: _CacheManagementPageState._readerImageCacheKey,
        label: l10n.cacheReaderImageLabel,
        description: l10n.cacheReaderImageDesc,
        icon: Icons.menu_book_outlined,
      ),
      await _buildImageCacheSection(
        tempDir: tempDir,
        id: 'image:default',
        cacheKey: DefaultCacheManager.key,
        label: l10n.cacheDefaultImageLabel,
        description: l10n.cacheDefaultImageDesc,
        icon: Icons.image_outlined,
      ),
    ];
  }

  Future<_MediaKitCacheSection?> _loadMediaKitSection() async {
    final loader = MediaKitNativeLoader.instance;
    if (!loader.needsOnDemandDownload) return null;

    final l10n = AppLocalizations.of(context)!;
    final info = await loader.installInfo();
    return _MediaKitCacheSection(
      id: _CacheManagementPageState._mediaKitSectionId,
      label: l10n.cacheMediaKitLabel,
      description: l10n.cacheMediaKitDesc,
      directoryPath: info.directoryPath,
      fileCount: info.fileCount,
      sizeBytes: info.sizeBytes,
      version: info.version,
      isInstalled: info.isInstalled,
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

  Future<_ImageCacheSection> _buildImageCacheSection({
    required Directory tempDir,
    required String id,
    required String cacheKey,
    required String label,
    required String description,
    required IconData icon,
  }) async {
    final directory = _cacheDirectoryFor(tempDir, cacheKey);
    final stats = await _directoryStats(directory);
    return _ImageCacheSection(
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

  Future<void> _clearImageCacheSection(_ImageCacheSection section) async {
    if (section.cacheKey == DefaultCacheManager.key) {
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
}
