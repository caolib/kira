import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_logger.dart';
import 'json_helpers.dart';

/// 漫画书签：记录阅读器中用户手动标记的位置（漫画 + 章节 + 页码）。
class ComicBookmark {
  final String pathWord;
  final String comicName;

  /// 封面 URL，打书签时从漫画详情本地缓存读取（无网络请求）。
  final String cover;

  /// 打书签时所在的章节分组，旧书签为空时回退到默认分组键。
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

abstract interface class BookmarkGroupMetadata<G> {
  String get pathWord;
  bool get pinned;
  G withPinned(bool pinned);
}

/// 分组元数据独立于条目，最后一个书签删掉后仍保留组头。
@immutable
class ComicBookmarkGroup implements BookmarkGroupMetadata<ComicBookmarkGroup> {
  const ComicBookmarkGroup({
    required this.pathWord,
    required this.comicName,
    this.cover = '',
    required this.updatedAt,
    this.pinned = false,
  });

  @override
  final String pathWord;
  final String comicName;
  final String cover;
  final DateTime updatedAt;
  @override
  final bool pinned;

  factory ComicBookmarkGroup.fromJson(Map<String, dynamic> json) =>
      ComicBookmarkGroup(
        pathWord: jsonString(json, 'pathWord'),
        comicName: jsonString(json, 'comicName'),
        cover: jsonString(json, 'cover'),
        updatedAt:
            DateTime.tryParse(jsonString(json, 'updatedAt')) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        pinned: jsonBool(json, 'pinned'),
      );

  @override
  ComicBookmarkGroup withPinned(bool pinned) => ComicBookmarkGroup(
    pathWord: pathWord,
    comicName: comicName,
    cover: cover,
    updatedAt: updatedAt,
    pinned: pinned,
  );

