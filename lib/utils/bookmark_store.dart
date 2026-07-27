import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 漫画书签：记录阅读器中用户手动标记的位置（漫画 + 章节 + 页码）。
///
/// 与 `ReadingHistory`（自动记录阅读进度）不同，书签由用户主动添加。
/// 全量列表存储在单个 `comic_bookmarks_v1` 键下（不带 cache_ 前缀，
/// 因此会随设置备份导出，也不会被缓存清理误删）。
class ComicBookmark {
  final String pathWord;
  final String comicName;

  /// 封面 URL，打书签时从漫画详情本地缓存读取（无网络请求）。
  /// 旧版本书签可能为空，列表页退化为占位图。
  final String cover;

  /// 打书签时所在的章节分组，从详情缓存读取。
  /// 旧版本书签可能为空，进入阅读器时回退到默认分组键。
  final String group;
  final String chapterUuid;
  final String chapterName;
  final int page;
  final DateTime? updatedAt;

  const ComicBookmark({
    required this.pathWord,
    required this.comicName,
    this.cover = '',
    this.group = '',
    required this.chapterUuid,
    required this.chapterName,
    required this.page,
    this.updatedAt,
  });

  /// 同一章节同一页视为同一书签。
  String get id => '$chapterUuid:$page';

  factory ComicBookmark.fromJson(Map<String, dynamic> json) {
    return ComicBookmark(
      pathWord: json['pathWord']?.toString() ?? '',
      comicName: json['comicName']?.toString() ?? '',
      cover: json['cover']?.toString() ?? '',
      group: json['group']?.toString() ?? '',
      chapterUuid: json['chapterUuid']?.toString() ?? '',
      chapterName: json['chapterName']?.toString() ?? '',
      page: _readInt(json['page']) ?? 1,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
    'pathWord': pathWord,
    'comicName': comicName,
    if (cover.isNotEmpty) 'cover': cover,
    if (group.isNotEmpty) 'group': group,
    'chapterUuid': chapterUuid,
    'chapterName': chapterName,
    'page': page,
    'updatedAt': ?updatedAt?.toIso8601String(),
  };

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

/// 书签 store：`ChangeNotifier` 单例，内存持有全量列表（按标记时间倒序，
/// 最新在前），变更时持久化到 SharedPreferences 并通知监听者。
class BookmarkStore extends ChangeNotifier {
  BookmarkStore._();

  static final BookmarkStore _instance = BookmarkStore._();
  factory BookmarkStore() => _instance;

  static const _key = 'comic_bookmarks_v1';

  /// 数量上限，超出时淘汰最旧的书签。
  @visibleForTesting
  static const maxBookmarks = 500;

  final List<ComicBookmark> _bookmarks = [];
  bool _loaded = false;

  List<ComicBookmark> get bookmarks => List.unmodifiable(_bookmarks);

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw);
      if (list is! List) return;
      _bookmarks
        ..clear()
        ..addAll(
          list
              .whereType<Map>()
              .map((e) => ComicBookmark.fromJson(Map<String, dynamic>.from(e)))
              .where((b) => b.pathWord.isNotEmpty && b.chapterUuid.isNotEmpty),
        );
    } catch (_) {
      // 数据损坏时视为空列表，下次写入自动覆盖。
    }
  }

  bool isBookmarked(String chapterUuid, int page) =>
      _bookmarks.any((b) => b.chapterUuid == chapterUuid && b.page == page);

  /// 切换指定位置的书签状态，返回 true 表示新增、false 表示移除。
  Future<bool> toggle({
    required String pathWord,
    required String comicName,
    String cover = '',
    String group = '',
    required String chapterUuid,
    required String chapterName,
    required int page,
  }) async {
    await ensureLoaded();
    final index = _bookmarks.indexWhere(
      (b) => b.chapterUuid == chapterUuid && b.page == page,
    );
    if (index >= 0) {
      _bookmarks.removeAt(index);
      await _persist();
      return false;
    }
    _bookmarks.insert(
      0,
      ComicBookmark(
        pathWord: pathWord,
        comicName: comicName,
        cover: cover,
        group: group,
        chapterUuid: chapterUuid,
        chapterName: chapterName,
        page: page,
        updatedAt: DateTime.now(),
      ),
    );
    if (_bookmarks.length > maxBookmarks) {
      _bookmarks.removeRange(maxBookmarks, _bookmarks.length);
    }
    await _persist();
    return true;
  }

  Future<void> remove(String id) async {
    await ensureLoaded();
    final index = _bookmarks.indexWhere((b) => b.id == id);
    if (index < 0) return;
    _bookmarks.removeAt(index);
    await _persist();
  }

  /// 删除某部漫画的全部书签，返回被删除的书签（用于撤销）。
  Future<List<ComicBookmark>> removeForComic(String pathWord) async {
    await ensureLoaded();
    final removed = _bookmarks.where((b) => b.pathWord == pathWord).toList();
    if (removed.isEmpty) return const [];
    _bookmarks.removeWhere((b) => b.pathWord == pathWord);
    await _persist();
    return removed;
  }

  /// 清空全部书签，返回被删除的书签（用于撤销）。
  Future<List<ComicBookmark>> clear() async {
    await ensureLoaded();
    if (_bookmarks.isEmpty) return const [];
    final removed = List<ComicBookmark>.of(_bookmarks);
    _bookmarks.clear();
    await _persist();
    return removed;
  }

  /// 批量恢复书签（撤销删除），按标记时间倒序归并。
  Future<void> restoreAll(List<ComicBookmark> items) async {
    await ensureLoaded();
    final existing = _bookmarks.map((b) => b.id).toSet();
    _bookmarks.addAll(items.where((b) => !existing.contains(b.id)));
    _bookmarks.sort(_byNewest);
    if (_bookmarks.length > maxBookmarks) {
      _bookmarks.removeRange(maxBookmarks, _bookmarks.length);
    }
    await _persist();
  }

  static int _byNewest(ComicBookmark a, ComicBookmark b) {
    final at = a.updatedAt;
    final bt = b.updatedAt;
    if (at == null && bt == null) return 0;
    if (at == null) return 1;
    if (bt == null) return -1;
    return bt.compareTo(at);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(_bookmarks.map((b) => b.toJson()).toList()),
    );
    notifyListeners();
  }

  /// 从磁盘重新加载。导入备份或重置应用覆写了 SharedPreferences 后调用，
  /// 使内存副本与磁盘一致。
  Future<void> reload() async {
    _loaded = false;
    _bookmarks.clear();
    await ensureLoaded();
    notifyListeners();
  }

  /// 清空内存状态，供测试隔离使用。
  @visibleForTesting
  void debugReset() {
    _bookmarks.clear();
    _loaded = false;
  }
}
