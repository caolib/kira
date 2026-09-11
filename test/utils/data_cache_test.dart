import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/data_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('remove deletes a cached entry', () async {
    final cache = DataCache();

    await cache.put('video_link', {'url': 'https://example.com/video.m3u8'});
    await cache.remove('video_link');

    expect(await cache.get('video_link'), isNull);
  });

  test('removeByPrefix deletes only matching cached entries', () async {
    final cache = DataCache();

    await cache.put('video_link_v1_anime-a_chapter-1_line-a', {
      'url': 'https://example.com/a.m3u8',
    });
    await cache.put('video_link_v1_anime-a_chapter-2_line-a', {
      'url': 'https://example.com/b.m3u8',
    });
    await cache.put('video_link_v1_anime-b_chapter-1_line-a', {
      'url': 'https://example.com/c.m3u8',
    });

    await cache.removeByPrefix('video_link_v1_anime-a_');

    expect(await cache.get('video_link_v1_anime-a_chapter-1_line-a'), isNull);
    expect(await cache.get('video_link_v1_anime-a_chapter-2_line-a'), isNull);
    expect(
      await cache.get('video_link_v1_anime-b_chapter-1_line-a'),
      isNotNull,
    );
  });

  test('get removes expired ttl entries', () async {
    final cache = DataCache();

    await cache.put('video_link', {
      'url': 'https://example.com/video.m3u8',
    }, ttl: const Duration(milliseconds: -1));

    expect(await cache.get('video_link'), isNull);
  });
}
