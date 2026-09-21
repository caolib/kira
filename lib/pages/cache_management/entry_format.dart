part of '../cache_management_page.dart';

extension _CacheEntryFormat on _CacheManagementPageState {
  bool _isAiConfigKey(String key) {
    if (_CacheManagementPageState._aiConfigKeys.contains(key)) return true;
    if (key.startsWith('ai_')) return true;
    return key.startsWith('zhipu_') &&
        !key.startsWith('zhipu_chapter_summary_');
  }

  _CacheCategory _categoryOf(String key) {
    if (key.startsWith(AppPersistentCache.prefix)) {
      return _CacheCategory.persistentCache;
    }
    if (_CacheManagementPageState._accountKeys.contains(key) ||
        key.startsWith('user_')) {
      return _CacheCategory.account;
    }
    if (key.startsWith('reading_history_')) return _CacheCategory.mangaHistory;
    if (key.startsWith('reading_stats_')) return _CacheCategory.mangaHistory;
    if (key.startsWith('comic_bookmarks')) return _CacheCategory.mangaHistory;
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
      'banner_',
      'download_',
      'local_bookshelf_',
      'backup_',
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
    _setState(() {
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
}
