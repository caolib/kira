import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';
import 'package:path_provider/path_provider.dart';

import '../api/api_client.dart';
import '../l10n/app_localizations.dart';
import '../models/user_manager.dart';
import '../theme/app_spacing.dart';
import '../utils/app_storage.dart';
import '../utils/font_manager.dart';
import '../utils/media_kit_native_loader.dart';
import '../utils/reading_history.dart';
import '../utils/toast.dart';

class CacheManagementPage extends StatefulWidget {
  const CacheManagementPage({super.key});

  @override
  State<CacheManagementPage> createState() => _CacheManagementPageState();
}

class _CacheManagementPageState extends State<CacheManagementPage> {
  static const _readerImageCacheKey = 'readerImageCache';
  static const _mediaKitSectionId = 'media_kit_native';
  static const _fontSectionId = 'downloaded_fonts';

  static const _aiConfigKeys = <String>{
    'zhipu_api_key',
    'zhipu_base_url',
    'zhipu_api_format',
    'zhipu_model',
    'zhipu_summary_enabled',
    'zhipu_spoiler_analysis',
    'zhipu_prompt_presets',
    'zhipu_active_preset',
    'zhipu_auto_summary',
    'zhipu_auto_summary_min',
    'zhipu_auto_summary_timing',
    'zhipu_summary_collapsed',
    'zhipu_spoiler_warn',
    'zhipu_custom_models',
    'ai_providers',
    'ai_active_provider',
    'ai_chat_sessions',
  };

  static const _accountKeys = <String>{
    'user_token',
    'user_username',
    'user_nickname',
    'user_avatar',
    'user_id',
    'saved_username',
    'saved_password',
    'saved_credentials',
    'auto_login',
    'login_source',
  };

  bool _loading = true;
  String? _error;
  List<_CacheSection> _sections = const [];
  List<_ImageCacheSection> _imageCacheSections = const [];
  _MediaKitCacheSection? _mediaKitSection;
  _FontCacheSection? _fontSection;
  final Set<String> _revealedSensitiveKeys = {};
  bool _selectionMode = false;
  final Set<String> _selectedSectionIds = {};

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 阅读进度防抖写入，先落盘再统计，否则刚读的章节不会出现在列表里，
      // 删除后也会被延迟写回。
      await ReadingHistory.flush();
      final prefs = await AppStorage.sharedPreferences();
      final entries =
          prefs.getKeys().where((key) => !_isAiConfigKey(key)).map((key) {
            final value = prefs.get(key);
            return _CacheEntry(
              key: key,
              value: value,
              category: _categoryOf(key),
              sensitive: _isSensitiveKey(key),
              sizeBytes: _estimateEntrySize(key, value),
            );
          }).toList()..sort((a, b) {
            final category = a.category.order.compareTo(b.category.order);
            if (category != 0) return category;
            return a.key.compareTo(b.key);
          });

      final sections = <_CacheSection>[];
      final cacheGroups = <String, List<_CacheEntry>>{};
      for (final entry in entries.where(
        (entry) => entry.category == _CacheCategory.persistentCache,
      )) {
        final group = _persistentCacheGroupOf(entry.key);
        cacheGroups.putIfAbsent(group, () => <_CacheEntry>[]).add(entry);
      }
      for (final category in _CacheCategory.values) {
        if (category == _CacheCategory.persistentCache) continue;
        final items = entries
            .where((entry) => entry.category == category)
            .toList(growable: false);
        if (items.isNotEmpty) {
          sections.add(_CacheSection(category: category, entries: items));
        }
      }

      final cacheGroupNames = cacheGroups.keys.toList()..sort();
      for (final group in cacheGroupNames) {
        sections.add(
          _CacheSection(
            category: _CacheCategory.persistentCache,
            entries: cacheGroups[group]!,
            cacheGroup: group,
          ),
        );
      }

      final imageCacheSections = await _loadImageCacheSections();
      final mediaKitSection = await _loadMediaKitSection();
      final fontSection = await _loadFontSection();

