import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SettingsBackupException implements Exception {
  final String message;

  const SettingsBackupException(this.message);

  @override
  String toString() => message;
}

class SettingsBackupSummary {
  final int preferenceCount;
  final DateTime? exportedAt;

  const SettingsBackupSummary({
    required this.preferenceCount,
    required this.exportedAt,
  });
}

class SettingsBackupService {
  static const _app = 'kira';
  static const _kind = 'settings_backup';
  static const _version = 1;
  static const _cachePrefix = 'cache_';
  static const _excludedPreferenceKeys = <String>{
    'local_bookshelf_show_update_only',
    'bookshelf_show_update_only',
  };

  Future<String> exportPlainText() async {
    final prefs = await SharedPreferences.getInstance();
    final entries = <String, Map<String, dynamic>>{};
    final keys = prefs.getKeys().where(_isUserPreferenceKey).toList()..sort();

    for (final key in keys) {
      final entry = _encodePreference(prefs.get(key));
      if (entry != null) {
        entries[key] = entry;
      }
    }

    return const JsonEncoder.withIndent('  ').convert({
      'app': _app,
      'kind': _kind,
      'version': _version,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'warning':
          'This backup is plain text and may contain tokens, accounts, passwords, and reading history.',
      'preferences': entries,
    });
  }

  SettingsBackupSummary inspectPlainText(String raw) {
    final backup = _parseBackup(raw);
    return SettingsBackupSummary(
      preferenceCount: backup.preferences.length,
      exportedAt: backup.exportedAt,
    );
  }

  Future<SettingsBackupSummary> importPlainText(String raw) async {
    final backup = _parseBackup(raw);
    final prefs = await SharedPreferences.getInstance();
    final existingKeys = prefs.getKeys().where(_isUserPreferenceKey).toList();

    for (final key in existingKeys) {
      await prefs.remove(key);
    }

    for (final entry in backup.preferences.entries) {
      await _writePreference(prefs, entry.key, entry.value);
    }

    return SettingsBackupSummary(
      preferenceCount: backup.preferences.length,
      exportedAt: backup.exportedAt,
    );
  }

  Future<int> clearAllPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().toList();

    for (final key in keys) {
      await prefs.remove(key);
    }

    return keys.length;
  }

  static bool _isUserPreferenceKey(String key) =>
      !key.startsWith(_cachePrefix) && !_excludedPreferenceKeys.contains(key);

  static Map<String, dynamic>? _encodePreference(Object? value) {
    if (value is String) {
      return {'type': 'string', 'value': value};
    }
    if (value is bool) {
      return {'type': 'bool', 'value': value};
    }
    if (value is int) {
      return {'type': 'int', 'value': value};
    }
    if (value is double) {
      return {'type': 'double', 'value': value};
    }
    if (value is List<String>) {
      return {'type': 'string_list', 'value': value};
    }
    return null;
  }

  static _ParsedSettingsBackup _parseBackup(String raw) {
    final normalized = _normalizeInput(raw);
    if (normalized.isEmpty) {
      throw const SettingsBackupException('剪贴板里没有可导入的配置');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(normalized);
    } catch (_) {
      throw const SettingsBackupException('配置格式不是有效的 JSON');
    }

    if (decoded is! Map) {
      throw const SettingsBackupException('配置格式不正确');
    }

    final map = Map<String, dynamic>.from(decoded);
    if (map['app'] != _app || map['kind'] != _kind) {
      throw const SettingsBackupException('这不是 Kira 的设置备份');
    }
    if (map['version'] != _version) {
      throw const SettingsBackupException('备份版本不受支持');
    }

    final rawPreferences = map['preferences'];
    if (rawPreferences is! Map) {
      throw const SettingsBackupException('配置内容缺失或格式不正确');
    }

    final preferences = <String, _PreferenceValue>{};
    for (final rawEntry in rawPreferences.entries) {
      final key = rawEntry.key.toString();
      if (key.isEmpty || key.startsWith(_cachePrefix)) {
        throw const SettingsBackupException('配置中包含不支持的字段');
      }
      if (_excludedPreferenceKeys.contains(key)) {
        continue;
      }
      if (rawEntry.value is! Map) {
        throw const SettingsBackupException('配置字段格式不正确');
      }
      preferences[key] = _decodePreference(
        Map<String, dynamic>.from(rawEntry.value as Map),
      );
    }

    final exportedAtRaw = map['exported_at'];
    final exportedAt = exportedAtRaw == null
        ? null
        : DateTime.tryParse(exportedAtRaw.toString());

    return _ParsedSettingsBackup(
      preferences: preferences,
      exportedAt: exportedAt,
    );
  }

  static _PreferenceValue _decodePreference(Map<String, dynamic> entry) {
    final type = entry['type'];
    final value = entry['value'];

    switch (type) {
      case 'string':
        if (value is String) return _PreferenceValue(type, value);
        break;
      case 'bool':
        if (value is bool) return _PreferenceValue(type, value);
        break;
      case 'int':
        if (value is int) return _PreferenceValue(type, value);
        break;
      case 'double':
        if (value is num) return _PreferenceValue(type, value.toDouble());
        break;
      case 'string_list':
        if (value is List && value.every((item) => item is String)) {
          return _PreferenceValue(type, List<String>.from(value));
        }
        break;
    }

    throw const SettingsBackupException('配置字段类型不受支持');
  }

  static Future<void> _writePreference(
    SharedPreferences prefs,
    String key,
    _PreferenceValue preference,
  ) async {
    switch (preference.type) {
      case 'string':
        await prefs.setString(key, preference.value as String);
        return;
      case 'bool':
        await prefs.setBool(key, preference.value as bool);
        return;
      case 'int':
        await prefs.setInt(key, preference.value as int);
        return;
      case 'double':
        await prefs.setDouble(key, preference.value as double);
        return;
      case 'string_list':
        await prefs.setStringList(key, preference.value as List<String>);
        return;
    }
  }

  static String _normalizeInput(String input) {
    final text = input.trim();
    if (!text.startsWith('```')) return text;

    final lines = const LineSplitter().convert(text);
    if (lines.length < 2 || lines.last.trim() != '```') return text;

    return lines.sublist(1, lines.length - 1).join('\n').trim();
  }
}

class _ParsedSettingsBackup {
  final Map<String, _PreferenceValue> preferences;
  final DateTime? exportedAt;

  const _ParsedSettingsBackup({
    required this.preferences,
    required this.exportedAt,
  });
}

class _PreferenceValue {
  final String type;
  final Object value;

  const _PreferenceValue(this.type, this.value);
}
