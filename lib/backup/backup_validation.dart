import 'dart:convert';

import 'backup_document.dart';
import 'backup_error.dart';

/// Runtime loaders often replace malformed JSON records with defaults. Refuse
/// those records before writing, rather than silently "restoring" empty data.
void validateBackupRecords(Map<String, BackupPreference> preferences) {
  for (final entry in preferences.entries) {
    final key = entry.key;
    final isMap =
        key.startsWith('reading_history_') ||
        key == 'reading_stats_v1' ||
        key == 'copy_home_section_collapsed';
    final isList = const {
      'comic_bookmarks_v1',
      'ai_providers',
      'saved_credentials',
      'zhipu_prompt_presets',
    }.contains(key);
    if (!isMap && !isList) continue;
    final value = entry.value.value;
    if (value is! String) _invalid();
    final Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      _invalid();
    }
    if (isMap && decoded is! Map<String, dynamic>) _invalid();
    if (isList) {
      if (decoded is! List) _invalid();
      final ids = <String>{};
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) _invalid();
        final required = switch (key) {
          'ai_providers' => const ['id'],
          'saved_credentials' => const ['username', 'password'],
          'zhipu_prompt_presets' => const ['id', 'name', 'prompt'],
          'comic_bookmarks_v1' => const ['pathWord', 'chapterUuid'],
          _ => const <String>[],
        };
        for (final field in required) {
          if (item[field] is! String) _invalid();
        }
        if (key == 'ai_providers') {
          final id = item['id'];
          if (id is! String || id.isEmpty || !ids.add(id)) _invalid();
          for (final field in [
            'name',
            'baseUrl',
            'apiKey',
            'apiFormat',
            'model',
          ]) {
            final value = item[field];
            if (value != null && value is! String) _invalid();
          }
          for (final field in ['isBuiltIn', 'enabled']) {
            final value = item[field];
            if (value != null && value is! bool) _invalid();
          }
          final models = item['models'];
          if (models != null &&
              (models is! List || models.any((model) => model is! String))) {
            _invalid();
          }
        }
      }
    }
  }
}

bool hasValidAiProviderReference(Map<String, BackupPreference> preferences) {
  final active = preferences['ai_active_provider']?.value;
  if (active == null || active == 'zhipu_bigmodel') return true;
  final providers = preferences['ai_providers']?.value;
  if (providers is! String) return false;
  final decoded = jsonDecode(providers);
  return decoded is List &&
      decoded.any(
        (item) => item is Map<String, dynamic> && item['id'] == active,
      );
}

Never _invalid() => throw const SettingsBackupException(
  SettingsBackupErrorCode.invalidFieldFormat,
);
