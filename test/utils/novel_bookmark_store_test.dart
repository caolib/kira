import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/novel_reading_progress.dart';
import 'package:kira/utils/novel_bookmark_store.dart';
import 'package:kira/utils/novel_reading_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late NovelBookmarkStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = NovelBookmarkStore.forTesting(prefs: Future.value(prefs));
  });

  tearDown(() async {
    await store.flush();
    store.dispose();
  });

  test('老数据：只有书签、没有分组元数据时仍视为已加入书签页', () async {
    // 分组元数据是后加的功能，旧版本只写了书签列表。
    final bookmark = NovelBookmark(position: _position());
    await prefs.setString(
      NovelBookmarkStore.storageKey,
      jsonEncode([bookmark.toJson()]),
    );
    await store.reload();

    expect(store.hasGroup('novel-a'), isTrue);
    expect(store.groups.single.name, '小说 A');
    expect(store.groups.single.pinned, isFalse);
  });

  test('旧分组默认未置顶；增删条目后仍可重载并取消置顶', () async {
    final oldGroup = {'pathWord': 'novel-a', 'name': '小说 A', 'cover': 'cover'};
    await prefs.setString(
      NovelBookmarkStore.groupsStorageKey,
      jsonEncode([oldGroup]),
    );
    await store.ensureLoaded();
    final original = store.groups.single;
    expect(original.pinned, isFalse);
    await store.addGroup(pathWord: 'other', name: '其他');
    var notifications = 0;
    store.addListener(() => notifications++);
    await store.setGroupPinned('novel-a', true);
    await store.setGroupPinned('novel-a', true);
    await store.setGroupPinned('missing', true);
    expect(notifications, 1);
    expect(store.groups.map((g) => g.pathWord), ['other', 'novel-a']);
    expect(store.groups.last.toJson(), {...original.toJson(), 'pinned': true});
    await store.toggle(progress: _position());
    await store.remove(store.bookmarks.single.id);
    await store.reload();
    expect(store.groups.first.pinned, isTrue);
    expect(store.groups.first.cover, 'cover');
    await store.setGroupPinned('novel-a', false);
    await store.reload();
    expect(store.groups.first.pinned, isFalse);
  });

  test('toggle persists exact anchors and excludes text URLs', () async {
    final progress = _position().copyWith(txtAddr: 'secret-signed-text-url');
    expect(await store.toggle(progress: progress), isTrue);
    expect(
      store.isBookmarked(
        pathWord: progress.pathWord,
        volumeId: progress.volumeId,
        entryIndex: 8,
        paragraphIndex: 12,
      ),
      isTrue,
    );
    final raw = prefs.getString(NovelBookmarkStore.storageKey)!;
    expect(raw, isNot(contains('txtAddr')));
    expect(raw, isNot(contains('secret-signed-text-url')));
    await store.reload();
    final bookmark = store.bookmarks.single;
    expect(bookmark.entryIndex, 8);
    expect(bookmark.paragraphIndex, 12);
    expect(bookmark.paragraphAlignment, -0.35);
    expect(bookmark.progress, 0.42);
    expect(bookmark.position.txtAddr, isEmpty);
    expect(() => store.bookmarks.clear(), throwsUnsupportedError);

    expect(
      await store.toggle(
        progress: progress.copyWith(paragraphAlignment: -0.351),
      ),
      isFalse,
    );
    expect(store.bookmarks, isEmpty);
  });

  test(
    'book, volume, original entry and paragraph all participate in identity',
    () async {
      final position = _position();
      for (final value in [
        position,
        position.copyWith(pathWord: 'other-book'),
        position.copyWith(volumeId: 'other-volume'),
        position.copyWith(entryIndex: 9),
        position.copyWith(paragraphIndex: 13),
      ]) {
        await store.toggle(progress: value);
      }
      expect(store.bookmarks, hasLength(5));
      expect(store.bookmarks.map((item) => item.id).toSet(), hasLength(5));
    },
  );

  test('concurrent initial loading does not hide existing bookmarks', () async {
    final existing = NovelBookmark(position: _position());
    await prefs.setString(
      NovelBookmarkStore.storageKey,
      jsonEncode([existing.toJson()]),
    );
    final delayed = Completer<SharedPreferences>();
    store.dispose();
    store = NovelBookmarkStore.forTesting(prefs: delayed.future);
    var loaded = false;
    final first = store.ensureLoaded();
    final second = store.ensureLoaded().then<void>((_) {
      loaded = true;
    });
    final toggle = store.toggle(
      progress: _position().copyWith(paragraphIndex: 99),
    );
    await Future<void>.delayed(Duration.zero);
    expect(loaded, isFalse);
    delayed.complete(prefs);
    await Future.wait<void>([first, second]);
    await toggle;
    expect(store.bookmarks, hasLength(2));
    expect(store.bookmarks.map((item) => item.paragraphIndex), contains(12));
  });

  test(
    'serialized writes publish only after persistence and retain call order',
    () async {
      final controlled = _ControlledPreferences(prefs);
      store.dispose();
      store = NovelBookmarkStore.forTesting(prefs: Future.value(controlled));
      final gate = Completer<void>();
      controlled.writeGate = gate;
      final first = store.toggle(progress: _position());
      await controlled.started.future;
      final second = store.toggle(
        progress: _position().copyWith(paragraphIndex: 99),
      );
      expect(store.bookmarks, isEmpty);
      expect(controlled.writes, 1);
      gate.complete();
      await Future.wait([first, second]);
      await store.reload();
      // 每次提交写两个键：书签列表 + 分组元数据（书签删光后组头仍要保留）。
      expect(controlled.writes, 4);
      expect(store.bookmarks, hasLength(2));
    },
  );

  test(
    'write failure is visible, retains memory, and does not poison queue',
    () async {
      final controlled = _ControlledPreferences(prefs)..failNextWrite = true;
      store.dispose();
      store = NovelBookmarkStore.forTesting(prefs: Future.value(controlled));
      var notifications = 0;
      store.addListener(() => notifications++);
      await expectLater(store.toggle(progress: _position()), throwsStateError);
      expect(store.bookmarks, isEmpty);
      expect(notifications, 0);
      expect(await store.toggle(progress: _position()), isTrue);
      expect(store.bookmarks, hasLength(1));
      expect(notifications, 1);
    },
  );

  test('置顶写失败不改变内存、不通知，队列可重试', () async {
    await store.addGroup(pathWord: 'novel-a', name: '小说 A');
    final controlled = _ControlledPreferences(prefs)..failNextWrite = true;
    store.dispose();
    store = NovelBookmarkStore.forTesting(prefs: Future.value(controlled));
    var notifications = 0;
    store.addListener(() => notifications++);
    await expectLater(store.setGroupPinned('novel-a', true), throwsStateError);
    final error = StateError('group write exception');
    controlled.nextError = error;
    await expectLater(
      store.setGroupPinned('novel-a', true),
      throwsA(same(error)),
    );
    expect(store.groups.single.pinned, isFalse);
    expect(notifications, 0);
    await store.reload();
    expect(store.groups.single.pinned, isFalse);
    await store.setGroupPinned('novel-a', true);
    expect(store.groups.single.pinned, isTrue);
  });

  test('空分组可删除并持久化，撤销恢复原始元数据但不覆盖新分组', () async {
    await store.addGroup(pathWord: 'novel-a', name: '小说 A');
    await store.addGroup(pathWord: 'novel-b', name: '小说 B');
    await store.setGroupPinned('novel-a', true);
    final original = store.groups.firstWhere((g) => g.pathWord == 'novel-a');
    expect(original.pinned, isTrue);
    expect(await store.removeGroup('novel-a'), isEmpty);
    await store.reload();
    expect(store.hasGroup('novel-a'), isFalse);
    expect(store.hasGroup('novel-b'), isTrue);

    await store.restoreAll(const [], groups: [original, original]);
    await store.reload();
    expect(store.groups, hasLength(2));
    expect(
      store.groups.firstWhere((g) => g.pathWord == 'novel-a').toJson(),
      original.toJson(),
    );
    expect(store.bookmarks, isEmpty);
    await store.removeGroup('novel-a');
    await store.addGroup(pathWord: 'novel-a', name: '新名称');
    await store.restoreAll(const [], groups: [original]);
    expect(store.groups.first.name, '新名称');
    expect(store.groups.first.pinned, isFalse);
  });

  test('空分组删除写入失败时保留组头，随后仍可删除', () async {
    await store.addGroup(pathWord: 'novel-a', name: '小说 A');
    final controlled = _ControlledPreferences(prefs)..failNextWrite = true;
    store.dispose();
    store = NovelBookmarkStore.forTesting(prefs: Future.value(controlled));
    await store.ensureLoaded();
    await expectLater(store.removeGroup('novel-a'), throwsStateError);
    expect(store.hasGroup('novel-a'), isTrue);
    await store.removeGroup('novel-a');
    await store.reload();
    expect(store.groups, isEmpty);
  });

  test('single/group/all deletions support deduplicating undo', () async {
    await store.toggle(progress: _position());
    await store.toggle(progress: _position().copyWith(paragraphIndex: 40));
    await store.toggle(progress: _position().copyWith(pathWord: 'other'));
    final removed = await store.remove(store.bookmarks.first.id);
    expect(removed, isNotNull);
    expect(await store.remove('missing'), isNull);
    await store.restoreAll([removed!, removed]);
    expect(store.bookmarks, hasLength(3));
    final group = await store.removeForNovel('novel-a');
    expect(group, hasLength(2));
    expect(store.bookmarks.single.pathWord, 'other');
    await store.restoreAll(group);
    final all = await store.clear();
    expect(all, hasLength(3));
    expect(store.bookmarks, isEmpty);
    await store.restoreAll(all);
    await store.reload();
    expect(store.bookmarks, hasLength(3));
    expect(store.bookmarks.map((item) => item.id).toSet(), hasLength(3));
  });

  test(
    'undo does not overwrite a newer bookmark of the same paragraph',
    () async {
      await store.toggle(progress: _position());
      final removed = await store.clear();
      await store.toggle(
        progress: _position().copyWith(paragraphAlignment: -0.7),
      );
      await store.restoreAll(removed);
      expect(store.bookmarks.single.paragraphAlignment, -0.7);
    },
  );

  test(
    'normalization deduplicates and retains newest bounded bookmarks',
    () async {
      final bookmarks = [
        for (var index = 0; index <= NovelBookmarkStore.maxBookmarks; index++)
          NovelBookmark(
            position: _position().copyWith(
              paragraphIndex: index,
              updatedAt: DateTime.utc(2026).add(Duration(seconds: index)),
            ),
          ),
      ];
      await store.restoreAll([...bookmarks, bookmarks.last]);
      expect(store.bookmarks, hasLength(NovelBookmarkStore.maxBookmarks));
      expect(
        store.bookmarks.first.paragraphIndex,
        NovelBookmarkStore.maxBookmarks,
      );
      expect(store.bookmarks.last.paragraphIndex, 1);
    },
  );

  test(
    'malformed records are skipped individually, invalid indexes rejected',
    () async {
      final valid = NovelBookmark(position: _position()).toJson();
      await prefs.setString(
        NovelBookmarkStore.storageKey,
        jsonEncode([
          {'pathWord': 'broken'},
          null,
          {...valid, 'entryIndex': '8'},
          {...valid, 'paragraphIndex': -1},
          {...valid, 'progress': 7},
          valid,
          valid,
        ]),
      );
      await store.ensureLoaded();
      expect(store.bookmarks, hasLength(1));
      for (final raw in ['not-json', '{}', 'null']) {
        await prefs.setString(NovelBookmarkStore.storageKey, raw);
        await store.reload();
        expect(store.bookmarks, isEmpty);
      }
    },
  );

  test('history deletion never reads or deletes manual bookmarks', () async {
    final history = NovelReadingStore(prefs: Future.value(prefs));
    await history.saveProgress(_position());
    await store.toggle(progress: _position());
    expect(await history.readRecent(), hasLength(1));
    await history.clear();
    await store.reload();
    expect(await history.readRecent(), isEmpty);
    expect(store.bookmarks, hasLength(1));
  });

  test(
    'restore barrier drains active writes and rejects pending mutations',
    () async {
      final controlled = _ControlledPreferences(prefs);
      store.dispose();
      store = NovelBookmarkStore.forTesting(prefs: Future.value(controlled));
      final gate = Completer<void>();
      controlled.writeGate = gate;
      final active = store.toggle(progress: _position());
      await controlled.started.future;
      final pending = store.toggle(
        progress: _position().copyWith(paragraphIndex: 50),
      );
      final queuedPin = store.setGroupPinned('novel-a', true);
      final paused = store.pauseForRestore();
      gate.complete();
      await Future.wait([active, pending]);
      await queuedPin;
      await paused;
      expect(store.bookmarks, hasLength(1));
      expect(store.groups.single.pinned, isFalse);
      final restored = NovelBookmark(
        position: _position().copyWith(volumeId: 'restored-volume'),
      );
      await prefs.setString(
        NovelBookmarkStore.storageKey,
        jsonEncode([restored.toJson()]),
      );
      await store.reload();
      await store.clear();
      await store.restoreAll([NovelBookmark(position: _position())]);
      expect(store.bookmarks.single.volumeId, 'restored-volume');
      store.resumeAfterRestore();
      await store.toggle(progress: _position());
      expect(store.bookmarks, hasLength(2));
    },
  );

  test(
    'restore barrier also blocks a toggle waiting on initial prefs',
    () async {
      final delayed = Completer<SharedPreferences>();
      store.dispose();
      store = NovelBookmarkStore.forTesting(prefs: delayed.future);
      final oldToggle = store.toggle(progress: _position());
      final paused = store.pauseForRestore();
      delayed.complete(prefs);
      await oldToggle;
      await paused;
      expect(prefs.getString(NovelBookmarkStore.storageKey), isNull);
      store.resumeAfterRestore();
    },
  );
}

NovelReadingProgress _position() => NovelReadingProgress(
  pathWord: 'novel-a',
  name: '小说 A',
  cover: '',
  volumeId: 'volume-1',
  volumeName: '第一卷',
  entryIndex: 8,
  chapterName: '第二章',
  paragraphIndex: 12,
  paragraphAlignment: -0.35,
  progress: 0.42,
  updatedAt: DateTime.utc(2026, 9, 25),
);

class _ControlledPreferences implements SharedPreferences {
  _ControlledPreferences(this.delegate);

  final SharedPreferences delegate;
  final started = Completer<void>();
  Completer<void>? writeGate;
  bool failNextWrite = false;
  Object? nextError;
  int writes = 0;

  @override
  Object? get(String key) => delegate.get(key);

  @override
  Future<bool> remove(String key) => delegate.remove(key);

  @override
  Future<bool> setString(String key, String value) async {
    writes++;
    if (!started.isCompleted) started.complete();
    final gate = writeGate;
    writeGate = null;
    if (gate != null) await gate.future;
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
    if (failNextWrite) {
      failNextWrite = false;
      return false;
    }
    return delegate.setString(key, value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
