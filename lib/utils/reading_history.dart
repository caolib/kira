import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_logger.dart';
import 'json_helpers.dart';

/// 本地阅读记录，记录每部漫画在各分组上次阅读到哪一话、章节列表页和图片页。
///
/// [save] 是防抖的：翻页会高频触发，而每次保存都要读回旧记录、合并已读章节
/// 集合、再把整条记录重新序列化写回——读得越多每页写入越大。窗口内的多次
/// 保存合并成一次落盘。
///
/// 防抖不会让读取方看到过期数据：[get] 与 [latestForComic] 会先冲刷待写队列。
/// 离开阅读页时应调用 [flush] 立即落盘。
class ReadingHistory {
  static const _prefix = 'reading_history_';
  static const defaultGroup = 'default';

  /// 合并窗口。取值需短到用户察觉不出，长到能吃掉连续翻页。
  static const _debounceDelay = Duration(milliseconds: 800);

  /// 按 (pathWord, group) 聚合的待写记录。
  ///
  /// 用 record 作键，值相等语义由语言保证，省去手工拼接分隔符的歧义。
  static final Map<(String, String?), _PendingSave> _pending = {};
  static Timer? _debounceTimer;
  static Future<void>? _queue;
  static bool _restoring = false;

  /// 组键在键名里分隔 pathWord 与组名的标记。
  /// [_pathWordOf] 反向还原 pathWord 时依赖同一个常量。
  static const _groupMarker = '_group_';

  /// 变更通知：每批记录落盘后递增。「继续阅读」这类展示页面监听它及时刷新，
  /// 否则页面常驻（底部导航分支 State 不重建）时会一直停留在旧记录。
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static String _legacyKey(String pathWord) => '$_prefix$pathWord';

  static String _groupKey(String pathWord, String group) =>
      '${_legacyKey(pathWord)}$_groupMarker${Uri.encodeComponent(group)}';

  static String? _normalizeGroup(String? group) {
    final trimmed = group?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// 保存阅读进度（防抖）。
  ///
  /// 返回的 Future 只表示已排入待写队列，**不代表已落盘**；需要确保写入
  /// 完成请调用 [flush]。
  static Future<void> save({
    required String pathWord,
    String? group,
    String? comicName,
    required String chapterUuid,
    required String chapterName,
    int? chapterListPage,
    int page = 1,
    int totalPage = 0,
  }) async {
    if (_restoring) return;
    final normalizedGroup = _normalizeGroup(group);
    final entry = _pending.putIfAbsent((
      pathWord,
      normalizedGroup,
    ), () => _PendingSave(pathWord: pathWord, group: normalizedGroup));
    entry.chapterUuid = chapterUuid;
    entry.chapterName = chapterName;
    // 有些入口(书签等)拿不到漫画名,空值不能把已知的名字抹掉。
    final trimmedComicName = comicName?.trim() ?? '';
    if (trimmedComicName.isNotEmpty) entry.comicName = trimmedComicName;
    entry.chapterListPage = chapterListPage;
    entry.page = page;
    entry.totalPage = totalPage;
    // 记录调用时刻而非落盘时刻：同一批 flush 写出的多条记录若共用落盘时间，
    // latestForComic 就无法分辨谁更新。
    entry.updatedAt = DateTime.now();
    // 窗口内每一话都要累积进已读集合，否则连续翻章时中间章节会漏记。
    if (chapterUuid.isNotEmpty) entry.readChapterUuids.add(chapterUuid);

    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDelay, _flushInBackground);
  }

  static Future<void> _flushInBackground() async {
    try {
      await flush();
    } catch (error, stack) {
      _logWarning(error, stack, 'flush');
    }
  }

