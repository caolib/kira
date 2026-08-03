import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/reading_stats.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 阅读统计存储的单元测试。
///
/// 覆盖：开关闸门、埋点去重/页数增量、daily 累加、聚合助手
/// （漫画数/章节数/页数/标签排序）、清除。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // 先建立 mock 后端，再清统计——clear() 内部会调用 getInstance()。
    SharedPreferences.setMockInitialValues({});
    await ReadingStats.clear();
    // 注入"已开启"桩，绝大多数测试需要统计在开启态运行。
    ReadingStats.setEnabledGate(() => true);
  });

  tearDown(() async {
    // 还原默认开关判定，避免污染其它测试套件。
    SharedPreferences.setMockInitialValues({});
    await ReadingStats.clear();
    ReadingStats.setEnabledGate(() => false);
  });

  group('开关闸门', () {
    test('未开启时 recordChapterRead 不写任何键', () async {
      ReadingStats.setEnabledGate(() => false);
      await ReadingStats.recordChapterRead(
        pathWord: 'comic-a',
        chapterUuid: 'ch-1',
        pageCount: 12,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('reading_stats_v1'), isNull);
    });
  });

  group('埋点', () {
    test('recordChapterRead 记录漫画/章节/页数', () async {
      await ReadingStats.recordChapterRead(
        pathWord: 'comic-a',
        chapterUuid: 'ch-1',
        pageCount: 12,
        comicName: '漫画A',
        tags: const ['恋爱', '校园'],
      );
      final snap = await ReadingStats.load();

      expect(comicsReadCount(snap), 1);
      expect(chaptersReadCount(snap), 1);
      expect(pagesReadCount(snap), 12);
      expect(snap.comicMeta['comic-a']!.name, '漫画A');
      expect(snap.comicMeta['comic-a']!.tags, ['恋爱', '校园']);
    });

    test('daily 按前进页数累加；同章重读不重复计入页数总和', () async {
      await ReadingStats.recordChapterRead(
        pathWord: 'comic-a',
        chapterUuid: 'ch-1',
        pageCount: 12,
        pagesToday: 12,
      );
      // 重读同一话又前进了 8 页：daily 继续 +8，但页数总和不翻倍
      await ReadingStats.recordChapterRead(
        pathWord: 'comic-a',
        chapterUuid: 'ch-1',
        pageCount: 12,
        pagesToday: 8,
      );
      final snap = await ReadingStats.load();

      expect(chaptersReadCount(snap), 1);
      expect(pagesReadCount(snap), 12); // 同 uuid 去重，不翻倍
      expect(snap.daily[_todayKey()], 20); // 12 + 8 前进页数累加
    });

    test('pagesToday 为 0 不增加当日活跃（回翻不计）', () async {
      await ReadingStats.recordChapterRead(
        pathWord: 'comic-a',
        chapterUuid: 'ch-1',
        pageCount: 12,
        pagesToday: 5,
      );
      // 回翻或无前进：delta 为 0（省略 pagesToday 即取默认 0），不应增加 daily
      await ReadingStats.recordChapterRead(
        pathWord: 'comic-a',
        chapterUuid: 'ch-1',
        pageCount: 12,
      );
      final snap = await ReadingStats.load();

      expect(snap.daily[_todayKey()], 5); // 仅首次的 5 页
    });

    test('概览页数记最远页：打开200页章节看1页只 +1 而非 +200', () async {
      // reader 传 pageCount = 当前页号（1），不是章节总页数（200）
      await ReadingStats.recordChapterRead(
        pathWord: 'comic-a',
        chapterUuid: 'ch-1',
        pageCount: 1,
        pagesToday: 1,
      );
      final snap = await ReadingStats.load();
      expect(pagesReadCount(snap), 1); // 不是 200
    });

    test('同章页数只增不减：翻到50页后回翻到10页仍记50', () async {
      await ReadingStats.recordChapterRead(
        pathWord: 'comic-a',
        chapterUuid: 'ch-1',
        pageCount: 50,
        pagesToday: 50,
      );
      // 回翻：pageCount 降到 10，但 chapterPages 只增不减，仍记 50
      await ReadingStats.recordChapterRead(
        pathWord: 'comic-a',
        chapterUuid: 'ch-1',
        pageCount: 10,
      );
      final snap = await ReadingStats.load();
      expect(pagesReadCount(snap), 50); // 不回退
    });

    test('多本漫画多章节累计漫画数/章节数/页数', () async {
      await ReadingStats.recordChapterRead(
        pathWord: 'comic-a',
        chapterUuid: 'a-1',
        pageCount: 10,
      );
      await ReadingStats.recordChapterRead(
        pathWord: 'comic-a',
        chapterUuid: 'a-2',
        pageCount: 14,
      );
      await ReadingStats.recordChapterRead(
        pathWord: 'comic-b',
        chapterUuid: 'b-1',
        pageCount: 8,
      );
      final snap = await ReadingStats.load();

      expect(comicsReadCount(snap), 2);
      expect(chaptersReadCount(snap), 3);
      expect(pagesReadCount(snap), 32);
    });

    test('comicName/tags 懒填充：已有非空时不被空值覆盖', () async {
      await ReadingStats.recordChapterRead(
        pathWord: 'comic-a',
        chapterUuid: 'ch-1',
        pageCount: 10,
        comicName: '漫画A',
        tags: const ['恋爱'],
      );
      // 第二次埋点不带 name/tags，不应清空已有数据
      await ReadingStats.recordChapterRead(
        pathWord: 'comic-a',
        chapterUuid: 'ch-2',
        pageCount: 12,
      );
      final snap = await ReadingStats.load();

      expect(snap.comicMeta['comic-a']!.name, '漫画A');
      expect(snap.comicMeta['comic-a']!.tags, ['恋爱']);
    });

    test('空 pathWord 或 chapterUuid 被忽略', () async {
      await ReadingStats.recordChapterRead(
        pathWord: '',
        chapterUuid: 'ch-1',
        pageCount: 10,
      );
      await ReadingStats.recordChapterRead(
        pathWord: 'comic-a',
        chapterUuid: '',
        pageCount: 10,
      );
      final snap = await ReadingStats.load();

      expect(snap.isEmpty, isTrue);
    });
  });

  group('聚合助手', () {
    test('topTags 按漫画数降序、同名标签在一本内只计一次', () async {
      await ReadingStats.recordChapterRead(
        pathWord: 'c1',
        chapterUuid: 'x',
        pageCount: 1,
        tags: const ['恋爱', '校园', '恋爱'], // 同名重复只计1
      );
      await ReadingStats.recordChapterRead(
        pathWord: 'c2',
        chapterUuid: 'x',
        pageCount: 1,
        tags: const ['恋爱'],
      );
      await ReadingStats.recordChapterRead(
        pathWord: 'c3',
        chapterUuid: 'x',
        pageCount: 1,
        tags: const ['校园', '日常'],
      );
      final snap = await ReadingStats.load();
      final tags = topTags(snap);

      // 恋爱: 2本, 校园: 2本, 日常: 1本
      expect(tags.length, 3);
      final byName = {for (final t in tags) t.name: t.count};
      expect(byName['恋爱'], 2);
      expect(byName['校园'], 2);
      expect(byName['日常'], 1);
      // 计数相同时按 name 字典序排：恋爱(U+604B) < 校园(U+6821)
      expect(tags.first.name, '恋爱');
    });

    test('topTags 遵守 limit', () async {
      for (var i = 0; i < 5; i++) {
        await ReadingStats.recordChapterRead(
          pathWord: 'c$i',
          chapterUuid: 'x-$i',
          pageCount: 1,
          tags: ['标签$i'],
        );
      }
      final snap = await ReadingStats.load();
      expect(topTags(snap, limit: 3).length, 3);
    });
  });

  group('清除', () {
    test('clear 删除全部统计数据', () async {
      // 预置一份已有数据
      SharedPreferences.setMockInitialValues({
        'reading_stats_v1': _encodeStats(
          comicMeta: {
            'c1': {'name': 'C1', 'tags': const <String>[], 'chapterPages': {'x': 5}},
          },
          daily: {_todayKey(): 5},
        ),
      });
      ReadingStats.resetMemoryCache();

      await ReadingStats.clear();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('reading_stats_v1'), isNull);
      expect((await ReadingStats.load()).isEmpty, isTrue);
    });
  });
}

// ── 测试辅助：构造持久化统计数据 ────────────────────────────────────

/// 编码 `_StatsData.toJson()` 的形状，用于预置持久化统计数据。
String _encodeStats({
  required Map<String, Map<String, dynamic>> comicMeta,
  required Map<String, int> daily,
  String? since,
}) {
  final result = <String, dynamic>{'comicMeta': comicMeta, 'daily': daily};
  if (since != null) result['since'] = since;
  return jsonEncode(result);
}

String _todayKey() {
  final t = DateTime.now();
  return '${t.year.toString().padLeft(4, '0')}'
      '-${t.month.toString().padLeft(2, '0')}'
      '-${t.day.toString().padLeft(2, '0')}';
}
