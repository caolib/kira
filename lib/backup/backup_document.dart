import 'dart:convert';

import 'backup_category.dart';
import 'backup_error.dart';
import 'backup_validation.dart';

class BackupPreference {
  final String type;
  final Object value;

  const BackupPreference._(this.type, this.value);

  static BackupPreference fromValue(Object value) {
    return switch (value) {
      String() => BackupPreference._('string', value),
      bool() => BackupPreference._('bool', value),
      int() => BackupPreference._('int', value),
      double() when value.isFinite => BackupPreference._('double', value),
      // Windows and Linux keep every preference in one JSON file, so a stored
      // string list is decoded as List<dynamic>; the element type is all that
      // matters here.
      final List<Object?> items when items.every((item) => item is String) =>
        BackupPreference._(
          'string_list',
          List<String>.unmodifiable(items.cast<String>()),
        ),
      _ => throw const SettingsBackupException(
        SettingsBackupErrorCode.unsupportedFieldType,
      ),
    };
  }

  factory BackupPreference.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      throw const SettingsBackupException(
        SettingsBackupErrorCode.invalidFieldFormat,
      );
    }
    final value = raw['value'];
    final type = raw['type'];
    final Object typed = switch (type) {
      'string' when value is String => value,
      'bool' when value is bool => value,
      'int' when value is int => value,
      'double' when value is num && value.isFinite => value.toDouble(),
      'string_list'
          when value is List && value.every((item) => item is String) =>
        List<String>.unmodifiable(value.whereType<String>()),
      _ => throw const SettingsBackupException(
        SettingsBackupErrorCode.unsupportedFieldType,
      ),
    };
    return fromValue(typed);
  }

  Map<String, Object> toJson() => {'type': type, 'value': value};
}

class BackupDocument {
  static const currentVersion = 2;

  final int sourceVersion;
  final DateTime? exportedAt;
  final Set<BackupCategory> categories;
  final Map<String, BackupPreference> preferences;
  final int skippedCount;
  bool _validated = false;

  BackupDocument({
    required Set<BackupCategory> categories,
    required Map<String, BackupPreference> preferences,
    this.exportedAt,
    this.sourceVersion = currentVersion,
    this.skippedCount = 0,
  }) : categories = Set.unmodifiable(categories),
       preferences = Map.unmodifiable(preferences);

  BackupDocument select(Set<BackupCategory> selected) {
    if (selected.isEmpty || !categories.containsAll(selected)) {
      throw const SettingsBackupException(SettingsBackupErrorCode.noCategories);
    }
    final result = BackupDocument(
      categories: selected,
      preferences: {
        for (final entry in preferences.entries)
          if (selected.contains(BackupSchema.categoryOf(entry.key)))
            entry.key: entry.value,
      },
      exportedAt: exportedAt,
      sourceVersion: sourceVersion,
      skippedCount: skippedCount,
    );
    result._validated = _validated;
    return result;
  }

  Map<String, Object?> get metadata => {
    'app': 'kira',
    'kind': 'settings_backup',
    'version': currentVersion,
    'exported_at': exportedAt?.toUtc().toIso8601String(),
    'categories': [
      for (final category in BackupCategory.values)
        if (categories.contains(category)) category.name,
    ],
  };

  Map<String, Object?> toJson() => {
    ...metadata,
    'preferences': {
      for (final entry in preferences.entries) entry.key: entry.value.toJson(),
    },
  };