  Map<String, dynamic> toJson() => {
    'pathWord': pathWord,
    'comicName': comicName,
    if (cover.isNotEmpty) 'cover': cover,
    'updatedAt': updatedAt.toIso8601String(),
    'pinned': pinned,
  };
}

/// 两类书签使用相同的串行写闸；写入成功才发布快照与通知。
abstract class BookmarkStoreBase<B, G extends BookmarkGroupMetadata<G>>
    extends ChangeNotifier {
  BookmarkStoreBase(
    this._itemsKey,
    this._groupsKey, {
    Future<SharedPreferences>? prefs,
  }) : _prefs = prefs;

  final String _itemsKey;
  final String _groupsKey;
  final Future<SharedPreferences>? _prefs;
  Future<SharedPreferences> get _preferences =>
      _prefs ?? SharedPreferences.getInstance();
  List<B> _bookmarks = const <Never>[];
  List<G> _groups = const <Never>[];
  Future<void>? _queue;
  bool _loaded = false;
  bool _restoring = false;
  int _restoreEpoch = 0;

  List<B> get bookmarks => _bookmarks;

  /// 保留最近一次加书签的时间顺序，置顶顺序由展示层决定。
  List<G> get groups => _groups;
  bool hasGroup(String pathWord) =>
      _groups.any((group) => group.pathWord == pathWord);

  @protected
  (List<B>, List<G>) readStored(SharedPreferences prefs);

  Future<void> _load() async {
    if (_loaded) return;
    final (items, groups) = readStored(await _preferences);
    _bookmarks = List.unmodifiable(items);
    _groups = List.unmodifiable(groups);
    _loaded = true;
  }

  Future<void> ensureLoaded() => _enqueue(_load);

  Future<void> setGroupPinned(String pathWord, bool pinned) => mutate<void>(
    blocked: () {},
    action: () async {
      final index = _groups.indexWhere((group) => group.pathWord == pathWord);
      if (index < 0 || _groups[index].pinned == pinned) return;
      final next = [..._groups]..[index] = _groups[index].withPinned(pinned);
      await commit(groups: next);
    },
  );

  @protected
  Future<T> mutate<T>({
    required T Function() blocked,
    required Future<T> Function() action,
  }) {
    final epoch = _restoreEpoch;
    final allowed = !_restoring;
    return _enqueue(() async {
      await _load();
      if (!allowed || _restoring || epoch != _restoreEpoch) return blocked();
      return action();
    });
  }

  Future<T> _enqueue<T>(Future<T> Function() action) async {
    final previous = _queue;
    final done = Completer<void>();
    _queue = done.future;
    try {
      if (previous != null) await previous;
      return await action();
    } finally {
      if (identical(_queue, done.future)) _queue = null;
      done.complete();
    }
  }

  @protected
  Future<void> commit({Iterable<B>? items, Iterable<G>? groups}) async {
    final nextItems = items == null ? _bookmarks : List<B>.unmodifiable(items);
    final nextGroups = groups == null ? _groups : List<G>.unmodifiable(groups);
    final values = {
      if (items != null) _itemsKey: jsonEncode(nextItems),
      // 更新条目时带上从旧版条目补出的组；单独置顶不重写条目。
      _groupsKey: jsonEncode(nextGroups),
    };
    final prefs = await _preferences;
    final originals = <String, Object?>{};
    try {
      for (final entry in values.entries) {
        originals[entry.key] = prefs.get(entry.key);
        if (!await prefs.setString(entry.key, entry.value)) {
          throw StateError('Bookmark persistence failed: ${entry.key}');
        }
      }
    } catch (error, stack) {
      // 平台可能先改缓存再报错。已写入和刚失败的键都要补偿，
      // 否则之后 reload 或备份仍可能读到失败操作的结果。
      for (final key in originals.keys.toList().reversed) {
        try {
          final ok = await switch (originals[key]) {
            null => prefs.remove(key),
            final String v => prefs.setString(key, v),
            final bool v => prefs.setBool(key, v),
            final int v => prefs.setInt(key, v),
            final double v => prefs.setDouble(key, v),
            final List<String> v => prefs.setStringList(key, v),
            _ => throw StateError('Invalid bookmark preference: $key'),
          };
          if (!ok) throw StateError('Bookmark rollback failed: $key');
        } catch (rollbackError, rollbackStack) {
          _logFailure(rollbackError, rollbackStack);
        }
      }
      _logFailure(error, stack);
      rethrow;
    }
    _bookmarks = nextItems;
    _groups = nextGroups;
    notifyListeners();
  }

  static void _logFailure(Object error, StackTrace stack) {
    unawaited(
      AppLogger.instance.recordWarning(
        error,
        stackTrace: stack,
        source: 'bookmark_store',
      ),
    );
  }

  /// 先关写闸再排空队列，阻止慢加载或旧撤销在恢复完成后写回旧数据。
  Future<void> pauseForRestore() {
    _restoring = true;
    _restoreEpoch++;
    return flush();
  }

  Future<void> flush() async {
    while (_queue != null) {
      await _queue;
    }
  }

  void resumeAfterRestore() => _restoring = false;

  Future<void> reload() => _enqueue(() async {
    _loaded = false;
    await _load();
    notifyListeners();
  });

  @visibleForTesting
  void debugReset() {
    assert(_queue == null, 'Flush pending bookmark operations first');
    _bookmarks = const <Never>[];
    _groups = const <Never>[];
    _loaded = false;
    _restoring = false;
    _restoreEpoch++;
  }
}

class BookmarkStore
    extends BookmarkStoreBase<ComicBookmark, ComicBookmarkGroup> {
  BookmarkStore._() : super(_key, groupsStorageKey);

  static final BookmarkStore _instance = BookmarkStore._();
  factory BookmarkStore() => _instance;

  static const _key = 'comic_bookmarks_v1';
  static const groupsStorageKey = 'comic_bookmark_groups_v1';
  @visibleForTesting
  static const maxBookmarks = 500;

  @override
  (List<ComicBookmark>, List<ComicBookmarkGroup>) readStored(
    SharedPreferences prefs,
  ) {
    List<T> readList<T>(String key, T Function(Map<String, dynamic>) parse) {
      final raw = prefs.get(key);
      if (raw is! String) return [];
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.whereType<Map<String, dynamic>>().map(parse).toList();
        }
      } on FormatException catch (error, stack) {
        // 不记录损坏 JSON 的正文。
        unawaited(
          AppLogger.instance.recordWarning(
            error.message,
            stackTrace: stack,
            source: 'bookmark_store.read',
          ),
        );
      }
      return [];
    }

