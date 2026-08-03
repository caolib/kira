import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/reading_stats.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 阅读统计存储的单元测试。
///
/// 覆盖：开关闸门、图片加载埋点计数（漫画/章节/图片数、daily 累加）、
/// 聚合助手（漫画数/章节数/页数/标签排序）、清除。
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
    test('未开启时 recordImageLoad 不写任何键', () async {
      ReadingStats.setEnabledGate(() => false);
      await ReadingStats.recordImageLoad(
        pathWord: 'comic-a',
        chapterUuid: 'ch-1',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('reading_stats_v1'), isNull);
    });
  });

  group('埋点', () {
    test('recordImageLoad 记录漫画/章节/图片数', () async {
      // 一次图片网络加载完成 = 漫画/章节/当日图片数各 +1
      await ReadingStats.recordImageLoad(
        pathWord: 'comic-a',
        chapterUuid: 'ch-1',
        comicName: '漫画A',
        tags: const ['恋爱', '校园'],
      );
      final snap = await ReadingStats.load();

      expect(comicsReadCount(snap), 1);
      expect(chaptersReadCount(snap), 1);
      expect(pagesReadCount(snap), 1);
      expect(snap.daily[_todayKey()], 1);
      expect(snap.comicMeta['comic-a']!.name, '漫画A');
      expect(snap.comicMeta['comic-a']!.tags, ['恋爱', '校园']);
    });

    test('同一章节多次加载累加图片数；章节数去重', () async {
      // 同一章图片重读/重试都算多少次请求，章节数只计一次
      await ReadingStats.recordImageLoad(
        pathWord: 'comic-a',
        chapterUuid: 'ch-1',
      );
      await ReadingStats.recordImageLoad(
        pathWord: 'comic-a',
        chapterUuid: 'ch-1',
      );
      final snap = await ReadingStats.load();

      expect(chaptersReadCount(snap), 1);
      expect(pagesReadCount(snap), 2);
      expect(snap.daily[_todayKey()], 2);
    });

    test('多本漫画多章节累计漫画数/章节数/图片数', () async {
      await ReadingStats.recordImageLoad(
        pathWord: 'comic-a',
        chapterUuid: 'a-1',
      );
      await ReadingStats.recordImageLoad(
        pathWord: 'comic-a',
        chapterUuid: 'a-2',
      );
      await ReadingStats.recordImageLoad(
        pathWord: 'comic-b',
        chapterUuid: 'b-1',
      );
      final snap = await ReadingStats.load();

      expect(comicsReadCount(snap), 2);
      expect(chaptersReadCount(snap), 3);
      expect(pagesReadCount(snap), 3);
      expect(snap.daily[_todayKey()], 3);
    });

    test('comicName/tags 懒填充：已有非空时不被空值覆盖', () async {
      await ReadingStats.recordImageLoad(
        pathWord: 'comic-a',
        chapterUuid: 'ch-1',
        comicName: '漫画A',
        tags: const ['恋爱'],
      );
      // 第二次埋点不带 name/tags，不应清空已有数据
      await ReadingStats.recordImageLoad(
        pathWord: 'comic-a',
        chapterUuid: 'ch-2',
      );
      final snap = await ReadingStats.load();

      expect(snap.comicMeta['comic-a']!.name, '漫画A');
      expect(snap.comicMeta['comic-a']!.tags, ['恋爱']);
    });

    test('空 pathWord 或 chapterUuid 被忽略', () async {
      await ReadingStats.recordImageLoad(pathWord: '', chapterUuid: 'ch-1');
      await ReadingStats.recordImageLoad(pathWord: 'comic-a', chapterUuid: '');
      final snap = await ReadingStats.load();

      expect(snap.isEmpty, isTrue);
    });
  });

  group('聚合助手', () {
    test('topTags 按漫画数降序、同名标签在一本内只计一次', () async {
      await ReadingStats.recordImageLoad(
        pathWord: 'c1',
        chapterUuid: 'x',
        tags: const ['恋爱', '校园', '恋爱'], // 同名重复只计1
      );
      await ReadingStats.recordImageLoad(
        pathWord: 'c2',
        chapterUuid: 'x',
        tags: const ['恋爱'],
      );
      await ReadingStats.recordImageLoad(
        pathWord: 'c3',
        chapterUuid: 'x',
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
      // 计数相同时按 name 字典序排：恋(U+604B) < 校(U+6821)
      expect(tags.first.name, '恋爱');
    });

    test('topTags 遵守 limit', () async {
      for (var i = 0; i < 5; i++) {
        await ReadingStats.recordImageLoad(
          pathWord: 'c$i',
          chapterUuid: 'x-$i',
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
            'c1': {
              'name': 'C1',
              'tags': const <String>[],
              'chapterImages': {'x': 5},
            },
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