  /// 立即落盘全部待写进度，并等待此前排队的读写完成。
  static Future<void> flush() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    final entries = _pending.values.toList(growable: false);
    _pending.clear();
    if (entries.isEmpty) return _queue ?? Future<void>.value();
    return _enqueue((prefs) async {
      for (final entry in entries) {
        await _write(prefs, entry);
      }
      // 落盘完成后再通知，保证监听方读到的是新数据。
      changes.value++;
    });
  }

  static Future<T> _enqueue<T>(
    FutureOr<T> Function(SharedPreferences prefs) action,
  ) {
    final operation = (_queue ?? Future<void>.value()).then(
      (_) async => action(await SharedPreferences.getInstance()),
    );
    late final Future<void> tail;
    void releaseIfIdle() {
      if (identical(_queue, tail)) _queue = null;
    }

    tail = operation.then<void>(
      (_) => releaseIfIdle(),
      onError: (Object error, StackTrace stack) => releaseIfIdle(),
    );
    _queue = tail;
    return operation;
  }

  static void _logWarning(Object error, StackTrace stack, String operation) {
    unawaited(
      AppLogger.instance.recordWarning(
        error,
        stackTrace: stack,
        source: 'reading_history.$operation',
      ),
    );
  }

  static Future<void> pauseForRestore() async {
    _restoring = true;
    await flush();
  }

  static void resumeAfterRestore() => _restoring = false;

  static void notifyRestored() => changes.value++;

  static Future<void> _write(
    SharedPreferences prefs,
    _PendingSave entry,
  ) async {
    final group = entry.group;
    final existing = _readFromPrefs(
      prefs,
      entry.pathWord,
      group: group,
      fallbackToLegacy: group == defaultGroup,
    );
    final readChapterUuids = <String>{
      ...?existing?.readChapterUuids,
      ...entry.readChapterUuids,
    }.toList()..sort();
    final data = jsonEncode({
      if (group != null && group.isNotEmpty) 'group': group,
      if (entry.comicName.isNotEmpty)
        'comicName': entry.comicName
      else if (existing?.comicName.isNotEmpty == true)
        'comicName': existing!.comicName,
      'chapterUuid': entry.chapterUuid,
      'chapterName': entry.chapterName,
      'chapterListPage': ?entry.chapterListPage,
      'page': entry.page,
      'totalPage': entry.totalPage,
      'updatedAt': entry.updatedAt.toIso8601String(),
      if (readChapterUuids.isNotEmpty) 'readChapterUuids': readChapterUuids,
    });
    if (group == null || group.isEmpty) {
      await _setString(prefs, _legacyKey(entry.pathWord), data);
      return;
    }
    await _setString(prefs, _groupKey(entry.pathWord, group), data);
    if (group == defaultGroup) {
      await _setString(prefs, _legacyKey(entry.pathWord), data);
    }
  }

  static Future<void> _setString(
    SharedPreferences prefs,
    String key,
    String value,
  ) async {
    if (!await prefs.setString(key, value)) {
      throw StateError('reading_history persistence failed');
    }
  }

  /// 获取阅读进度，返回 null 表示无记录
  static Future<ReadingRecord?> get(
    String pathWord, {
    String? group,
    bool fallbackToLegacy = true,
  }) async {
    await flush();
    return _enqueue(
      (prefs) => _readFromPrefs(
        prefs,
        pathWord,
        group: group,
        fallbackToLegacy: fallbackToLegacy,
      ),
    );
  }

  /// 获取这部漫画最近更新过的本地阅读记录，跨分组查询。
  static Future<ReadingRecord?> latestForComic(String pathWord) async {
    await flush();
    return _enqueue((prefs) {
      final legacyKey = _legacyKey(pathWord);
      final groupPrefix = '${legacyKey}_group_';
      final groupKeys =
          prefs.getKeys().where((key) => key.startsWith(groupPrefix)).toList()
            ..sort();
      final keys = [legacyKey, ...groupKeys];

      ReadingRecord? latest;
      for (final key in keys) {
        final record = _readKey(prefs, key);
        if (record == null || record.chapterUuid.isEmpty) continue;
        if (latest == null || _isRecordNewer(record, latest)) {
          latest = record;
        }
      }
      return latest;
    });
  }

  /// 批量查询作品全部分组的累计已读章节，不改变最近续读位置。
  static Future<Map<String, Set<String>>> readChapterUuidsForComics(
    Iterable<String> pathWords,
  ) async {
    final wanted = pathWords.toSet();
    await flush();
    return _enqueue((prefs) {
      final chapters = <String, Set<String>>{};
      for (final key in prefs.getKeys()) {
        if (!key.startsWith(_prefix)) continue;
        final pathWord = _pathWordOf(key);
        if (!wanted.contains(pathWord)) continue;
        final record = _readKey(prefs, key);
        if (record == null) continue;
        chapters
            .putIfAbsent(pathWord, () => <String>{})
            .addAll(record.readChapterUuids);
      }
      return chapters;
    });
  }

  /// 获取全库最近更新的阅读记录,用于「继续阅读」入口。
  ///
  /// 返回 null 表示本地还没有任何阅读记录。同时带回 pathWord——
  /// 键名里的 pathWord 是唯一的漫画标识,记录本身不重复存一份。
  static Future<({String pathWord, ReadingRecord record})?>
  latestRecord() async => (await readRecent(limit: 1)).firstOrNull;

  /// 每部漫画仅返回最近分组，默认分组的旧键镜像不会重复展示。
  static Future<List<({String pathWord, ReadingRecord record})>> readRecent({
    int? limit,
  }) async {
    await flush();
    return _enqueue((prefs) {
      if (limit != null && limit <= 0) {
        return <({String pathWord, ReadingRecord record})>[];
      }
      final keys =
          prefs.getKeys().where((key) => key.startsWith(_prefix)).toList()
            ..sort();
      final byComic = <String, ReadingRecord>{};
      for (final key in keys) {
        final pathWord = _pathWordOf(key);
        final record = _readKey(prefs, key);
        if (pathWord.isEmpty || record == null || record.chapterUuid.isEmpty) {
          continue;
        }
        final current = byComic[pathWord];
        if (current == null || _isRecordNewer(record, current)) {
          byComic[pathWord] = record;
        }
      }
      final records =
          [
            for (final entry in byComic.entries)
              (pathWord: entry.key, record: entry.value),
          ]..sort((a, b) {
            final aTime = a.record.updatedAt;
            final bTime = b.record.updatedAt;
            final byTime = aTime == null
                ? bTime == null
                      ? 0
                      : 1
                : bTime == null
                ? -1
                : bTime.compareTo(aTime);
            return byTime != 0 ? byTime : a.pathWord.compareTo(b.pathWord);
          });
      return List<({String pathWord, ReadingRecord record})>.unmodifiable(
        limit == null ? records : records.take(limit),
      );
    });
  }

  /// 删除作品的全部分组与旧键；先前待写位置不能在删除后复活。
  static Future<void> removeProgress(String pathWord) =>
      _removeWhere((key) => _pathWordOf(key) == pathWord);

  /// 仅清空漫画阅读记录，不影响小说、下载、书签或设置。
  static Future<void> clear() => _removeWhere((_) => true);

  static Future<void> _removeWhere(bool Function(String key) matches) {
    // 同步排入现有待写进度，随后删除排在它们之后；删除失败时保留先前位置。
    final writing = flush();
    return _enqueue((prefs) async {
      await writing;
      final keys =
          prefs
              .getKeys()
              .where((key) => key.startsWith(_prefix) && matches(key))
              .toList()
            ..sort();
      for (final key in keys) {
        final previous = prefs.get(key);
        try {
          if (!await prefs.remove(key)) {
            throw StateError('reading_history removal failed');
          }
        } catch (error, stack) {
          try {
            await _restoreValue(prefs, key, previous);
            await prefs.reload();
          } catch (rollbackError, rollbackStack) {
            _logWarning(rollbackError, rollbackStack, 'remove_rollback');
          }
          Error.throwWithStackTrace(error, stack);
        }
      }
      changes.value++;
    });
  }

  static Future<bool> _restoreValue(
    SharedPreferences prefs,
    String key,
    Object? value,
  ) => switch (value) {
    String() => prefs.setString(key, value),
    int() => prefs.setInt(key, value),
    double() => prefs.setDouble(key, value),
    bool() => prefs.setBool(key, value),
    List<String>() => prefs.setStringList(key, value),
    null => prefs.remove(key),
    _ => throw const FormatException('Unsupported reading history preference'),
  };

  /// 从 `reading_history_<pathWord>[_group_<g>]` 键名还原 pathWord。
  ///
  /// 组键的 pathWord 部分不含 [_groupMarker](pathWord 是站点的 slug/ID)。
  /// 只拆第一次标记，组名自身可以包含同一子串。
  static String _pathWordOf(String key) {
    final body = key.substring(_prefix.length);
    final markerIndex = body.indexOf(_groupMarker);
    return markerIndex < 0 ? body : body.substring(0, markerIndex);
  }

  static bool _isRecordNewer(ReadingRecord candidate, ReadingRecord current) {
    final candidateUpdatedAt = candidate.updatedAt;
    final currentUpdatedAt = current.updatedAt;
    if (candidateUpdatedAt != null && currentUpdatedAt != null) {
      return candidateUpdatedAt.isAfter(currentUpdatedAt);
    }
    if (candidateUpdatedAt != null) return true;
    if (currentUpdatedAt != null) return false;
    return false;
  }

  static ReadingRecord? _readFromPrefs(
    SharedPreferences prefs,
    String pathWord, {
    String? group,
    bool fallbackToLegacy = true,
  }) {
    final normalizedGroup = _normalizeGroup(group);
    final key = normalizedGroup == null || normalizedGroup.isEmpty
        ? _legacyKey(pathWord)
        : _groupKey(pathWord, normalizedGroup);
    if (prefs.containsKey(key)) return _readKey(prefs, key);
    return fallbackToLegacy && normalizedGroup == defaultGroup
        ? _readKey(prefs, _legacyKey(pathWord))
        : null;
  }

  static ReadingRecord? _readKey(SharedPreferences prefs, String key) {
    try {
      final raw = prefs.get(key);
      if (raw == null) return null;
      if (raw is! String) {
        throw const FormatException('Reading history must be JSON text');
      }
      final markerIndex = key.indexOf(_groupMarker, _prefix.length);
      final group = markerIndex < 0
          ? null
          : Uri.decodeComponent(
              key.substring(markerIndex + _groupMarker.length),
            );
      return _decode(raw, group: group);
    } catch (error, stack) {
      _logWarning(error, stack, 'read');
      return null;
    }
  }

  static ReadingRecord? _decode(String raw, {String? group}) {
    try {
      final map = jsonDecode(raw);
      if (map is! Map<String, dynamic>) {
        throw const FormatException('Reading history must be an object');
      }
      final chapterUuid = jsonString(map, 'chapterUuid');
      final readChapterUuids = _readStringSet(map['readChapterUuids']).toSet()
        ..add(chapterUuid);
      readChapterUuids.remove('');
      return ReadingRecord(
        chapterUuid: chapterUuid,
        chapterName: jsonString(map, 'chapterName'),
        comicName: jsonString(map, 'comicName'),
        chapterListPage: _readInt(map['chapterListPage']),
        page: _readInt(map['page']) ?? 1,
        totalPage: _readInt(map['totalPage']) ?? 0,
        readChapterUuids: readChapterUuids,
        group: jsonString(map, 'group').nullIfEmpty() ?? group,
        updatedAt: _readDateTime(map['updatedAt'] ?? map['updated_at']),
      );
    } catch (error, stack) {
      _logWarning(error, stack, 'decode');
      return null;
    }
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static DateTime? _readDateTime(Object? value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static Set<String> _readStringSet(Object? value) {
    if (value is List) {
      return value
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toSet();
    }
    if (value is String) {
      try {
        return _readStringSet(jsonDecode(value));
      } catch (error, stack) {
        _logWarning(error, stack, 'read_chapters');
        return const <String>{};
      }
    }
    return const <String>{};
  }
}

/// 一条待落盘的阅读进度，累积防抖窗口内的多次保存。
class _PendingSave {
  _PendingSave({required this.pathWord, required this.group});

  final String pathWord;
  final String? group;

  String chapterUuid = '';
  String chapterName = '';
  String comicName = '';
  int? chapterListPage;
  int page = 1;
  int totalPage = 0;

  /// 最后一次 [ReadingHistory.save] 的调用时刻，落盘时原样写出。
  DateTime updatedAt = DateTime.now();

  /// 窗口内读过的全部章节。逐条累加而非整体覆盖，否则连续翻章时
  /// 中间章节不会被计入已读。
  final Set<String> readChapterUuids = {};
}

class ReadingRecord {
  final String chapterUuid;
  final String chapterName;

  /// 漫画名,仅用于「继续阅读」副标题展示;旧记录没有这个字段,可能为空。
  final String comicName;

  /// 章节列表分页页码,0-based;旧记录可能为空。
  final int? chapterListPage;
  final int page;
  final int totalPage;
  final Set<String> readChapterUuids;
  final String? group;
  final DateTime? updatedAt;

  const ReadingRecord({
    required this.chapterUuid,
    required this.chapterName,
    this.comicName = '',
    this.chapterListPage,
    required this.page,
    this.totalPage = 0,
    this.readChapterUuids = const <String>{},
    this.group,
    this.updatedAt,
  });
}
