import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/novel/novel_api.dart';
import '../repositories/novel_repository.dart';
import '../utils/app_logger.dart';
import '../utils/novel_bookmark_store.dart';
import '../utils/novel_download_manager.dart';
import '../utils/novel_download_store.dart';
import '../utils/novel_reading_store.dart';
import 'app_providers.dart';

final novelApiProvider = Provider<NovelApi>(
  (ref) => ref.read(apiClientProvider).novel,
);

final novelRepositoryProvider = Provider<NovelRepository>(
  (ref) => NovelRepository(api: ref.read(novelApiProvider)),
);

final novelShelfRepoProvider = Provider<NovelBookshelfRepository>((ref) {
  final repository = NovelBookshelfRepository(api: ref.read(novelApiProvider));
  ref.onDispose(repository.dispose);
  return repository;
});

final novelDownloadStoreProvider = Provider<NovelDownloadStore>(
  (ref) => NovelDownloadStore(),
);

final novelDownloadManagerProvider = Provider<NovelDownloadManager>(
  (ref) => NovelDownloadManager(),
);

/// 只查已加载的下载清单和当前账号的详情缓存，不为统计发起网络请求。
final localNovelTagsProvider = Provider<Future<List<String>> Function(String)>((
  ref,
) {
  final downloads = ref.watch(novelDownloadStoreProvider);
  final repository = ref.watch(novelRepositoryProvider);
  return (pathWord) async {
    try {
      final local = downloads.getLocalNovelInfo(pathWord)?.book.themeNames;
      if (local != null && local.isNotEmpty) return local;
      final book = (await repository.loadDetailFromCache(pathWord))?.book;
      return book != null && book.pathWord == pathWord
          ? book.themeNames
          : const [];
    } catch (error, stack) {
      await AppLogger.instance.recordWarning(
        error,
        stackTrace: stack,
        source: 'reading_stats.novel_tags',
      );
      return const [];
    }
  };
});

final novelReadingStoreProvider = Provider<NovelReadingStore>(
  (ref) => NovelReadingStore(),
);

final novelBookmarkStoreProvider = Provider<NovelBookmarkStore>(
  (ref) => NovelBookmarkStore(),
);
