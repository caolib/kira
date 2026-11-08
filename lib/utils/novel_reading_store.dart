import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/novel_reading_progress.dart';
import 'app_logger.dart';

/// 按书保存轻小说阅读位置，每次读取当前 prefs，不保留一次性加载的副本。
class NovelReadingStore {
  NovelReadingStore({Future<SharedPreferences>? prefs})
    : _prefs = prefs ?? SharedPreferences.getInstance();

  /// 与漫画的 reading_history_ 独立，不能被漫画继续阅读入口识别。
  static const prefix = 'novel_reading_history_';

  /// 进度变更通知，供「我的」继续阅读等常驻页面刷新；与漫画的
  /// [ReadingHistory.changes] 各管各的数据。
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  /// 写入成功后自增，供调用方在完成时刷新界面。
  static void notifyChanged() => changes.value++;

  // 默认 prefs 在实例间共享，因此队列也在实例间共享。读取和删除同样排队，
  // 避免慢写完成前读出旧位置，或删除后又被此前的异步写入恢复。
  static Future<void>? _queue;
  final Future<SharedPreferences> _prefs;

  Future<NovelReadingProgress?> readProgress(String pathWord) =>
      _enqueue((prefs) => _read(prefs, '$prefix$pathWord'));

  /// 批量查询累计已读卷；旧记录的当前卷也视为已读。
  Future<Map<String, Set<String>>> readVolumeIdsForBooks(
    Iterable<String> pathWords,
  ) => _enqueue((prefs) {
    final volumes = <String, Set<String>>{};
    for (final pathWord in pathWords.toSet()) {
      final record = _read(prefs, '$prefix$pathWord');
      if (record == null) continue;
      volumes[pathWord] = {...record.readVolumeIds, record.volumeId};
    }
    return volumes;
  });

  Future<List<NovelReadingProgress>> readRecent({int? limit = 30}) =>
      _enqueue((prefs) {
        if (limit != null && limit <= 0) {
          return const <NovelReadingProgress>[];
        }
        final records = <NovelReadingProgress>[];
        for (final key in prefs.getKeys()) {
          if (!key.startsWith(prefix)) continue;
          final record = _read(prefs, key);
          if (record != null) records.add(record);
        }
        records.sort((a, b) {
          final byTime = b.updatedAt.compareTo(a.updatedAt);
          return byTime != 0 ? byTime : a.pathWord.compareTo(b.pathWord);
        });
        return List<NovelReadingProgress>.unmodifiable(
          limit == null ? records : records.take(limit),
        );
      });

  /// 完成的 Future 表示已经写入；同书较旧的事件不会覆盖较新的位置。
  Future<void> saveProgress(NovelReadingProgress progress) => _enqueue((
    prefs,
  ) async {
    if (progress.pathWord.trim().isEmpty || progress.volumeId.trim().isEmpty) {
      throw ArgumentError('Novel progress requires book and volume IDs');
    }
    final key = '$prefix${progress.pathWord}';
    final existing = _read(prefs, key);
    if (existing != null && progress.updatedAt.isBefore(existing.updatedAt)) {
      return;
    }
    // 已读卷集合只增不减：并入旧记录的集合后加上当前卷，详情页据此淡化
    // 已读章节卡片；旧记录没有该字段时也能从当前卷开始积累。
    final merged = progress.copyWith(
      readVolumeIds: {
        ...?existing?.readVolumeIds,
        ...progress.readVolumeIds,
        progress.volumeId,
      },
    );
    if (!await prefs.setString(key, jsonEncode(merged.toJson()))) {
      throw StateError('Novel reading progress persistence failed');
    }
    notifyChanged();
  });

  Future<void> removeProgress(String pathWord) => _enqueue((prefs) async {
    if (!await prefs.remove('$prefix$pathWord')) {
      throw StateError('Novel reading progress removal failed');
    }
    notifyChanged();
  });

  /// 仅清理轻小说阅读历史，不影响漫画历史、阅读设置或其他缓存。
  Future<void> clear() => _enqueue((prefs) async {
    final keys = prefs
        .getKeys()
        .where((key) => key.startsWith(prefix))
        .toList();
    for (final key in keys) {
      if (!await prefs.remove(key)) {
        throw StateError('Novel reading history clearing failed');
      }
    }
    notifyChanged();
  });

  Future<T> _enqueue<T>(FutureOr<T> Function(SharedPreferences prefs) action) {
    final operation = (_queue ?? Future<void>.value()).then(
      (_) async => action(await _prefs),
    );
    late final Future<void> tail;
    void releaseIfIdle() {
      // 只释放自己仍是队尾的空闲队列，不能清掉后来排入的任务。
      // 不长期持有已完成 Future 及其 Zone，下一批从调用方上下文开始。
      if (identical(_queue, tail)) _queue = null;
    }

    // 单次失败返回给调用方，同时恢复队列，不能阻断下一次保存。
    tail = operation.then<void>(
      (_) => releaseIfIdle(),
      onError: (Object error, StackTrace stack) {
        releaseIfIdle();
        unawaited(
          AppLogger.instance.recordWarning(
            error,
            stackTrace: stack,
            source: 'novel_reading_store',
          ),
        );
      },
    );
    _queue = tail;
    return operation;
  }

  static NovelReadingProgress? _read(SharedPreferences prefs, String key) {
    try {
      final raw = prefs.get(key);
      if (raw == null) return null;
      if (raw is! String) {
        throw const FormatException('Novel reading progress must be JSON text');
      }
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) {
        throw const FormatException('Novel reading progress must be an object');
      }
      final record = NovelReadingProgress.fromJson(json);
      if (key != '$prefix${record.pathWord}') {
        throw const FormatException('Novel reading progress key mismatch');
      }
      return record;
    } catch (error, stack) {
      // 不记录原始 JSON/地址，避免损坏内容或签名参数进入日志。
      unawaited(
        AppLogger.instance.recordWarning(
          'Skipped invalid novel reading progress (${error.runtimeType})',
          stackTrace: stack,
          source: 'novel_reading_store.read',
        ),
      );
      return null;
    }
  }
}
