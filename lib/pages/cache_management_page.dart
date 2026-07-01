import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

import '../api/api_client.dart';
import '../models/user_manager.dart';
import '../utils/app_storage.dart';
import '../utils/toast.dart';

class CacheManagementPage extends StatefulWidget {
  const CacheManagementPage({super.key});

  @override
  State<CacheManagementPage> createState() => _CacheManagementPageState();
}

class _CacheManagementPageState extends State<CacheManagementPage> {
  static const _readerImageCacheKey = 'readerImageCache';

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

      if (!mounted) return;
      setState(() {
        _sections = sections;
        _imageCacheSections = imageCacheSections;
        final sectionIds = <String>{
          ...sections.map((section) => section.id),
          ...imageCacheSections
              .where((section) => !section.isEmpty)
              .map((section) => section.id),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除缓存项'),
        content: Text('确定要删除 ${entry.key} 吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final prefs = await AppStorage.sharedPreferences();
      await prefs.remove(entry.key);
      if (entry.category == _CacheCategory.account) {
        ApiClient().clearAuthState();
        await UserManager().init();
      }
      _revealedSensitiveKeys.remove(entry.key);
      if (mounted) showToast(context, '已删除 ${entry.key}');
      await _loadEntries();
    } catch (e) {
      if (mounted) showToast(context, '删除失败：$e', isError: true);
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

  Future<void> _deleteSelectedSections() async {
    final sections = _selectedSections;
    final imageSections = _selectedImageCacheSections;
    if (sections.isEmpty && imageSections.isEmpty) return;

    final entries = sections.expand((section) => section.entries).toList();
    final keys = entries.map((entry) => entry.key).toSet();
    final imageCacheBytes = imageSections.fold<int>(
      0,
      (sum, section) => sum + section.sizeBytes,
    );
    final deleteTargets = <String>[
      if (keys.isNotEmpty) '${keys.length} 项本地数据',
      if (imageSections.isNotEmpty)
        '${imageSections.length} 个图片缓存（${_formatBytes(imageCacheBytes)}）',
    ];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除选中缓存'),
        content: Text('确定要删除选中卡片中的 ${deleteTargets.join('、')} 吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
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
      if (entries.any((entry) => entry.category == _CacheCategory.account)) {
        ApiClient().clearAuthState();
        await UserManager().init();
      }
      _revealedSensitiveKeys.removeAll(keys);
      _selectedSectionIds.clear();
      _selectionMode = false;
      if (mounted) showToast(context, '已删除选中缓存');
      await _loadEntries();
    } catch (e) {
      if (mounted) showToast(context, '删除失败：$e', isError: true);
    }
  }

  Future<void> _deleteImageCacheSection(_ImageCacheSection section) async {
    if (section.isEmpty) {
      showToast(context, '暂无可清理的图片缓存');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空图片缓存'),
        content: Text(
          '确定要清空 ${section.label} 吗？将删除 ${section.fileCount} 个文件，释放约 ${_formatBytes(section.sizeBytes)}。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _clearImageCacheSection(section);
      if (mounted) showToast(context, '已清空 ${section.label}');
      await _loadEntries();
    } catch (e) {
      if (mounted) showToast(context, '清理失败：$e', isError: true);
    }
  }

  Future<List<_ImageCacheSection>> _loadImageCacheSections() async {
    final tempDir = await getTemporaryDirectory();
    return [
      await _buildImageCacheSection(
        tempDir: tempDir,
        id: 'image:reader',
        cacheKey: _readerImageCacheKey,
        label: '图片缓存 / 漫画阅读器',
        description: '漫画章节图片缓存。再次打开读过的章节时，图片会优先从这里读取。',
        icon: Icons.menu_book_outlined,
      ),
      await _buildImageCacheSection(
        tempDir: tempDir,
        id: 'image:default',
        cacheKey: DefaultCacheManager.key,
        label: '图片缓存 / 封面与头像',
        description: '封面、头像等 CachedNetworkImage 默认使用的图片缓存。',
        icon: Icons.image_outlined,
      ),
    ];
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
    final imageCacheFiles = _imageCacheSections.fold<int>(
      0,
      (sum, section) => sum + section.fileCount,
    );
    final imageCacheBytes = _imageCacheSections.fold<int>(
      0,
      (sum, section) => sum + section.sizeBytes,
    );
    final totalBytes = localBytes + imageCacheBytes;
    final maxSectionCardHeight = MediaQuery.sizeOf(context).height * 0.5;
    final maxSectionEntriesHeight = (maxSectionCardHeight - 73)
        .clamp(96.0, maxSectionCardHeight)
        .toDouble();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectionMode ? '已选 ${_selectedSectionIds.length} 个卡片' : '缓存管理',
        ),
        actions: [
          if (_selectionMode)
            IconButton(
              tooltip: '删除选中卡片',
              onPressed: _selectedSectionIds.isEmpty
                  ? null
                  : _deleteSelectedSections,
              icon: const Icon(Icons.delete_sweep_rounded),
            ),
          IconButton(
            tooltip: _selectionMode ? '退出多选' : '多选卡片',
            onPressed: _loading ? null : _toggleSelectionMode,
            icon: Icon(
              _selectionMode
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
            ),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _loadEntries,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
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
                      '共 $localTotal 项本地数据 · 图片缓存 $imageCacheFiles 个文件 · ${_formatBytes(totalBytes)}',
                    ),
                    subtitle: const Text(
                      '按缓存、账号、设置、历史等分类显示；AI 配置 key 已隐藏；图片文件缓存可单独清理。',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_imageCacheSections.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Text(
                      '图片缓存',
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
                  const SizedBox(height: 12),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text(
                    '数据缓存',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (_sections.isEmpty)
                  Card(
                    color: cs.surfaceContainerLow,
                    child: const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('没有可显示的本地键值数据')),
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
                                title: Text(section.label),
                                subtitle: Text(
                                  '${section.entries.length} 项 · ${_formatBytes(section.sizeBytes)}',
                                  style: tt.bodySmall,
                                ),
                                trailing: Icon(section.category.icon),
                              )
                            : ExpansionTile(
                                shape: const Border(),
                                collapsedShape: const Border(),
                                leading: Icon(section.category.icon),
                                title: Text(section.label),
                                subtitle: Text(
                                  '${section.entries.length} 项 · ${_formatBytes(section.sizeBytes)}',
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
              tooltip: revealed ? '隐藏敏感内容' : '显示敏感内容',
              onPressed: onToggleSensitive,
              icon: Icon(
                revealed ? Icons.visibility_off_rounded : Icons.visibility,
              ),
            ),
          IconButton(
            tooltip: '删除',
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
        final tt = Theme.of(dialogContext).textTheme;
        final maxContentHeight = MediaQuery.sizeOf(dialogContext).height * 0.6;

        return AlertDialog(
          title: const Text('缓存项数据'),
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
                const SizedBox(height: 12),
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
              child: const Text('关闭'),
            ),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: value));
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('复制'),
            ),
          ],
        );
      },
    );

    if (copied == true && context.mounted) {
      showToast(context, '缓存数据已复制');
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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final subtitle = '${section.fileCount} 个文件 · $sizeLabel';

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
          : ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              leading: Icon(section.icon),
              title: Text(section.label),
              subtitle: Text(subtitle, style: tt.bodySmall),
              children: [
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('说明'),
                  subtitle: Text(section.description),
                ),
                ListTile(
                  leading: const Icon(Icons.key_rounded),
                  title: const Text('缓存标识'),
                  subtitle: SelectableText(
                    section.cacheKey,
                    style: tt.bodySmall?.copyWith(fontFamily: 'monospace'),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: const Text('缓存目录'),
                  subtitle: SelectableText(
                    section.directoryPath,
                    style: tt.bodySmall?.copyWith(fontFamily: 'monospace'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: section.isEmpty ? null : onClear,
                        icon: const Icon(Icons.cleaning_services_rounded),
                        label: const Text('清空'),
                      ),
                    ],
                  ),
                ),
              ],
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
            const SizedBox(height: 12),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
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

  String get label {
    final cacheGroup = this.cacheGroup;
    if (category == _CacheCategory.persistentCache && cacheGroup != null) {
      return '${category.label} / $cacheGroup';
    }
    return category.label;
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

class _DirectoryStats {
  const _DirectoryStats({this.fileCount = 0, this.sizeBytes = 0});

  final int fileCount;
  final int sizeBytes;
}

enum _CacheCategory {
  persistentCache(0, '业务缓存', Icons.storage_rounded),
  account(1, '账号数据', Icons.account_circle_outlined),
  appSettings(2, '应用设置', Icons.tune_rounded),
  mangaHistory(3, '漫画阅读历史', Icons.history_edu_rounded),
  animeHistory(4, '动漫播放历史', Icons.play_circle_outline_rounded),
  bindings(5, '弹幕绑定', Icons.link_rounded),
  aiSummaryCache(6, 'AI 总结缓存', Icons.summarize_outlined),
  other(99, '其他数据', Icons.more_horiz_rounded);

  const _CacheCategory(this.order, this.label, this.icon);

  final int order;
  final String label;
  final IconData icon;
}
