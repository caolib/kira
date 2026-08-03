import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/reader_settings.dart';

/// 阅读统计的本地存储与聚合。
///
/// 与阅读历史（ReadingHistory）不同：这里不存"读到哪一页"，而是聚合计数——读过
/// 多少本漫画、多少话、多少页、常看类型、每日阅读活跃度（热力图）。
///
/// ## 开关
/// 默认关闭。开关位 [ReaderSettings.readingStatsEnabled]（bool，prefs 键
/// `reader_reading_stats_enabled`）。关闭时 [recordChapterRead] 立即返回，
/// 不写任何统计键——未开启的用户零成本。
///
/// ## 数据来源
/// 首次开启后数据为空，之后纯靠 [recordChapterRead] 增量累积（阅读章节时
/// 由 reader 埋点）。不从本地缓存导入历史数据。
///
/// ## 存储
/// 单键 `reading_stats_v1`（JSON），结构见 [_StatsData]。约 120KB/100 部，
/// 配合 daily 730 天裁剪 + chapterPages 按 uuid 去重，增长可控。
class ReadingStats {
  static const _dataKey = 'reading_stats_v1';

  /// daily 计数保留天数。超过的旧条目在每次写入时裁剪。
  static const _dailyRetentionDays = 730;

  /// 埋点写入防抖窗口。连续翻章时合并多次计数为一次落盘。
  static const _debounceDelay = Duration(milliseconds: 800);

  /// 内存缓存，避免每次埋点都解码整条 JSON。lazily 加载。
  static _StatsData? _cache;

  static bool _dirty = false;
  static Timer? _debounceTimer;

  // ── 开关 ──────────────────────────────────────────────────────────

  /// 统计是否已开启的判定函数。默认读取 [ReaderSettings] 的同步内存值；
  /// 测试可经 [setEnabledGate] 注入桩。
  static bool Function() _enabledGate = () =>
      ReaderSettings().readingStatsEnabled;

  /// 仅供测试覆写开关判定。
  @visibleForTesting
  static void setEnabledGate(bool Function() gate) => _enabledGate = gate;

  /// 统计是否已开启。reader 埋点前快速判断；统计页也用它决定显示哪个态。
  static bool get isEnabled => _enabledGate();

  // ── 埋点 ──────────────────────────────────────────────────────────

