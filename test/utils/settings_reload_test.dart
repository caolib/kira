import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/api/ai_api.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/utils/app_logger.dart';
import 'package:kira/utils/download_manager.dart';
import 'package:kira/utils/font_manager.dart';
import 'package:kira/utils/reading_stats.dart';
import 'package:kira/utils/settings_backup.dart';
import 'package:kira/utils/settings_reload.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

/// 回归测试:导入备份后,内存单例必须跟上 prefs。
///
/// 修复前,`DownloadManager` / `AiSettings` / `AppLogger` / `ReadingStats` /
/// `FontManager` 都用一次性守卫只在进程内加载一次,导入后内存里仍是旧值,
/// 表现为“导入成功但设置不生效、要重启才恢复”。
///
/// 这里刻意使用生产单例而非 `forTesting` 实例:`reloadRuntimeSettings` 刷新
/// 的正是这些单例,只有它们能真实反映缺陷。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory root;

  setUp(() async {
    setupSecureCredentialStoreForTest();
    root = await Directory.systemTemp.createTemp('kira_import_apply_test');
    // DownloadManager._initialize 会解析下载根目录,需要 path_provider。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          return root.path;
        });
    SharedPreferences.setMockInitialValues({
      'download_image_concurrency': 8,
      'zhipu_model': 'old-model',
      'app_logging_enabled': false,
    });
    ReadingStats.reloadFromPrefs();
    FontManager().reloadFromPrefs();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    teardownSecureCredentialStoreForTest();
    try {
      if (await root.exists()) await root.delete(recursive: true);
    } on FileSystemException {
      // 后台任务可能仍在写文件;清理失败不影响断言。
    }
  });

  /// 构造一份含指定覆盖项的备份 JSON。
  String backupWith(Map<String, Map<String, Object>> overrides) {
    return jsonEncode({
      'app': 'kira',
      'kind': 'settings_backup',
      'version': 1,
      'exported_at': '2026-05-06T10:00:00.000Z',
      'preferences': overrides,
    });
  }

  Future<void> importAndReload(
    Map<String, Map<String, Object>> overrides,
  ) async {
    await SettingsBackupService().importPlainText(backupWith(overrides));
    await reloadRuntimeSettings();
  }

  test('import applies download concurrency to the manager', () async {
    final manager = DownloadManager();
    await manager.init();
    expect(manager.imageDownloadConcurrency, 8);
    expect(manager.downloadCommentsEnabled, isTrue);

    await importAndReload({
      'download_image_concurrency': {'type': 'int', 'value': 20},
      'download_chapter_comments': {'type': 'bool', 'value': false},
    });

    expect(manager.imageDownloadConcurrency, 20);
    expect(manager.downloadCommentsEnabled, isFalse);
  });

  test('import applies AI settings to the singleton', () async {
    final ai = AiSettings();
    await ai.load();
    expect(ai.model, 'old-model');

    await importAndReload({
      'zhipu_model': {'type': 'string', 'value': 'new-model'},
    });

    expect(ai.model, 'new-model');
  });

  test('import applies logger settings to the singleton', () async {
    final logger = AppLogger.instance;
    await logger.init();
    expect(logger.loggingEnabled, isFalse);

    await importAndReload({
      'app_logging_enabled': {'type': 'bool', 'value': true},
    });

    expect(logger.loggingEnabled, isTrue);
  });

  test('import refreshes the reading stats cache', () async {
    expect((await ReadingStats.load()).isEmpty, isTrue);

    await importAndReload({
      'reading_stats_v1': {
        'type': 'string',
        'value': jsonEncode({
          'since': '2026-01-01',
          'daily': <String, int>{},
          'comicMeta': {
            'pw': {
              'name': 'X',
              'tags': <String>[],
              'chapterImages': {'c1': 3},
            },
          },
        }),
      },
    });

    expect((await ReadingStats.load()).comicMeta.keys, contains('pw'));
  });

  test('reload does not multiply sub-store notifications', () async {
    // init() 会重复调用:ChangeNotifier.addListener 对同一闭包是累加的,
    // 不先移除就会让每次通知被放大。
    final user = UserManager();
    await user.init();
    await user.init();

    var notifications = 0;
    void listener() => notifications++;
    user.addListener(listener);
    user.reader.notifyListeners();
    user.removeListener(listener);

    expect(notifications, 1);
  });
}
