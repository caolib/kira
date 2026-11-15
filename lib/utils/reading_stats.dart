import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/reader_settings.dart';
import 'app_logger.dart';
import 'app_storage.dart';
import 'novel_reading_ranges.dart';
import 'novel_reading_store.dart';

/// 本地阅读统计，与保存断点的阅读历史分离。
/// 小说统计全零时可从本地历史补书/卷/当前章节，不猜算历史字数。
///
/// 漫画沿用原口径：图片真实网络加载成功 +1，缓存/下载不计入。
/// 小说按实际展示的正文记录，在线、缓存与下载共用：书/卷/章累计去重，
/// 字数与每日活跃度按当天展示的字符区间去重，隔天重读重新计数。
/// 不统计预加载、插图或空章节，也不使用随排版改变的小说页数。
///
/// 两类共用默认关闭的 [ReaderSettings.readingStatsEnabled]，但数据互相隔离。
/// 单键 `reading_stats_v1` 保留旧漫画字段，新增 novelMeta/novelDaily/novelSince，
/// 因此继续使用既有阅读统计备份分类、恢复锁与清除边界。
class ReadingStats {
  static const _dataKey = 'reading_stats_v1';
  static const _dailyRetentionDays = 730;
  static const _debounceDelay = Duration(milliseconds: 800);

  static _StatsData? _cache;
  static bool _dirty = false;
  static Timer? _debounceTimer;
  static Future<void>? _flushing;
  static bool _restoring = false;
  static Future<void>? _clearing;
  static Future<void>? _initializingNovels;

  /// 清除/恢复会作废等待加载或写盘的旧记录。
  static int _generation = 0;

  static bool Function() _enabledGate = () =>
      ReaderSettings().readingStatsEnabled;

  @visibleForTesting
  static void setEnabledGate(bool Function() gate) => _enabledGate = gate;

  static bool get isEnabled => _enabledGate();

  /// 漫画每次图片网络加载成功 +1；漫画/章节去重，页数按请求累加。
  static Future<void> recordImageLoad({
    required String pathWord,
    required String chapterUuid,
    String? comicName,
    List<String>? tags,
  }) async {
    if (_restoring || _clearing != null || !isEnabled) return;
    if (pathWord.isEmpty || chapterUuid.isEmpty) return;
    final generation = _generation;
    final data = await _loadCache();
    if (_restoring ||
        _clearing != null ||
        !isEnabled ||
        generation != _generation) {
      return;
    }
    final today = _dayKey(DateTime.now());
    final comic = data.comicMeta.putIfAbsent(
      pathWord,
      () => _ComicStatData(name: '', tags: const [], chapterImages: {}),
    );
    if (comicName != null && comicName.isNotEmpty && comic.name.isEmpty) {
      comic.name = comicName;
    }
    if (tags != null && tags.isNotEmpty && comic.tags.isEmpty) {
      comic.tags = List<String>.unmodifiable(tags);
    }
    comic.chapterImages[chapterUuid] =
        (comic.chapterImages[chapterUuid] ?? 0) + 1;
    data.daily[today] = (data.daily[today] ?? 0) + 1;
    data.since ??= today;
    _pruneDaily(data.daily);
    _scheduleFlush();
  }

