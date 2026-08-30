import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/download_manager.dart';

void main() {
  final sep = Platform.pathSeparator;
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
