import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/reading_history.dart';
import 'package:kira/utils/settings_backup.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Map<String, dynamic> decodeBackup(String backup) {
    final decoded = jsonDecode(backup);
    if (decoded is! Map) fail('backup is not a JSON object');
    return Map<String, dynamic>.from(decoded);
  }

  Map<String, dynamic> preferencesOf(Map<String, dynamic> backup) {
    final preferences = backup['preferences'];
    if (preferences is! Map) fail('preferences is not a JSON object');
    return Map<String, dynamic>.from(preferences);
  }

  test(
    'exports persistent settings excluding cache and sensitive data by default',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_token', 'token-1');
      await prefs.setString('saved_password', 'password-1');
      await prefs.setString('zhipu_api_key', 'api-key-1');
      await prefs.setBool('auto_login', true);
      await prefs.setBool('image_viewer_auto_rotate_landscape', true);
      await prefs.setInt('image_viewer_landscape_rotation', -1);
      await prefs.setString('cache_home', '{"stale":false}');
      await prefs.setString(
        'cache_manga_chapter_detail_v1_comic-a_chapter-3',
        '{"chapter":{"contents":[{"url":"https://example.com/1.jpg"}]}}',
      );
      await ReadingHistory.save(
        pathWord: 'comic-a',
        group: ReadingHistory.defaultGroup,
        chapterUuid: 'chapter-3',
        chapterName: '第3话',
        page: 5,
        totalPage: 20,
      );

      final backup = await SettingsBackupService().exportPlainText();
      final decoded = decodeBackup(backup);
      final preferences = preferencesOf(decoded);

      expect(decoded['includes_sensitive'], isFalse);
      expect(decoded['skipped_sensitive_count'], 3);
      expect(preferences.containsKey('user_token'), isFalse);
      expect(preferences.containsKey('saved_password'), isFalse);
      expect(preferences.containsKey('zhipu_api_key'), isFalse);
      expect(preferences['auto_login']?['value'], true);
      expect(preferences['image_viewer_auto_rotate_landscape']?['value'], true);
      expect(preferences['image_viewer_landscape_rotation']?['value'], -1);
      expect(preferences.containsKey('reading_history_comic-a'), isTrue);
      expect(preferences.containsKey('cache_home'), isFalse);
      expect(
        preferences.containsKey(
          'cache_manga_chapter_detail_v1_comic-a_chapter-3',
        ),
        isFalse,
      );
    },
  );

  test('exports sensitive settings only when requested', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_token', 'token-1');
    await prefs.setString('saved_password', 'password-1');
    await prefs.setString('zhipu_api_key', 'api-key-1');
    await prefs.setString(
      'ai_providers',
      jsonEncode([
        {'name': 'OpenAI', 'apiKey': 'provider-api-key'},
      ]),
    );
    await prefs.setBool('auto_login', true);

    final backup = await SettingsBackupService().exportPlainText(
      options: const SettingsBackupOptions(includeSensitive: true),
    );
    final decoded = decodeBackup(backup);
    final preferences = preferencesOf(decoded);
    final summary = SettingsBackupService().inspectPlainText(backup);

    expect(decoded['includes_sensitive'], isTrue);
    expect(decoded['skipped_sensitive_count'], 0);
    expect(summary.sensitivePreferenceCount, 4);
    expect(preferences['user_token']?['value'], 'token-1');
    expect(preferences['saved_password']?['value'], 'password-1');
    expect(preferences['zhipu_api_key']?['value'], 'api-key-1');
    expect(preferences.containsKey('ai_providers'), isTrue);
    expect(preferences['auto_login']?['value'], true);
  });

  test('import overrides user settings and keeps cache untouched', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_token', 'old-token');
    await prefs.setBool('auto_login', false);
    await prefs.setString('cache_home', '{"stale":true}');
    await prefs.setString(
      'cache_manga_chapter_detail_v1_comic-b_chapter-8',
      '{"chapter":{"contents":[{"url":"https://example.com/old.jpg"}]}}',
    );

    final backup = jsonEncode({
      'app': 'kira',
      'kind': 'settings_backup',
      'version': 1,
      'exported_at': '2026-05-06T10:00:00.000Z',
      'preferences': {
        'user_token': {'type': 'string', 'value': 'new-token'},
        'auto_login': {'type': 'bool', 'value': true},
        'image_viewer_auto_rotate_landscape': {'type': 'bool', 'value': true},
        'image_viewer_landscape_rotation': {'type': 'int', 'value': -1},
        'reading_history_comic-b': {
          'type': 'string',
          'value': jsonEncode({
            'chapterUuid': 'chapter-8',
            'chapterName': '第8话',
            'page': 9,
            'totalPage': 30,
          }),
        },
      },
    });

    final summary = await SettingsBackupService().importPlainText(backup);
    final record = await ReadingHistory.get('comic-b');

    expect(summary.preferenceCount, 5);
    expect(prefs.getString('user_token'), 'new-token');
    expect(prefs.getBool('auto_login'), isTrue);
    expect(prefs.getBool('image_viewer_auto_rotate_landscape'), isTrue);
    expect(prefs.getInt('image_viewer_landscape_rotation'), -1);
    expect(record?.chapterUuid, 'chapter-8');
    expect(record?.page, 9);
    expect(prefs.getString('cache_home'), '{"stale":true}');
    expect(
      prefs.getString('cache_manga_chapter_detail_v1_comic-b_chapter-8'),
      '{"chapter":{"contents":[{"url":"https://example.com/old.jpg"}]}}',
    );
  });

  test(
    'clearAllPreferences removes settings, reading history, and cache',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_token', 'token-1');
      await prefs.setString('cache_home', '{"stale":false}');
      await ReadingHistory.save(
        pathWord: 'comic-c',
        chapterUuid: 'chapter-12',
        chapterName: '第12话',
        page: 4,
        totalPage: 18,
      );

      final removedCount = await SettingsBackupService().clearAllPreferences();

      expect(removedCount, 3);
      expect(prefs.getKeys(), isEmpty);
      expect(await ReadingHistory.get('comic-c'), isNull);
    },
  );
}