  /// 记录实际展示的段落字符区间，不复制正文，不额外排版。
  /// 同日重叠区间只扫描新覆盖的字符；跨日/重启/排版变化口径一致。
  static Future<void> recordNovelReading({
    required String pathWord,
    required String volumeId,
    required int entryIndex,
    required int paragraphIndex,
    required String text,
    required int start,
    required int end,
    String? novelName,
    List<String>? tags,
    DateTime? readAt,
  }) async {
    if (_restoring || _clearing != null || !isEnabled) return;
    if (pathWord.isEmpty ||
        volumeId.isEmpty ||
        entryIndex < 0 ||
        paragraphIndex < 0 ||
        text.isEmpty ||
        end <= start) {
      return;
    }
    final generation = _generation;
    final today = _dayKey(readAt ?? DateTime.now());
    final initialization = _initializingNovels;
    if (initialization != null) await initialization;
    final data = await _loadCache();
    if (_restoring ||
        _clearing != null ||
        !isEnabled ||
        generation != _generation) {
      return;
    }
    final novel =
        data.novelMeta[pathWord] ??
        _NovelStatData(name: '', tags: const [], chapters: {});
    if (novel.rangeDay != today) {
      novel.ranges.clear();
      novel.rangeDay = today;
    }
    // JSON 元组避免卷 ID 含分隔符时与章节/段落索引发生键碰撞。
    final key = jsonEncode([volumeId, entryIndex, paragraphIndex]);
    final ranges = novel.ranges.putIfAbsent(key, NovelReadingRanges.new);
    final added = ranges.add(text, start, end);
    if (added == 0) return;
    data.novelMeta[pathWord] = novel;
    if (novelName != null && novelName.isNotEmpty && novel.name.isEmpty) {
      novel.name = novelName;
    }
    if (tags != null && tags.isNotEmpty && novel.tags.isEmpty) {
      novel.tags = List<String>.unmodifiable(tags);
    }
    final chapters = novel.chapters.putIfAbsent(volumeId, () => {});
    chapters[entryIndex.toString()] = today;
    novel.totalWords += added;
    data.novelDaily[today] = (data.novelDaily[today] ?? 0) + added;
    data.novelSince ??= today;
    _pruneDaily(data.novelDaily);
    _scheduleFlush(novel: true);
  }

  /// 开启后仅在小说统计全零时从全部本地断点初始化；清除后可再次初始化。
  /// 只补书/已知卷/当前章节，不推算历史字数、其他章节或每日活跃度。
  static Future<void> initializeNovelsFromHistory() {
    if (_restoring || _clearing != null || !isEnabled) return Future.value();
    final pending = _initializingNovels;
    if (pending != null) return pending;
    final generation = _generation;
    late final Future<void> operation;
    operation = _initializeNovelsFromHistory(generation).whenComplete(() {
      if (identical(_initializingNovels, operation)) _initializingNovels = null;
    });
    _initializingNovels = operation;
    return operation;
  }

  static Future<void> _initializeNovelsFromHistory(int generation) async {
    bool active() =>
        !_restoring &&
        _clearing == null &&
        isEnabled &&
        generation == _generation;
    final data = await _loadCache();
    if (!active()) return;
    // 初始化标记只避免重复合并非零数据，不能阻止全零统计重新初始化。
    if (data.novelHistoryInitialized && data.hasNovelStats) {
      await _flush();
      return;
    }
    var changed = !data.novelHistoryInitialized;
    if (!data.hasNovelStats) {
      final records = await NovelReadingStore(
        prefs: AppStorage.sharedPreferences(),
      ).readRecent(limit: null);
      if (!active()) return;
      // 记录调用会等待本次初始化；仍防御性检查，绝不覆盖已有小说统计。
      if (!data.hasNovelStats) {
        for (final record in records) {
          final volumes = {
            ...record.readVolumeIds.where((id) => id.trim().isNotEmpty),
            record.volumeId,
          };
          final chapters = <String, Map<String, String>>{
            for (final volume in volumes) volume: {},
          };
          // contents 的原始索引含插图，也可能跳读，不能用索引 + 1 猜章节数。
          chapters[record.volumeId]![record.entryIndex.toString()] = _dayKey(
            record.updatedAt.toLocal(),
          );
          data.novelMeta[record.pathWord] = _NovelStatData(
            name: record.name,
            tags: const [],
            chapters: chapters,
          );
          changed = true;
        }
      }
    }
    if (changed) {
      data.novelHistoryInitialized = true;
      _scheduleFlush(novel: true);
    }
    await _flush();
  }

