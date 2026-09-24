import 'dart:async';

import 'app_logger.dart';
import 'app_storage.dart';

/// 页面持有的本地搜索历史，不参与设置备份，也不缓存为全局单例。
///
/// 读取、添加、删除和清空按调用顺序串行执行，避免启动恢复或慢写入覆盖
/// 后续操作。每次操作都读取当前存储，缓存管理/应用重置后不会复活旧副本。
class SearchHistory {
  SearchHistory({AppPreferences? preferences})
    : _preferences = preferences ?? AppPreferences();

  static const storageKey = 'search_history_v1';
  static const maxEntries = 20;
  static final _pendingWrites = <Future<void>>{};

  /// 缓存管理与应用重置先等已有写入结束，避免清理后被旧提交写回。
  static Future<void> flush() async {
    while (_pendingWrites.isNotEmpty) {
      await Future.wait(_pendingWrites.toList());
    }
  }

  final AppPreferences _preferences;
  Future<void> _queue = Future<void>.value();
  List<String> _entries = const [];

  Future<List<String>> load() => _enqueue();

  Future<List<String>> add(String query) {
    final keyword = query.trim();
    if (keyword.isEmpty) return load();
    return _enqueue((entries) => [keyword, ...entries]);
  }

  Future<List<String>> remove(String query) {
    final keyword = query.trim();
    return _enqueue(
      (entries) => entries.where((entry) => entry != keyword).toList(),
    );
  }

  Future<List<String>> clear() => _enqueue((_) => const []);

  Future<List<String>> _enqueue([List<String> Function(List<String>)? update]) {
    final operation = _queue.then((_) async {
      try {
        _entries = _normalize(
          await _preferences.getStringList(storageKey) ?? const [],
        );
      } catch (error, stack) {
        _recordWarning(error, stack, 'read');
      }

      if (update != null) {
        // 内存结果先更新；存储失败不能阻止本次搜索或删除操作。
        _entries = _normalize(update(_entries));
        try {
          final saved = _entries.isEmpty
              ? await _preferences.remove(storageKey)
              : await _preferences.setStringList(storageKey, _entries);
          if (!saved) throw StateError('Search history persistence failed');
        } catch (error, stack) {
          _recordWarning(error, stack, 'write');
        }
      }
      return List<String>.unmodifiable(_entries);
    });
    _queue = operation.then<void>((_) {});
    if (update != null) {
      final pending = _queue;
      _pendingWrites.add(pending);
      unawaited(
        pending.then<void>((_) {
          _pendingWrites.remove(pending);
        }),
      );
    }
    return operation;
  }

  static List<String> _normalize(Iterable<String> entries) {
    final seen = <String>{};
    for (final entry in entries) {
      final keyword = entry.trim();
      if (keyword.isEmpty) continue;
      seen.add(keyword);
      if (seen.length == maxEntries) break;
    }
    return seen.toList(growable: false);
  }

  static void _recordWarning(Object error, StackTrace stack, String action) {
    unawaited(
      AppLogger.instance.recordWarning(
        error,
        stackTrace: stack,
        source: 'search_history.$action',
      ),
    );
  }
}
