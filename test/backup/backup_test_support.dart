import 'package:kira/backup/backup_category.dart';
import 'package:kira/backup/backup_document.dart';
import 'package:kira/backup/backup_journal.dart';
import 'package:kira/backup/backup_preferences.dart';
import 'package:kira/backup/backup_runtime.dart';

BackupDocument backupDocument(
  Map<String, Object> values, {
  Set<BackupCategory>? categories,
}) => BackupDocument(
  categories:
      categories ??
      values.keys
          .map(BackupSchema.categoryOf)
          .whereType<BackupCategory>()
          .toSet(),
  preferences: values.map(
    (key, value) => MapEntry(key, BackupPreference.fromValue(value)),
  ),
  exportedAt: DateTime.utc(2026, 9, 14),
);

class MemoryBackupJournal implements BackupJournal {
  BackupDocument? pending;
  bool failSave = false;
  bool failClear = false;
  int saves = 0;

  @override
  Future<BackupDocument?> read() async => pending;

  @override
  Future<void> save(BackupDocument original) async {
    if (failSave) throw StateError('journal write failed');
    pending = original;
    saves++;
  }

  @override
  Future<void> clear() async {
    if (failClear) throw StateError('journal clear failed');
    pending = null;
  }
}

class TestBackupRuntime implements BackupRuntime {
  final BackupRuntime? delegate;
  bool paused = false;
  int reloads = 0;
  int flushes = 0;
  int failReloads = 0;
  Set<BackupCategory>? reloadedCategories;

  TestBackupRuntime({this.delegate});

  @override
  Future<void> flush() async {
    flushes++;
    await delegate?.flush();
  }

  @override
  Future<void> pause() async {
    paused = true;
    await delegate?.pause();
  }

  @override
  Future<void> reload(Set<BackupCategory> categories) async {
    reloads++;
    reloadedCategories = categories;
    if (failReloads > 0) {
      failReloads--;
      throw StateError('reload failed');
    }
  }

  @override
  void resume() {
    paused = false;
    delegate?.resume();
  }
}

class MemoryBackupPreferences implements BackupPreferences {
  final Map<String, Object> values;
  int reads = 0;
  int writes = 0;
  int? failAtWrite;
  bool failAllWrites = false;
  Future<void> Function()? beforeWrite;

  MemoryBackupPreferences([Map<String, Object> initial = const {}])
    : values = Map.of(initial);

  @override
  Future<Map<String, Object>> readAll() async {
    reads++;
    return Map.of(values);
  }

  Future<void> _writeGate() async {
    writes++;
    await beforeWrite?.call();
    if (failAllWrites || writes == failAtWrite) {
      throw StateError('injected persistence failure');
    }
  }

  @override
  Future<void> write(String key, Object value) async {
    await _writeGate();
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    await _writeGate();
    values.remove(key);
  }
}