  static void _scheduleFlush({bool novel = false}) {
    _dirty = true;
    // 小说滚动高频采样只合并写盘：最多每 5 秒一次，不因持续滚动无限推迟。
    // 返回/后台/备份仍由显式 flush 立即保存。
    if (novel && (_debounceTimer?.isActive ?? false)) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(
      novel ? const Duration(seconds: 5) : _debounceDelay,
      () {
        unawaited(
          _flush().catchError((Object error, StackTrace stack) {
            unawaited(
              AppLogger.instance.recordWarning(
                error,
                stackTrace: stack,
                source: 'reading_stats.flush',
              ),
            );
          }),
        );
      },
    );
  }

  /// 冲刷待写后返回不可变快照。
  static Future<ReadingStatsSnapshot> load() async {
    await flush();
    return (await _loadCache()).toSnapshot();
  }

  /// 导入/清除后丢弃缓存，避免旧快照覆盖刚恢复的记录。
  static void reloadFromPrefs() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _generation++;
    _cache = null;
    _dirty = false;
    _initializingNovels = null;
  }

  static Future<void> flush() async {
    final initialization = _initializingNovels;
    if (initialization != null) await initialization;
    await _flush();
  }

  static Future<void> pauseForRestore() async {
    _restoring = true;
    await flush();
    _generation++;
  }

  static void resumeAfterRestore() => _restoring = false;

  /// novel 为 true/false 时仅清除小说/漫画；省略时清全部。
  /// 不改变开关、阅读断点、另一类型统计或下载。
  static Future<void> clear({bool? novel}) async {
    while (_clearing != null) {
      await _clearing;
    }
    final operation = _clear(novel);
    _clearing = operation;
    try {
      await operation;
    } finally {
      _clearing = null;
    }
  }

  static Future<void> _clear(bool? novel) async {
    await flush();
    final data = await _loadCache();
    reloadFromPrefs();
    final prefs = await AppStorage.sharedPreferences();
    try {
      final next = _StatsData(
        comicMeta: novel == true ? data.comicMeta : {},
        daily: novel == true ? data.daily : {},
        since: novel == true ? data.since : null,
        novelMeta: novel == false ? data.novelMeta : {},
        novelDaily: novel == false ? data.novelDaily : {},
        novelSince: novel == false ? data.novelSince : null,
        // 清除小说时重置初始化标记，下一次加载统计可重新导入本地断点。
        novelHistoryInitialized: novel == false && data.novelHistoryInitialized,
      );
      if (!await prefs.setString(_dataKey, jsonEncode(next.toJson()))) {
        throw StateError('reading_stats removal failed');
      }
      _cache = next;
    } catch (error, stack) {
      // prefs 可能先改插件缓存再返回写入失败；重载后才能重试清除。
      try {
        await prefs.reload();
      } catch (reloadError, reloadStack) {
        unawaited(
          AppLogger.instance.recordWarning(
            reloadError,
            stackTrace: reloadStack,
            source: 'reading_stats.clear_reload',
          ),
        );
      }
      _cache = data;
      Error.throwWithStackTrace(error, stack);
    }
  }

  static Future<_StatsData> _loadCache() async {
    if (_cache != null) return _cache!;
    final generation = _generation;
    final prefs = await AppStorage.sharedPreferences();
    if (generation != _generation) return _StatsData.empty();
    // 同时到达的漫画/小说埋点必须共享同一对象，不能互相覆盖首次加载。
    if (_cache != null) return _cache!;
    final raw = prefs.getString(_dataKey);
    if (raw == null || raw.isEmpty) return _cache = _StatsData.empty();
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) {
        throw const FormatException('reading_stats 顶层不是 JSON 对象');
      }
      _cache = _StatsData.fromJson(json);
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'reading_stats.load_cache',
        ),
      );
      _cache = _StatsData.empty();
    }
    return _cache!;
  }

  static Future<void> _flush() async {
    while (_flushing != null) {
      await _flushing;
    }
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (!_dirty) return;
    final data = _cache;
    final gen = _generation;
    if (data == null) {
      _dirty = false;
      return;
    }
    final writing = _writeCache(data, gen);
    _flushing = writing;
    try {
      await writing;
    } finally {
      _flushing = null;
    }
  }

  static Future<void> _writeCache(_StatsData data, int gen) async {
    final prefs = await AppStorage.sharedPreferences();
    if (gen != _generation) return;
    _dirty = false;
    try {
      if (!await prefs.setString(_dataKey, jsonEncode(data.toJson()))) {
        throw StateError('reading_stats persistence failed');
      }
    } catch (_) {
      // 平台返回 false 或抛错都保留待写状态，下一次 flush 可以重试。
      // 错误原样交给调用方；防抖调用在 _scheduleFlush 中记录日志。
      if (gen == _generation) _dirty = true;
      rethrow;
    }
  }

  static void _pruneDaily(Map<String, int> daily) {
    if (daily.length < 200) return;
    final cutoff = DateTime.now().subtract(
      const Duration(days: _dailyRetentionDays),
    );
    final cutoffKey = _dayKey(cutoff);
    daily.removeWhere((k, _) => k.compareTo(cutoffKey) < 0);
  }

  static String _dayKey(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}'
      '-${t.month.toString().padLeft(2, '0')}'
      '-${t.day.toString().padLeft(2, '0')}';
}

