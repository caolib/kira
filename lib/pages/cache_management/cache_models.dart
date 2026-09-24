part of '../cache_management_page.dart';

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

enum _CacheCategory {
  persistentCache(0, Icons.storage_rounded),
  account(1, Icons.account_circle_outlined),
  appSettings(2, Icons.tune_rounded),
  mangaHistory(3, Icons.history_edu_rounded),
  searchHistory(4, Icons.manage_search_rounded),
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
    _CacheCategory.searchHistory => l10n.cacheCategorySearchHistory,
    _CacheCategory.aiSummaryCache => l10n.cacheCategoryAiSummaryCache,
    _CacheCategory.other => l10n.cacheCategoryOther,
  };
}
