import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/novel_reading_progress.dart';
import 'app_logger.dart';
import 'bookmark_store.dart' show BookmarkGroupMetadata, BookmarkStoreBase;
import 'json_helpers.dart';

/// 用户主动标记的轻小说段落，与自动更新的最后阅读进度相互独立。
@immutable
class NovelBookmark {
  NovelBookmark({required NovelReadingProgress position})
    : position = position.copyWith(txtAddr: '') {
    if (pathWord.trim().isEmpty || volumeId.trim().isEmpty) {
      throw ArgumentError('Novel bookmark requires book and volume IDs');
    }
  }

  /// 保存原始目录索引和段落锚点，不保存正文地址、账号或鉴权数据。
  final NovelReadingProgress position;

  String get pathWord => position.pathWord;
  String get name => position.name;
  String get cover => position.cover;
  String get volumeId => position.volumeId;
  String get volumeName => position.volumeName;
  String get chapterName => position.chapterName;
  int get entryIndex => position.entryIndex;
  int get paragraphIndex => position.paragraphIndex;
  double get paragraphAlignment => position.paragraphAlignment;
  double get progress => position.progress;
  DateTime get updatedAt => position.updatedAt;

  /// 同一段落只有一个书签；浮点对齐值不参与身份，避免滚动微移产生重复项。
  String get id => positionId(
    pathWord: pathWord,
    volumeId: volumeId,
    entryIndex: entryIndex,
    paragraphIndex: paragraphIndex,
  );

  static String positionId({
    required String pathWord,
    required String volumeId,
    required int entryIndex,
    required int paragraphIndex,
  }) => jsonEncode([pathWord, volumeId, entryIndex, paragraphIndex]);

  factory NovelBookmark.fromJson(Map<String, dynamic> json) {
    for (final key in ['pathWord', 'volumeId', 'updatedAt']) {
      if (json[key] is! String || jsonString(json, key).trim().isEmpty) {
        throw const FormatException('Invalid novel bookmark identity/date');
      }
    }
    for (final key in ['entryIndex', 'paragraphIndex']) {
      final value = json[key];
      if (value is! int || value < 0) {
        throw const FormatException('Invalid novel bookmark index');
      }
    }
    for (final key in ['name', 'cover', 'volumeName', 'chapterName']) {
      if (json[key] != null && json[key] is! String) {
        throw const FormatException('Invalid novel bookmark label');
      }
    }
    for (final key in ['paragraphAlignment', 'progress']) {
      final value = json[key];
      if (value != null && (value is! num || !value.isFinite)) {
        throw const FormatException('Invalid novel bookmark position');
      }
    }
    final progress = jsonDouble(json, 'progress');
    final updatedAt = DateTime.tryParse(jsonString(json, 'updatedAt'));
    if (updatedAt == null || progress < 0 || progress > 1) {
      throw const FormatException('Invalid novel bookmark progress/date');
    }
    return NovelBookmark(
      position: NovelReadingProgress(
        pathWord: jsonString(json, 'pathWord'),
        name: jsonString(json, 'name'),
        cover: jsonString(json, 'cover'),
        volumeId: jsonString(json, 'volumeId'),
        volumeName: jsonString(json, 'volumeName'),
        chapterName: jsonString(json, 'chapterName'),
        entryIndex: jsonInt(json, 'entryIndex'),
        paragraphIndex: jsonInt(json, 'paragraphIndex'),
        paragraphAlignment: jsonDouble(json, 'paragraphAlignment'),
        progress: progress,
        updatedAt: updatedAt,
      ),
    );
  }

  Map<String, dynamic> toJson() => position.toJson()..remove('txtAddr');
}

/// 书签组的元数据：书签被删光后组头仍要保留（封面、书名、继续阅读入口），
/// 因此在加书签时单独记一份，删除书签时不动它。
@immutable
class NovelBookmarkGroup implements BookmarkGroupMetadata<NovelBookmarkGroup> {
  const NovelBookmarkGroup({
    required this.pathWord,
    required this.name,
    this.cover = '',
    required this.updatedAt,
    this.pinned = false,
  });

  @override
  final String pathWord;
  final String name;
  final String cover;
  final DateTime updatedAt;
  @override
  final bool pinned;

