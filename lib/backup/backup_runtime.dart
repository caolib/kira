import '../api/api_client.dart';
import '../models/user_manager.dart';
import '../utils/bookmark_store.dart';
import '../utils/network_auto_test_scheduler.dart';
import '../utils/novel_bookmark_store.dart';
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
      NovelBookmarkStore().flush(),
    ]);
  }

  @override
  Future<void> pause() async {
    await NetworkAutoTestScheduler.pauseForRestore();
    await UserManager().pauseAccountMutationsForRestore();
    await Future.wait([
      ReadingHistory.pauseForRestore(),
      ReadingStats.pauseForRestore(),
      BookmarkStore().pauseForRestore(),
      NovelBookmarkStore().pauseForRestore(),
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
    NetworkAutoTestScheduler.resumeAfterRestore();
    UserManager().resumeAccountMutationsAfterRestore();
    ReadingHistory.resumeAfterRestore();
    ReadingStats.resumeAfterRestore();
    BookmarkStore().resumeAfterRestore();
    NovelBookmarkStore().resumeAfterRestore();
  }
}