  /// 记一次章节阅读（翻页/换章时由 reader 调用）。
  ///
  /// - 未开启时立即返回，零写入。
  /// - [pageCount] 是该章**当前翻到的页号**（1-based），存储端按
  ///   `max(已存, pageCount)` 合并——只增不减，反映"翻到过的最远页"。
  ///   这样概览页数 = 各章最远页之和，反映实际阅读量，而非章节总页数
  ///   （打开200页章节只看1页不会 +200）。
  /// - [pagesToday] 是本次埋点新前进的页数（翻页前进 N → +N，回翻不计），
  ///   累加进 [daily] 当日条目。热力图按"当天页数"分级，不受章节页数
  ///   差异影响，用户间可比。
  /// - [comicName] / [tags] 懒填充：传入非空且当前为空时才写入，避免覆盖
  ///   已有更完整的数据。
  /// - 防抖落盘：连续翻页合并为一次写。
  static Future<void> recordChapterRead({
    required String pathWord,
    required String chapterUuid,
    int pageCount = 0,
    int pagesToday = 0,
    String? comicName,
    List<String>? tags,
  }) async {
    if (!isEnabled) return;
    if (pathWord.isEmpty || chapterUuid.isEmpty) return;

    final data = await _loadCache();
    final today = _todayKey();

    // comicMeta 增量更新
    final comic = data.comicMeta.putIfAbsent(
      pathWord,
      () => _ComicStatData(name: '', tags: const [], chapterPages: {}),
    );
    if (comicName != null && comicName.isNotEmpty && comic.name.isEmpty) {
      comic.name = comicName;
    }
    if (tags != null && tags.isNotEmpty && comic.tags.isEmpty) {
      comic.tags = List<String>.unmodifiable(tags);
    }
    // 按 uuid 去重且只增不减：记录该章翻到的最远页号（回翻不降）
    final prev = comic.chapterPages[chapterUuid] ?? 0;
    if (pageCount > prev) comic.chapterPages[chapterUuid] = pageCount;

    // daily 当日阅读页数（前进页数累加；回翻不计）
    if (pagesToday > 0) {
      data.daily[today] = (data.daily[today] ?? 0) + pagesToday;
    }

    // since 首次记录日
    data.since ??= today;

    // 裁剪过旧的 daily 条目
    _pruneDaily(data);

    _dirty = true;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDelay, () => unawaited(_flush()));
  }

  // ── 加载 / 清除 ───────────────────────────────────────────────────

  /// 读取当前统计快照（冲刷待写后返回）。
  static Future<ReadingStatsSnapshot> load() async {
    await _flush();
    final data = await _loadCache();
    return data.toSnapshot();
  }

  /// 仅复位内存缓存，不读写 prefs。供测试在 `setMockInitialValues` 之后
  /// 强制下次 `load()` 从新的 prefs 重新读取。
  @visibleForTesting
  static void resetMemoryCache() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _cache = null;
    _dirty = false;
  }

  /// 清除全部统计数据（不改变开关状态）。
  static Future<void> clear() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _cache = null;
    _dirty = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dataKey);
  }

  // ── 内部：缓存读写 ────────────────────────────────────────────────

  static Future<_StatsData> _loadCache() async {
    if (_cache != null) return _cache!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_dataKey);
    if (raw == null || raw.isEmpty) {
      return _cache = _StatsData.empty();
    }
    try {
      final json = jsonDecode(raw);
      _cache = _StatsData.fromJson(json as Map<String, dynamic>);
    } catch (_) {
      _cache = _StatsData.empty();
    }
    return _cache!;
  }

  static Future<void> _flush() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (!_dirty) return;
    final data = _cache;
    if (data == null) {
      _dirty = false;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dataKey, jsonEncode(data.toJson()));
    _dirty = false;
  }

  static void _pruneDaily(_StatsData data) {
    if (data.daily.length < 200) return; // 量小不裁剪，省一次日期解析
    final cutoff = DateTime.now().subtract(
      const Duration(days: _dailyRetentionDays),
    );
    final cutoffKey = _dayKey(cutoff);
    data.daily.removeWhere((k, _) => k.compareTo(cutoffKey) < 0);
  }

  // ── 日期键 ────────────────────────────────────────────────────────

  static String _todayKey() => _dayKey(DateTime.now());

  static String _dayKey(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}'
      '-${t.month.toString().padLeft(2, '0')}'
      '-${t.day.toString().padLeft(2, '0')}';
}

// ── 聚合助手（纯函数，可单测） ──────────────────────────────────────

/// 读过的漫画数 = comicMeta 键数。
int comicsReadCount(ReadingStatsSnapshot s) => s.comicMeta.length;

/// 读过的章节数 = 各漫画 chapterPages 键数之和。
int chaptersReadCount(ReadingStatsSnapshot s) =>
    s.comicMeta.values.fold<int>(0, (sum, c) => sum + c.chapterPages.length);

/// 阅读页数 = 各漫画 chapterPages 值之和（按章节 uuid 去重后）。
int pagesReadCount(ReadingStatsSnapshot s) =>
    s.comicMeta.values.fold<int>(0, (sum, c) {
      var sub = 0;
      for (final pages in c.chapterPages.values) {
        sub += pages;
      }
      return sum + sub;
    });