int comicsReadCount(ReadingStatsSnapshot s) => s.comicMeta.length;

int chaptersReadCount(ReadingStatsSnapshot s) =>
    s.comicMeta.values.fold<int>(0, (sum, c) => sum + c.chapterImages.length);

int pagesReadCount(ReadingStatsSnapshot s) => s.comicMeta.values.fold<int>(
  0,
  (sum, c) => sum + c.chapterImages.values.fold<int>(0, (a, b) => a + b),
);

int novelsReadCount(ReadingStatsSnapshot s) => s.novelMeta.length;

int novelWordsReadCount(ReadingStatsSnapshot s) =>
    s.novelMeta.values.fold<int>(0, (sum, n) => sum + n.totalWords);

int novelVolumesReadCount(ReadingStatsSnapshot s) =>
    s.novelMeta.values.fold<int>(0, (sum, n) => sum + n.chapters.length);

int novelChaptersReadCount(ReadingStatsSnapshot s) =>
    s.novelMeta.values.fold<int>(
      0,
      (sum, n) => sum + n.chapters.values.fold<int>(0, (a, b) => a + b.length),
    );

/// 常看类型按累计已读章节数加权，每本书内的同名标签只计一次。
List<TagCount> topTags(ReadingStatsSnapshot s, {int limit = 10}) => _topTags(
  s.comicMeta.values.map((c) => (c.tags, c.chapterImages.length)),
  limit,
);

List<TagCount> topNovelTags(ReadingStatsSnapshot s, {int limit = 10}) =>
    _topTags(
      s.novelMeta.values.map(
        (n) => (
          n.tags,
          n.chapters.values.fold<int>(0, (sum, c) => sum + c.length),
        ),
      ),
      limit,
    );

List<TagCount> _topTags(Iterable<(List<String>, int)> books, int limit) {
  final counts = <String, int>{};
  for (final (tags, weight) in books) {
    if (weight <= 0) continue;
    for (final tag in tags.toSet()) {
      if (tag.isEmpty) continue;
      counts[tag] = (counts[tag] ?? 0) + weight;
    }
  }
  final list =
      counts.entries.map((e) => TagCount(name: e.key, count: e.value)).toList()
        ..sort((a, b) {
          final cmp = b.count.compareTo(a.count);
          return cmp != 0 ? cmp : a.name.compareTo(b.name);
        });
  return list.take(limit).toList();
}

class ReadingStatsSnapshot {
  final Map<String, ComicStat> comicMeta;
  final Map<String, int> daily;
  final DateTime? since;
  final Map<String, NovelStat> novelMeta;
  final Map<String, int> novelDaily;
  final DateTime? novelSince;
  final bool novelHistoryInitialized;

