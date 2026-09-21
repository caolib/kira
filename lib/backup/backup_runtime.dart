import '../api/api_client.dart';
import '../utils/bookmark_store.dart';
import '../utils/reading_history.dart';
import '../utils/reading_stats.dart';
import '../utils/settings_reload.dart';
import 'backup_category.dart';

abstract interface class BackupRuntime {
  Future<void> flush();
  Future<void> pause();
  Future<void> reload(Set<BackupCategory> categories);
  void resume();
}

class SettingsBackupRuntime implements BackupRuntime {
  @override
  Future<void> flush() async {
    await Future.wait([
      ReadingHistory.flush(),
      ReadingStats.flush(),
      BookmarkStore().flush(),
    ]);
  }

  @override
  Future<void> pause() async {
    await Future.wait([
      ReadingHistory.pauseForRestore(),
      ReadingStats.pauseForRestore(),
      BookmarkStore().pauseForRestore(),
    ]);
  }

  @override
  Future<void> reload(Set<BackupCategory> categories) async {
    if (categories.contains(BackupCategory.account)) {
      ApiClient().user.clearAuthState();
    }
    await reloadRuntimeSettings(categories: categories, strict: true);
    if (categories.contains(BackupCategory.readingHistory)) {
      ReadingHistory.notifyRestored();
    }
  }

  @override
  void resume() {
    ReadingHistory.resumeAfterRestore();
    ReadingStats.resumeAfterRestore();
    BookmarkStore().resumeAfterRestore();
  }
}
