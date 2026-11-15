import 'dart:convert';
import 'dart:io';

import 'package:kira/utils/novel_reading_ranges.dart';

/// 仓库根目录：dart run scripts/benchmark_novel_reading_stats.dart
/// 仅测字符增量去重/序列化，不代表真机滚动、磁盘或渲染性能。
void main() {
  final text = List.filled(20, '这是用于阅读统计的普通正文，包含标点与 English。 ').join();
  const paragraphs = 2000;
  // 先预热，避免把首次 JIT 编译算作单次稳态计数开销。
  for (var i = 0; i < 2000; ++i) {
    NovelReadingRanges().add(text, 0, text.length);
  }
  final ranges = List.generate(paragraphs, (_) => NovelReadingRanges());
  final countWatch = Stopwatch()..start();
  var total = 0;
  for (final range in ranges) {
    total += range.add(text, 0, text.length);
  }
  countWatch.stop();
  final duplicateWatch = Stopwatch()..start();
  var duplicates = 0;
  for (var repeat = 0; repeat < 100; ++repeat) {
    for (final range in ranges) {
      duplicates += range.add(text, 0, text.length);
    }
  }
  duplicateWatch.stop();
  final jsonWatch = Stopwatch()..start();
  final data = {
    for (var i = 0; i < ranges.length; ++i)
      '["volume",0,$i]': ranges[i].toJson(),
  };
  final encoded = jsonEncode(data);
  jsonWatch.stop();
  if (duplicates != 0) throw StateError('Duplicate ranges were counted');
  stdout.writeln(
    'New text: $total characters / $paragraphs paragraphs, '
    '${countWatch.elapsedMicroseconds} us total, '
    '${(countWatch.elapsedMicroseconds / paragraphs).toStringAsFixed(2)} us/paragraph',
  );
  stdout.writeln(
    'Duplicate ranges: ${paragraphs * 100} reports, '
    '${duplicateWatch.elapsedMicroseconds} us total, '
    '${(duplicateWatch.elapsedMicroseconds / (paragraphs * 100)).toStringAsFixed(3)} us/report',
  );
  stdout.writeln(
    'Range JSON: ${utf8.encode(encoded).length} bytes, '
    '${jsonWatch.elapsedMicroseconds} us (one serialization; no disk I/O)',
  );
}
