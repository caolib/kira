import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/chapter.dart';
import 'package:kira/models/comic.dart';
import 'package:kira/utils/download_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not met before the timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

ChapterDetail _detail(String uuid, {int pages = 2}) => ChapterDetail(
  uuid: uuid,
  index: 1,
  name: uuid,
  contents: [for (var i = 0; i < pages; i++) 'https://image/$uuid/$i.jpg'],
);

Comic _comic() => Comic(name: 'Comic', pathWord: 'pw', cover: '');

Future<File> _writeFakeImage(
  String imageUrl,
  Directory chapterDir,
  int index,
) async {
  await chapterDir.create(recursive: true);
  final file = File(
    '${chapterDir.path}${Platform.pathSeparator}${index.toString().padLeft(3, '0')}.jpg',
  );
  await file.writeAsString(imageUrl);
  return file;
}

void main() {
  final sep = Platform.pathSeparator;

  group('concurrency settings clamp', () {
    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
    });

    test('image concurrency clamps to 1-32, invalid falls back to 8', () async {
      final manager = DownloadManager();
      expect(await manager.setImageDownloadConcurrency(0), 8);
      expect(await manager.setImageDownloadConcurrency(99), 32);
      expect(await manager.setImageDownloadConcurrency(16), 16);
      expect(manager.imageDownloadConcurrency, 16);
    });
  });

  group('pause controls', () {
    test('global pause/resume toggles the paused flag idempotently', () {
      final manager = DownloadManager()..resumeDownloads();
      expect(manager.paused, isFalse);

      manager.pauseDownloads();
      manager.pauseDownloads();
      expect(manager.paused, isTrue);

      manager.resumeDownloads();
      manager.resumeDownloads();
      expect(manager.paused, isFalse);
    });

    test('per-chapter pause/resume tracks task keys', () {
      final manager = DownloadManager();
      manager.pauseChapter('pw', 'ch1');
      expect(manager.isChapterPaused('pw', 'ch1'), isTrue);
      expect(manager.isChapterPaused('pw', 'ch2'), isFalse);

      // 重复暂停幂等，恢复后可再次安全恢复（no-op）。
      manager.pauseChapter('pw', 'ch1');
      manager.resumeChapter('pw', 'ch1');
      manager.resumeChapter('pw', 'ch1');
      expect(manager.isChapterPaused('pw', 'ch1'), isFalse);
    });
  });

  group('batch pause/resume', () {
    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
    });

    test('pauseChapters marks multiple chapters paused idempotently', () {
      final manager = DownloadManager();
      manager.pauseChapters([
        (pathWord: 'pw', chapterUuid: 'ch1'),
        (pathWord: 'pw', chapterUuid: 'ch2'),
        (pathWord: 'pw', chapterUuid: 'ch1'),
      ]);
      expect(manager.isChapterPaused('pw', 'ch1'), isTrue);
      expect(manager.isChapterPaused('pw', 'ch2'), isTrue);
      expect(manager.isChapterPaused('pw', 'ch3'), isFalse);

      manager.resumeChapters([
        (pathWord: 'pw', chapterUuid: 'ch1'),
        (pathWord: 'pw', chapterUuid: 'ch3'),
      ]);
      expect(manager.isChapterPaused('pw', 'ch1'), isFalse);
      expect(manager.isChapterPaused('pw', 'ch2'), isTrue);
      expect(manager.isChapterPaused('pw', 'ch3'), isFalse);
    });

    test('empty/no-op batch does not break', () {
      final manager = DownloadManager();
      manager.pauseChapters(const []);
      manager.resumeChapters(const []);
      expect(manager.paused, isFalse);
    });
  });

  group('queue cancellation and recovery', () {
    late Directory root;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({
        'download_chapter_comments': false,
      });
      root = await Directory.systemTemp.createTemp('kira_download_queue_test');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('deleting a pending chapter keeps other chapters queued', () async {
      final manager = DownloadManager.forTesting(
        rootDirectory: root,
        chapterDetailLoader: (pathWord, chapterUuid) async =>
            _detail(chapterUuid),
        imageDownloader: _writeFakeImage,
      );
      await manager.init();
      manager.pauseDownloads();

      await manager.enqueueChapters(
        pathWord: 'pw',
        comic: _comic(),
        chapters: [
          Chapter(uuid: 'ch1', index: 1, name: '1'),
          Chapter(uuid: 'ch2', index: 2, name: '2'),
        ],
      );

      await manager.deleteQueuedChapter('pw', 'ch1');

      expect(manager.isQueued('pw', 'ch1'), isFalse);
      expect(manager.isQueued('pw', 'ch2'), isTrue);
      expect(manager.tasks.map((task) => task.chapterUuid), ['ch2']);

      await manager.deleteQueuedChapter('pw', 'ch2');
    });

    test('deleting while chapter details are loading releases the run', () async {
      final detailStarted = Completer<void>();
      final detailGate = Completer<void>();
      var firstDetail = true;
      final manager = DownloadManager.forTesting(
        rootDirectory: root,
        chapterDetailLoader: (pathWord, chapterUuid) async {
          if (firstDetail) {
            firstDetail = false;
            detailStarted.complete();
            await detailGate.future;
          }
          return _detail(chapterUuid);
        },
        imageDownloader: _writeFakeImage,
      );
      await manager.init();

      await manager.enqueueChapters(
        pathWord: 'pw',
        comic: _comic(),
        chapters: [Chapter(uuid: 'ch1', index: 1, name: '1')],
      );
      await detailStarted.future;

      final deleting = manager.deleteQueuedChapter('pw', 'ch1');
      expect(manager.tasks, isEmpty);
      detailGate.complete();
      await deleting;

      expect(manager.isBusy, isFalse);
      expect(manager.isQueued('pw', 'ch1'), isFalse);
      expect(
        Directory(
          '${root.path}${Platform.pathSeparator}pw${Platform.pathSeparator}ch1',
        ).existsSync(),
        isFalse,
      );

      final prefs = await SharedPreferences.getInstance();
      final state =
          jsonDecode(prefs.getString('download_queue_state_v1')!)
              as Map<String, dynamic>;
      expect(state['tasks'], isEmpty);

      // The cancelled key must not poison a later task with the same identity.
      await manager.enqueueChapters(
        pathWord: 'pw',
        comic: _comic(),
        chapters: [Chapter(uuid: 'ch1', index: 1, name: '1')],
      );
      await _waitUntil(() => !manager.isQueued('pw', 'ch1'));
      expect(manager.isDownloaded('pw', 'ch1'), isTrue);
    });

    test(
      'deleting while an image request is in flight cleans the chapter',
      () async {
        final imageStarted = Completer<void>();
        final imageGate = Completer<void>();
        final manager = DownloadManager.forTesting(
          rootDirectory: root,
          chapterDetailLoader: (pathWord, chapterUuid) async =>
              _detail(chapterUuid),
          imageDownloader: (url, directory, index) async {
            if (!imageStarted.isCompleted) imageStarted.complete();
            await imageGate.future;
            return _writeFakeImage(url, directory, index);
          },
        );
        await manager.init();

        await manager.enqueueChapters(
          pathWord: 'pw',
          comic: _comic(),
          chapters: [Chapter(uuid: 'ch1', index: 1, name: '1')],
        );
        await imageStarted.future;

        final deleting = manager.deleteQueuedChapter('pw', 'ch1');
        expect(manager.tasks, isEmpty);
        imageGate.complete();
        await deleting;

        expect(manager.isBusy, isFalse);
        expect(manager.isDownloaded('pw', 'ch1'), isFalse);
        expect(manager.downloadedChapters('pw'), isEmpty);
      },
    );

    test(
      'resume starts a queue restored in the globally paused state',
      () async {
        final chapter = Chapter(uuid: 'ch1', index: 1, name: '1');
        SharedPreferences.setMockInitialValues({
          'download_chapter_comments': false,
          'download_queue_state_v1': jsonEncode({
            'version': 1,
            'paused': true,
            'paused_tasks': [],
            'tasks': [
              DownloadManager.encodeQueueTaskJson(
                pathWord: 'pw',
                group: 'default',
                chapter: chapter,
                isRetry: false,
                attempt: 1,
              ),
            ],
            'succeeded': 0,
            'batch_failures': [],
          }),
        });

        var detailCalls = 0;
        final manager = DownloadManager.forTesting(
          rootDirectory: root,
          chapterDetailLoader: (pathWord, chapterUuid) async {
            detailCalls++;
            return _detail(chapterUuid);
          },
          imageDownloader: _writeFakeImage,
        );
        await manager.init();
        expect(manager.paused, isTrue);
        expect(manager.tasks.single.status, ComicDownloadTaskStatus.paused);
        expect(detailCalls, 0);

        manager.resumeDownloads();
        await _waitUntil(() => manager.tasks.isEmpty);

        expect(detailCalls, 1);
        expect(manager.isDownloaded('pw', 'ch1'), isTrue);
      },
    );

    test('local comic deletion also cancels queued chapters', () async {
      final manager = DownloadManager.forTesting(
        rootDirectory: root,
        chapterDetailLoader: (pathWord, chapterUuid) async =>
            _detail(chapterUuid),
        imageDownloader: _writeFakeImage,
      );
      await manager.init();
      manager.pauseDownloads();
      await manager.enqueueChapters(
        pathWord: 'pw',
        comic: _comic(),
        chapters: [
          Chapter(uuid: 'ch1', index: 1, name: '1'),
          Chapter(uuid: 'ch2', index: 2, name: '2'),
        ],
      );

      await manager.deleteLocalComics(['pw']);

      expect(manager.tasks, isEmpty);
      expect(manager.isBusy, isFalse);
      expect(manager.localComics(), isEmpty);
    });

    test('concurrent chapter deletion keeps remaining comic files', () async {
      final manager = DownloadManager.forTesting(
        rootDirectory: root,
        chapterDetailLoader: (pathWord, chapterUuid) async =>
            _detail(chapterUuid, pages: 1),
        imageDownloader: _writeFakeImage,
      );
      await manager.init();
      await manager.enqueueChapters(
        pathWord: 'pw',
        comic: _comic(),
        chapters: [
          Chapter(uuid: 'ch1', index: 1, name: '1'),
          Chapter(uuid: 'ch2', index: 2, name: '2'),
        ],
      );
      await _waitUntil(() => manager.tasks.isEmpty);
      expect(manager.downloadedChapters('pw'), hasLength(2));

      await Future.wait([
        manager.deleteQueuedChapter('pw', 'ch1'),
        manager.deleteQueuedChapter('pw', 'ch2'),
      ]);

      expect(manager.downloadedChapters('pw'), isEmpty);
      expect(manager.localComics(), isEmpty);
      expect(Directory(root.path).listSync(), isNotEmpty);
    });

    test('downloaded file count excludes chapter metadata', () async {
      final manager = DownloadManager.forTesting(rootDirectory: root);
      await manager.init();
      final chapterDir = Directory(
        '${root.path}${Platform.pathSeparator}pw${Platform.pathSeparator}ch1',
      )..createSync(recursive: true);
      File(
        '${chapterDir.path}${Platform.pathSeparator}001.jpg',
      ).writeAsStringSync('a');
      File(
        '${chapterDir.path}${Platform.pathSeparator}002.png',
      ).writeAsStringSync('b');
      File(
        '${chapterDir.path}${Platform.pathSeparator}chapter.json',
      ).writeAsStringSync('{}');
      File(
        '${chapterDir.path}${Platform.pathSeparator}temporary.bin',
      ).writeAsStringSync('x');

      expect(await manager.downloadedFileCountOf('pw', 'ch1'), 2);
    });
  });

  group('queue task persistence round-trip', () {
    test('encode/decode preserves all task fields', () {
      final encoded = DownloadManager.encodeQueueTaskJson(
        pathWord: 'comic-a',
        group: 'g1',
        chapter: Chapter(uuid: 'ch-9', index: 3, name: '第3话', ordered: 9),
        isRetry: true,
        attempt: 2,
        notBefore: DateTime(2026, 1, 2, 3, 4, 5),
      );

      final restored = DownloadManager.decodeQueueTaskJson(encoded);

      expect(restored, isNotNull);
      expect(restored!.pathWord, 'comic-a');
      expect(restored.group, 'g1');
      expect(restored.chapter.uuid, 'ch-9');
      expect(restored.chapter.index, 3);
      expect(restored.chapter.name, '第3话');
      expect(restored.chapter.ordered, 9);
      expect(restored.isRetry, isTrue);
      expect(restored.attempt, 2);
      expect(restored.notBefore, DateTime(2026, 1, 2, 3, 4, 5));
    });

    test('decode defaults group to "default" and attempt to 1', () {
      final restored = DownloadManager.decodeQueueTaskJson({
        'path_word': 'pw',
        'chapter_uuid': 'ch',
      });
      expect(restored, isNotNull);
      expect(restored!.group, 'default');
      expect(restored.attempt, 1);
      expect(restored.isRetry, isFalse);
      expect(restored.notBefore, isNull);
    });

    test('decode returns null for missing pathWord or chapterUuid', () {
      expect(
        DownloadManager.decodeQueueTaskJson({'chapter_uuid': 'ch'}),
        isNull,
      );
      expect(DownloadManager.decodeQueueTaskJson({'path_word': 'pw'}), isNull);
      expect(DownloadManager.decodeQueueTaskJson('not-a-map'), isNull);
      expect(DownloadManager.decodeQueueTaskJson(null), isNull);
    });
  });

  group('DownloadedChapterSummary.failedIndices', () {
    test('round-trips non-empty failed indices', () {
      final original = DownloadedChapterSummary(
        chapterUuid: 'u-1',
        chapterName: '第1话',
        chapterGroup: 'g',
        chapterIndex: 1,
        chapterOrder: 2,
        pageCount: 200,
        savedAt: DateTime(2024, 1, 2, 3, 4, 5),
        failedIndices: const [3, 189, 190],
      );

      final restored = DownloadedChapterSummary.fromJson(original.toJson());

      expect(restored.failedIndices, [3, 189, 190]);
      expect(restored.isPartial, isTrue);
      expect(restored.pageCount, 200);
      expect(restored.chapterUuid, 'u-1');
    });

    test('empty failed indices => not partial', () {
      final original = DownloadedChapterSummary(
        chapterUuid: 'u-2',
        chapterName: '第2话',
        pageCount: 10,
        savedAt: DateTime(2024),
      );
      final restored = DownloadedChapterSummary.fromJson(original.toJson());

      expect(restored.failedIndices, isEmpty);
      expect(restored.isPartial, isFalse);
    });

    test('legacy manifest without failed_indices field defaults to empty', () {
      final legacyJson = <String, dynamic>{
        'chapter_uuid': 'u-3',
        'chapter_name': '第3话',
        'chapter_group': 'default',
        'chapter_index': 0,
        'chapter_order': 0,
        'page_count': 5,
        'saved_at': '2024-01-01T00:00:00.000',
      };
      final restored = DownloadedChapterSummary.fromJson(legacyJson);

      expect(restored.failedIndices, isEmpty);
      expect(restored.isPartial, isFalse);
      expect(restored.pageCount, 5);
    });

    test('sortOrder prefers chapterOrder when non-zero', () {
      final summary = DownloadedChapterSummary(
        chapterUuid: 'u',
        chapterName: 'n',
        pageCount: 1,
        savedAt: DateTime(2024),
        chapterIndex: 5,
        chapterOrder: 9,
      );
      expect(summary.sortOrder, 9);
    });
  });

  group('chapterDownloadOrder', () {
    Chapter ch(int ordered, int index, [String uuid = 'u']) =>
        Chapter(uuid: uuid, index: index, name: 'n', ordered: ordered);

    test('sorts by ordered ascending', () {
      final list = [ch(29, 0, 'a'), ch(13, 1, 'b')];
      list.sort(DownloadManager.chapterDownloadOrder);
      expect(list.map((c) => c.ordered).toList(), [13, 29]);
    });

    test('falls back to index when ordered is 0', () {
      final list = [ch(0, 5, 'a'), ch(0, 2, 'b')];
      list.sort(DownloadManager.chapterDownloadOrder);
      expect(list.map((c) => c.index).toList(), [2, 5]);
    });

    test('mixed ordered/index uses ordered when present', () {
      final list = [ch(0, 7, 'a'), ch(3, 1, 'b'), ch(0, 2, 'c')];
      list.sort(DownloadManager.chapterDownloadOrder);
      expect(list.map((c) => c.ordered > 0 ? c.ordered : c.index).toList(), [
        2,
        3,
        7,
      ]);
    });

    test('equal keys resolve deterministically by uuid', () {
      final list = [ch(1, 0, 'b'), ch(1, 0, 'a')];
      list.sort(DownloadManager.chapterDownloadOrder);
      expect(list.first.uuid, 'a');
    });
  });

  group('chapterRetryDelay', () {
    test('escalates 5s/15s/30s and clamps out-of-range indices', () {
      expect(DownloadManager.chapterRetryDelay(1), const Duration(seconds: 5));
      expect(DownloadManager.chapterRetryDelay(2), const Duration(seconds: 15));
      expect(DownloadManager.chapterRetryDelay(3), const Duration(seconds: 30));
      expect(
        DownloadManager.chapterRetryDelay(99),
        const Duration(seconds: 30),
      );
      expect(DownloadManager.chapterRetryDelay(0), const Duration(seconds: 5));
    });
  });

  group('imageRetryDelay', () {
    test('base delays 1s/2s, rate-limited doubles and clamps', () {
      expect(DownloadManager.imageRetryDelay(1), const Duration(seconds: 1));
      expect(DownloadManager.imageRetryDelay(2), const Duration(seconds: 2));
      expect(DownloadManager.imageRetryDelay(3), const Duration(seconds: 2));
      expect(
        DownloadManager.imageRetryDelay(1, rateLimited: true),
        const Duration(seconds: 4),
      );
      expect(
        DownloadManager.imageRetryDelay(2, rateLimited: true),
        const Duration(seconds: 8),
      );
      expect(DownloadManager.imageRetryDelay(0), const Duration(seconds: 1));
    });
  });

  group('ChapterDownloadProgress', () {
    test('ratio is completed/total, failed defaults to 0', () {
      const progress = ChapterDownloadProgress(completed: 3, total: 10);
      expect(progress.ratio, closeTo(0.3, 1e-9));
      expect(progress.failed, 0);
    });

    test('zero total guards against division by zero', () {
      const progress = ChapterDownloadProgress(
        completed: 0,
        total: 0,
        failed: 2,
      );
      expect(progress.ratio, 0);
      expect(progress.failed, 2);
    });
  });

  group('DownloadMigrationProgress', () {
    test('ratio guards against zero total', () {
      const progress = DownloadMigrationProgress(
        current: 2,
        total: 0,
        pathWord: 'a',
      );
      expect(progress.ratio, 0);
    });
  });

  group('normalizeDirectoryPath', () {
    test('null / empty / whitespace => null', () {
      expect(DownloadManager.normalizeDirectoryPath(null), isNull);
      expect(DownloadManager.normalizeDirectoryPath(''), isNull);
      expect(DownloadManager.normalizeDirectoryPath('   '), isNull);
    });

    test('strips trailing separators and whitespace', () {
      expect(DownloadManager.normalizeDirectoryPath('/a/b/'), '/a/b');
      expect(DownloadManager.normalizeDirectoryPath('  /a/b\\  '), '/a/b');
    });

    test('keeps single-character root intact', () {
      expect(DownloadManager.normalizeDirectoryPath('/'), '/');
    });
  });

  group('rewritePathPrefix', () {
    test('rewrites paths under the old root', () {
      expect(
        DownloadManager.rewritePathPrefix('/old/a/b/001.jpg', '/old', '/new'),
        '/new${sep}a${sep}b${sep}001.jpg',
      );
    });

    test('tolerates trailing separators on both roots', () {
      expect(
        DownloadManager.rewritePathPrefix('/old/x/1.jpg', '/old/', '/new/'),
        '/new${sep}x${sep}1.jpg',
      );
    });

    test('accepts backslash separator in stored paths', () {
      expect(
        DownloadManager.rewritePathPrefix(
          r'C:\old\x\1.jpg',
          r'C:\old',
          r'D:\new',
        ),
        r'D:\new' + sep + r'x\1.jpg',
      );
    });

    test('returns null for paths outside the old root', () {
      expect(
        DownloadManager.rewritePathPrefix('/other/a.jpg', '/old', '/new'),
        isNull,
      );
      expect(
        DownloadManager.rewritePathPrefix('/oldx/a.jpg', '/old', '/new'),
        isNull,
      );
    });

    test('returns null for the root itself or empty inputs', () {
      expect(DownloadManager.rewritePathPrefix('/old', '/old', '/new'), isNull);
      expect(DownloadManager.rewritePathPrefix('', '/old', '/new'), isNull);
      expect(
        DownloadManager.rewritePathPrefix('/old/a.jpg', '', '/new'),
        isNull,
      );
      expect(
        DownloadManager.rewritePathPrefix('/old/a.jpg', '/old', ''),
        isNull,
      );
    });
  });

  group('moveDirectory', () {
    late Directory sandbox;

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp('kira_move_test');
    });

    tearDown(() async {
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    });

    test('renames directory to target and removes source', () async {
      final from = Directory('${sandbox.path}${sep}a')..createSync();
      File('${from.path}${sep}001.jpg').writeAsStringSync('img');

      await DownloadManager.moveDirectory(
        from,
        Directory('${sandbox.path}${sep}b'),
      );

      expect(from.existsSync(), isFalse);
      expect(File('${sandbox.path}${sep}b${sep}001.jpg').existsSync(), isTrue);
    });

    test('missing source is a no-op', () async {
      final target = Directory('${sandbox.path}${sep}t');
      await DownloadManager.moveDirectory(
        Directory('${sandbox.path}${sep}gone'),
        target,
      );
      expect(target.existsSync(), isFalse);
    });

    test('replaces an existing target directory', () async {
      final from = Directory('${sandbox.path}${sep}a')..createSync();
      File('${from.path}${sep}new.jpg').writeAsStringSync('n');
      final to = Directory('${sandbox.path}${sep}b')..createSync();
      File('${to.path}${sep}stale.jpg').writeAsStringSync('old');

      await DownloadManager.moveDirectory(from, to);

      expect(File('${to.path}${sep}new.jpg').existsSync(), isTrue);
      expect(File('${to.path}${sep}stale.jpg').existsSync(), isFalse);
    });
  });

  group('isDirectoryWritable', () {
    late Directory sandbox;

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp('kira_probe_test');
    });

    tearDown(() async {
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    });

    test('writable directory reports true', () async {
      expect(await DownloadManager.isDirectoryWritable(sandbox), isTrue);
      expect(
        sandbox.listSync(),
        isEmpty,
        reason: 'probe file must be cleaned up',
      );
    });

    test('file path reports false', () async {
      final filePath = '${sandbox.path}${sep}occupied.txt';
      File(filePath).writeAsStringSync('x');
      expect(
        await DownloadManager.isDirectoryWritable(Directory(filePath)),
        isFalse,
      );
    });
  });

  group('resolveRootDirectory', () {
    late Directory sandbox;

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp('kira_root_test');
    });

    tearDown(() async {
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    });

    Directory defaultRoot() =>
        Directory('${sandbox.path}${sep}comic_downloads');

    test('null custom path falls back to default', () async {
      final root = await DownloadManager.resolveRootDirectory(
        customPath: null,
        defaultParentPath: sandbox.path,
      );
      expect(root.path, defaultRoot().path);
    });

    test('missing custom path is created and used', () async {
      final custom = '${sandbox.path}${sep}custom';
      final root = await DownloadManager.resolveRootDirectory(
        customPath: custom,
        defaultParentPath: sandbox.path,
      );
      expect(root.path, custom);
      expect(Directory(custom).existsSync(), isTrue);
    });

    test('custom path occupied by a file falls back to default', () async {
      final filePath = '${sandbox.path}${sep}occupied.txt';
      File(filePath).writeAsStringSync('x');

      final root = await DownloadManager.resolveRootDirectory(
        customPath: filePath,
        defaultParentPath: sandbox.path,
      );
      expect(root.path, defaultRoot().path);
    });
  });

  group('rewriteStoredPaths', () {
    late Directory sandbox;
    late Directory oldRoot;
    late Directory newRoot;
    final sep = Platform.pathSeparator;

    setUp(() async {
      sandbox = await Directory.systemTemp.createTemp('kira_rewrite_test');
      oldRoot = Directory('${sandbox.path}${sep}old')..createSync();
      newRoot = Directory('${sandbox.path}${sep}new')..createSync();
    });

    tearDown(() async {
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    });

    test('rewrites comic cover fields and chapter contents', () async {
      final comicDir = Directory('${oldRoot.path}${sep}comicA')..createSync();
      final chapterDir = Directory('${comicDir.path}${sep}ch1')..createSync();
      final coverPath = '${oldRoot.path}${sep}comicA${sep}cover.jpg';
      final imagePath = '${oldRoot.path}${sep}comicA${sep}ch1${sep}001.jpg';
      File('${comicDir.path}${sep}comic.json').writeAsStringSync(
        jsonEncode({
          'comic': {'name': 'A', 'cover': coverPath},
          'cover_path': coverPath,
          'updated_at': '2024-01-01T00:00:00.000',
        }),
      );
      File('${chapterDir.path}${sep}chapter.json').writeAsStringSync(
        jsonEncode({
          'uuid': 'u1',
          'contents': [imagePath, ''],
          'comments': <String>[],
          'comment_total': 0,
        }),
      );

      await DownloadManager.rewriteStoredPaths(
        comicDir,
        fromRoot: oldRoot.path,
        toRoot: newRoot.path,
      );

      final newCoverPath = '${newRoot.path}${sep}comicA${sep}cover.jpg';
      final newImagePath = '${newRoot.path}${sep}comicA${sep}ch1${sep}001.jpg';
      final comic =
          jsonDecode(
                File('${comicDir.path}${sep}comic.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(comic['cover_path'], newCoverPath);
      expect((comic['comic'] as Map<String, dynamic>)['cover'], newCoverPath);

      final chapter =
          jsonDecode(
                File('${chapterDir.path}${sep}chapter.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(chapter['contents'], [newImagePath, '']);
    });

    test('leaves paths outside the old root untouched', () async {
      final comicDir = Directory('${oldRoot.path}${sep}comicB')..createSync();
      File('${comicDir.path}${sep}comic.json').writeAsStringSync(
        '{"comic":{"name":"B","cover":"/elsewhere/c.jpg"},'
        '"cover_path":"/elsewhere/c.jpg",'
        '"updated_at":"2024-01-01T00:00:00.000"}',
      );

      await DownloadManager.rewriteStoredPaths(
        comicDir,
        fromRoot: oldRoot.path,
        toRoot: newRoot.path,
      );

      final comic =
          jsonDecode(
                File('${comicDir.path}${sep}comic.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(comic['cover_path'], '/elsewhere/c.jpg');
    });

    test('skips a missing comic directory', () async {
      final missing = Directory('${newRoot.path}${sep}ghost');
      await DownloadManager.rewriteStoredPaths(
        missing,
        fromRoot: oldRoot.path,
        toRoot: newRoot.path,
      );
      expect(missing.existsSync(), isFalse);
    });
  });
}