      if (!mounted) return;
      setState(() {
        _sections = sections;
        _imageCacheSections = imageCacheSections;
        _mediaKitSection = mediaKitSection;
        _fontSection = fontSection;
        final sectionIds = <String>{
          ...sections.map((section) => section.id),
          ...imageCacheSections
              .where((section) => !section.isEmpty)
              .map((section) => section.id),
          if (mediaKitSection != null && !mediaKitSection.isEmpty)
            mediaKitSection.id,
        };
        _selectedSectionIds.removeWhere((id) => !sectionIds.contains(id));
        if (sectionIds.isEmpty) {
          _selectionMode = false;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _deleteEntry(_CacheEntry entry) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.cacheDeleteEntryTitle),
        content: Text(l10n.cacheDeleteEntryContent(entry.key)),
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
      await prefs.remove(entry.key);
      if (entry.category == _CacheCategory.account) {
        ApiClient().user.clearAuthState();
        await UserManager().init();
      }
      _revealedSensitiveKeys.remove(entry.key);
      if (mounted) showToast(context, l10n.cacheEntryDeletedToast(entry.key));
      await _loadEntries();
    } catch (e) {
      if (mounted) {
        showToast(context, l10n.cacheDeleteFailedToast('$e'), isError: true);
      }
    }
  }