/// 最爱标签：聚合各漫画 tags，按"出现过的漫画数"降序取前 [limit] 条。
List<TagCount> topTags(ReadingStatsSnapshot s, {int limit = 10}) {
  final counts = <String, int>{};
  for (final comic in s.comicMeta.values) {
    // 同一漫画内同名的标签只计一次
    final seen = <String>{};
    for (final tag in comic.tags) {
      if (tag.isEmpty || !seen.add(tag)) continue;
      counts[tag] = (counts[tag] ?? 0) + 1;
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

// ── 模型 ──────────────────────────────────────────────────────────

/// 统计页展示用的不可变快照。
class ReadingStatsSnapshot {
  final Map<String, ComicStat> comicMeta;
  final Map<String, int> daily;
  final DateTime? since;

  const ReadingStatsSnapshot({
    required this.comicMeta,
    required this.daily,
    this.since,
  });

  /// 是否完全没有任何统计数据（既无漫画也无活动）。
  bool get isEmpty => comicMeta.isEmpty && daily.isEmpty;
}

/// 单本漫画的统计条目。
class ComicStat {
  final String name;
  final List<String> tags;
  final Map<String, int> chapterPages;

  const ComicStat({
    required this.name,
    required this.tags,
    required this.chapterPages,
  });
}

/// 标签计数（用于最爱标签排序展示）。
class TagCount {
  final String name;
  final int count;

  const TagCount({required this.name, required this.count});
}

// ── 内部可变数据（存储/序列化用） ──────────────────────────────────

class _StatsData {
  final Map<String, _ComicStatData> comicMeta;
  final Map<String, int> daily;
  String? since;

  _StatsData({required this.comicMeta, required this.daily, this.since});

  factory _StatsData.empty() => _StatsData(comicMeta: {}, daily: {});

  factory _StatsData.fromJson(Map<String, dynamic> json) {
    final metaRaw = json['comicMeta'];
    final comicMeta = <String, _ComicStatData>{};
    if (metaRaw is Map) {
      for (final entry in metaRaw.entries) {
        final pw = entry.key.toString();
        final m = entry.value;
        if (m is Map) {
          comicMeta[pw] = _ComicStatData(
            name: m['name']?.toString() ?? '',
            tags:
                (m['tags'] as List?)
                    ?.map((t) => t.toString())
                    .where((t) => t.isNotEmpty)
                    .toList() ??
                const [],
            chapterPages: _readIntMap(m['chapterPages']),
          );
        }
      }
    }
    final daily = <String, int>{};
    final dailyRaw = json['daily'];
    if (dailyRaw is Map) {
      for (final entry in dailyRaw.entries) {
        final v = entry.value;
        if (v is int) {
          daily[entry.key.toString()] = v;
        } else if (v is num) {
          daily[entry.key.toString()] = v.toInt();
        }
      }
    }
    return _StatsData(
      comicMeta: comicMeta,
      daily: daily,
      since: json['since']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'comicMeta': {
      for (final e in comicMeta.entries)
        e.key: {
          'name': e.value.name,
          'tags': e.value.tags,
          'chapterPages': e.value.chapterPages,
        },
    },
    'daily': daily,
    if (since != null) 'since': since,
  };

  ReadingStatsSnapshot toSnapshot() {
    final meta = comicMeta.map(
      (k, v) => MapEntry(
        k,
        ComicStat(
          name: v.name,
          tags: List<String>.unmodifiable(v.tags),
          chapterPages: Map<String, int>.unmodifiable(v.chapterPages),
        ),
      ),
    );
    final d = Map<String, int>.unmodifiable(daily);
    final s = since == null ? null : DateTime.tryParse(since!);
    return ReadingStatsSnapshot(
      comicMeta: Map<String, ComicStat>.unmodifiable(meta),
      daily: d,
      since: s,
    );
  }
}

class _ComicStatData {
  String name;
  List<String> tags;
  final Map<String, int> chapterPages;

  _ComicStatData({
    required this.name,
    required this.tags,
    required this.chapterPages,
  });
}

Map<String, int> _readIntMap(Object? value) {
  if (value is Map) {
    final result = <String, int>{};
    for (final entry in value.entries) {
      final v = entry.value;
      if (v is int) {
        result[entry.key.toString()] = v;
      } else if (v is num) {
        result[entry.key.toString()] = v.toInt();
      }
    }
    return result;
  }
  return {};
}