  const ReadingStatsSnapshot({
    required this.comicMeta,
    required this.daily,
    this.since,
    this.novelMeta = const {},
    this.novelDaily = const {},
    this.novelSince,
    this.novelHistoryInitialized = false,
  });

  bool get isEmpty =>
      comicMeta.isEmpty &&
      daily.isEmpty &&
      novelMeta.isEmpty &&
      novelDaily.isEmpty;
}

class ComicStat {
  final String name;
  final List<String> tags;
  final Map<String, int> chapterImages;

  const ComicStat({
    required this.name,
    required this.tags,
    required this.chapterImages,
  });
}

class NovelStat {
  final String name;
  final List<String> tags;
  final int totalWords;

  /// 卷 ID → 原始章节索引 → 最后阅读日期。
  /// 历史初始化只能确认已读卷而不知章节时，对应卷保留空 Map。
  final Map<String, Map<String, String>> chapters;

  const NovelStat({
    required this.name,
    required this.tags,
    required this.chapters,
    this.totalWords = 0,
  });
}

class TagCount {
  final String name;
  final int count;

  const TagCount({required this.name, required this.count});
}

class _StatsData {
  final Map<String, _ComicStatData> comicMeta;
  final Map<String, int> daily;
  String? since;
  final Map<String, _NovelStatData> novelMeta;
  final Map<String, int> novelDaily;
  String? novelSince;
  bool novelHistoryInitialized;

  /// 小说、卷、章节或字数非零时不合并历史；仅有零值日期不算阅读量。
  bool get hasNovelStats =>
      novelMeta.isNotEmpty || novelDaily.values.any((count) => count != 0);

  _StatsData({
    required this.comicMeta,
    required this.daily,
    this.since,
    required this.novelMeta,
    required this.novelDaily,
    this.novelSince,
    this.novelHistoryInitialized = false,
  });

  factory _StatsData.empty() =>
      _StatsData(comicMeta: {}, daily: {}, novelMeta: {}, novelDaily: {});