  void _toggleSelectionMode() {
    setState(() {
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
    setState(() {
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

  Future<List<_ImageCacheSection>> _loadImageCacheSections() async {
    final l10n = AppLocalizations.of(context)!;
    final tempDir = await getTemporaryDirectory();
    return [
      await _buildImageCacheSection(
        tempDir: tempDir,
        id: 'image:reader',
        cacheKey: _readerImageCacheKey,
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
      id: _mediaKitSectionId,
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
        } catch (_) {}
      }
      totalBytes += sizeBytes;
      fonts.add(_FontCacheEntry(id: name, name: name, sizeBytes: sizeBytes));
    }

    if (fonts.isEmpty) return null;
    if (!mounted) return null;

    final l10n = AppLocalizations.of(context)!;
    return _FontCacheSection(
      id: _fontSectionId,
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

  bool _isAiConfigKey(String key) {
    if (_aiConfigKeys.contains(key)) return true;
    if (key.startsWith('ai_')) return true;
    return key.startsWith('zhipu_') &&
        !key.startsWith('zhipu_chapter_summary_');
  }

  _CacheCategory _categoryOf(String key) {
    if (key.startsWith(AppPersistentCache.prefix)) {
      return _CacheCategory.persistentCache;
    }
    if (_accountKeys.contains(key) || key.startsWith('user_')) {
      return _CacheCategory.account;
    }
    if (key.startsWith('reading_history_')) return _CacheCategory.mangaHistory;
    if (key.startsWith('reading_stats_')) return _CacheCategory.mangaHistory;
    if (key.startsWith('comic_bookmarks')) return _CacheCategory.mangaHistory;
    if (key.startsWith('anime_playback_history_')) {
      return _CacheCategory.animeHistory;
    }
    if (key.startsWith('dandanplay_binding_')) {
      return _CacheCategory.bindings;
    }
    if (key.startsWith('zhipu_chapter_summary_')) {
      return _CacheCategory.aiSummaryCache;
    }
    if (_looksLikeSettingKey(key)) return _CacheCategory.appSettings;
    return _CacheCategory.other;
  }

  String _persistentCacheGroupOf(String key) {
    final normalizedKey = key.startsWith(AppPersistentCache.prefix)
        ? key.substring(AppPersistentCache.prefix.length)
        : key;
    final group = normalizedKey.split('_').first.trim();
    return group.isEmpty ? 'other' : group;
  }

  bool _looksLikeSettingKey(String key) {
    const settingPrefixes = <String>[
      'theme_',
      'custom_theme_',
      'dark_mode_',
      'bottom_nav_',
      'nav_',
      'last_nav_',
      'desktop_font_',
      'bookshelf_',
      'reader_',
      'image_',
      'comment_',
      'auto_check_',
      'skipped_update_',
      'disclaimer_',
      'api_route',
      'anime_feature_',
      'banner_',
      'anime_home_',
      'anime_skip_',
      'anime_playback_progress_',
      'danmaku_',
      'local_bookshelf_',
    ];
    return settingPrefixes.any(key.startsWith);
  }

  bool _isSensitiveKey(String key) {
    final normalized = key.toLowerCase();
    return normalized.contains('password') ||
        normalized.contains('token') ||
        key == 'saved_credentials';
  }

  void _toggleSensitive(String key) {
    setState(() {
      if (!_revealedSensitiveKeys.add(key)) {
        _revealedSensitiveKeys.remove(key);
      }
    });
  }

  String _formatValue(_CacheEntry entry) {
    final revealSensitive = _revealedSensitiveKeys.contains(entry.key);
    final displayValue = _displayValue(entry, revealSensitive: revealSensitive);
    const encoder = JsonEncoder.withIndent('  ');
    if (displayValue is String) return displayValue;
    if (displayValue is num || displayValue is bool || displayValue == null) {
      return displayValue.toString();
    }
    return encoder.convert(displayValue);
  }

  Object? _displayValue(_CacheEntry entry, {required bool revealSensitive}) {
    final decoded = _decodeValue(entry.value);
    final value = entry.category == _CacheCategory.persistentCache
        ? _decodeCachePayload(decoded)
        : decoded;
    if (!revealSensitive) {
      return _maskSensitiveValue(value, entryKey: entry.key);
    }
    return value;
  }

  Object? _decodeValue(Object? value) {
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        try {
          return jsonDecode(trimmed);
        } catch (_) {
          return value;
        }
      }
    }
    return value;
  }

  Object? _decodeCachePayload(Object? value) {
    if (value is Map && value.containsKey(AppPersistentCache.dataKey)) {
      return {
        'data': value[AppPersistentCache.dataKey],
        if (value[AppPersistentCache.expiresAtKey] != null)
          'expiresAt': _formatEpochMillis(
            value[AppPersistentCache.expiresAtKey],
          ),
      };
    }
    return value;
  }

  Object? _maskSensitiveValue(Object? value, {String? entryKey}) {
    if (entryKey != null && _isSensitiveKey(entryKey)) {
      if (value is String || value is num || value is bool || value == null) {
        return '••••••';
      }
    }
    if (value is Map) {
      return value.map((key, child) {
        final name = key.toString();
        final masked = _isSensitiveField(name)
            ? '••••••'
            : _maskSensitiveValue(child);
        return MapEntry(name, masked);
      });
    }
    if (value is List) {
      return value.map(_maskSensitiveValue).toList(growable: false);
    }
    return value;
  }

  bool _isSensitiveField(String key) {
    final normalized = key.toLowerCase();
    return normalized.contains('password') || normalized.contains('token');
  }

  String _formatEpochMillis(Object? value) {
    final millis = value is int
        ? value
        : value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '');
    if (millis == null) return value?.toString() ?? '';
    final local = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final second = local.second.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute:$second';
  }

  String _preview(_CacheEntry entry) {
    final value = _formatValue(entry).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (value.length <= 80) return value;
    return '${value.substring(0, 80)}...';
  }

  int _estimateEntrySize(String key, Object? value) {
    return utf8.encode(key).length +
        utf8.encode(_encodeSizeValue(value)).length;
  }

  String _encodeSizeValue(Object? value) {
    if (value is String) return value;
    return jsonEncode(value);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final localTotal = _sections.fold<int>(
      0,
      (sum, section) => sum + section.entries.length,
    );
    final localBytes = _sections.fold<int>(
      0,
      (sum, section) => sum + section.sizeBytes,
    );
    final imageCacheBytes = _imageCacheSections.fold<int>(
      0,
      (sum, section) => sum + section.sizeBytes,
    );
    final mediaKitBytes = _mediaKitSection?.sizeBytes ?? 0;
    final fontBytes = _fontSection?.sizeBytes ?? 0;
    final totalBytes = localBytes + imageCacheBytes + mediaKitBytes + fontBytes;
    final maxSectionCardHeight = MediaQuery.sizeOf(context).height * 0.5;
    final maxSectionEntriesHeight = (maxSectionCardHeight - 73)
        .clamp(96.0, maxSectionCardHeight)
        .toDouble();
    final mediaKitSection = _mediaKitSection;
    final fontSection = _fontSection;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectionMode
              ? l10n.cacheSelectedCards(_selectedSectionIds.length)
              : l10n.cacheManagementTitle,
        ),
        actions: [
          if (_selectionMode)
            IconButton(
              tooltip: l10n.cacheDeleteSelectedCardsTooltip,
              onPressed: _selectedSectionIds.isEmpty
                  ? null
                  : _deleteSelectedSections,
              icon: const Icon(Icons.delete_sweep_rounded),
            ),
          IconButton(
            tooltip: _selectionMode
                ? l10n.cacheExitMultiSelectTooltip
                : l10n.cacheMultiSelectTooltip,
            onPressed: _loading ? null : _toggleSelectionMode,
            icon: Icon(
              _selectionMode
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
            ),
          ),
          IconButton(
            tooltip: l10n.refreshButton,
            onPressed: _loading ? null : _loadEntries,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: ExpressiveLoadingIndicator())
          : _error != null
          ? _ErrorView(error: _error!, onRetry: _loadEntries)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Card(
                  color: cs.surfaceContainerLow,
                  child: ListTile(
                    leading: const Icon(Icons.info_outline_rounded),
                    title: Text(
                      l10n.cacheSummary(localTotal, _formatBytes(totalBytes)),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (_imageCacheSections.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Text(
                      l10n.cacheImageCacheSection,
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  ..._imageCacheSections.map(
                    (section) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ImageCacheSectionCard(
                        section: section,
                        selectionMode: _selectionMode,
                        selected: _selectedSectionIds.contains(section.id),
                        sizeLabel: _formatBytes(section.sizeBytes),
                        onToggleSelected: () =>
                            _toggleImageSectionSelected(section),
                        onClear: () => _deleteImageCacheSection(section),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (mediaKitSection != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Text(
                      l10n.cacheMediaKitSection,
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _MediaKitCacheSectionCard(
                      section: mediaKitSection,
                      selectionMode: _selectionMode,
                      selected: _selectedSectionIds.contains(
                        mediaKitSection.id,
                      ),
                      sizeLabel: _formatBytes(mediaKitSection.sizeBytes),
                      onToggleSelected: () =>
                          _toggleMediaKitSectionSelected(mediaKitSection),
                      onClear: () => _deleteMediaKitSection(mediaKitSection),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (fontSection != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Text(
                      l10n.cacheFontSection,
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _FontCacheSectionCard(
                      section: fontSection,
                      selectionMode: _selectionMode,
                      selected: _selectedSectionIds.contains(fontSection.id),
                      sizeLabel: _formatBytes(fontSection.sizeBytes),
                      onToggleSelected: () =>
                          _toggleFontSectionSelected(fontSection),
                      onClear: () => _deleteFontSection(fontSection),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text(
                    l10n.cacheDataCacheSection,
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (_sections.isEmpty)
                  Card(
                    color: cs.surfaceContainerLow,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(child: Text(l10n.cacheNoLocalKeyValueData)),
                    ),
                  )
                else
                  ..._sections.map(
                    (section) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        color: cs.surfaceContainerLow,
                        child: _selectionMode
                            ? ListTile(
                                onTap: () => _toggleSectionSelected(section),
                                leading: Checkbox(
                                  value: _selectedSectionIds.contains(
                                    section.id,
                                  ),
                                  onChanged: (_) =>
                                      _toggleSectionSelected(section),
                                ),
                                title: Text(section.label(l10n)),
                                subtitle: Text(
                                  l10n.cacheEntryCountSize(
                                    section.entries.length,
                                    _formatBytes(section.sizeBytes),
                                  ),
                                  style: tt.bodySmall,
                                ),
                                trailing: Icon(section.category.icon),
                              )
                            : ExpansionTile(
                                shape: const Border(),
                                collapsedShape: const Border(),
                                leading: Icon(section.category.icon),
                                title: Text(section.label(l10n)),
                                subtitle: Text(
                                  l10n.cacheEntryCountSize(
                                    section.entries.length,
                                    _formatBytes(section.sizeBytes),
                                  ),
                                  style: tt.bodySmall,
                                ),
                                children: [
                                  const Divider(height: 1),
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxHeight: maxSectionEntriesHeight,
                                    ),
                                    child: ListView.builder(
                                      primary: false,
                                      shrinkWrap: true,
                                      padding: EdgeInsets.zero,
                                      itemCount: section.entries.length,
                                      itemBuilder: (context, index) {
                                        final entry = section.entries[index];
                                        return _CacheEntryTile(
                                          entry: entry,
                                          preview: _preview(entry),
                                          sizeLabel: _formatBytes(
                                            entry.sizeBytes,
                                          ),
                                          value: _formatValue(entry),
                                          revealed: _revealedSensitiveKeys
                                              .contains(entry.key),
                                          onToggleSensitive: entry.sensitive
                                              ? () =>
                                                    _toggleSensitive(entry.key)
                                              : null,
                                          onDelete: () => _deleteEntry(entry),
                                        );
                                      },
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      12,
                                    ),
                                    child: Row(
                                      children: [
                                        const Spacer(),
                                        FilledButton.tonalIcon(
                                          onPressed: () =>
                                              _deleteCacheSection(section),
                                          icon: const Icon(
                                            Icons.delete_outline_rounded,
                                          ),
                                          label: Text(l10n.cacheClearButton),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _CacheEntryTile extends StatelessWidget {
  const _CacheEntryTile({
    required this.entry,
    required this.preview,
    required this.sizeLabel,
    required this.value,
    required this.revealed,
    required this.onToggleSensitive,
    required this.onDelete,
  });

  final _CacheEntry entry;
  final String preview;
  final String sizeLabel;
  final String value;
  final bool revealed;
  final VoidCallback? onToggleSensitive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 8),
      onTap: () => _showDetailDialog(context),
      title: Text(
        entry.key,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: tt.bodyMedium?.copyWith(fontFamily: 'monospace'),
      ),
      subtitle: Text(
        '${entry.typeLabel} · $sizeLabel · $preview',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: tt.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onToggleSensitive != null)
            IconButton(
              tooltip: revealed
                  ? l10n.cacheHideSensitiveTooltip
                  : l10n.cacheShowSensitiveTooltip,
              onPressed: onToggleSensitive,
              icon: Icon(
                revealed ? Icons.visibility_off_rounded : Icons.visibility,
              ),
            ),
          IconButton(
            tooltip: l10n.deleteButton,
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline_rounded, color: cs.error),
          ),
        ],
      ),
    );
  }

  Future<void> _showDetailDialog(BuildContext context) async {
    final copied = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        final tt = Theme.of(dialogContext).textTheme;
        final maxContentHeight = MediaQuery.sizeOf(dialogContext).height * 0.6;

        return AlertDialog(
          title: Text(l10n.cacheEntryDataTitle),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  entry.key,
                  style: tt.titleSmall?.copyWith(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 6),
                Text('$sizeLabel · ${entry.typeLabel}', style: tt.bodySmall),
                const SizedBox(height: AppSpacing.md),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxContentHeight),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      value,
                      style: tt.bodySmall?.copyWith(fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.closeButton),
            ),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: value));
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              },
              icon: const Icon(Icons.copy_rounded),
              label: Text(l10n.copyButton),
            ),
          ],
        );
      },
    );

    if (copied == true && context.mounted) {
      showToast(context, AppLocalizations.of(context)!.cacheDataCopiedToast);
    }
  }
}

class _ImageCacheSectionCard extends StatelessWidget {
  const _ImageCacheSectionCard({
    required this.section,
    required this.selectionMode,
    required this.selected,
    required this.sizeLabel,
    required this.onToggleSelected,
    required this.onClear,
  });

  final _ImageCacheSection section;
  final bool selectionMode;
  final bool selected;
  final String sizeLabel;
  final VoidCallback onToggleSelected;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final subtitle = l10n.cacheFileCountSize(section.fileCount, sizeLabel);

    return Card(
      color: cs.surfaceContainerLow,
      child: selectionMode
          ? ListTile(
              enabled: !section.isEmpty,
              onTap: section.isEmpty ? null : onToggleSelected,
              leading: Checkbox(
                value: selected,
                onChanged: section.isEmpty ? null : (_) => onToggleSelected(),
              ),
              title: Text(section.label),
              subtitle: Text(subtitle, style: tt.bodySmall),
              trailing: Icon(section.icon),
            )
          : ListTile(
              leading: Icon(section.icon),
              title: Text(section.label),
              subtitle: Text(subtitle, style: tt.bodySmall),
              trailing: FilledButton.tonalIcon(
                onPressed: section.isEmpty ? null : onClear,
                icon: const Icon(Icons.cleaning_services_rounded),
                label: Text(l10n.cacheClearButton),
              ),
            ),
    );
  }
}

class _MediaKitCacheSectionCard extends StatelessWidget {
  const _MediaKitCacheSectionCard({
    required this.section,
    required this.selectionMode,
    required this.selected,
    required this.sizeLabel,
    required this.onToggleSelected,
    required this.onClear,
  });

  final _MediaKitCacheSection section;
  final bool selectionMode;
  final bool selected;
  final String sizeLabel;
  final VoidCallback onToggleSelected;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final subtitle = section.isEmpty
        ? l10n.cacheNoMediaKitToClear
        : l10n.cacheFileCountSize(section.fileCount, sizeLabel);

    return Card(
      color: cs.surfaceContainerLow,
      child: selectionMode
          ? ListTile(
              enabled: !section.isEmpty,
              onTap: section.isEmpty ? null : onToggleSelected,
              leading: Checkbox(
                value: selected,
                onChanged: section.isEmpty ? null : (_) => onToggleSelected(),
              ),
              title: Text(section.label),
              subtitle: Text(subtitle, style: tt.bodySmall),
              trailing: const Icon(Icons.video_settings_rounded),
            )
          : ListTile(
              leading: const Icon(Icons.video_settings_rounded),
              title: Text(section.label),
              subtitle: Text(subtitle, style: tt.bodySmall),
              trailing: FilledButton.tonalIcon(
                onPressed: section.isEmpty ? null : onClear,
                icon: const Icon(Icons.delete_outline_rounded),
                label: Text(l10n.deleteButton),
              ),
            ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 40),
            const SizedBox(height: AppSpacing.md),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(AppLocalizations.of(context)!.retryButton),
            ),
          ],
        ),
      ),
    );
  }
}

class _CacheSection {
  const _CacheSection({
    required this.category,
    required this.entries,
    this.cacheGroup,
  });

  final _CacheCategory category;
  final List<_CacheEntry> entries;
  final String? cacheGroup;

  String get id => '${category.name}:${cacheGroup ?? ''}';

  String label(AppLocalizations l10n) {
    final cacheGroup = this.cacheGroup;
    final categoryLabel = category.label(l10n);
    if (category == _CacheCategory.persistentCache && cacheGroup != null) {
      return '$categoryLabel / $cacheGroup';
    }
    return categoryLabel;
  }

  int get sizeBytes =>
      entries.fold<int>(0, (sum, entry) => sum + entry.sizeBytes);
}

class _CacheEntry {
  const _CacheEntry({
    required this.key,
    required this.value,
    required this.category,
    required this.sensitive,
    required this.sizeBytes,
  });

  final String key;
  final Object? value;
  final _CacheCategory category;
  final bool sensitive;
  final int sizeBytes;

  String get typeLabel {
    final value = this.value;
    if (value is String) return 'String';
    if (value is bool) return 'bool';
    if (value is int) return 'int';
    if (value is double) return 'double';
    if (value is List<String>) return 'StringList';
    return value.runtimeType.toString();
  }
}

class _ImageCacheSection {
  const _ImageCacheSection({
    required this.id,
    required this.cacheKey,
    required this.label,
    required this.description,
    required this.directoryPath,
    required this.fileCount,
    required this.sizeBytes,
    required this.icon,
  });

  final String id;
  final String cacheKey;
  final String label;
  final String description;
  final String directoryPath;
  final int fileCount;
  final int sizeBytes;
  final IconData icon;

  bool get isEmpty => fileCount == 0 && sizeBytes == 0;
}

class _MediaKitCacheSection {
  const _MediaKitCacheSection({
    required this.id,
    required this.label,
    required this.description,
    required this.directoryPath,
    required this.fileCount,
    required this.sizeBytes,
    required this.version,
    required this.isInstalled,
  });

  final String id;
  final String label;
  final String description;
  final String directoryPath;
  final int fileCount;
  final int sizeBytes;
  final String? version;
  final bool isInstalled;

  bool get isEmpty => fileCount == 0 && sizeBytes == 0;
}

class _DirectoryStats {
  const _DirectoryStats({this.fileCount = 0, this.sizeBytes = 0});

  final int fileCount;
  final int sizeBytes;
}

class _FontCacheEntry {
  const _FontCacheEntry({
    required this.id,
    required this.name,
    required this.sizeBytes,
  });

  final String id;
  final String name;
  final int sizeBytes;
}

class _FontCacheSection {
  const _FontCacheSection({
    required this.id,
    required this.label,
    required this.description,
    required this.fonts,
    required this.sizeBytes,
  });

  final String id;
  final String label;
  final String description;
  final List<_FontCacheEntry> fonts;
  final int sizeBytes;

  bool get isEmpty => fonts.isEmpty;
}

class _FontCacheSectionCard extends StatelessWidget {
  const _FontCacheSectionCard({
    required this.section,
    required this.selectionMode,
    required this.selected,
    required this.sizeLabel,
    required this.onToggleSelected,
    required this.onClear,
  });

  final _FontCacheSection section;
  final bool selectionMode;
  final bool selected;
  final String sizeLabel;
  final VoidCallback onToggleSelected;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final subtitle = l10n.cacheFileCountSize(section.fonts.length, sizeLabel);

    return Card(
      color: cs.surfaceContainerLow,
      child: selectionMode
          ? ListTile(
              enabled: !section.isEmpty,
              onTap: section.isEmpty ? null : onToggleSelected,
              leading: Checkbox(
                value: selected,
                onChanged: section.isEmpty ? null : (_) => onToggleSelected(),
              ),
              title: Text(section.label),
              subtitle: Text(subtitle, style: tt.bodySmall),
              trailing: const Icon(Icons.font_download_outlined),
            )
          : ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              leading: const Icon(Icons.font_download_outlined),
              title: Text(section.label),
              subtitle: Text(subtitle, style: tt.bodySmall),
              children: [
                const Divider(height: 1),
                for (final font in section.fonts)
                  ListTile(
                    leading: const Icon(Icons.text_fields),
                    title: Text(font.name),
                    trailing: Text(
                      _FontCacheSectionCard._formatFileSize(font.sizeBytes),
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: section.isEmpty ? null : onClear,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: Text(l10n.deleteButton),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  static String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  }
}

enum _CacheCategory {
  persistentCache(0, Icons.storage_rounded),
  account(1, Icons.account_circle_outlined),
  appSettings(2, Icons.tune_rounded),
  mangaHistory(3, Icons.history_edu_rounded),
  animeHistory(4, Icons.play_circle_outline_rounded),
  bindings(5, Icons.link_rounded),
  aiSummaryCache(6, Icons.summarize_outlined),
  other(99, Icons.more_horiz_rounded);

  const _CacheCategory(this.order, this.icon);

  final int order;
  final IconData icon;

  String label(AppLocalizations l10n) => switch (this) {
    _CacheCategory.persistentCache => l10n.cacheCategoryPersistentCache,
    _CacheCategory.account => l10n.cacheCategoryAccount,
    _CacheCategory.appSettings => l10n.cacheCategoryAppSettings,
    _CacheCategory.mangaHistory => l10n.cacheCategoryMangaHistory,
    _CacheCategory.animeHistory => l10n.cacheCategoryAnimeHistory,
    _CacheCategory.bindings => l10n.cacheCategoryBindings,
    _CacheCategory.aiSummaryCache => l10n.cacheCategoryAiSummaryCache,
    _CacheCategory.other => l10n.cacheCategoryOther,
  };
}