  static BackupDocument parse(String raw) {
    var text = raw.trim();
    if (text.startsWith('\uFEFF')) text = text.substring(1).trimLeft();
    if (text.startsWith('```')) {
      final lines = const LineSplitter().convert(text);
      if (lines.length >= 2 && lines.last.trim() == '```') {
        text = lines.sublist(1, lines.length - 1).join('\n').trim();
      }
    }
    if (text.isEmpty) {
      throw const SettingsBackupException(SettingsBackupErrorCode.emptyFile);
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const SettingsBackupException(SettingsBackupErrorCode.invalidJson);
    }
    if (decoded is! Map<String, dynamic>) {
      throw const SettingsBackupException(
        SettingsBackupErrorCode.invalidFormat,
      );
    }
    if (decoded['app'] != 'kira' || decoded['kind'] != 'settings_backup') {
      throw const SettingsBackupException(SettingsBackupErrorCode.wrongApp);
    }
    final version = decoded['version'];
    if (version is! int || (version != 1 && version != currentVersion)) {
      throw const SettingsBackupException(
        SettingsBackupErrorCode.unsupportedVersion,
      );
    }
    final rawPreferences = decoded['preferences'];
    if (rawPreferences is! Map<String, dynamic>) {
      throw const SettingsBackupException(
        SettingsBackupErrorCode.missingContent,
      );
    }
    final categories = <BackupCategory>{};
    if (version == currentVersion) {
      final names = decoded['categories'];
      if (names is! List || names.isEmpty) {
        throw const SettingsBackupException(
          SettingsBackupErrorCode.noCategories,
        );
      }
      for (final name in names) {
        final category = BackupCategory.values
            .where((category) => category.name == name)
            .firstOrNull;
        if (category == null || !categories.add(category)) {
          throw const SettingsBackupException(
            SettingsBackupErrorCode.invalidFormat,
          );
        }
      }
    }
    final preferences = <String, BackupPreference>{};
    var skipped = 0;
    for (final entry in rawPreferences.entries) {
      final category = BackupSchema.categoryOf(entry.key);
      if (category == null) {
        // v1 exported arbitrary local data. Read the file, but never restore
        // caches, paths, WebDAV secrets or unknown preferences from it.
        if (version == 1) {
          skipped++;
          continue;
        }
        throw const SettingsBackupException(
          SettingsBackupErrorCode.unsupportedField,
        );
      }
      if (version == 1) categories.add(category);
      if (!categories.contains(category)) {
        throw const SettingsBackupException(
          SettingsBackupErrorCode.invalidFieldFormat,
        );
      }
      final preference = BackupPreference.fromJson(entry.value);
      if (preference.type != BackupSchema.typeOf(entry.key)) {
        throw const SettingsBackupException(
          SettingsBackupErrorCode.unsupportedFieldType,
        );
      }
      // ThemeMode is indexed directly by both the facade and theme store.
      if (entry.key == 'theme_mode' &&
          (preference.value is! int ||
              !const {0, 1, 2}.contains(preference.value))) {
        throw const SettingsBackupException(
          SettingsBackupErrorCode.invalidFieldFormat,
        );
      }
      preferences[entry.key] = preference;
    }
    final date = decoded['exported_at'];
    if (date != null && (date is! String || DateTime.tryParse(date) == null)) {
      throw const SettingsBackupException(
        SettingsBackupErrorCode.invalidFieldFormat,
      );
    }
    validateBackupRecords(preferences);
    if (version == 1 && !hasValidAiProviderReference(preferences)) {
      // Old "safe" exports omitted ai_providers but kept the selected id.
      // Drop that dangling reference; never bind it to local providers.
      preferences.remove('ai_active_provider');
      skipped++;
      if (!preferences.keys.any(
        (key) => BackupSchema.categoryOf(key) == BackupCategory.aiConnection,
      )) {
        categories.remove(BackupCategory.aiConnection);
      }
    }
    if (!hasValidAiProviderReference(preferences)) {
      throw const SettingsBackupException(
        SettingsBackupErrorCode.invalidFieldFormat,
      );
    }
    final result = BackupDocument(
      categories: categories,
      preferences: preferences,
      exportedAt: date is String ? DateTime.parse(date) : null,
      sourceVersion: version,
      skippedCount: skipped,
    );
    result._validated = true;
    return result;
  }

  void validate() {
    if (_validated) return;
    for (final entry in preferences.entries) {
      if (!categories.contains(BackupSchema.categoryOf(entry.key)) ||
          entry.value.type != BackupSchema.typeOf(entry.key) ||
          (entry.key == 'theme_mode' &&
              !const {0, 1, 2}.contains(entry.value.value))) {
        throw const SettingsBackupException(
          SettingsBackupErrorCode.invalidFieldFormat,
        );
      }
    }
    validateBackupRecords(preferences);
    if (!hasValidAiProviderReference(preferences)) {
      throw const SettingsBackupException(
        SettingsBackupErrorCode.invalidFieldFormat,
      );
    }
    _validated = true;
  }
}

class BackupCategorySummary {
  final int count;
  final int rawBytes;

  const BackupCategorySummary({required this.count, required this.rawBytes});
}
