import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 轻量级 JSON 缓存，基于 SharedPreferences
class DataCache {
  static final DataCache _instance = DataCache._();
  factory DataCache() => _instance;
  DataCache._();

  static const _prefix = 'cache_';

  Future<void> put(String key, dynamic data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$key', jsonEncode(data));
  }

  Future<dynamic> get(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$key');
    if (raw == null) return null;
    return jsonDecode(raw);
  }
}
