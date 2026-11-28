import 'package:flutter_test/flutter_test.dart';
import 'package:kira/backup/backup_codec.dart';
import 'package:kira/models/reader_settings.dart';
import 'package:kira/models/secure_credential_store.dart';
import 'package:kira/utils/settings_backup.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../account_storage_test_support.dart';
import 'backup_test_support.dart';

const _prefix = 'reader_reading_stats_';
const _defaultOrder = ['overview', 'tags', 'activity'];
const _novelOrder = ['activity', 'overview', 'tags'];
const _comicOrder = ['tags', 'activity', 'overview'];
const _newTypes = {
  '${_prefix}show_comics': 'bool',
  '${_prefix}show_novels': 'bool',
  '${_prefix}novel_chart_style': 'int',
  '${_prefix}novel_show_overview': 'bool',
  '${_prefix}novel_show_tags': 'bool',
  '${_prefix}novel_show_activity_chart': 'bool',
  '${_prefix}novel_section_order': 'string_list',
};

class _ReaderSettingsRuntime extends TestBackupRuntime {
  @override
  Future<void> reload(Set<BackupCategory> categories) async {
    await super.reload(categories);
    if (categories.contains(BackupCategory.settings)) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      await ReaderSettings().initFromPrefs(prefs);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final settings = ReaderSettings();
  final codec = BackupCodec();
  late AccountPreferencesPlatform platform;
  late MemoryBackupJournal journal;
  late _ReaderSettingsRuntime runtime;
  late SettingsBackupService service;

  SettingsBackupService createService() => SettingsBackupService(
    journal: journal,
    runtime: runtime,
    logger: TestBackupLogger(),
  );

  setUp(() async {
    platform = AccountPreferencesPlatform()..install();
    SecureCredentialStore.resetInstance();
    settings.resetPrefsCache();
    await settings.initFromPrefs(await SharedPreferences.getInstance());
    journal = MemoryBackupJournal();
    runtime = _ReaderSettingsRuntime();
    service = createService();
  });

  tearDown(() {
    settings.resetPrefsCache();
    platform.dispose();
    SecureCredentialStore.resetInstance();
  });

  Future<void> recreate() async {
    SharedPreferences.resetStatic();
    SecureCredentialStore.resetInstance();
    settings.resetPrefsCache();
    await ReaderSettings().initFromPrefs(await SharedPreferences.getInstance());
    service = createService();
  }

  Future<BackupDocument> exportThroughCodec() async {
    final document = (await service.capture()).select({
      BackupCategory.settings,
    });
    final encoded = await codec.encode(await codec.prepare(document));
    return codec.decode(encoded.bytes);
  }

  Future<void> seedComicSettings() async {
    await settings.setReadingStatsEnabled(true);
    await settings.setReadingStatsChartStyle(1);
    await settings.setReadingStatsShowOverview(false);
    await settings.setReadingStatsShowTags(false);
    await settings.setReadingStatsShowActivityChart(false);
    await settings.setReadingStatsSectionOrder(_comicOrder);
  }

  Future<void> seedNovelSettings({bool hideComics = true}) async {
    // 两个显示键都经过真实 setter 落盘，但最终至少有一类显示。
    await settings.setReadingStatsShowNovels(false);
    await settings.setReadingStatsShowNovels(true);
    await settings.setReadingStatsShowComics(false);
    if (!hideComics) {
      await settings.setReadingStatsShowComics(true);
      await settings.setReadingStatsShowNovels(false);
    }
    await settings.setNovelReadingStatsChartStyle(1);
    await settings.setNovelReadingStatsShowOverview(false);
    await settings.setNovelReadingStatsShowTags(false);
    await settings.setNovelReadingStatsShowActivityChart(false);
    await settings.setNovelReadingStatsSectionOrder(_novelOrder);
  }

  Future<void> resetNovelSettings() async {
    await settings.setReadingStatsShowComics(true);
    await settings.setReadingStatsShowNovels(true);
    await settings.setNovelReadingStatsChartStyle(0);
    await settings.setNovelReadingStatsShowOverview(true);
    await settings.setNovelReadingStatsShowTags(true);
    await settings.setNovelReadingStatsShowActivityChart(true);
    await settings.setNovelReadingStatsSectionOrder(_defaultOrder);
  }

  void expectComicSettings() {
    expect(settings.readingStatsEnabled, isTrue);
    expect(settings.readingStatsChartStyle, 1);
    expect(settings.readingStatsShowOverview, isFalse);
    expect(settings.readingStatsShowTags, isFalse);
    expect(settings.readingStatsShowActivityChart, isFalse);
    expect(settings.readingStatsSectionOrder, _comicOrder);
  }

  void expectNovelSettings({bool defaults = false, bool hideComics = true}) {
    expect(settings.readingStatsShowComics, defaults || !hideComics);
    expect(settings.readingStatsShowNovels, defaults || hideComics);
    expect(settings.novelReadingStatsChartStyle, defaults ? 0 : 1);
    expect(settings.novelReadingStatsShowOverview, defaults);
    expect(settings.novelReadingStatsShowTags, defaults);
    expect(settings.novelReadingStatsShowActivityChart, defaults);
    expect(
      settings.novelReadingStatsSectionOrder,
      defaults ? _defaultOrder : _novelOrder,
    );
  }

  test('章节自动定位沿用布尔设置备份，旧备份恢复为关闭', () async {
    const key = 'reader_auto_locate_last_read_chapter';
    expect(settings.autoLocateLastReadChapter, isFalse);
    final legacy = await exportThroughCodec();
    expect(legacy.preferences[key], isNull);

    platform
      ..failKey = key
      ..failValue = true;
    await expectLater(
      settings.setAutoLocateLastReadChapter(true),
      throwsStateError,
    );
    expect(settings.autoLocateLastReadChapter, isFalse);
    expect((await SharedPreferences.getInstance()).getBool(key), isNull);

    await settings.setAutoLocateLastReadChapter(true);
    await recreate();
    expect(settings.autoLocateLastReadChapter, isTrue);
    final enabled = await exportThroughCodec();
    expect(enabled.preferences[key]?.type, 'bool');
    expect(enabled.preferences[key]?.value, isTrue);

    await service.restore(legacy, {BackupCategory.settings});
    expect(settings.autoLocateLastReadChapter, isFalse);
    await service.restore(enabled, {BackupCategory.settings});
    await recreate();
    expect(settings.autoLocateLastReadChapter, isTrue);
  });

  test('all seven keys have exact portable settings types', () {
    for (final entry in _newTypes.entries) {
      expect(
        BackupSchema.categoryOf(entry.key),
        BackupCategory.settings,
        reason: entry.key,
      );
      expect(BackupSchema.typeOf(entry.key), entry.value, reason: entry.key);
    }
    expect(BackupSchema.typeOf('${_prefix}novel_unknown'), isNull);
    expect(BackupSchema.typeOf('${_prefix}novel_enabled'), isNull);
  });

  for (final hideComics in [true, false]) {
    test('real setters export/codec/restore/reload both domains '
        '(hide comics: $hideComics)', () async {
      await seedComicSettings();
      final comicValues = Map.of(platform.values);
      await seedNovelSettings(hideComics: hideComics);
      for (final entry in comicValues.entries) {
        expect(platform.values[entry.key], entry.value, reason: entry.key);
      }
      final expected = Map.of(platform.values);
      final document = await exportThroughCodec();
      expect(document.preferences, hasLength(comicValues.length + 7));
      for (final entry in _newTypes.entries) {
        expect(document.preferences[entry.key]?.type, entry.value);
        expect(
          document.preferences[entry.key]?.value,
          expected['flutter.${entry.key}'],
        );
      }

      await resetNovelSettings();
      // 重建默认 prefs 后端与备份服务，避免恢复只修改旧内存缓存。
      await recreate();
      await service.restore(document, {BackupCategory.settings});
      expect(platform.values, expected);
      expect(runtime.reloads, 1);
      expect(runtime.reloadedCategories, {BackupCategory.settings});
      expect(runtime.paused, isFalse);
      expect(journal.pending, isNull);
      expectComicSettings();
      expectNovelSettings(hideComics: hideComics);
      for (var boot = 0; boot < 2; boot++) {
        await recreate();
        expectComicSettings();
        expectNovelSettings(hideComics: hideComics);
      }
    });
  }

  test(
    'old comic-only backup restores novel defaults, not comic choices',
    () async {
      await seedComicSettings();
      final expected = Map.of(platform.values);
      final legacy = await exportThroughCodec();
      expect(
        legacy.preferences.keys.toSet().intersection(_newTypes.keys.toSet()),
        isEmpty,
      );
      await seedNovelSettings();
      await service.restore(legacy, {BackupCategory.settings});
      expect(platform.values, expected);
      expectComicSettings();
      expectNovelSettings(defaults: true);
      await recreate();
      expectComicSettings();
      expectNovelSettings(defaults: true);
    },
  );

  test(
    'empty settings backup clears saved values and reloads true defaults',
    () async {
      final empty = await exportThroughCodec();
      expect(empty.preferences, isEmpty);
      await seedComicSettings();
      await seedNovelSettings();
      await service.restore(empty, {BackupCategory.settings});
      expect(platform.values, isEmpty);
      expect(settings.readingStatsEnabled, isFalse);
      expectNovelSettings(defaults: true);
      await recreate();
      expect(settings.readingStatsEnabled, isFalse);
      expect(settings.readingStatsChartStyle, 0);
      expect(settings.readingStatsSectionOrder, _defaultOrder);
      expectNovelSettings(defaults: true);
    },
  );

  for (final suffix in [
    'novel_show_overview',
    'novel_chart_style',
    'novel_section_order',
  ]) {
    test(
      'restore rolls back a false $suffix write and remains retryable',
      () async {
        await seedComicSettings();
        await seedNovelSettings();
        final document = await exportThroughCodec();
        await resetNovelSettings();
        final original = Map.of(platform.values);
        platform
          ..failKey = '$_prefix$suffix'
          ..beforeWrite = (_, value) async => platform.failValue = value;
        await expectLater(
          service.restore(document, {BackupCategory.settings}),
          throwsA(
            isA<SettingsBackupException>().having(
              (error) => error.code,
              'code',
              SettingsBackupErrorCode.writeFailed,
            ),
          ),
        );
        expect(platform.values, original);
        expect(journal.pending, isNull);
        expect(runtime.paused, isFalse);
        expectComicSettings();
        expectNovelSettings(defaults: true);
        await recreate();
        expectComicSettings();
        expectNovelSettings(defaults: true);
        platform.beforeWrite = null;
        await service.restore(document, {BackupCategory.settings});
        await recreate();
        expectComicSettings();
        expectNovelSettings();
      },
    );
  }
}
