import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:system_fonts/system_fonts.dart';

import '../api/ai_api.dart';
import '../backup/backup_category.dart';
import '../backup/backup_error.dart';
import '../models/user_manager.dart';
import 'app_logger.dart';
import 'bookmark_store.dart';
import 'download_manager.dart';
import 'font_manager.dart';
import 'reading_stats.dart';

/// 把 SharedPreferences 的当前内容重新灌入各内存单例。
///
/// 导入备份或清除数据后必须调用。这些单例大多用 `_loaded` / `_initialized`
/// 之类的守卫只在进程内加载一次;prefs 被外部改写后内存态不会自己跟上,
/// 表现为“导入成功但设置不生效、要重启才恢复”(如并发下载数量)。
///
/// 每个子系统独立容错:任一个失败只记日志,不阻断其余部分——否则用户刚
/// 导入的其余设置会一起失效。
Future<void> reloadRuntimeSettings({
  Set<BackupCategory>? categories,
  bool strict = false,
}) async {
  bool includes(BackupCategory category) =>
      categories == null || categories.contains(category);
  final settings = includes(BackupCategory.settings);
  if (settings || includes(BackupCategory.account)) {
    await _reloadStep(
      'user_manager',
      () => UserManager().init(persistMigrations: categories == null),
      strict: strict,
    );
  }
  if (settings) {
    await _reloadStep(
      'download_manager',
      () => categories == null
          ? DownloadManager().reloadFromPrefs()
          : DownloadManager().reloadScalarSettings(),
      strict: strict,
    );
  }
  if (settings || includes(BackupCategory.aiConnection)) {
    await _reloadStep(
      'ai_settings',
      () => AiSettings().reloadFromPrefs(persistMigrations: categories == null),
      strict: strict,
    );
  }
  if (settings) {
    await _reloadStep(
      'app_logger',
      () => AppLogger.instance.reloadFromPrefs(),
      strict: strict,
    );
    await _reloadStep(
      'font_manager',
      () async => FontManager().reloadFromPrefs(),
      strict: strict,
    );
  }
  if (includes(BackupCategory.readingStatistics)) {
    await _reloadStep(
      'reading_stats',
      () async => ReadingStats.reloadFromPrefs(),
      strict: strict,
    );
  }
  if (includes(BackupCategory.bookmarks)) {
    await _reloadStep(
      'bookmarks',
      () => BookmarkStore().reload(),
      strict: strict,
    );
  }
  // A missing desktop font is not a storage-transaction failure.
  if (settings) await _reloadStep('fonts', _reapplyFonts);
}

Future<void> _reloadStep(
  String source,
  Future<void> Function() step, {
  bool strict = false,
}) async {
  try {
    await step();
  } catch (e, stack) {
    await AppLogger.instance.recordWarning(
      strict
          ? const SettingsBackupException(SettingsBackupErrorCode.writeFailed)
          : e,
      stackTrace: stack,
      source: 'settings_reload.$source',
    );
    if (strict) {
      throw const SettingsBackupException(SettingsBackupErrorCode.writeFailed);
    }
  }
}

/// 重新把选中的字体加载进引擎,与 `main.dart` 冷启动的处理保持一致。
///
/// 只改字体名而不加载字节,文字会退回默认字体——同样是“要重启才生效”。
Future<void> _reapplyFonts() async {
  final user = UserManager();
  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    final desktopFont = user.desktopFontFamily;
    if (desktopFont.isNotEmpty) {
      try {
        await SystemFonts().loadFont(desktopFont);
      } catch (e, stack) {
        unawaited(
          AppLogger.instance.recordWarning(
            e,
            stackTrace: stack,
            source: 'settings_reload.desktop_font',
          ),
        );
      }
    }
  }
  final appFont = user.theme.appFontFamily;
  if (appFont.isNotEmpty) {
    unawaited(FontManager().ensureFontReady(appFont));
  }
}
