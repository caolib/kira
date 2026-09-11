part of '../cache_management_page.dart';

extension _CacheSectionCleanup on _CacheManagementPageState {
  void _toggleSelectionMode() {
    _setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) {
        _selectedSectionIds.clear();
      }
    });
  }

  void _toggleSectionSelected(_CacheSection section) {
    _toggleSectionIdSelected(section.id);
  }

  void _toggleImageSectionSelected(_ImageCacheSection section) {
    if (section.isEmpty) return;
    _toggleSectionIdSelected(section.id);
  }

  void _toggleMediaKitSectionSelected(_MediaKitCacheSection section) {
    if (section.isEmpty) return;
    _toggleSectionIdSelected(section.id);
  }

  void _toggleFontSectionSelected(_FontCacheSection section) {
    if (section.isEmpty) return;
    _toggleSectionIdSelected(section.id);
  }

  void _toggleSectionIdSelected(String id) {
    _setState(() {
      if (!_selectedSectionIds.add(id)) {
        _selectedSectionIds.remove(id);
      }
    });
  }

  List<_CacheSection> get _selectedSections => _sections
      .where((section) => _selectedSectionIds.contains(section.id))
      .toList(growable: false);

  List<_ImageCacheSection> get _selectedImageCacheSections =>
      _imageCacheSections
          .where(
            (section) =>
                !section.isEmpty && _selectedSectionIds.contains(section.id),
          )
          .toList(growable: false);

  bool get _mediaKitSelected {
    final section = _mediaKitSection;
    return section != null &&
        !section.isEmpty &&
        _selectedSectionIds.contains(section.id);
  }

  bool get _fontSelected {
    final section = _fontSection;
    return section != null &&
        !section.isEmpty &&
        _selectedSectionIds.contains(section.id);
  }

  Future<void> _deleteSelectedSections() async {
    final l10n = AppLocalizations.of(context)!;
    final sections = _selectedSections;
    final imageSections = _selectedImageCacheSections;
    final mediaKit = _mediaKitSelected ? _mediaKitSection : null;
    final font = _fontSelected ? _fontSection : null;
    if (sections.isEmpty &&
        imageSections.isEmpty &&
        mediaKit == null &&
        font == null) {
      return;
    }

    final entries = sections.expand((section) => section.entries).toList();
    final keys = entries.map((entry) => entry.key).toSet();
    final imageCacheBytes = imageSections.fold<int>(
      0,
      (sum, section) => sum + section.sizeBytes,
    );
    final deleteTargets = <String>[
      if (keys.isNotEmpty) l10n.cacheLocalDataTarget(keys.length),
      if (imageSections.isNotEmpty)
        l10n.cacheImageDataTarget(
          imageSections.length,
          _formatBytes(imageCacheBytes),
        ),
      if (mediaKit != null)
        l10n.cacheMediaKitDataTarget(_formatBytes(mediaKit.sizeBytes)),
      if (font != null)
        l10n.cacheFontDataTarget(
          font.fonts.length,
          _formatBytes(font.sizeBytes),
        ),
    ];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.cacheDeleteSelectedTitle),
        content: Text(
          l10n.cacheDeleteSelectedContent(deleteTargets.join(', ')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.deleteButton),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final prefs = await AppStorage.sharedPreferences();
      if (keys.isNotEmpty) {
        await Future.wait(keys.map(prefs.remove));
      }
      for (final section in imageSections) {
        await _clearImageCacheSection(section);
      }
      if (mediaKit != null) {
        await MediaKitNativeLoader.instance.uninstall();
      }
      if (font != null) {
        for (final f in font.fonts) {
          await FontManager().deleteFont(f.id);
        }
        if (UserManager().theme.appFontFamily.isNotEmpty) {
          await UserManager().theme.setAppFontFamily(FontManager.defaultFontId);
        }
      }
      if (entries.any((entry) => entry.category == _CacheCategory.account)) {
        ApiClient().user.clearAuthState();
        await UserManager().init();
      }
      _revealedSensitiveKeys.removeAll(keys);
      _selectedSectionIds.clear();
      _selectionMode = false;
      if (mounted) showToast(context, l10n.cacheSelectedDeletedToast);
      await _loadEntries();
    } catch (e) {
      if (mounted) {
        showToast(context, l10n.cacheDeleteFailedToast('$e'), isError: true);
      }
    }
  }

  Future<void> _deleteImageCacheSection(_ImageCacheSection section) async {
    final l10n = AppLocalizations.of(context)!;
    if (section.isEmpty) {
      showToast(context, l10n.cacheNoImageCacheToClear);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.cacheClearImageCacheTitle),
        content: Text(
          l10n.cacheClearImageCacheContent(
            section.label,
            section.fileCount,
            _formatBytes(section.sizeBytes),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.cacheClearButton),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _clearImageCacheSection(section);
      if (mounted) {
        showToast(context, l10n.cacheImageCacheClearedToast(section.label));
      }
      await _loadEntries();
    } catch (e) {
      if (mounted) {
        showToast(context, l10n.cacheCleanFailedToast('$e'), isError: true);
      }
    }
  }

  Future<void> _deleteMediaKitSection(_MediaKitCacheSection section) async {
    final l10n = AppLocalizations.of(context)!;
    if (section.isEmpty) {
      showToast(context, l10n.cacheNoMediaKitToClear);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.cacheClearMediaKitTitle),
        content: Text(
          l10n.cacheClearMediaKitContent(
            section.fileCount,
            _formatBytes(section.sizeBytes),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.deleteButton),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await MediaKitNativeLoader.instance.uninstall();
      if (mounted) {
        showToast(context, l10n.cacheMediaKitClearedToast);
      }
      await _loadEntries();
    } catch (e) {
      if (mounted) {
        showToast(context, l10n.cacheCleanFailedToast('$e'), isError: true);
      }
    }
  }

  Future<void> _deleteFontSection(_FontCacheSection section) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.cacheClearFontTitle),
        content: Text(
          l10n.cacheClearFontContent(
            section.fonts.length,
            _formatBytes(section.sizeBytes),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.deleteButton),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      for (final f in section.fonts) {
        await FontManager().deleteFont(f.id);
      }
      if (UserManager().theme.appFontFamily.isNotEmpty) {
        await UserManager().theme.setAppFontFamily(FontManager.defaultFontId);
      }
      if (mounted) {
        showToast(context, l10n.cacheFontClearedToast);
      }
      await _loadEntries();
    } catch (e) {
      if (mounted) {
        showToast(context, l10n.cacheCleanFailedToast('$e'), isError: true);
      }
    }
  }

  Future<void> _deleteCacheSection(_CacheSection section) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteButton),
        content: Text(l10n.cacheClearDataSectionContent(section.label(l10n))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.deleteButton),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final prefs = await AppStorage.sharedPreferences();
      final keys = section.entries.map((e) => e.key).toSet();
      await Future.wait(keys.map(prefs.remove));
      if (section.entries.any((e) => e.category == _CacheCategory.account)) {
        ApiClient().user.clearAuthState();
        await UserManager().init();
      }
      _revealedSensitiveKeys.removeAll(keys);
      if (mounted) {
        showToast(context, l10n.cacheSelectedDeletedToast);
      }
      await _loadEntries();
    } catch (e) {
      if (mounted) {
        showToast(context, l10n.cacheCleanFailedToast('$e'), isError: true);
      }
    }
  }
}
