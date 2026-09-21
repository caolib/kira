import 'package:shared_preferences/shared_preferences.dart';

import 'backup_error.dart';

abstract interface class BackupPreferences {
  Future<Map<String, Object>> readAll();
  Future<void> write(String key, Object value);
  Future<void> remove(String key);
}

class SharedBackupPreferences implements BackupPreferences {
  @override
  Future<Map<String, Object>> readAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().toList()..sort();
    final snapshot = <String, Object>{};
    for (final key in keys) {
      final value = prefs.get(key);
      if (value != null) {
        snapshot[key] = value is List<String> ? List<String>.of(value) : value;
      }
    }
    return snapshot;
  }

  @override
  Future<void> write(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    final ok = await switch (value) {
      String() => prefs.setString(key, value),
      bool() => prefs.setBool(key, value),
      int() => prefs.setInt(key, value),
      double() => prefs.setDouble(key, value),
      List<String>() => prefs.setStringList(key, value),
      _ => throw const SettingsBackupException(
        SettingsBackupErrorCode.unsupportedFieldType,
      ),
    };
    if (!ok) {
      throw const SettingsBackupException(SettingsBackupErrorCode.writeFailed);
    }
  }

  @override
  Future<void> remove(String key) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove(key)) {
      throw const SettingsBackupException(SettingsBackupErrorCode.writeFailed);
    }
  }
}
