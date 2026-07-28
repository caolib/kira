import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/app_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('clearExpired drops expired entries and keeps fresh ones', () async {
    final cache = AppStorage.cache;

    await cache.put('stale', {'v': 1}, ttl: const Duration(milliseconds: 1));
    await cache.put('fresh', {'v': 2}, ttl: const Duration(hours: 1));
    await Future<void>.delayed(const Duration(milliseconds: 5));

    final removed = await cache.clearExpired();

    expect(removed, 1);
    expect(await cache.get('stale'), isNull);
    expect(await cache.get('fresh'), isNotNull);
  });

  test('clearExpired leaves entries stored without a TTL alone', () async {
    final cache = AppStorage.cache;

    // 无 TTL 的条目不带过期戳，应当永久保留（如用户手动固定的数据）。
    await cache.put('forever', {'v': 3});

    final removed = await cache.clearExpired();

    expect(removed, 0);
    expect(await cache.get('forever'), isNotNull);
  });

  test('clearExpired ignores non-cache preference keys', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_token', 'token-1');
    // 构造一个键名不带 cache_ 前缀、但内容里含过期戳的偏好项。
    await prefs.setString(
      'looks_like_cache',
      '{"__cache_data__":{"v":4},"__cache_expires_at__":1}',
    );

    final removed = await AppStorage.cache.clearExpired();

    expect(removed, 0);
    expect(prefs.getString('user_token'), 'token-1');
    expect(prefs.getString('looks_like_cache'), isNotNull);
  });

  test('clearExpired reports how many entries it dropped', () async {
    final cache = AppStorage.cache;

    for (final key in ['a', 'b', 'c']) {
      await cache.put(key, {'v': key}, ttl: const Duration(milliseconds: 1));
    }
    await cache.put('keep', {'v': 'keep'}, ttl: const Duration(hours: 1));
    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(await cache.clearExpired(), 3);
    expect(await cache.get('keep'), isNotNull);
  });
}
