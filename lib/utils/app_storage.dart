import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Central access point for lightweight app storage.
///
/// The split keeps cache cleanup from accidentally deleting user settings:
/// - [memory] is process-local and disappears when the app restarts.
/// - [cache] is persistent but disposable, using the existing `cache_` prefix.
/// - [preferences] reads and writes raw SharedPreferences keys unchanged.
class AppStorage {
  AppStorage._();

  static final memory = AppMemoryCache();
  static final cache = AppPersistentCache();
  static final preferences = AppPreferences();

  static Future<SharedPreferences>? _prefsFuture;

  static Future<SharedPreferences> sharedPreferences() {
    return _prefsFuture ??= SharedPreferences.getInstance();
  }
}

class AppMemoryCache {
  final Map<String, _MemoryCacheEntry> _entries = {};

  void put(String key, Object? data, {Duration? ttl}) {
    _entries[key] = _MemoryCacheEntry(
      data,
      expiresAt: ttl == null ? null : DateTime.now().add(ttl),
    );
  }

  void set(String key, Object? data, {Duration? ttl}) {
    put(key, data, ttl: ttl);
  }

  T? get<T>(String key) {
    final data = getRaw(key);
    if (data is T) return data;
    return null;
  }

  Object? getRaw(String key) {
    final entry = _entries[key];
    if (entry == null) return null;
    if (entry.isExpired) {
      _entries.remove(key);
      return null;
    }
    return entry.data;
  }

  bool containsKey(String key) {
    final entry = _entries[key];
    if (entry == null) return false;
    if (entry.isExpired) {
      _entries.remove(key);
      return false;
    }
    return true;
  }

  void remove(String key) {
    _entries.remove(key);
  }

  void removeByPrefix(String keyPrefix) {
    _entries.removeWhere((key, _) => key.startsWith(keyPrefix));
  }

  void clearExpired() {
    _entries.removeWhere((_, entry) => entry.isExpired);
  }

  void clear() {
    _entries.clear();
  }
}

class _MemoryCacheEntry {
  const _MemoryCacheEntry(this.data, {this.expiresAt});

  final Object? data;
  final DateTime? expiresAt;

  bool get isExpired {
    final expiresAt = this.expiresAt;
    return expiresAt != null && DateTime.now().isAfter(expiresAt);
  }
}

/// Persistent JSON cache compatible with the former DataCache implementation.
class AppPersistentCache {
  static const prefix = 'cache_';
  static const dataKey = '__cache_data__';
  static const expiresAtKey = '__cache_expires_at__';

  String fullKey(String key) => key.startsWith(prefix) ? key : '$prefix$key';

  Future<void> put(String key, dynamic data, {Duration? ttl}) async {
    final prefs = await AppStorage.sharedPreferences();
    final payload = ttl == null
        ? data
        : {
            dataKey: data,
            expiresAtKey: DateTime.now().add(ttl).millisecondsSinceEpoch,
          };
    await prefs.setString(fullKey(key), jsonEncode(payload));
  }

  Future<void> set(String key, dynamic data, {Duration? ttl}) {
    return put(key, data, ttl: ttl);
  }

  Future<dynamic> get(String key) async {
    final prefs = await AppStorage.sharedPreferences();
    final cacheKey = fullKey(key);
    final raw = prefs.getString(cacheKey);
    if (raw == null) return null;

    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic> && decoded.containsKey(dataKey)) {
      final expiresAt = decoded[expiresAtKey] as int?;
      if (expiresAt != null &&
          DateTime.now().millisecondsSinceEpoch > expiresAt) {
        await prefs.remove(cacheKey);
        return null;
      }
      return decoded[dataKey];
    }
    return decoded;
  }

  Future<T?> getAs<T>(String key) async {
    final data = await get(key);
    if (data is T) return data;
    return null;
  }

  Future<bool> containsKey(String key) async {
    final prefs = await AppStorage.sharedPreferences();
    final cacheKey = fullKey(key);
    if (!prefs.containsKey(cacheKey)) return false;
    final value = await get(key);
    return value != null || prefs.containsKey(cacheKey);
  }

  Future<void> remove(String key) async {
    final prefs = await AppStorage.sharedPreferences();
    await prefs.remove(fullKey(key));
  }

  Future<void> removeByPrefix(String keyPrefix) async {
    final prefs = await AppStorage.sharedPreferences();
    final fullPrefix = fullKey(keyPrefix);
    final keys = prefs.getKeys().where((key) => key.startsWith(fullPrefix));
    await Future.wait(keys.map(prefs.remove));
  }

  Future<void> clearExpired() async {
    final prefs = await AppStorage.sharedPreferences();
    final keys = prefs.getKeys().where((key) => key.startsWith(prefix));
    for (final key in keys) {
      await get(key);
    }
  }
}

/// Thin wrapper around SharedPreferences that preserves existing raw keys.
class AppPreferences {
  Future<Object?> get(String key) async {
    final prefs = await AppStorage.sharedPreferences();
    return prefs.get(key);
  }

  Future<String?> getString(String key) async {
    final prefs = await AppStorage.sharedPreferences();
    return prefs.getString(key);
  }

  Future<bool?> getBool(String key) async {
    final prefs = await AppStorage.sharedPreferences();
    return prefs.getBool(key);
  }

  Future<int?> getInt(String key) async {
    final prefs = await AppStorage.sharedPreferences();
    return prefs.getInt(key);
  }

  Future<double?> getDouble(String key) async {
    final prefs = await AppStorage.sharedPreferences();
    return prefs.getDouble(key);
  }

  Future<List<String>?> getStringList(String key) async {
    final prefs = await AppStorage.sharedPreferences();
    return prefs.getStringList(key);
  }

  Future<dynamic> getJson(String key) async {
    final raw = await getString(key);
    if (raw == null || raw.isEmpty) return null;
    return jsonDecode(raw);
  }

  Future<bool> setString(String key, String value) async {
    final prefs = await AppStorage.sharedPreferences();
    return prefs.setString(key, value);
  }

  Future<bool> setBool(String key, bool value) async {
    final prefs = await AppStorage.sharedPreferences();
    return prefs.setBool(key, value);
  }

  Future<bool> setInt(String key, int value) async {
    final prefs = await AppStorage.sharedPreferences();
    return prefs.setInt(key, value);
  }

  Future<bool> setDouble(String key, double value) async {
    final prefs = await AppStorage.sharedPreferences();
    return prefs.setDouble(key, value);
  }

  Future<bool> setStringList(String key, List<String> value) async {
    final prefs = await AppStorage.sharedPreferences();
    return prefs.setStringList(key, value);
  }

  Future<bool> setJson(String key, Object? value) async {
    return setString(key, jsonEncode(value));
  }

  Future<bool> containsKey(String key) async {
    final prefs = await AppStorage.sharedPreferences();
    return prefs.containsKey(key);
  }

  Future<bool> remove(String key) async {
    final prefs = await AppStorage.sharedPreferences();
    return prefs.remove(key);
  }

  Future<Set<String>> keys() async {
    final prefs = await AppStorage.sharedPreferences();
    return prefs.getKeys();
  }
}
