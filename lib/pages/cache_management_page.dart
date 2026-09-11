import 'dart:async';
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
import '../utils/app_logger.dart';
import '../utils/app_storage.dart';
import '../utils/font_manager.dart';
import '../utils/reading_history.dart';
import '../utils/toast.dart';

part 'cache_management/cache_models.dart';
part 'cache_management/entry_format.dart';
part 'cache_management/entry_tile.dart';
part 'cache_management/section_cards.dart';
part 'cache_management/section_cleanup.dart';
part 'cache_management/section_load.dart';

class CacheManagementPage extends StatefulWidget {
  const CacheManagementPage({super.key});

  @override
  State<CacheManagementPage> createState() => _CacheManagementPageState();
}

class _CacheManagementPageState extends State<CacheManagementPage> {
  static const _readerImageCacheKey = 'readerImageCache';
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
  _FontCacheSection? _fontSection;
  final Set<String> _revealedSensitiveKeys = {};
  bool _selectionMode = false;
  final Set<String> _selectedSectionIds = {};

  /// extension part 文件里的成员不是 State 子类成员，不能直接调用受保护的
  /// [setState]，统一经由这个转发方法。
  void _setState(VoidCallback fn) => setState(fn);

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
      final fontSection = await _loadFontSection();

      if (!mounted) return;
      setState(() {
        _sections = sections;
        _imageCacheSections = imageCacheSections;
        _fontSection = fontSection;
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
    final fontBytes = _fontSection?.sizeBytes ?? 0;
    final totalBytes = localBytes + imageCacheBytes + fontBytes;
    final maxSectionCardHeight = MediaQuery.sizeOf(context).height * 0.5;
    final maxSectionEntriesHeight = (maxSectionCardHeight - 73)
        .clamp(96.0, maxSectionCardHeight)
        .toDouble();
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
