import 'app_storage.dart';

/// 轻量级 JSON 缓存，兼容旧的 `cache_` 前缀和 TTL 数据格式。
///
/// 新代码优先使用 [AppStorage.cache]；保留此类用于兼容现有调用点。
class DataCache {
  static final DataCache _instance = DataCache._();
  factory DataCache() => _instance;
  DataCache._();

  Future<void> put(String key, dynamic data, {Duration? ttl}) async {
    await AppStorage.cache.put(key, data, ttl: ttl);
  }

  Future<dynamic> get(String key) async {
    return AppStorage.cache.get(key);
  }

  Future<void> remove(String key) async {
    await AppStorage.cache.remove(key);
  }

  Future<void> removeByPrefix(String keyPrefix) async {
    await AppStorage.cache.removeByPrefix(keyPrefix);
  }
}