  factory _StatsData.fromJson(Map<String, dynamic> json) {
    final comicMeta = <String, _ComicStatData>{};
    final metaRaw = json['comicMeta'];
    if (metaRaw is Map) {
      for (final entry in metaRaw.entries) {
        final m = entry.value;
        if (m is! Map) continue;
        comicMeta[entry.key.toString()] = _ComicStatData(
          name: m['name']?.toString() ?? '',
          tags: _readTags(m['tags']),
          chapterImages: _readIntMap(m['chapterImages']),
        );
      }
    }
    final novelMeta = <String, _NovelStatData>{};
    final novelRaw = json['novelMeta'];
    if (novelRaw is Map) {
      for (final entry in novelRaw.entries) {
        final m = entry.value;
        if (entry.key is! String || entry.key.toString().isEmpty || m is! Map) {
          continue;
        }
        final chapters = _readNovelChapters(m['chapters']);
        if (chapters.isEmpty) continue;
        novelMeta[entry.key.toString()] = _NovelStatData(
          name: m['name']?.toString() ?? '',
          tags: _readTags(m['tags']),
          chapters: chapters,
          totalWords: switch (m['totalWords']) {
            final int count when count > 0 => count,
            _ => 0,
          },
          rangeDay: m['rangeDay'] is String ? m['rangeDay'].toString() : null,
          ranges: _readRanges(m['ranges']),
        );
      }
    }
    return _StatsData(
      comicMeta: comicMeta,
      daily: _readIntMap(json['daily']),
      since: json['since']?.toString(),
      novelMeta: novelMeta,
      novelDaily: _readIntMap(json['novelDaily']),
      novelSince: json['novelSince']?.toString(),
      novelHistoryInitialized: json['novelHistoryInitialized'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'comicMeta': {
      for (final e in comicMeta.entries)
        e.key: {
          'name': e.value.name,
          'tags': e.value.tags,
          'chapterImages': e.value.chapterImages,
        },
    },
    'daily': daily,
    if (since != null) 'since': since,
    'novelMeta': {
      for (final e in novelMeta.entries)
        e.key: {
          'name': e.value.name,
          'tags': e.value.tags,
          'chapters': e.value.chapters,
          'totalWords': e.value.totalWords,
          if (e.value.rangeDay != null) 'rangeDay': e.value.rangeDay,
          'ranges': {
            for (final r in e.value.ranges.entries) r.key: r.value.toJson(),
          },
        },
    },
    'novelDaily': novelDaily,
    if (novelSince != null) 'novelSince': novelSince,
    if (novelHistoryInitialized) 'novelHistoryInitialized': true,
  };

  ReadingStatsSnapshot toSnapshot() => ReadingStatsSnapshot(
    comicMeta: Map.unmodifiable(
      comicMeta.map(
        (k, v) => MapEntry(
          k,
          ComicStat(
            name: v.name,
            tags: List.unmodifiable(v.tags),
            chapterImages: Map.unmodifiable(v.chapterImages),
          ),
        ),
      ),
    ),
    daily: Map.unmodifiable(daily),
    since: since == null ? null : DateTime.tryParse(since!),
    novelMeta: Map.unmodifiable(
      novelMeta.map(
        (k, v) => MapEntry(
          k,
          NovelStat(
            name: v.name,
            tags: List.unmodifiable(v.tags),
            totalWords: v.totalWords,
            chapters: Map.unmodifiable(
              v.chapters.map(
                (volume, chapters) => MapEntry(
                  volume,
                  Map<String, String>.unmodifiable(chapters),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    novelDaily: Map.unmodifiable(novelDaily),
    novelSince: novelSince == null ? null : DateTime.tryParse(novelSince!),
    novelHistoryInitialized: novelHistoryInitialized,
  );
}

class _ComicStatData {
  String name;
  List<String> tags;
  final Map<String, int> chapterImages;

  _ComicStatData({
    required this.name,
    required this.tags,
    required this.chapterImages,
  });
}

class _NovelStatData {
  String name;
  List<String> tags;
  final Map<String, Map<String, String>> chapters;
  int totalWords;
  String? rangeDay;
  final Map<String, NovelReadingRanges> ranges;

  _NovelStatData({
    required this.name,
    required this.tags,
    required this.chapters,
    this.totalWords = 0,
    this.rangeDay,
    Map<String, NovelReadingRanges>? ranges,
  }) : ranges = ranges ?? {};
}

Map<String, NovelReadingRanges> _readRanges(Object? value) {
  if (value is! Map) return {};
  return {
    for (final entry in value.entries)
      if (entry.key is String)
        entry.key.toString(): NovelReadingRanges.fromJson(entry.value),
  };
}

Map<String, Map<String, String>> _readNovelChapters(Object? value) {
  final result = <String, Map<String, String>>{};
  if (value is! Map) return result;
  for (final volume in value.entries) {
    final raw = volume.value;
    if (volume.key is! String || volume.key.toString().isEmpty || raw is! Map) {
      continue;
    }
    final chapters = <String, String>{};
    for (final chapter in raw.entries) {
      final index = int.tryParse(chapter.key.toString());
      final date = chapter.value;
      if (index == null || index < 0 || date is! String) continue;
      if (DateTime.tryParse(date) == null) continue;
      chapters[index.toString()] = date;
    }
    if (chapters.isNotEmpty || raw.isEmpty) {
      result[volume.key.toString()] = chapters;
    }
  }
  return result;
}

Map<String, int> _readIntMap(Object? value) {
  if (value is Map) {
    final result = <String, int>{};
    for (final entry in value.entries) {
      final v = entry.value;
      if (v is int) {
        result[entry.key.toString()] = v;
      } else if (v is num && v.isFinite) {
        result[entry.key.toString()] = v.toInt();
      }
    }
    return result;
  }
  return {};
}

List<String> _readTags(Object? value) {
  if (value is List) {
    return value.whereType<String>().where((t) => t.isNotEmpty).toList();
  }
  return const [];
}
