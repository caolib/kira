import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/novel.dart';
import 'package:kira/models/novel_download.dart';
import 'package:kira/models/novel_volume_snapshot.dart';
import 'package:kira/utils/json_helpers.dart';
import 'package:kira/utils/novel_download_store.dart';
import 'package:path/path.dart' as p;

const downloadBook = NovelBook(
  pathWord: 'book',
  name: '测试小说',
  cover: 'https://cdn.invalid/cover',
);
const downloadVolume = NovelVolume(
  id: 'v1',
  name: '第一卷',
  bookPathWord: 'book',
  txtAddr: 'https://cdn.invalid/v1.txt',
  txtEncoding: 'utf-8',
  contents: [
    NovelContentEntry(name: '正文', contentType: 1, endLines: 4),
    NovelContentEntry(
      name: '插图',
      contentType: 2,
      content: 'https://cdn.invalid/image1',
    ),
    NovelContentEntry(
      name: '插图2',
      contentType: 2,
      content: 'https://cdn.invalid/image2',
    ),
  ],
);
const downloadSnapshot = NovelVolumeSnapshot(
  detail: NovelVolumeDetail(book: downloadBook, volume: downloadVolume),
  text: '\r\n正文\r\n\r\n结尾\r\n',
);

Future<void> saveFixture(
  NovelDownloadStore store, {
  bool complete = false,
}) async {
  await store.saveSnapshot(
    book: downloadBook,
    volumes: [
      downloadVolume,
      const NovelVolume(id: 'v2', name: '未下载卷'),
    ],
    snapshot: downloadSnapshot,
  );
  if (complete) {
    for (final url in downloadSnapshot.imageUrls) {
      await store.saveImage('book', 'v1', url, [1, 2, 3]);
    }
  }
}

