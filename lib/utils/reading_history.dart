import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地阅读记录，记录每部漫画在各分组上次阅读到哪一话、章节列表页和图片页。
class ReadingHistory {
  static const _prefix = 'reading_history_';
  static const defaultGroup = 'default';

  static String _legacyKey(String pathWord) => '$_prefix$pathWord';

  static String _groupKey(String pathWord, String group) =>
      '${_legacyKey(pathWord)}_group_${Uri.encodeComponent(group)}';

  static String? _normalizeGroup(String? group) {
    final trimmed = group?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// 保存阅读进度
  static Future<void> save({
    required String pathWord,
    String? group,
    required String chapterUuid,
    required String chapterName,
    int? chapterListPage,
    int page = 1,
    int totalPage = 0,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedGroup = _normalizeGroup(group);
    final existing = _readFromPrefs(
      prefs,
      pathWord,
      group: normalizedGroup,
      fallbackToLegacy: normalizedGroup == defaultGroup,
    );
    final readChapterUuids = <String>{
      ...?existing?.readChapterUuids,
      if (chapterUuid.isNotEmpty) chapterUuid,
    }.toList()..sort();
    final data = jsonEncode({
      if (normalizedGroup != null && normalizedGroup.isNotEmpty)
        'group': normalizedGroup,
      'chapterUuid': chapterUuid,
      'chapterName': chapterName,
      'chapterListPage': ?chapterListPage,
      'page': page,
      'totalPage': totalPage,
      if (readChapterUuids.isNotEmpty) 'readChapterUuids': readChapterUuids,
    });
    if (normalizedGroup == null || normalizedGroup.isEmpty) {
      await prefs.setString(_legacyKey(pathWord), data);
      return;
    }
    await prefs.setString(_groupKey(pathWord, normalizedGroup), data);
    if (normalizedGroup == defaultGroup) {
      await prefs.setString(_legacyKey(pathWord), data);
    }
  }

  /// 获取阅读进度，返回 null 表示无记录
  static Future<ReadingRecord?> get(
    String pathWord, {
    String? group,
    bool fallbackToLegacy = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return _readFromPrefs(
      prefs,
      pathWord,
      group: group,
      fallbackToLegacy: fallbackToLegacy,
    );
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
      final readChapterUuids = _readStringSet(map['readChapterUuids'])
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

class ReadingRecord {
  final String chapterUuid;
  final String chapterName;

  /// 章节列表分页页码，0-based；旧记录可能为空。
  final int? chapterListPage;
  final int page;
  final int totalPage;
  final Set<String> readChapterUuids;
  final String? group;

  const ReadingRecord({
    required this.chapterUuid,
    required this.chapterName,
    this.chapterListPage,
    required this.page,
    this.totalPage = 0,
    this.readChapterUuids = const <String>{},
    this.group,
  });
}
