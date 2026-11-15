import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/chapter.dart';
import 'package:kira/utils/download_manager.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory container;
  late Directory root;
  late Directory chapter;

  setUp(() async {
    setupSecureCredentialStoreForTest();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    SharedPreferences.setMockInitialValues({
      'download_save_directory': '/outside/old',
    });
    container = await Directory.systemTemp.createTemp('kira_ios_downloads_');
    root = Directory(p.join(container.path, 'Documents', 'comic_downloads'));
    chapter = Directory(p.join(root.path, 'book', 'chapter'));
    await chapter.create(recursive: true);
    await File(p.join(chapter.path, '000.jpg')).writeAsBytes([1, 2, 3]);
    await File(p.join(root.path, 'book', 'cover.jpg')).writeAsBytes([1, 2, 3]);
    await File(p.join(root.path, 'manifest.json')).writeAsString(
      jsonEncode({
        'version': 1,
        'comics': {
          'book': {
            'chapter': {
              'chapter_uuid': 'chapter',
              'chapter_name': 'Chapter',
              'chapter_index': 1,
              'page_count': 1,
              'failed_indices': <int>[],
            },
          },
        },
      }),
    );
    const oldRoot =
        '/var/mobile/Containers/Data/Application/OLD/Documents/comic_downloads';
    await File(p.join(chapter.path, 'chapter.json')).writeAsString(
      jsonEncode(
        ChapterDetail(
          uuid: 'chapter',
          index: 1,
          name: 'Chapter',
          contents: ['$oldRoot/book/chapter/000.jpg'],
          isDownloaded: true,
        ).toDownloadJson(),
      ),
    );
    await File(p.join(root.path, 'book', 'comic.json')).writeAsString(
      jsonEncode({
        'comic': {
          'name': 'Book',
          'path_word': 'book',
          'cover': '$oldRoot/book/cover.jpg',
        },
        'cover_path': '$oldRoot/book/cover.jpg',
        'updated_at': DateTime.utc(2026).toIso8601String(),
      }),
    );
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await container.delete(recursive: true);
    teardownSecureCredentialStoreForTest();
  });

  test(
    'cold-start iOS restores images and covers after container move',
    () async {
      final manager = DownloadManager.forTesting(rootDirectory: root);
      await manager.init();
      expect(manager.customSaveDirectory, isNull);
      final detail = await manager.getDownloadedChapterDetail(
        'book',
        'chapter',
      );
      expect(detail, isNotNull);
      expect(detail!.contents, [p.join(chapter.path, '000.jpg')]);
      expect(manager.isDownloaded('book', 'chapter'), isTrue);
      final local = manager.localComics().single.info;
      expect(local.coverPath, p.join(root.path, 'book', 'cover.jpg'));
      expect(local.comic.cover, local.coverPath);

      final rebuilt = DownloadManager.forTesting(rootDirectory: root);
      await rebuilt.init();
      expect(
        (await rebuilt.getDownloadedChapterDetail('book', 'chapter'))!.contents,
        detail.contents,
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          'download_save_directory',
        ),
        '/outside/old',
      );
    },
  );

  test(
    'partial iOS download survives a move and cold-start retry reuses saved pages',
    () async {
      const oldRoot =
          '/var/mobile/Containers/Data/Application/OLD/Documents/comic_downloads';
      await File(p.join(root.path, 'manifest.json')).writeAsString(
        jsonEncode({
          'version': 1,
          'comics': {
            'book': {
              'chapter': {
                'chapter_uuid': 'chapter',
                'chapter_name': 'Chapter',
                'chapter_index': 1,
                'page_count': 2,
                'failed_indices': [1],
              },
            },
          },
        }),
      );
      await File(p.join(chapter.path, 'chapter.json')).writeAsString(
        jsonEncode(
          ChapterDetail(
            uuid: 'chapter',
            index: 1,
            name: 'Chapter',
            contents: ['$oldRoot/book/chapter/000.jpg', ''],
            isDownloaded: true,
          ).toDownloadJson(),
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('download_chapter_comments', false);
      await prefs.setString(
        'download_queue_state_v1',
        jsonEncode({
          'version': 1,
          'paused': true,
          'paused_tasks': <String>[],
          'tasks': [
            DownloadManager.encodeQueueTaskJson(
              pathWord: 'book',
              group: 'default',
              chapter: Chapter(uuid: 'chapter', index: 1, name: 'Chapter'),
              isRetry: true,
              attempt: 0,
            ),
          ],
          'succeeded': 0,
          'batch_failures': <Object>[],
        }),
      );

      final first = DownloadManager.forTesting(rootDirectory: root);
      await first.init();
      final partial = await first.getDownloadedChapterDetail('book', 'chapter');
      expect(partial!.contents, [p.join(chapter.path, '000.jpg'), '']);
      expect(first.isPartial('book', 'chapter'), isTrue);
      expect(first.failedCountOf('book', 'chapter'), 1);
      first.dispose();

      final downloadedPages = <int>[];
      final rebuilt = DownloadManager.forTesting(
        rootDirectory: root,
        chapterDetailLoader: (_, uuid) async => ChapterDetail(
          uuid: uuid,
          index: 1,
          name: 'Chapter',
          contents: [
            'https://example.com/first.jpg',
            'https://example.com/second.jpg',
          ],
        ),
        imageDownloader: (url, directory, page) async {
          downloadedPages.add(page);
          final file = File(
            p.join(directory.path, '${page.toString().padLeft(3, '0')}.jpg'),
          );
          await file.writeAsString(url);
          return file;
        },
      );
      await rebuilt.init();
      expect(rebuilt.paused, isTrue);
      expect(rebuilt.tasks.single.status, ComicDownloadTaskStatus.paused);
      final finished = Completer<void>();
      var idleNotifications = 0;
      void onChanged() {
        if (!rebuilt.isBusy &&
            ++idleNotifications >= 2 &&
            !finished.isCompleted) {
          // Completion of the chapter and then the queue runner's final write.
          finished.complete();
        }
      }

      rebuilt.addListener(onChanged);
      try {
        rebuilt.resumeDownloads();
        await finished.future.timeout(const Duration(seconds: 5));
        expect(
          downloadedPages,
          [2],
          reason: 'The relocated first page must not be downloaded again',
        );
        expect(await File(p.join(chapter.path, '000.jpg')).readAsBytes(), [
          1,
          2,
          3,
        ]);
        expect(rebuilt.isPartial('book', 'chapter'), isFalse);
        final completed = await rebuilt.getDownloadedChapterDetail(
          'book',
          'chapter',
        );
        expect(completed!.contents, [
          p.join(chapter.path, '000.jpg'),
          p.join(chapter.path, '002.jpg'),
        ]);
        expect(rebuilt.tasks, isEmpty);
        await prefs.reload();
        final queue = jsonDecode(prefs.getString('download_queue_state_v1')!);
        expect(queue['tasks'], isEmpty);
        expect(prefs.getString('download_save_directory'), '/outside/old');
      } finally {
        rebuilt.removeListener(onChanged);
        rebuilt.dispose();
      }
    },
  );

  test('missing owned image is still recognized as damaged', () async {
    await File(p.join(chapter.path, '000.jpg')).delete();
    final manager = DownloadManager.forTesting(rootDirectory: root);
    await manager.init();
    expect(await manager.getDownloadedChapterDetail('book', 'chapter'), isNull);
    expect(manager.isDownloaded('book', 'chapter'), isFalse);
  });

  test(
    'iOS rejects custom directory before moving or saving anything',
    () async {
      final manager = DownloadManager.forTesting(rootDirectory: root);
      await expectLater(
        manager.setSaveDirectory('/outside/new'),
        throwsUnsupportedError,
      );
      expect(File(p.join(chapter.path, '000.jpg')).existsSync(), isTrue);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'download_save_directory',
        ),
        '/outside/old',
      );
    },
  );
}
