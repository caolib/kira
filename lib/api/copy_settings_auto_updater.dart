import 'dart:async';

import '../api/api_client.dart';
import '../models/user_manager.dart';
import '../utils/app_logger.dart';

/// 自动更新 COPY 高级设置（API host + app version）。
///
/// 策略：仅在应用启动时检查一次。若距上次更新已超过 [staleThreshold]，
/// 则后台自动拉取最新值并写入；失败静默（只记录日志），不打扰用户。
/// 不保证每次启动都更新——只在「过时」时才尝试。
class CopySettingsAutoUpdater {
  CopySettingsAutoUpdater._();

  static const staleThreshold = Duration(days: 1);

  /// 应用启动时调用一次。fire-and-forget，失败不抛出。
  static void maybeUpdateOnStartup() {
    final user = UserManager();
    if (!user.copyAutoUpdate) return;

    final last = user.copySettingsUpdatedAt;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (last != null && now - last < staleThreshold.inMilliseconds) {
      return; // 未过时，跳过
    }

    unawaited(_update(user));
  }

  static Future<void> _update(UserManager user) async {
    try {
      final apiHost = await ApiClient().network.fetchCopyApiHost();
      final version = await ApiClient().manga.fetchCopyLatestAppVersion();

      await user.setCopyApiHost(apiHost);
      await user.setCopyAppVersion(version);
      await user.markCopySettingsUpdated();
    } catch (e, stack) {
      // 失败就失败：记录一次时间戳，避免每次启动都因网络问题反复重试。
      // ponytail: 这里即使失败也标记更新时间，防止启动时高频重试
      await user.markCopySettingsUpdated();
      unawaited(
        AppLogger.instance.recordWarning(
          'COPY 设置自动更新失败: $e',
          stackTrace: stack,
          source: 'copy_auto_update',
        ),
      );
    }
  }
}
