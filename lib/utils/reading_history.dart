import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地阅读记录，记录每部漫画上次阅读到哪一话、第几页
class ReadingHistory {
  static const _prefix = 'reading_history_';

  /// 保存阅读进度
  static Future<void> save({
    required String pathWord,
    required String chapterUuid,
    required String chapterName,
    int page = 1,
    int totalPage = 0,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode({
      'chapterUuid': chapterUuid,
      'chapterName': chapterName,
      'page': page,
      'totalPage': totalPage,
    });
    await prefs.setString('$_prefix$pathWord', data);
  }

  /// 获取阅读进度，返回 null 表示无记录
  static Future<ReadingRecord?> get(String pathWord) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$pathWord');
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return ReadingRecord(
        chapterUuid: map['chapterUuid'] as String,
        chapterName: map['chapterName'] as String,
        page: map['page'] as int? ?? 1,
        totalPage: map['totalPage'] as int? ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

class ReadingRecord {
  final String chapterUuid;
  final String chapterName;
  final int page;
  final int totalPage;

  const ReadingRecord({
    required this.chapterUuid,
    required this.chapterName,
    required this.page,
    this.totalPage = 0,
  });
}
