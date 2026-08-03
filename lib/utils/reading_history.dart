import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// 公开前缀，供统计扫描 `reading_history_*` 键复用。
  static const legacyKeyPrefix = _prefix;

  /// 合并窗口。取值需短到用户察觉不出，长到能吃掉连续翻页。
  static const _debounceDelay = Duration(milliseconds: 800);

  /// 按 (pathWord, group) 聚合的待写记录。
  ///
  /// 用 record 作键，值相等语义由语言保证，省去手工拼接分隔符的歧义。
  static final Map<(String, String?), _PendingSave> _pending = {};
  static Timer? _debounceTimer;

  static String _legacyKey(String pathWord) => '$_prefix$pathWord';

  static String _groupKey(String pathWord, String group) =>
      '${_legacyKey(pathWord)}_group_${Uri.encodeComponent(group)}';

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
    required String chapterUuid,
    required String chapterName,
    int? chapterListPage,
    int page = 1,
    int totalPage = 0,
  }) async {
    final normalizedGroup = _normalizeGroup(group);
    final entry = _pending.putIfAbsent((
      pathWord,
      normalizedGroup,
    ), () => _PendingSave(pathWord: pathWord, group: normalizedGroup));
    entry.chapterUuid = chapterUuid;
    entry.chapterName = chapterName;
    entry.chapterListPage = chapterListPage;
    entry.page = page;
    entry.totalPage = totalPage;
    // 记录调用时刻而非落盘时刻：同一批 flush 写出的多条记录若共用落盘时间，
    // latestForComic 就无法分辨谁更新。
    entry.updatedAt = DateTime.now();
    // 窗口内每一话都要累积进已读集合，否则连续翻章时中间章节会漏记。
    if (chapterUuid.isNotEmpty) entry.readChapterUuids.add(chapterUuid);

    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDelay, () => unawaited(flush()));
  }

  /// 立即落盘全部待写进度。无待写数据时为无开销的空操作。
  static Future<void> flush() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (_pending.isEmpty) return;

    final entries = _pending.values.toList(growable: false);
    _pending.clear();

    final prefs = await SharedPreferences.getInstance();
    for (final entry in entries) {
      await _write(prefs, entry);
    }
  }

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
      'chapterUuid': entry.chapterUuid,
      'chapterName': entry.chapterName,
      'chapterListPage': ?entry.chapterListPage,
      'page': entry.page,
      'totalPage': entry.totalPage,
      'updatedAt': entry.updatedAt.toIso8601String(),
      if (readChapterUuids.isNotEmpty) 'readChapterUuids': readChapterUuids,
    });
    if (group == null || group.isEmpty) {
      await prefs.setString(_legacyKey(entry.pathWord), data);
      return;
    }
    await prefs.setString(_groupKey(entry.pathWord, group), data);
    if (group == defaultGroup) {
      await prefs.setString(_legacyKey(entry.pathWord), data);
    }
  }

  /// 获取阅读进度，返回 null 表示无记录
  static Future<ReadingRecord?> get(
    String pathWord, {
    String? group,
    bool fallbackToLegacy = true,
  }) async {
    await flush();
    final prefs = await SharedPreferences.getInstance();
    return _readFromPrefs(
      prefs,
      pathWord,
      group: group,
      fallbackToLegacy: fallbackToLegacy,
    );
  }

  /// 获取这部漫画最近更新过的本地阅读记录，跨分组查询。
  static Future<ReadingRecord?> latestForComic(String pathWord) async {
    await flush();
    final prefs = await SharedPreferences.getInstance();
    final legacyKey = _legacyKey(pathWord);
    final groupPrefix = '${legacyKey}_group_';
    final groupKeys =
        prefs.getKeys().where((key) => key.startsWith(groupPrefix)).toList()
          ..sort();
    final keys = [legacyKey, ...groupKeys];

    ReadingRecord? latest;
    for (final key in keys) {
      final raw = prefs.getString(key);
      if (raw == null) continue;
      final record = _decode(raw);
      if (record == null) continue;
      if (latest == null || _isRecordNewer(record, latest)) {
        latest = record;
      }
    }
    return latest;
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
    final raw = normalizedGroup == null || normalizedGroup.isEmpty
        ? prefs.getString(_legacyKey(pathWord))
        : prefs.getString(_groupKey(pathWord, normalizedGroup)) ??
              (fallbackToLegacy && normalizedGroup == defaultGroup
                  ? prefs.getString(_legacyKey(pathWord))
                  : null);
    if (raw == null) return null;
    return _decode(raw);
  }

  static ReadingRecord? _decode(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final chapterUuid = map['chapterUuid']?.toString() ?? '';
      final readChapterUuids = _readStringSet(map['readChapterUuids']).toSet()
        ..add(chapterUuid);
      readChapterUuids.remove('');
      return ReadingRecord(
        chapterUuid: chapterUuid,
        chapterName: map['chapterName']?.toString() ?? '',
        chapterListPage: _readInt(map['chapterListPage']),
        page: _readInt(map['page']) ?? 1,
        totalPage: _readInt(map['totalPage']) ?? 0,
        readChapterUuids: readChapterUuids,
        group: map['group']?.toString(),
        updatedAt: _readDateTime(map['updatedAt'] ?? map['updated_at']),
      );
    } catch (_) {
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
      } catch (_) {
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

  /// 章节列表分页页码，0-based；旧记录可能为空。
  final int? chapterListPage;
  final int page;
  final int totalPage;
  final Set<String> readChapterUuids;
  final String? group;
  final DateTime? updatedAt;

  const ReadingRecord({
    required this.chapterUuid,
    required this.chapterName,
    this.chapterListPage,
    required this.page,
    this.totalPage = 0,
    this.readChapterUuids = const <String>{},
    this.group,
    this.updatedAt,
  });
}
