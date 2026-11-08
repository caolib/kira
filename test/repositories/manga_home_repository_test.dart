import 'package:flutter_test/flutter_test.dart';
import 'package:kira/api/api_client.dart';
import 'package:kira/api/manga/manga_api.dart';
import 'package:kira/models/comic.dart' hide Theme;
import 'package:kira/repositories/manga_home_repository.dart';
import 'package:kira/utils/app_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

class _FakeMangaApi extends Fake implements MangaApi {
  CopyMangaHome home = const CopyMangaHome();
  Object? error;
  int calls = 0;

  @override
  Future<CopyMangaHome> getCopyMangaHome() async {
    calls++;
    if (error != null) throw error!;
    return home;
  }
}

class _FakeApiClient extends Fake implements ApiClient {
  _FakeApiClient(this.manga);

  @override
  final MangaApi manga;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ApiClient originalApi;
  late _FakeMangaApi manga;
  late MangaHomeRepository repository;

  setUp(() {
    setupSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({});
    originalApi = ApiClient();
    manga = _FakeMangaApi();
    ApiClient.setTestInstance(_FakeApiClient(manga));
    repository = MangaHomeRepository();
  });

  tearDown(() {
    ApiClient.setTestInstance(originalApi);
    teardownSecureCredentialStoreForTest();
  });

  test('空响应抛出异常，不写入首页缓存', () async {
    await expectLater(
      repository.loadB(),
      throwsA(isA<EmptyCopyMangaHomeException>()),
    );
    expect(await AppStorage.cache.get(repository.cacheKeyB), isNull);
    expect(manga.calls, 1);
  });

  test('空响应保留正常缓存，重建仓库和重试后仍可读取', () async {
    manga.home = CopyMangaHome(
      recComics: [Comic(name: '旧作品', pathWord: 'old', cover: '')],
    );
    await repository.loadB();
    final cached = await AppStorage.cache.get(repository.cacheKeyB);
    manga.home = const CopyMangaHome();

    await expectLater(
      repository.loadB(),
      throwsA(isA<EmptyCopyMangaHomeException>()),
    );
    expect(await AppStorage.cache.get(repository.cacheKeyB), cached);
    final rebuilt = MangaHomeRepository();
    expect((await rebuilt.loadBFromCache())!.home.recComics.single.name, '旧作品');

    manga.home = CopyMangaHome(
      recComics: [Comic(name: '新作品', pathWord: 'new', cover: '')],
    );
    await rebuilt.loadB();
    expect((await rebuilt.loadBFromCache())!.home.recComics.single.name, '新作品');
    expect(manga.calls, 3);
  });

  test('忽略旧版保存的全空首页缓存', () async {
    await AppStorage.cache.put(
      repository.cacheKeyB,
      const CopyMangaHomeData(home: CopyMangaHome()).toJson(),
      ttl: const Duration(hours: 1),
    );

    expect(await repository.loadBFromCache(), isNull);
  });

  test('保留原始请求异常与正常缓存', () async {
    manga.home = CopyMangaHome(
      recComics: [Comic(name: '缓存作品', pathWord: 'cached', cover: '')],
    );
    await repository.loadB();
    final error = StateError('服务器暂时不可用');
    manga.error = error;

    await expectLater(repository.loadB(), throwsA(same(error)));
    expect(
      (await repository.loadBFromCache())!.home.recComics.single.name,
      '缓存作品',
    );
  });
}