Future<List<File>> filesUnder(Directory root) async => [
  await for (final entry in root.list(recursive: true, followLinks: false))
    if (entry is File) entry,
];
Future<Map<String, dynamic>> readJson(File file) async =>
    jsonMap({'v': jsonDecode(await file.readAsString())}, 'v')!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory parent;
  late Directory root;
  late NovelDownloadStore store;
  setUp(() async {
    parent = await Directory.systemTemp.createTemp('novel_store_test_');
    root = Directory(p.join(parent.path, 'downloads'));
    store = NovelDownloadStore.forTesting(rootDirectory: root);
    await store.init();
  });
  tearDown(() async {
    await parent.delete(recursive: true);
  });

  test(
    'snapshot preserves original whitespace, complete directory and image mapping across restart',
    () async {
      await saveFixture(store, complete: true);
      await store.saveCover('book', [3, 2, 1]);
      final restored = NovelDownloadStore.forTesting(rootDirectory: root);
      await restored.init();
      expect(
        (await restored.readVolumeSnapshot('book', 'v1'))!.text,
        downloadSnapshot.text,
      );
      expect(
        (await restored.readVolumeSnapshot(
          'book',
          'v1',
        ))!.content.entries.first.paragraphs,
        ['', '正文', '', '结尾'],
      );
      expect(restored.downloadedVolumes('book'), {'v1'});
      expect(restored.getLocalNovelInfo('book')!.volumes.map((v) => v.id), [
        'v1',
        'v2',
      ]);
      expect(restored.coverPath('book'), isNotNull);
      expect(
        await restored.readImageBytes(
          'book',
          'v1',
          downloadSnapshot.imageUrls.first,
        ),
        [1, 2, 3],
      );
      expect(await restored.readVolumeSnapshot('book', 'v2'), isNull);
    },
  );

  test(
    'downloaded TXT references decode after restart without rewriting the snapshot',
    () async {
      const snapshot = NovelVolumeSnapshot(
        detail: NovelVolumeDetail(book: downloadBook, volume: downloadVolume),
        text: '\r\n&#16034;&#15970;狓\r\n\r\n&#x20000;\r\n',
      );
      await store.saveSnapshot(
        book: downloadBook,
        volumes: [downloadVolume],
        snapshot: snapshot,
      );
      final restored = NovelDownloadStore.forTesting(rootDirectory: root);
      await restored.init();
      final loaded = (await restored.readVolumeSnapshot('book', 'v1'))!;
      expect(loaded.text, snapshot.text);
      expect(loaded.content.entries.first.paragraphs, [
        '',
        '㺢㹢狓',
        '',
        '\u{20000}',
      ]);
      expect(
        (await restored.readVolumeSnapshot('book', 'v1'))!.text,
        snapshot.text,
      );
    },
  );

  test(
    'partial text is readable, missing or corrupted illustrations are not completed',
    () async {
      await saveFixture(store, complete: true);
      final image = (await filesUnder(
        root,
      )).firstWhere((f) => p.basename(f.path).endsWith('.bin'));
      await image.writeAsBytes([9]);
      final restored = NovelDownloadStore.forTesting(rootDirectory: root);
      await restored.init();
      expect(
        restored.getLocalNovelInfo('book')!.downloaded['v1']!.status,
        NovelDownloadStatus.partial,
      );
      expect(restored.downloadedVolumes('book'), isEmpty);
      expect(await restored.readVolumeSnapshot('book', 'v1'), isNotNull);
      await restored.saveImage('book', 'v1', downloadSnapshot.imageUrls.first, [
        1,
        2,
        3,
      ]);
      await restored.saveImage('book', 'v1', downloadSnapshot.imageUrls.last, [
        1,
        2,
        3,
      ]);
      expect(restored.downloadedVolumes('book'), {'v1'});
    },
  );

  test(
    'missing snapshot is marked repairable, never reported complete',
    () async {
      await saveFixture(store, complete: true);
      final file = (await filesUnder(
        root,
      )).firstWhere((f) => p.basename(f.path).startsWith('snapshot_'));
      await file.delete();
      final restored = NovelDownloadStore.forTesting(rootDirectory: root);
      await restored.init();
      expect(restored.getLocalNovelInfo('book')!.needsRepair, isTrue);
      expect(await restored.readVolumeSnapshot('book', 'v1'), isNull);
      expect(restored.downloadedVolumes('book'), isEmpty);
    },
  );

  test(
    'startup probes size only; corrupted bytes are caught when the volume is read',
    () async {
      await saveFixture(store, complete: true);
      final snapshotFile = (await filesUnder(
        root,
      )).firstWhere((f) => p.basename(f.path).startsWith('snapshot_'));
      // Same length, different content: only a digest check can notice, and
      // startup must not pay for one.
      final tampered = List<int>.of(await snapshotFile.readAsBytes());
      tampered[0] = tampered[0] == 0x7b ? 0x5b : 0x7b;
      await snapshotFile.writeAsBytes(tampered);
      final restored = NovelDownloadStore.forTesting(rootDirectory: root);
      await restored.init();
      expect(
        restored.getLocalNovelInfo('book')!.downloaded['v1']!.status,
        NovelDownloadStatus.completed,
      );
      expect(await restored.readVolumeSnapshot('book', 'v1'), isNull);
      expect(
        restored.getLocalNovelInfo('book')!.downloaded['v1']!.status,
        NovelDownloadStatus.needsRepair,
      );
    },
  );

  test(
    'bad root manifest is preserved and unknown directories are never removed',
    () async {
      final manifest = File(p.join(root.path, NovelDownloadStore.manifestName));
      await manifest.writeAsString('{broken');
      final unknown = File(p.join(root.path, 'unknown', 'keep.txt'));
      await unknown.parent.create();
      await unknown.writeAsString('keep');
      final restored = NovelDownloadStore.forTesting(rootDirectory: root);
      await restored.init();
      expect(restored.hasManifestError, isTrue);
      await expectLater(saveFixture(restored), throwsStateError);
      expect(await manifest.readAsString(), '{broken');
      expect(await unknown.readAsString(), 'keep');
    },
  );

  test('manifest traversal cannot read or delete outside files', () async {
    await saveFixture(store, complete: true);
    final outside = File(p.join(parent.path, 'outside.bin'));
    await outside.writeAsBytes([1, 2, 3]);
    final manifest = (await filesUnder(root)).firstWhere(
      (f) =>
          p.basename(f.path) == 'manifest_v1.json' &&
          p.dirname(f.path) != root.path,
    );
    final json = await readJson(manifest);
    final snapshot = jsonMap(json, 'snapshot')!;
    snapshot['path'] = '../../../../outside.bin';
    json['snapshot'] = snapshot;
    await manifest.writeAsString(jsonEncode(json));
    final restored = NovelDownloadStore.forTesting(rootDirectory: root);
    await restored.init();
    expect(await restored.readVolumeSnapshot('book', 'v1'), isNull);
    await restored.deleteNovel('book');
    expect(await outside.readAsBytes(), [1, 2, 3]);
  });

  test('invalid directory line ranges are rejected before saving', () async {
    final invalid = NovelVolumeSnapshot(
      detail: downloadSnapshot.detail,
      text: 'only one line',
    );
    await expectLater(
      store.saveSnapshot(
        book: downloadBook,
        volumes: [downloadVolume],
        snapshot: invalid,
      ),
      throwsFormatException,
    );
    expect(store.localNovels, isEmpty);
  });

  test(
    'concurrent volumes serialize root manifest without losing records',
    () async {
      await Future.wait([
        for (var i = 0; i < 5; i++)
          store.saveSnapshot(
            book: downloadBook,
            volumes: [downloadVolume],
            snapshot: NovelVolumeSnapshot(
              detail: NovelVolumeDetail(
                book: downloadBook,
                volume: NovelVolume(
                  id: 'v$i',
                  name: '卷$i',
                  txtAddr: downloadVolume.txtAddr,
                  contents: downloadVolume.contents,
                ),
              ),
              text: downloadSnapshot.text,
            ),
          ),
      ]);
      final restored = NovelDownloadStore.forTesting(rootDirectory: root);
      await restored.init();
      expect(restored.getLocalNovelInfo('book')!.downloaded.length, 5);
    },
  );

  test('cancelled queued write cannot publish a late snapshot', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var current = true;
    final slow = NovelDownloadStore.forTesting(
      rootDirectory: root,
      beforeWrite: (path) async {
        if (p.basename(path).startsWith('snapshot_')) {
          entered.complete();
          await release.future;
        }
      },
    );
    await slow.init();
    final write = expectLater(
      slow.saveSnapshot(
        book: downloadBook,
        volumes: [downloadVolume],
        snapshot: downloadSnapshot,
        isCurrent: () => current,
      ),
      throwsA(isA<NovelDownloadWriteCancelled>()),
    );
    await entered.future;
    current = false;
    release.complete();
    await write;
    await slow.waitForWrites();
    expect(await slow.readVolumeSnapshot('book', 'v1'), isNull);
    expect(slow.localNovels, isEmpty);
  });

  test(
    'migration commit failure rolls back only newly created files',
    () async {
      await saveFixture(store, complete: true);
      final target = Directory(p.join(parent.path, 'target'));
      await target.create();
      await expectLater(
        store.migrateTo(
          target.path,
          commit: (_) async => throw StateError('prefs write'),
        ),
        throwsStateError,
      );
      expect(store.rootPath, root.path);
      expect(await target.list().isEmpty, isTrue);
      expect(await store.readVolumeSnapshot('book', 'v1'), isNotNull);
      expect(store.downloadedVolumes('book'), {'v1'});
    },
  );

  test(
    'migration copy failure preserves source and nonempty targets',
    () async {
      await saveFixture(store, complete: true);
      final target = Directory(p.join(parent.path, 'target'));
      final failing = NovelDownloadStore.forTesting(
        rootDirectory: root,
        copyFile: (from, to) async {
          await to.writeAsString('partial');
          throw const FileSystemException('copy failed');
        },
      );
      await failing.init();
      await expectLater(
        failing.migrateTo(target.path),
        throwsA(isA<FileSystemException>()),
      );
      expect(await target.exists(), isFalse);
      expect(await failing.readVolumeSnapshot('book', 'v1'), isNotNull);
      await target.create();
      final keep = File(p.join(target.path, 'keep'));
      await keep.writeAsString('existing');
      await expectLater(failing.migrateTo(target.path), throwsStateError);
      expect(await keep.readAsString(), 'existing');
    },
  );

  test(
    'manifest write failure cannot leave an in-memory completed snapshot',
    () async {
      var fail = true;
      final failing = NovelDownloadStore.forTesting(
        rootDirectory: root,
        beforeWrite: (path) async {
          if (fail &&
              path == p.join(root.path, NovelDownloadStore.manifestName)) {
            throw const FileSystemException('disk full');
          }
        },
      );
      await failing.init();
      await expectLater(
        saveFixture(failing),
        throwsA(isA<FileSystemException>()),
      );
      expect(await failing.readVolumeSnapshot('book', 'v1'), isNull);
      fail = false;
      await saveFixture(failing, complete: true);
      final restored = NovelDownloadStore.forTesting(rootDirectory: root);
      await restored.init();
      expect(restored.downloadedVolumes('book'), {'v1'});
    },
  );

  test(
    'migration can return to the default root without orphan empty directories',
    () async {
      await saveFixture(store, complete: true);
      await store.migrateTo(p.join(parent.path, 'other'));
      expect(await root.list().isEmpty, isTrue);
      await store.migrateTo(root.path);
      expect(store.downloadedVolumes('book'), {'v1'});
      expect(await store.readVolumeSnapshot('book', 'v1'), isNotNull);
    },
  );

  test('concurrent init awaits full manifest validation', () async {
    await saveFixture(store, complete: true);
    final restored = NovelDownloadStore.forTesting(rootDirectory: root);
    final init = restored.init();
    final read = restored.readVolumeSnapshot('book', 'v1');
    await init;
    expect(await read, isNotNull);
  });

  test(
    'successful migration retains offline relative mapping and leaves unknown source files',
    () async {
      await saveFixture(store, complete: true);
      final unknown = File(p.join(root.path, 'keep'));
      await unknown.writeAsString('unindexed');
      final target = p.join(parent.path, 'new-root');
      await store.migrateTo(target);
      expect(store.rootPath, target);
      expect(
        await store.readImageBytes(
          'book',
          'v1',
          downloadSnapshot.imageUrls.first,
        ),
        [1, 2, 3],
      );
      expect(await unknown.readAsString(), 'unindexed');
      final restored = NovelDownloadStore.forTesting(
        rootDirectory: Directory(target),
      );
      await restored.init();
      expect(restored.downloadedVolumes('book'), {'v1'});
    },
  );
}