    final items = readList(
      _key,
      ComicBookmark.fromJson,
    ).where((b) => b.pathWord.isNotEmpty && b.chapterUuid.isNotEmpty).toList();
    final groups = readList(
      groupsStorageKey,
      ComicBookmarkGroup.fromJson,
    ).where((g) => g.pathWord.isNotEmpty).toList();
    final known = groups.map((group) => group.pathWord).toSet();
    final previousLength = groups.length;
    // 旧版只有条目，没有组元数据；只读补齐，不回写。
    for (final bookmark in items) {
      if (!known.add(bookmark.pathWord)) continue;
      groups.add(
        ComicBookmarkGroup(
          pathWord: bookmark.pathWord,
          comicName: bookmark.comicName,
          cover: bookmark.cover,
          updatedAt:
              bookmark.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
    }
    if (groups.length != previousLength) {
      groups.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
    return (items, groups);
  }

  bool isBookmarked(String chapterUuid, int page) =>
      bookmarks.any((b) => b.chapterUuid == chapterUuid && b.page == page);

  Future<void> addGroup({
    required String pathWord,
    required String comicName,
    String cover = '',
  }) => mutate<void>(
    blocked: () {},
    action: () async {
      if (hasGroup(pathWord)) return;
      await commit(
        items: bookmarks,
        groups: _updatedGroups(pathWord, comicName, cover),
      );
    },
  );

  /// 取消收藏：分组与条目一起删除。
  Future<List<ComicBookmark>> removeGroup(String pathWord) => mutate(
    blocked: () => const <ComicBookmark>[],
    action: () async {
      final removed = bookmarks.where((b) => b.pathWord == pathWord).toList();
      if (removed.isEmpty && !hasGroup(pathWord)) {
        return const <ComicBookmark>[];
      }
      await commit(
        items: bookmarks.where((b) => b.pathWord != pathWord),
        groups: groups.where((g) => g.pathWord != pathWord),
      );
      return removed;
    },
  );

  /// 切换指定位置的书签状态，返回 true 表示新增、false 表示移除。
  Future<bool> toggle({
    required String pathWord,
    required String comicName,
    String cover = '',
    String group = '',
    required String chapterUuid,
    required String chapterName,
    required int page,
  }) => mutate(
    blocked: () => isBookmarked(chapterUuid, page),
    action: () async {
      if (isBookmarked(chapterUuid, page)) {
        await commit(
          items: bookmarks.where(
            (b) => b.chapterUuid != chapterUuid || b.page != page,
          ),
        );
        return false;
      }
      final bookmark = ComicBookmark(
        pathWord: pathWord,
        comicName: comicName,
        cover: cover,
        group: group,
        chapterUuid: chapterUuid,
        chapterName: chapterName,
        page: page,
        updatedAt: DateTime.now(),
      );
      await commit(
        items: [bookmark, ...bookmarks].take(maxBookmarks),
        groups: _updatedGroups(pathWord, comicName, cover),
      );
      return true;
    },
  );

  Iterable<ComicBookmarkGroup> _updatedGroups(
    String pathWord,
    String comicName,
    String cover,
  ) {
    final previous = groups.where((g) => g.pathWord == pathWord).firstOrNull;
    return [
      ComicBookmarkGroup(
        pathWord: pathWord,
        comicName: comicName.isEmpty ? previous?.comicName ?? '' : comicName,
        cover: cover.isEmpty ? previous?.cover ?? '' : cover,
        updatedAt: DateTime.now(),
        pinned: previous?.pinned ?? false,
      ),
      ...groups.where((g) => g.pathWord != pathWord),
    ].take(maxBookmarks);
  }

  Future<void> remove(String id) => mutate<void>(
    blocked: () {},
    action: () async {
      if (!bookmarks.any((b) => b.id == id)) return;
      await commit(items: bookmarks.where((b) => b.id != id));
    },
  );

  Future<List<ComicBookmark>> removeForComic(String pathWord) => mutate(
    blocked: () => const <ComicBookmark>[],
    action: () async {
      final removed = bookmarks.where((b) => b.pathWord == pathWord).toList();
      if (removed.isNotEmpty) {
        await commit(items: bookmarks.where((b) => b.pathWord != pathWord));
      }
      return removed;
    },
  );

  Future<List<ComicBookmark>> clear() => mutate(
    blocked: () => const <ComicBookmark>[],
    action: () async {
      final removed = bookmarks;
      if (removed.isNotEmpty) await commit(items: const []);
      return removed;
    },
  );

  /// 撤销只补回缺失的书签和分组，不覆盖同一作品后来的置顶选择。
  Future<void> restoreAll(
    List<ComicBookmark> items, {
    List<ComicBookmarkGroup> groups = const [],
  }) => mutate<void>(
    blocked: () {},
    action: () async {
      final ids = bookmarks.map((b) => b.id).toSet();
      final next = [...bookmarks, ...items.where((b) => ids.add(b.id))]
        ..sort(_byNewest);
      final known = this.groups.map((g) => g.pathWord).toSet();
      final nextGroups = [
        ...this.groups,
        ...groups.where((g) => known.add(g.pathWord)),
      ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      await commit(
        items: next.take(maxBookmarks),
        groups: nextGroups.take(maxBookmarks),
      );
    },
  );

  static int _byNewest(ComicBookmark a, ComicBookmark b) {
    final at = a.updatedAt;
    final bt = b.updatedAt;
    if (at == null && bt == null) return 0;
    if (at == null) return 1;
    if (bt == null) return -1;
    return bt.compareTo(at);
  }
}