  factory NovelBookmarkGroup.fromJson(Map<String, dynamic> json) =>
      NovelBookmarkGroup(
        pathWord: jsonString(json, 'pathWord'),
        name: jsonString(json, 'name'),
        cover: jsonString(json, 'cover'),
        pinned: jsonBool(json, 'pinned'),
        updatedAt:
            DateTime.tryParse(jsonString(json, 'updatedAt')) ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  @override
  NovelBookmarkGroup withPinned(bool pinned) => NovelBookmarkGroup(
    pathWord: pathWord,
    name: name,
    cover: cover,
    updatedAt: updatedAt,
    pinned: pinned,
  );

  Map<String, dynamic> toJson() => {
    'pathWord': pathWord,
    'name': name,
    if (cover.isNotEmpty) 'cover': cover,
    'updatedAt': updatedAt.toIso8601String(),
    'pinned': pinned,
  };
}

/// 轻小说书签单例，保存原始阅读位置与独立的分组元数据。
class NovelBookmarkStore
    extends BookmarkStoreBase<NovelBookmark, NovelBookmarkGroup> {
  NovelBookmarkStore._() : super(storageKey, groupsStorageKey);

  static final NovelBookmarkStore _instance = NovelBookmarkStore._();
  factory NovelBookmarkStore() => _instance;

  @visibleForTesting
  NovelBookmarkStore.forTesting({required Future<SharedPreferences> prefs})
    : super(storageKey, groupsStorageKey, prefs: prefs);

  // 不使用 novel_reading_history_ 前缀，避免被自动阅读历史枚举/清理。
  static const storageKey = 'novel_bookmarks_v1';

  /// 组元数据单独存一个键：清空书签时保留，组头才不会跟着消失。
  static const groupsStorageKey = 'novel_bookmark_groups_v1';
  static const maxBookmarks = 500;

  bool isBookmarked({
    required String pathWord,
    required String volumeId,
    required int entryIndex,
    required int paragraphIndex,
  }) {
    final id = NovelBookmark.positionId(
      pathWord: pathWord,
      volumeId: volumeId,
      entryIndex: entryIndex,
      paragraphIndex: paragraphIndex,
    );
    return bookmarks.any((bookmark) => bookmark.id == id);
  }

  /// 返回 true 表示新增，false 表示取消；Future 完成时已持久化。
  Future<bool> toggle({required NovelReadingProgress progress}) {
    final bookmark = NovelBookmark(
      position: progress.copyWith(updatedAt: DateTime.now()),
    );
    return mutate(
      blocked: () => bookmarks.any((item) => item.id == bookmark.id),
      action: () async {
        final exists = bookmarks.any((item) => item.id == bookmark.id);
        // 记下组元数据：这之后即使书签被删光，书签页也保留该组。
        await _commit(
          exists
              ? bookmarks.where((item) => item.id != bookmark.id)
              : [bookmark, ...bookmarks],
          groups: exists
              ? null
              : _updatedGroups(
                  pathWord: bookmark.pathWord,
                  name: bookmark.name,
                  cover: bookmark.cover,
                ),
        );
        return !exists;
      },
    );
  }

  Future<NovelBookmark?> remove(String id) => mutate(
    blocked: () => null,
    action: () async {
      final index = bookmarks.indexWhere((item) => item.id == id);
      if (index < 0) return null;
      final removed = bookmarks[index];
      await _commit(bookmarks.where((item) => item.id != id));
      return removed;
    },
  );

  Future<List<NovelBookmark>> removeForNovel(String pathWord) => mutate(
    blocked: () => const <NovelBookmark>[],
    action: () async {
      final removed = bookmarks
          .where((item) => item.pathWord == pathWord)
          .toList();
      if (removed.isNotEmpty) {
        await _commit(bookmarks.where((item) => item.pathWord != pathWord));
      }
      return removed;
    },
  );

  Future<List<NovelBookmark>> clear() => mutate(
    blocked: () => const <NovelBookmark>[],
    action: () async {
      final removed = bookmarks;
      if (removed.isNotEmpty) await _commit(const []);
      return removed;
    },
  );

  /// 只登记分组、不加具体书签：详情页的「加入书签」入口。
  Future<void> addGroup({
    required String pathWord,
    required String name,
    String cover = '',
  }) => mutate<void>(
    blocked: () {},
    action: () async {
      if (hasGroup(pathWord)) return;
      await commit(
        items: bookmarks,
        groups: _updatedGroups(pathWord: pathWord, name: name, cover: cover),
      );
    },
  );

  /// 取消收藏：分组连同该轻小说的书签一起移除，返回被删除的书签。
  Future<List<NovelBookmark>> removeGroup(String pathWord) => mutate(
    blocked: () => const <NovelBookmark>[],
    action: () async {
      final removed = bookmarks
          .where((item) => item.pathWord == pathWord)
          .toList();
      if (removed.isEmpty && !hasGroup(pathWord)) {
        return const <NovelBookmark>[];
      }
      await _commit(
        bookmarks.where((item) => item.pathWord != pathWord),
        groups: groups.where((group) => group.pathWord != pathWord),
      );
      return removed;
    },
  );

  /// 撤销只补回缺失的书签，不覆盖用户随后重新标记的位置。
  Future<void> restoreAll(
    List<NovelBookmark> items, {
    List<NovelBookmarkGroup> groups = const [],
  }) {
    final snapshot = List<NovelBookmark>.of(items);
    final groupSnapshot = List<NovelBookmarkGroup>.of(groups);
    return mutate<void>(
      blocked: () {},
      action: () async {
        final ids = bookmarks.map((item) => item.id).toSet();
        final added = snapshot.where((item) => ids.add(item.id)).toList();
        final knownGroups = this.groups.map((group) => group.pathWord).toSet();
        final addedGroups = groupSnapshot
            .where((group) => knownGroups.add(group.pathWord))
            .toList();
        if (added.isEmpty && addedGroups.isEmpty) return;
        final nextGroups = [...this.groups, ...addedGroups]
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        await _commit([
          ...bookmarks,
          ...added,
        ], groups: nextGroups.take(maxBookmarks));
      },
    );
  }

  Future<void> _commit(
    Iterable<NovelBookmark> items, {
    Iterable<NovelBookmarkGroup>? groups,
  }) => commit(items: _normalize(items), groups: groups);

  /// 更新书名、封面及最近标记时间，保留用户的置顶选择。
  Iterable<NovelBookmarkGroup> _updatedGroups({
    required String pathWord,
    required String name,
    required String cover,
  }) {
    final previous = groups
        .where((group) => group.pathWord == pathWord)
        .firstOrNull;
    return [
      NovelBookmarkGroup(
        pathWord: pathWord,
        name: name.isEmpty ? previous?.name ?? '' : name,
        cover: cover.isEmpty ? previous?.cover ?? '' : cover,
        updatedAt: DateTime.now(),
        pinned: previous?.pinned ?? false,
      ),
      ...groups.where((group) => group.pathWord != pathWord),
    ].take(maxBookmarks);
  }

  @override
  (List<NovelBookmark>, List<NovelBookmarkGroup>) readStored(
    SharedPreferences prefs,
  ) {
    final items = <NovelBookmark>[];
    try {
      final raw = prefs.get(storageKey);
      if (raw != null) {
        if (raw is! String) {
          throw const FormatException('Novel bookmarks must be JSON text');
        }
        final decoded = jsonDecode(raw);
        if (decoded is! List) {
          throw const FormatException('Novel bookmarks must be a list');
        }
        for (final value in decoded) {
          try {
            if (value is! Map<String, dynamic>) {
              throw const FormatException('Novel bookmark must be an object');
            }
            items.add(NovelBookmark.fromJson(value));
          } catch (error, stack) {
            _logFailure('read_item', error, stack);
          }
        }
      }
    } catch (error, stack) {
      _logFailure('read', error, stack);
    }
    final bookmarks = _normalize(items);
    return (bookmarks, _withGroupsFromBookmarks(_readGroups(prefs), bookmarks));
  }

  /// 补上「有书签但还没有组元数据」的作品：组元数据是后加的功能，
  /// 老书签没有对应记录，否则详情页书签按钮会显示成未添加、删光书签后组也会消失。
  /// 只改内存，不在这里写盘——读取路径保持只读，下次任何写入会带上补齐的组。
  static List<NovelBookmarkGroup> _withGroupsFromBookmarks(
    List<NovelBookmarkGroup> groups,
    List<NovelBookmark> bookmarks,
  ) {
    final known = groups.map((group) => group.pathWord).toSet();
    final added = <NovelBookmarkGroup>[];
    for (final bookmark in bookmarks) {
      if (!known.add(bookmark.pathWord)) continue;
      added.add(
        NovelBookmarkGroup(
          pathWord: bookmark.pathWord,
          name: bookmark.name,
          cover: bookmark.cover,
          updatedAt: bookmark.updatedAt,
        ),
      );
    }
    if (added.isEmpty) return groups;
    final merged = [...groups, ...added]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List.unmodifiable(merged);
  }

  /// 组元数据读失败时按空处理，不影响书签本身。
  static List<NovelBookmarkGroup> _readGroups(SharedPreferences prefs) {
    try {
      final raw = prefs.get(groupsStorageKey);
      if (raw is! String) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final groups = <NovelBookmarkGroup>[];
      for (final value in decoded) {
        try {
          if (value is! Map<String, dynamic>) {
            throw const FormatException('Novel bookmark group must be object');
          }
          final group = NovelBookmarkGroup.fromJson(value);
          if (group.pathWord.isNotEmpty) groups.add(group);
        } catch (error, stack) {
          _logFailure('read_group', error, stack);
        }
      }
      return List.unmodifiable(groups.take(maxBookmarks));
    } catch (error, stack) {
      _logFailure('read_groups', error, stack);
      return const [];
    }
  }

  static List<NovelBookmark> _normalize(Iterable<NovelBookmark> items) {
    final sorted = items.toList()
      ..sort((a, b) {
        final byDate = b.updatedAt.compareTo(a.updatedAt);
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });
    final ids = <String>{};
    return List<NovelBookmark>.unmodifiable(
      sorted.where((item) => ids.add(item.id)).take(maxBookmarks),
    );
  }

  static void _logFailure(String action, Object error, StackTrace stack) {
    // 不把损坏 JSON、正文地址或签名查询参数写入日志。
    unawaited(
      AppLogger.instance.recordWarning(
        'Novel bookmark $action failed (${error.runtimeType})',
        stackTrace: stack,
        source: 'novel_bookmark_store',
      ),
    );
  }
}
