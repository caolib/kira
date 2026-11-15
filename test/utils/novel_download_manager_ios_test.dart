import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/novel_download_manager.dart';
import 'package:kira/utils/novel_download_store.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';
import 'novel_download_store_test.dart'
    show downloadSnapshot, filesUnder, saveFixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory container;
  late Directory root;
  late Directory outside;
  final managers = <NovelDownloadManager>[];
  var networkCalls = 0;

  NovelDownloadManager create() {
    final manager = NovelDownloadManager.forTesting(
      store: NovelDownloadStore.forTesting(rootDirectory: root),
      snapshotLoader: (_, _, {required cancelToken}) async {
        networkCalls++;
        throw StateError('Offline test must not request a snapshot');
      },
      imageLoader: (_, {required cancelToken}) async {
        networkCalls++;
        throw StateError('Offline test must not request an image');
      },
      identityProvider: () => const NovelDownloadIdentity(host: 'copy.invalid'),
      defaultRoot: () async => root.path,
    );
    managers.add(manager);
    return manager;
  }

  setUp(() async {
    setupSecureCredentialStoreForTest();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    SharedPreferences.setMockInitialValues({
      NovelDownloadManager.saveDirectoryKey: '/outside/old',
    });
    networkCalls = 0;
    managers.clear();
    container = await Directory.systemTemp.createTemp('kira_ios_novels_');
    root = Directory(p.join(container.path, 'Documents', 'novel_downloads'));
    outside = Directory(p.join(container.path, 'outside'));
    await outside.create();
    await File(
      p.join(outside.path, 'keep.txt'),
    ).writeAsString('not a download');
    final store = NovelDownloadStore.forTesting(rootDirectory: root);
    await store.init();
    await saveFixture(store, complete: true);
  });

  tearDown(() async {
    for (final manager in managers) {
      manager.dispose();
      await manager.waitForIdle();
    }
    debugDefaultTargetPlatformOverride = null;
    await container.delete(recursive: true);
    teardownSecureCredentialStoreForTest();
  });

  test(
    'iOS ignores external preference and preserves relative offline files across rebuild',
    () async {
      final first = create();
      await first.init();
      expect(first.customSaveDirectory, isNull);
      expect(first.rootPath, root.path);
      expect(
        (await first.store.readVolumeSnapshot('book', 'v1'))!.text,
        downloadSnapshot.text,
      );

      final rebuilt = create();
      await rebuilt.init();
      expect(rebuilt.isVolumeDownloaded('book', 'v1'), isTrue);
      expect(
        (await rebuilt.store.readVolumeSnapshot('book', 'v1'))!.text,
        downloadSnapshot.text,
      );
      for (final url in downloadSnapshot.imageUrls) {
        expect(await rebuilt.store.readImageBytes('book', 'v1', url), [
          1,
          2,
          3,
        ]);
      }
      expect(networkCalls, 0);
      expect(
        (await SharedPreferences.getInstance()).getString(
          NovelDownloadManager.saveDirectoryKey,
        ),
        '/outside/old',
      );
    },
  );

  test(
    'iOS custom-directory rejection leaves stored files and prefs untouched',
    () async {
      final before = {
        for (final file in await filesUnder(root))
          file.path: await file.readAsBytes(),
      };
      final manager = create();
      await expectLater(
        manager.setSaveDirectory(outside.path),
        throwsUnsupportedError,
      );
      final after = {
        for (final file in await filesUnder(root))
          file.path: await file.readAsBytes(),
      };
      expect(after, before);
      expect(
        await File(p.join(outside.path, 'keep.txt')).readAsString(),
        'not a download',
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          NovelDownloadManager.saveDirectoryKey,
        ),
        '/outside/old',
      );
      expect(networkCalls, 0);
    },
  );
}
