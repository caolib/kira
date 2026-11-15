import 'package:flutter_test/flutter_test.dart';
import 'package:kira/backup/backup_codec.dart';
import 'package:kira/models/novel_reading_progress.dart';
import 'package:kira/models/reader_settings.dart';
import 'package:kira/utils/novel_reading_store.dart';
import 'package:kira/utils/reading_stats.dart';
import 'package:kira/utils/settings_backup.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../account_storage_test_support.dart';
import '../test_helpers.dart';
import 'backup_test_support.dart';

class _StatsRuntime extends TestBackupRuntime {
  @override
  Future<void> flush() => ReadingStats.flush();

  @override
  Future<void> pause() => ReadingStats.pauseForRestore();

  @override
  Future<void> reload(Set<BackupCategory> categories) async {
    await (await SharedPreferences.getInstance()).reload();
    if (categories.contains(BackupCategory.readingStatistics)) {
      ReadingStats.reloadFromPrefs();
    }
  }

  @override
  void resume() => ReadingStats.resumeAfterRestore();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AccountPreferencesPlatform platform;

  setUp(() {
    setupSecureCredentialStoreForTest();
    platform = AccountPreferencesPlatform()..install();
    ReadingStats.reloadFromPrefs();
    ReadingStats.resumeAfterRestore();
    ReadingStats.setEnabledGate(() => true);
  });

  tearDown(() {
    ReadingStats.reloadFromPrefs();
    ReadingStats.resumeAfterRestore();
    ReadingStats.setEnabledGate(() => ReaderSettings().readingStatsEnabled);
    platform.dispose();
    teardownSecureCredentialStoreForTest();
  });

  Future<void> read() => ReadingStats.recordNovelReading(
    pathWord: 'novel',
    volumeId: 'v1',
    entryIndex: 2,
    paragraphIndex: 8,
    text: '这是阅读过的正文',
    start: 0,
    end: 8,
    tags: ['奇幻'],
    novelName: '书名',
  );

  test(
    'real records export, decode, restore, cold reload and keep daily dedup',
    () async {
      await ReadingStats.recordImageLoad(
        pathWord: 'comic',
        chapterUuid: 'chapter',
      );
      await read();
      final service = SettingsBackupService(
        journal: MemoryBackupJournal(),
        runtime: _StatsRuntime(),
        logger: TestBackupLogger(),
      );
      final codec = BackupCodec();
      final snapshot = await service.capture();
      expect(
        snapshot.select({BackupCategory.settings}).preferences,
        isNot(contains('reading_stats_v1')),
      );
      final original = snapshot.select({BackupCategory.readingStatistics});
      expect(original.preferences['reading_stats_v1']!.type, 'string');
      final encoded = await codec.encode(await codec.prepare(original));
      final document = await codec.decode(encoded.bytes);
      await ReadingStats.clear(novel: true);
      expect(novelWordsReadCount(await ReadingStats.load()), 0);
      await service.restore(document, {BackupCategory.readingStatistics});
      SharedPreferences.resetStatic();
      ReadingStats.reloadFromPrefs();
      final restored = await ReadingStats.load();
      expect(pagesReadCount(restored), 1);
      expect(novelWordsReadCount(restored), 8);
      expect(restored.novelMeta['novel']!.name, '书名');
      expect(topNovelTags(restored).single.name, '奇幻');
      await read();
      expect(novelWordsReadCount(await ReadingStats.load()), 8);
    },
  );

  test(
    'history initialization and reinitialization survive statistics backup restore',
    () async {
      await NovelReadingStore().saveProgress(
        NovelReadingProgress(
          pathWord: 'old-book',
          name: '旧小说',
          cover: '',
          volumeId: 'v2',
          volumeName: '第二卷',
          entryIndex: 8,
          chapterName: '当前章节',
          updatedAt: DateTime(2026, 8, 3),
          readVolumeIds: const {'v1'},
        ),
      );
      await ReadingStats.initializeNovelsFromHistory();
      final service = SettingsBackupService(
        journal: MemoryBackupJournal(),
        runtime: _StatsRuntime(),
        logger: TestBackupLogger(),
      );
      final codec = BackupCodec();
      final snapshot = (await service.capture()).select({
        BackupCategory.readingStatistics,
      });
      final encoded = await codec.encode(await codec.prepare(snapshot));
      final document = await codec.decode(encoded.bytes);
      await ReadingStats.clear(novel: true);
      await service.restore(document, {BackupCategory.readingStatistics});
      SharedPreferences.resetStatic();
      ReadingStats.reloadFromPrefs();
      final restored = await ReadingStats.load();
      expect(novelsReadCount(restored), 1);
      expect(novelVolumesReadCount(restored), 2);
      expect(novelChaptersReadCount(restored), 1);
      expect(novelWordsReadCount(restored), 0);
      expect(restored.novelHistoryInitialized, isTrue);

      await ReadingStats.clear(novel: true);
      final cleared = (await service.capture()).select({
        BackupCategory.readingStatistics,
      });
      final clearedBytes = await codec.encode(await codec.prepare(cleared));
      final clearedDocument = await codec.decode(clearedBytes.bytes);
      await read();
      await service.restore(clearedDocument, {
        BackupCategory.readingStatistics,
      });
      SharedPreferences.resetStatic();
      ReadingStats.reloadFromPrefs();
      final empty = await ReadingStats.load();
      expect(empty.isEmpty, isTrue);
      expect(empty.novelHistoryInitialized, isFalse);
      await ReadingStats.initializeNovelsFromHistory();
      final initialized = await ReadingStats.load();
      expect(initialized.novelMeta.keys, ['old-book']);
      expect(novelVolumesReadCount(initialized), 2);
      expect(novelChaptersReadCount(initialized), 1);
      expect(novelWordsReadCount(initialized), 0);
      expect(initialized.novelDaily, isEmpty);
      expect(await NovelReadingStore().readProgress('old-book'), isNotNull);
    },
  );

  test(
    'old comic-only backup replaces selected statistics without fabricated novels',
    () async {
      await read();
      final service = SettingsBackupService(
        journal: MemoryBackupJournal(),
        runtime: _StatsRuntime(),
        logger: TestBackupLogger(),
      );
      final document = backupDocument({
        'reading_stats_v1':
            '{"comicMeta":{"comic":{"name":"漫画","tags":[],"chapterImages":{"c":7}}},"daily":{"2026-01-01":7}}',
      });
      await service.restore(document, {BackupCategory.readingStatistics});
      final restored = await ReadingStats.load();
      expect(pagesReadCount(restored), 7);
      expect(novelWordsReadCount(restored), 0);
      expect(restored.novelDaily, isEmpty);
      expect(restored.novelSince, isNull);
    },
  );
}
