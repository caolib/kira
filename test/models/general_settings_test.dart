import 'package:flutter_test/flutter_test.dart';
import 'package:kira/backup/backup_category.dart';
import 'package:kira/models/general_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GeneralSettings settings;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    settings = GeneralSettings()..resetPrefsCache();
  });

  test('剪贴板分享链接自动识别默认关闭', () async {
    await settings.initFromPrefs(await SharedPreferences.getInstance());
    expect(settings.autoCheckClipboardSharedLinks, isFalse);
  });

  test('开关持久化，重载保留选择且每次修改只通知一次', () async {
    final prefs = await SharedPreferences.getInstance();
    await settings.initFromPrefs(prefs);
    var notifications = 0;
    void onChanged() => notifications++;
    settings.addListener(onChanged);
    addTearDown(() => settings.removeListener(onChanged));

    await settings.setAutoCheckClipboardSharedLinks(true);
    expect(settings.autoCheckClipboardSharedLinks, isTrue);
    expect(prefs.getBool('auto_check_clipboard_shared_links'), isTrue);
    expect(notifications, 1);

    settings.resetPrefsCache();
    await settings.initFromPrefs(await SharedPreferences.getInstance());
    expect(settings.autoCheckClipboardSharedLinks, isTrue);
    await settings.setAutoCheckClipboardSharedLinks(true);
    expect(notifications, 1);

    await settings.setAutoCheckClipboardSharedLinks(false);
    expect(prefs.getBool('auto_check_clipboard_shared_links'), isFalse);
    expect(notifications, 2);
    settings.resetPrefsCache();
    await settings.initFromPrefs(await SharedPreferences.getInstance());
    expect(settings.autoCheckClipboardSharedLinks, isFalse);
  });

  test('未设置时恢复默认值并重新绑定持久化后端', () async {
    await settings.initFromPrefs(await SharedPreferences.getInstance());
    await settings.setAutoCheckClipboardSharedLinks(true);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await settings.initFromPrefs(prefs);
    expect(settings.autoCheckClipboardSharedLinks, isFalse);
    await settings.setAutoCheckClipboardSharedLinks(true);
    expect(prefs.getBool('auto_check_clipboard_shared_links'), isTrue);
  });

  test('剪贴板开关按布尔型普通设置纳入备份', () {
    const key = 'auto_check_clipboard_shared_links';
    expect(BackupSchema.categoryOf(key), BackupCategory.settings);
    expect(BackupSchema.typeOf(key), 'bool');
  });
}
