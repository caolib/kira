import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kira/backup/backup_category.dart';
import 'package:kira/utils/app_storage.dart';
import 'package:kira/utils/search_history.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('persists a StringList under the local-only versioned key', () async {
    final history = SearchHistory();
    await history.clear();
    await history.add('  海贼王  ');
    await history.add('火影忍者');
    await history.add('海贼王');

    final prefs = await AppStorage.sharedPreferences();
    expect(prefs.get(SearchHistory.storageKey), ['海贼王', '火影忍者']);
    expect(await SearchHistory().load(), ['海贼王', '火影忍者']);
    expect(BackupSchema.categoryOf(SearchHistory.storageKey), isNull);
    expect(BackupSchema.typeOf(SearchHistory.storageKey), isNull);

    await history.clear();
    expect(prefs.containsKey(SearchHistory.storageKey), isFalse);
  });

  test('normalizes restored entries and exposes immutable snapshots', () async {
    final preferences = _MemoryPreferences([
      ' 海贼王 ',
      '',
      '海贼王',
      '  ',
      '火影忍者',
      ...List.generate(25, (index) => '漫画$index'),
    ]);
    final history = SearchHistory(preferences: preferences);
    final entries = await history.load();

    expect(entries, hasLength(SearchHistory.maxEntries));
    expect(entries.take(3), ['海贼王', '火影忍者', '漫画0']);
    expect(entries.last, '漫画17');
    expect(() => entries.add('修改快照'), throwsUnsupportedError);
  });

  test(
    'trims, deduplicates and promotes recent searches with a 20-item cap',
    () async {
      final preferences = _MemoryPreferences();
      final history = SearchHistory(preferences: preferences);
      for (var index = 0; index < 25; index++) {
        await history.add('漫画$index');
      }
      expect(await history.add('  漫画10  '), [
        '漫画10',
        for (var index = 24; index >= 5; index--)
          if (index != 10) '漫画$index',
      ]);
      expect(preferences.stored, hasLength(20));
      expect(preferences.stored?.last, '漫画5');
    },
  );

  test('blank searches do not create or rewrite history', () async {
    final preferences = _MemoryPreferences();
    final history = SearchHistory(preferences: preferences);
    expect(await history.add(' \n '), isEmpty);
    expect(preferences.writes, isEmpty);
    expect(preferences.stored, isNull);
  });

  test('single deletion preserves order and clear removes the key', () async {
    final preferences = _MemoryPreferences(['A', 'B', 'C']);
    final history = SearchHistory(preferences: preferences);
    expect(await history.remove(' B '), ['A', 'C']);
    expect(preferences.stored, ['A', 'C']);
    expect(await history.remove('missing'), ['A', 'C']);
    expect(await history.clear(), isEmpty);
    expect(preferences.stored, isNull);
  });

  test('startup restore cannot overwrite queued searches and clear', () async {
    final gate = Completer<void>();
    final preferences = _MemoryPreferences(['旧历史'])..readGate = gate;
    final history = SearchHistory(preferences: preferences);
    final restoring = history.load();
    final first = history.add('A');
    final second = history.add('B');
    final clearing = history.clear();
    final last = history.add('C');

    await Future<void>.delayed(Duration.zero);
    expect(preferences.reads, 1);
    expect(preferences.writes, isEmpty);
    gate.complete();

    expect(await restoring, ['旧历史']);
    expect(await first, ['A', '旧历史']);
    expect(await second, ['B', 'A', '旧历史']);
    expect(await clearing, isEmpty);
    expect(await last, ['C']);
    expect(preferences.stored, ['C']);
  });

  test('slow writes finish before later deletion and new searches', () async {
    final gate = Completer<void>();
    final preferences = _MemoryPreferences(['旧历史'])..writeGate = gate;
    final history = SearchHistory(preferences: preferences);
    final first = history.add('A');
    await Future<void>.delayed(Duration.zero);
    expect(preferences.writes, [
      ['A', '旧历史'],
    ]);

    final removing = history.remove('旧历史');
    final clearing = history.clear();
    final last = history.add('B');
    await Future<void>.delayed(Duration.zero);
    expect(preferences.writes, hasLength(1));
    expect(preferences.removals, 0);
    gate.complete();
    await Future.wait([first, removing, clearing, last]);

    expect(preferences.stored, ['B']);
    expect(await history.load(), ['B']);
  });

  test(
    'external clearing waits for queued writes from a kept-alive page',
    () async {
      final gate = Completer<void>();
      final preferences = _MemoryPreferences(['旧历史'])..writeGate = gate;
      final history = SearchHistory(preferences: preferences);
      final first = history.add('A');
      final second = history.add('B');
      await Future<void>.delayed(Duration.zero);

      final clearing = () async {
        await SearchHistory.flush();
        await preferences.remove(SearchHistory.storageKey);
      }();
      await Future<void>.delayed(Duration.zero);
      expect(preferences.removals, 0);
      gate.complete();
      await Future.wait([first, second, clearing]);

      expect(preferences.stored, isNull);
      expect(await history.load(), isEmpty);
      expect(await history.add('清理后的新搜索'), ['清理后的新搜索']);
    },
  );

  test(
    'cache deletion does not resurrect a page-local history snapshot',
    () async {
      final preferences = _MemoryPreferences(['旧历史']);
      final history = SearchHistory(preferences: preferences);
      expect(await history.load(), ['旧历史']);
      preferences.stored = null;

      expect(await history.add('新搜索'), ['新搜索']);
      preferences.stored = null;
      expect(await history.load(), isEmpty);
    },
  );

  test(
    'false persistence result is contained and does not poison the queue',
    () async {
      final preferences = _MemoryPreferences(['旧历史'])..failNextWrite = true;
      final history = SearchHistory(preferences: preferences);
      expect(await history.add('A'), ['A', '旧历史']);
      expect(preferences.stored, ['旧历史']);
      expect(await history.add('B'), ['B', '旧历史']);
      expect(preferences.stored, ['B', '旧历史']);
    },
  );

  test(
    'read and write exceptions do not escape search history operations',
    () async {
      final preferences = _MemoryPreferences(['旧历史']);
      final history = SearchHistory(preferences: preferences);
      await history.load();
      preferences.throwNextRead = true;
      expect(await history.add('A'), ['A', '旧历史']);
      preferences.throwNextWrite = true;
      expect(await history.add('B'), ['B', 'A', '旧历史']);
      expect(await history.clear(), isEmpty);
      expect(preferences.stored, isNull);
    },
  );
}

class _MemoryPreferences extends AppPreferences {
  _MemoryPreferences([this.stored]);

  List<String>? stored;
  Completer<void>? readGate;
  Completer<void>? writeGate;
  bool failNextWrite = false;
  bool throwNextRead = false;
  bool throwNextWrite = false;
  int reads = 0;
  int removals = 0;
  final List<List<String>> writes = [];

  @override
  Future<List<String>?> getStringList(String key) async {
    expect(key, SearchHistory.storageKey);
    reads++;
    final gate = readGate;
    readGate = null;
    if (gate != null) await gate.future;
    if (throwNextRead) {
      throwNextRead = false;
      throw StateError('Test read failure');
    }
    return stored?.toList();
  }

  @override
  Future<bool> setStringList(String key, List<String> value) async {
    expect(key, SearchHistory.storageKey);
    writes.add(value.toList());
    final gate = writeGate;
    writeGate = null;
    if (gate != null) await gate.future;
    if (throwNextWrite) {
      throwNextWrite = false;
      throw StateError('Test write failure');
    }
    if (failNextWrite) {
      failNextWrite = false;
      return false;
    }
    stored = value.toList();
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    expect(key, SearchHistory.storageKey);
    removals++;
    stored = null;
    return true;
  }
}
