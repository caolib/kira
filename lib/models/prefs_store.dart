import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Base class for domain-specific preference stores.
///
/// Provides a shared `_prefs` getter and typed helpers to eliminate
/// the repeated `SharedPreferences.getInstance() → set* → notifyListeners()`
/// boilerplate found across UserManager's 60+ setters.
abstract class PrefsStore extends ChangeNotifier {
  SharedPreferences? _cachedPrefs;

  /// Lazily resolves SharedPreferences once per store instance.
  Future<SharedPreferences> get prefs async {
    return _cachedPrefs ??= await SharedPreferences.getInstance();
  }

  // ── Typed helpers ──────────────────────────────────────────────────

  /// Read a `String?` preference.
  Future<String?> getString(String key) async =>
      (await prefs).getString(key);

  /// Read an `int?` preference.
  Future<int?> getInt(String key) async => (await prefs).getInt(key);

  /// Read a `double?` preference.
  Future<double?> getDouble(String key) async =>
      (await prefs).getDouble(key);

  /// Read a `bool?` preference.
  Future<bool?> getBool(String key) async => (await prefs).getBool(key);

  /// Read a `List<String>?` preference.
  Future<List<String>?> getStringList(String key) async =>
      (await prefs).getStringList(key);

  /// Write a `String` value and optionally notify.
  Future<void> setString(String key, String value, {bool notify = true}) async {
    await (await prefs).setString(key, value);
    if (notify) notifyListeners();
  }

  /// Write an `int` value and optionally notify.
  Future<void> setInt(String key, int value, {bool notify = true}) async {
    await (await prefs).setInt(key, value);
    if (notify) notifyListeners();
  }

  /// Write a `double` value and optionally notify.
  Future<void> setDouble(String key, double value, {bool notify = true}) async {
    await (await prefs).setDouble(key, value);
    if (notify) notifyListeners();
  }

  /// Write a `bool` value and optionally notify.
  Future<void> setBool(String key, bool value, {bool notify = true}) async {
    await (await prefs).setBool(key, value);
    if (notify) notifyListeners();
  }

  /// Write a `List<String>` value and optionally notify.
  Future<void> setStringList(
    String key,
    List<String> value, {
    bool notify = true,
  }) async {
    await (await prefs).setStringList(key, value);
    if (notify) notifyListeners();
  }

  /// Remove a key and optionally notify.
  Future<void> remove(String key, {bool notify = true}) async {
    await (await prefs).remove(key);
    if (notify) notifyListeners();
  }
}
