import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 轻量级 JSON 缓存，基于 SharedPreferences
class DataCache {
  static final DataCache _instance = DataCache._();
  factory DataCache() => _instance;
  DataCache._();

  static const _prefix = 'cache_';
  static const _dataKey = '__cache_data__';
  static const _expiresAtKey = '__cache_expires_at__';

  Future<void> put(String key, dynamic data, {Duration? ttl}) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = ttl == null
        ? data
        : {
            _dataKey: data,
            _expiresAtKey: DateTime.now().add(ttl).millisecondsSinceEpoch,
          };
    await prefs.setString('$_prefix$key', jsonEncode(payload));
  }

  Future<dynamic> get(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$key');
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic> && decoded.containsKey(_dataKey)) {
      final expiresAt = decoded[_expiresAtKey] as int?;
      if (expiresAt != null &&
          DateTime.now().millisecondsSinceEpoch > expiresAt) {
        await prefs.remove('$_prefix$key');
        return null;
      }
      return decoded[_dataKey];
    }
    return decoded;
  }
}
