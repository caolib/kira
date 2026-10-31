import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/api/novel/novel_api.dart';
import 'package:kira/models/novel.dart';
import 'package:kira/models/novel_reader_settings.dart';
import 'package:kira/models/novel_reader_status_settings.dart';
import 'package:kira/models/novel_reading_progress.dart';
import 'package:kira/pages/novel_reader/novel_reader_document.dart';
import 'package:kira/pages/novel_reader/novel_reader_page_view.dart';
import 'package:kira/pages/novel_reader/novel_reader_viewport.dart';
import 'package:kira/pages/novel_reader_page.dart';
import 'package:kira/providers/novel_providers.dart';
import 'package:kira/repositories/novel_repository.dart';
import 'package:kira/utils/novel_bookmark_store.dart';
import 'package:kira/utils/novel_reading_store.dart';
import 'package:kira/widgets/novel_page_curl.dart';
import 'package:kira/widgets/reader_status_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

/// 翻页模式集成测试：点击分区、模式切换的位置交接、音量键拦截、
/// 卷末自动跳卷与进度落盘。
const _volumeChannel = MethodChannel('io.github.caolib.kira/volume');

class _Api implements NovelApi {
  @override
  bool get hasCopyToken => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected API access: ${invocation.memberName}');
}

class _Repository implements NovelRepository {
  _Repository(this.content);

  final Map<String, NovelVolumeContent> content;
  final calls = <String>[];

  @override
  Future<NovelVolumeContent> loadVolumeContent(
    String pathWord,
    String volumeId, {
    bool refresh = false,
  }) async {
    calls.add('$pathWord/$volumeId/$refresh');
    return content[volumeId]!;
  }

  @override
  Future<List<NovelVolume>> loadVolumes(
    String pathWord, {
    bool refresh = false,
  }) async => content.values
      .where((item) => item.detail.book.pathWord == pathWord)
      .map((item) => item.detail.volume)
      .toList();

  @override
  Future<NovelVolumeDetail> loadVolumeDetail(
    String pathWord,
    String volumeId, {
    bool refresh = false,
  }) async => content[volumeId]!.detail;

  @override
  Future<NovelVolumeContent?> getCachedVolumeContent(
    String pathWord,
    String volumeId,
  ) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected repository access: ${invocation.memberName}',
  );
}

class _Store implements NovelReadingStore {
  _Store(this.preferences);

  final SharedPreferences preferences;
  final writes = <NovelReadingProgress>[];

  @override
  Future<NovelReadingProgress?> readProgress(String pathWord) async {
    final raw = preferences.getString('test_novel_progress_$pathWord');
    if (raw == null) return null;
    final json = jsonDecode(raw);
    return json is Map<String, dynamic>
        ? NovelReadingProgress.fromJson(json)
        : null;
  }

  @override
  Future<void> saveProgress(NovelReadingProgress progress) async {
    writes.add(progress);
    await preferences.setString(
      'test_novel_progress_${progress.pathWord}',
      jsonEncode(progress.toJson()),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected reading store access: ${invocation.memberName}',
  );
}

NovelVolumeContent _volume({
  String book = 'book',
  String id = 'v1',
  int entries = 3,
  int paragraphs = 100,
  List<List<String>>? entryTexts,
  String? previous,
  String? next,
}) {
  final texts = entryTexts ?? _texts(id, List.filled(entries, paragraphs));
  final parsed = <NovelReaderEntry>[
    for (var entry = 0; entry < texts.length; entry++)
      NovelReaderEntry(
        entryIndex: entry,
        entry: NovelContentEntry(name: '$id chapter $entry', contentType: 1),
        paragraphs: texts[entry],
      ),
  ];
  return NovelVolumeContent(
    detail: NovelVolumeDetail(
      book: NovelBook(pathWord: book, name: '$book title'),
      volume: NovelVolume(
        id: id,
        name: '$id volume',
        bookPathWord: book,
        prev: previous,
        next: next,
        contents: parsed.map((item) => item.entry).toList(),
      ),
    ),
    entries: parsed,
  );
}

late NovelBookmarkStore _bookmarks;

/// 生成 [counts] 指定的各章节段落文本（内容仅用于区分段落）。
List<List<String>> _texts(String id, List<int> counts) => [
  for (var entry = 0; entry < counts.length; entry++)
    [
      for (var paragraph = 0; paragraph < counts[entry]; paragraph++)
        '$id entry $entry paragraph $paragraph',
    ],
];

Future<void> _seedSettings(
  WidgetTester tester,
  NovelReaderSettings settings,
) async {
  await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues({
      NovelReaderSettings.storageKey: jsonEncode(settings.toJson()),
    });
    await SharedPreferences.getInstance();
  });
}

Future<void> _mount(
  WidgetTester tester, {
  required _Repository repository,
  required _Store store,
  bool paged = true,
  NovelReaderSettings? settings,
  String book = 'book',
  String volume = 'v1',
  bool settle = true,
}) async {
  await _seedSettings(
    tester,
    settings ??
        NovelReaderSettings(
          mode: paged ? NovelReaderMode.paged : NovelReaderMode.scroll,
        ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        novelRepositoryProvider.overrideWithValue(repository),
        novelReadingStoreProvider.overrideWithValue(store),
        novelBookmarkStoreProvider.overrideWithValue(_bookmarks),
        novelApiProvider.overrideWithValue(_Api()),
      ],
      child: wrapWithApp(
        NovelReaderPage(pathWord: book, volumeId: volume),
        wrapInScaffold: false,
      ),
    ),
  );
  if (settle) await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle(
    const Duration(milliseconds: 20),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 3),
  );
}

Future<void> _remove(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await _settle(tester);
}

NovelReaderPageViewState _pager(WidgetTester tester) =>
    tester.state<NovelReaderPageViewState>(find.byType(NovelReaderPageView));

NovelReaderLocation _pagedLocation(WidgetTester tester) =>
    _pager(tester).currentLocation!;

/// 工具栏收起时只是滑出屏幕（保留在树里做过渡），所以按位移判断显隐。
bool _toolbarHidden(WidgetTester tester) {
  final slide = tester.widget<AnimatedSlide>(
    find.ancestor(
      of: find.byKey(const ValueKey('novel-reader-back')),
      matching: find.byType(AnimatedSlide),
    ),
  );
  return slide.offset.dy != 0;
}

/// 模拟原生侧的音量键回调。
Future<void> _pressVolume(WidgetTester tester, String method) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    _volumeChannel.name,
    const StandardMethodCodec().encodeMethodCall(MethodCall(method)),
    (ByteData? _) {},
  );
  await _settle(tester);
}

/// 顶部屏障区域：底部弹层之外，点按即关闭弹层。
Future<void> _dismissSheet(WidgetTester tester) async {
  await tester.tapAt(const Offset(400, 40));
  await _settle(tester);
}

Future<void> _showToolbar(WidgetTester tester) async {
  if (!_toolbarHidden(tester)) return;
  final surface = find.byType(NovelReaderPageView).evaluate().isNotEmpty
      ? find.byType(NovelReaderPageView)
      : find.byType(NovelReaderViewport);
  await tester.tapAt(tester.getCenter(surface));
  await _settle(tester);
  expect(_toolbarHidden(tester), isFalse);
}

Future<void> _openSettings(WidgetTester tester) async {
  await _showToolbar(tester);
  await tester.tap(find.byKey(const ValueKey('novel-reader-settings')));
  await _settle(tester);
}

Future<void> _tapSheetSwitch(WidgetTester tester, String key) async {
  final expand = find.descendant(
    of: find.byKey(const ValueKey('novel-page-turn-settings')),
    matching: find.byIcon(Icons.expand_more),
  );
  if (expand.evaluate().isNotEmpty) {
    await tester.ensureVisible(expand);
    await _settle(tester);
    await tester.tap(expand);
    await _settle(tester);
  }
  final finder = find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(Switch),
  );
  await tester.ensureVisible(finder);
  await _settle(tester);
  await tester.tap(finder);
  await _settle(tester);
}

Future<void> _slideTo(WidgetTester tester, double item) async {
  await _showToolbar(tester);
  final slider = tester.widget<Slider>(
    find.byKey(const ValueKey('novel-reader-progress')),
  );
  slider.onChanged!(item);
  slider.onChangeEnd!(item);
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Store store;
  late _Repository repository;

  setUp(() async {
    setupSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({});
    store = _Store(await SharedPreferences.getInstance());
    _bookmarks = NovelBookmarkStore.forTesting(
      prefs: Future.value(store.preferences),
    );
    repository = _Repository({'v1': _volume()});
  });

  tearDown(teardownSecureCredentialStoreForTest);

  testWidgets('dragging the sheet curls it and settles on release', (
    tester,
  ) async {
    await _mount(tester, repository: repository, store: store);
    final start = _pagedLocation(tester);
    final surface = find.byKey(const ValueKey('novel-page-surface'));
    // 缓慢拖过约 1/3 视口：松手后落页。
    final gesture = await tester.startGesture(tester.getCenter(surface));
    for (var step = 0; step < 6; step++) {
      await gesture.moveBy(const Offset(-60, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    // 拖动过程中显示卷曲（被翻起的页与露出的页同时在场）。
    expect(find.byType(NovelPageCurl), findsOneWidget);
    await gesture.up();
    await _settle(tester);
    expect(find.byType(NovelPageCurl), findsNothing, reason: '落页后回到静止页');
    expect(_pagedLocation(tester).progress, greaterThan(start.progress));

    // 反向拖回：落回原页，位置与翻页前一致。
    final gestureBack = await tester.startGesture(tester.getCenter(surface));
    for (var step = 0; step < 6; step++) {
      await gestureBack.moveBy(const Offset(60, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gestureBack.up();
    await _settle(tester);
    expect(find.byType(NovelPageCurl), findsNothing);
    expect(_pagedLocation(tester).progress, closeTo(start.progress, 1e-9));
    expect(tester.takeException(), isNull);
    await _remove(tester);
  });

  testWidgets('a short drag does not turn the page', (tester) async {
    await _mount(tester, repository: repository, store: store);
    final start = _pagedLocation(tester);
    // 只拖 40px（不足 1/3 视口）且松手时速度低：回弹不翻页。
    final gesture = await tester.startGesture(const Offset(700, 300));
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await _settle(tester);
    expect(find.byType(NovelPageCurl), findsNothing);
    expect(_pagedLocation(tester).progress, closeTo(start.progress, 1e-9));
    expect(tester.takeException(), isNull);
    await _remove(tester);
  });

  for (final realistic in [true, false]) {
    for (final instant in [true, false]) {
      testWidgets(
        'paged taps dismiss toolbar before turning realistic=$realistic instant=$instant',
        (tester) async {
          await _mount(
            tester,
            repository: repository,
            store: store,
            settings: NovelReaderSettings(
              mode: NovelReaderMode.paged,
              realisticPageTurn: realistic,
              instantPageTurn: instant,
            ),
          );
          expect(find.byType(NovelReaderPageView), findsOneWidget);
          expect(find.byType(NovelReaderViewport), findsNothing);
          final start = _pagedLocation(tester).progress;
          expect(_toolbarHidden(tester), isTrue);
          await _showToolbar(tester);
          expect(_pagedLocation(tester).progress, closeTo(start, 1e-9));
          expect(_toolbarHidden(tester), isFalse);

          // 工具栏显示时点右侧只收起；再次点击才翻到下一页。
          await tester.tapAt(const Offset(700, 300));
          await _settle(tester);
          expect(_pagedLocation(tester).progress, closeTo(start, 1e-9));
          expect(_toolbarHidden(tester), isTrue);
          await tester.tapAt(const Offset(700, 300));
          await _settle(tester);
          final next = _pagedLocation(tester).progress;
          expect(next, greaterThan(start));

          // 在可回翻的页面唤出工具栏，点左侧同样先收起、不翻页。
          await tester.tapAt(const Offset(400, 300));
          await _settle(tester);
          expect(_toolbarHidden(tester), isFalse);
          expect(_pagedLocation(tester).progress, closeTo(next, 1e-9));
          await tester.tapAt(const Offset(100, 300));
          await _settle(tester);
          expect(_pagedLocation(tester).progress, closeTo(next, 1e-9));
          expect(_toolbarHidden(tester), isTrue);
          await tester.tapAt(const Offset(100, 300));
          await _settle(tester);
          expect(_pagedLocation(tester).progress, closeTo(start, 1e-9));

          // 中间区域只切换工具栏，不改变位置。
          await tester.tapAt(const Offset(400, 300));
          await _settle(tester);
          expect(_toolbarHidden(tester), isFalse);
          await tester.tapAt(const Offset(400, 300));
          await _settle(tester);
          expect(_toolbarHidden(tester), isTrue);
          expect(_pagedLocation(tester).progress, closeTo(start, 1e-9));
          expect(tester.takeException(), isNull);
          await _remove(tester);
        },
      );
    }
  }

  testWidgets('switching scroll to paged keeps the reading position', (
    tester,
  ) async {
    await _mount(tester, repository: repository, store: store, paged: false);
    await _slideTo(tester, 150);
    final before = tester
        .state<NovelReaderViewportState>(find.byType(NovelReaderViewport))
        .currentLocation!;
    expect(before.itemIndex, 150);
    await _openSettings(tester);
    await tester.tap(find.text('翻页'));
    await _settle(tester);
    await _dismissSheet(tester);
    expect(find.byType(NovelReaderPageView), findsOneWidget);
    expect(find.byType(NovelReaderViewport), findsNothing);
    final after = _pagedLocation(tester);
    // 页首段落不晚于切换前的位置，且与旧进度基本连续（误差小于一页）。
    expect(after.itemIndex, lessThanOrEqualTo(before.itemIndex));
    expect(after.progress, closeTo(before.progress, 0.06));
    expect(tester.takeException(), isNull);
    await _remove(tester);
  });

  testWidgets('volume keys turn pages only when paged and enabled', (
    tester,
  ) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _volumeChannel,
      (call) async {
        calls.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _volumeChannel,
        null,
      ),
    );
    await _mount(tester, repository: repository, store: store);
    expect(calls, contains('enable'));
    final start = _pagedLocation(tester).progress;
    // 音量- 下一页、音量+ 上一页（与漫画一致）。
    await _pressVolume(tester, 'volumeDown');
    expect(_pagedLocation(tester).progress, greaterThan(start));
    await _pressVolume(tester, 'volumeUp');
    expect(_pagedLocation(tester).progress, closeTo(start, 1e-9));
    // 关掉开关后立即解除拦截，音量键不再翻页。
    await tester.tapAt(const Offset(400, 300));
    await _settle(tester);
    await _openSettings(tester);
    await _tapSheetSwitch(tester, 'novel-volume-key');
    expect(calls.last, 'disable');
    await _dismissSheet(tester);
    final held = _pagedLocation(tester).progress;
    await _pressVolume(tester, 'volumeUp');
    expect(_pagedLocation(tester).progress, closeTo(held, 1e-9));
    expect(tester.takeException(), isNull);
    await _remove(tester);
  });

  testWidgets('scroll mode never intercepts the volume keys', (tester) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _volumeChannel,
      (call) async {
        calls.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _volumeChannel,
        null,
      ),
    );
    await _mount(tester, repository: repository, store: store, paged: false);
    expect(calls, isNot(contains('enable')));
    expect(find.byType(NovelReaderViewport), findsOneWidget);
    await _remove(tester);
  });

  testWidgets('turning past the last page opens the next volume', (
    tester,
  ) async {
    repository = _Repository({
      'v1': _volume(entries: 1, paragraphs: 6, next: 'v2'),
      'v2': _volume(id: 'v2', entries: 1, paragraphs: 6),
    });
    await _mount(tester, repository: repository, store: store);
    await _slideTo(tester, 5);
    final last = _pagedLocation(tester).progress;
    await tester.tapAt(const Offset(700, 300));
    await _settle(tester);
    expect(_pagedLocation(tester).progress, closeTo(last, 1e-9));
    expect(
      repository.calls.any((call) => call.startsWith('book/v2/')),
      isFalse,
    );
    expect(_toolbarHidden(tester), isTrue);
    await tester.tapAt(const Offset(700, 300));
    await _settle(tester);
    expect(
      repository.calls.any((call) => call.startsWith('book/v2/')),
      isTrue,
      reason: '末页继续翻页应自动进入下一卷',
    );
    expect(
      find.text('v2 chapter 0'),
      findsWidgets,
      reason: '应显示下一卷的章节名（页面标题与工具栏）',
    );
    expect(tester.takeException(), isNull);
    await _remove(tester);
  });

  testWidgets('paged mode persists the page position while turning', (
    tester,
  ) async {
    await _mount(tester, repository: repository, store: store);
    expect(_toolbarHidden(tester), isTrue);
    await tester.tapAt(const Offset(700, 300));
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await _settle(tester);
    expect(store.writes, isNotEmpty);
    final saved = store.writes.last;
    expect(saved.progress, greaterThan(0));
    final location = _pagedLocation(tester);
    expect(saved.entryIndex, location.anchor.entryIndex);
    expect(saved.paragraphIndex, location.anchor.paragraphIndex);
    await _remove(tester);
  });

  testWidgets('leaving a volume by page turn skips the remaining chapters', (
    tester,
  ) async {
    // 末章只有一段：末页页首仍属于第 1 章。若按「下一章」处理会停在本卷
    // 中间（原地不动），正确行为是直接进入下一卷。
    repository = _Repository({
      'v1': _volume(entryTexts: _texts('v1', [40, 1]), next: 'v2'),
      'v2': _volume(id: 'v2', entries: 1, paragraphs: 6),
    });
    await _mount(tester, repository: repository, store: store);
    await _slideTo(tester, 40);
    expect(
      _pagedLocation(tester).anchor.entryIndex,
      0,
      reason: '前提：末页页首仍属于第 1 章',
    );
    await tester.tapAt(const Offset(400, 300));
    await _settle(tester);
    await tester.tapAt(const Offset(700, 300));
    await _settle(tester);
    expect(
      repository.calls.any((call) => call.startsWith('book/v2/')),
      isTrue,
      reason: '末页继续翻页应进入下一卷，而不是跳回本卷下一章',
    );
    expect(find.text('v2 chapter 0'), findsWidgets);
    expect(tester.takeException(), isNull);
    await _remove(tester);
  });

  testWidgets('turning back past the first page lands on the volume tail', (
    tester,
  ) async {
    repository = _Repository({
      'v1': _volume(entryTexts: _texts('v1', [40, 30]), next: 'v2'),
      'v2': _volume(id: 'v2', entryTexts: _texts('v2', [6]), previous: 'v1'),
    });
    await _mount(tester, repository: repository, store: store, volume: 'v2');
    await _showToolbar(tester);
    final start = _pagedLocation(tester).progress;
    await tester.tapAt(const Offset(100, 300));
    await _settle(tester);
    expect(_pagedLocation(tester).progress, closeTo(start, 1e-9));
    expect(
      repository.calls.any((call) => call.startsWith('book/v1/')),
      isFalse,
    );
    expect(_toolbarHidden(tester), isTrue);
    await tester.tapAt(const Offset(100, 300));
    await _settle(tester);
    expect(
      repository.calls.any((call) => call.startsWith('book/v1/')),
      isTrue,
      reason: '首页继续回翻应加载上一卷',
    );
    // 落在文档末段（最后一页附近），而不是末章开头（第 41/70 段）。
    expect(_pagedLocation(tester).progress, greaterThan(0.9));
    expect(tester.takeException(), isNull);
    await _remove(tester);
  });

  testWidgets('swiping past the last page opens the next volume', (
    tester,
  ) async {
    repository = _Repository({
      'v1': _volume(entries: 1, paragraphs: 60, next: 'v2'),
      'v2': _volume(id: 'v2', entries: 1, paragraphs: 6),
    });
    await _mount(tester, repository: repository, store: store);
    await _slideTo(tester, 59);
    // 末页只有回弹：滑动越界也要按卷界处理（与漫画一致）。
    await tester.drag(
      find.byKey(const ValueKey('novel-page-surface')),
      const Offset(-300, 0),
    );
    await _settle(tester);
    expect(
      repository.calls.any((call) => call.startsWith('book/v2/')),
      isTrue,
      reason: '末页继续滑动应进入下一卷',
    );
    expect(find.text('v2 chapter 0'), findsWidgets);
    expect(tester.takeException(), isNull);
    await _remove(tester);
  });

  testWidgets('pages render without overflowing the viewport', (tester) async {
    // 段距 32 时每页排满后距页底只剩约 12px：若末片段再加一次段距
    // （渲染与分页测量重复计入），Column 会高出页面并报溢出。
    await _mount(
      tester,
      repository: repository,
      store: store,
      settings: const NovelReaderSettings(
        mode: NovelReaderMode.paged,
        paragraphSpacing: 32,
      ),
    );
    expect(_toolbarHidden(tester), isTrue);
    for (var turn = 1; turn <= 6; turn++) {
      await tester.tapAt(const Offset(700, 300));
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: '第 $turn 页渲染溢出');
    }
    await _remove(tester);
  });

  testWidgets(
    'changing animation settings during a turn is safe in the reader',
    (tester) async {
      await _mount(tester, repository: repository, store: store);
      await _openSettings(tester);
      final instantTile = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('novel-instant-page-turn')),
      );
      final before = _pagedLocation(tester).progress;
      _pager(tester).nextPage();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      instantTile.onChanged!(true);
      await _settle(tester);
      expect(_pagedLocation(tester).progress, greaterThan(before));
      expect(find.byType(NovelPageCurl), findsNothing);
      expect(tester.takeException(), isNull);
      await _remove(tester);
    },
  );

  testWidgets('focus mode masks top and bottom bands without blocking taps', (
    tester,
  ) async {
    await _mount(
      tester,
      repository: repository,
      store: store,
      settings: const NovelReaderSettings(
        mode: NovelReaderMode.paged,
        focusModeEnabled: true,
      ),
    );
    final height =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final top = tester.getRect(
      find.byKey(const ValueKey('novel-focus-mask-top')),
    );
    final bottom = tester.getRect(
      find.byKey(const ValueKey('novel-focus-mask-bottom')),
    );
    expect(top.top, closeTo(0, 1));
    expect(top.height, closeTo(height * 0.2, 1));
    expect(bottom.bottom, closeTo(height, 1));
    expect(bottom.height, closeTo(height * (1 - 0.55), 1));
    // 遮罩触摸穿透：被遮区域点按仍能呼出工具栏。
    expect(_toolbarHidden(tester), isTrue);
    await tester.tapAt(const Offset(400, 60));
    await _settle(tester);
    expect(_toolbarHidden(tester), isFalse, reason: '遮罩不应吞掉点按');
    expect(tester.takeException(), isNull);
    await _remove(tester);
  });

  for (final mode in NovelReaderMode.values) {
    for (final position in [0, 3]) {
      for (final keepVisible in [false, true]) {
        testWidgets(
          'focus status layer $mode position $position keep visible $keepVisible',
          (tester) async {
            await tester.runAsync(() async {
              final prefs = await SharedPreferences.getInstance();
              final status = NovelReaderStatusSettings();
              await status.initFromPrefs(prefs);
              await status.setStatusOverlay(true);
              await status.setStatusOverlayPosition(position);
            });
            await _mount(
              tester,
              repository: repository,
              store: store,
              settings: NovelReaderSettings(
                mode: mode,
                focusModeEnabled: true,
                focusKeepStatusVisible: keepVisible,
              ),
            );
            expect(find.byType(ReaderStatusOverlay), findsOneWidget);
            final stack = find.ancestor(
              of: find.byKey(const ValueKey('novel-focus-mask-widget')),
              matching: find.byType(Stack),
            );
            final children = tester.widget<Stack>(stack.first).children;
            final maskAt = children.indexWhere(
              (child) => child.key == const ValueKey('novel-focus-mask-widget'),
            );
            final overlayAt = children.indexWhere(
              (child) => child.key == const ValueKey('novel-status-overlay'),
            );
            expect(maskAt, isNonNegative);
            expect(overlayAt, isNonNegative);
            expect(
              overlayAt,
              keepVisible ? greaterThan(maskAt) : lessThan(maskAt),
            );
            expect(_toolbarHidden(tester), isTrue);
            final band = tester.getRect(
              find.byKey(
                ValueKey(
                  position < 3
                      ? 'novel-focus-mask-top'
                      : 'novel-focus-mask-bottom',
                ),
              ),
            );
            final showToolbar = find.byKey(
              const ValueKey('novel-reader-show-toolbar'),
            );
            expect(band.contains(tester.getCenter(showToolbar)), isTrue);
            await tester.tap(showToolbar);
            await _settle(tester);
            expect(_toolbarHidden(tester), isFalse);
            expect(showToolbar.hitTestable(), findsNothing);
            expect(tester.takeException(), isNull);
            await _remove(tester);
          },
        );
      }
    }
  }

  for (final mode in NovelReaderMode.values) {
    for (final key in [
      'novel-focus-top',
      'novel-focus-bottom',
      'novel-focus-opacity',
    ]) {
      testWidgets('focus preview $mode $key hides and restores both bars', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(375, 850);
        addTearDown(tester.view.reset);
        await _mount(
          tester,
          repository: repository,
          store: store,
          settings: NovelReaderSettings(mode: mode, focusModeEnabled: true),
        );
        await _openSettings(tester);
        final expand = find.byKey(const ValueKey('novel-focus-details-toggle'));
        await tester.ensureVisible(expand);
        await _settle(tester);
        await tester.tap(expand);
        await _settle(tester);
        final slider = find.byKey(ValueKey(key));
        await tester.ensureVisible(slider);
        await _settle(tester);
        final surface = mode == NovelReaderMode.paged
            ? find.byType(NovelReaderPageView)
            : find.byType(NovelReaderViewport);
        final surfaceState = tester.state(surface);
        final surfaceRect = tester.getRect(surface);
        final anchor = mode == NovelReaderMode.paged
            ? _pagedLocation(tester).anchor
            : null;
        final fade = find.byKey(const ValueKey('app-sheet-fade'));
        final systemUiCalls = <MethodCall>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
              systemUiCalls.add(call);
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );

        final gesture = await tester.startGesture(tester.getCenter(slider));
        await gesture.moveBy(const Offset(30, 0));
        await _settle(tester);
        for (final barKey in ['novel-reader-back', 'novel-reader-settings']) {
          final bar = find.byKey(ValueKey(barKey));
          final slide = tester.widget<AnimatedSlide>(
            find.ancestor(of: bar, matching: find.byType(AnimatedSlide)),
          );
          expect(slide.offset.dy, barKey == 'novel-reader-back' ? -1.05 : 1.05);
          expect(bar.hitTestable(), findsNothing);
        }
        expect(tester.widget<AnimatedOpacity>(fade).opacity, 0);
        final before = tester.widget<Slider>(slider).value;
        await gesture.moveBy(Offset(key == 'novel-focus-top' ? -300 : 300, 0));
        await _settle(tester);
        expect(tester.widget<Slider>(slider).value, isNot(before));
        if (key == 'novel-focus-top') {
          expect(
            tester
                .getSize(find.byKey(const ValueKey('novel-focus-mask-top')))
                .height,
            closeTo(0, 1),
          );
        } else if (key == 'novel-focus-bottom') {
          expect(
            tester
                .getSize(find.byKey(const ValueKey('novel-focus-mask-bottom')))
                .height,
            closeTo(0, 1),
          );
        }
        expect(tester.state(surface), same(surfaceState));
        expect(tester.getRect(surface), surfaceRect);
        if (anchor != null) {
          final current = _pagedLocation(tester).anchor;
          expect(current.entryIndex, anchor.entryIndex);
          expect(current.paragraphIndex, anchor.paragraphIndex);
          expect(current.alignment, closeTo(anchor.alignment, 1e-6));
          expect(current.volumeId, anchor.volumeId);
        }
        expect(systemUiCalls, isEmpty, reason: '拖动预览不能切换系统栏');

        await gesture.up();
        await _settle(tester);
        expect(_toolbarHidden(tester), isFalse);
        expect(tester.widget<AnimatedOpacity>(fade).opacity, 1);
        final bottomSlide = tester.widget<AnimatedSlide>(
          find.ancestor(
            of: find.byKey(const ValueKey('novel-reader-settings')),
            matching: find.byType(AnimatedSlide),
          ),
        );
        expect(bottomSlide.offset, Offset.zero);
        expect(systemUiCalls, isEmpty);
        await tester.binding.handlePopRoute();
        await _settle(tester);
        expect(_toolbarHidden(tester), isFalse);
        expect(tester.takeException(), isNull);
        await _remove(tester);
      });
    }
  }

  testWidgets('closing settings during focus preview restores the toolbar', (
    tester,
  ) async {
    await _mount(
      tester,
      repository: repository,
      store: store,
      settings: const NovelReaderSettings(focusModeEnabled: true),
    );
    await _openSettings(tester);
    final expand = find.byKey(const ValueKey('novel-focus-details-toggle'));
    await tester.ensureVisible(expand);
    await _settle(tester);
    await tester.tap(expand);
    await _settle(tester);
    final slider = find.byKey(const ValueKey('novel-focus-top'));
    await tester.ensureVisible(slider);
    await _settle(tester);
    final control = tester.widget<Slider>(slider);
    control.onChangeStart!(control.value);
    await _settle(tester);
    expect(_toolbarHidden(tester), isTrue);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(_toolbarHidden(tester), isFalse);
    expect(tester.takeException(), isNull);
    await _remove(tester);
  });

  testWidgets('focus status visibility updates live and persists', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final status = NovelReaderStatusSettings();
      await status.initFromPrefs(await SharedPreferences.getInstance());
      await status.setStatusOverlay(true);
    });
    await _mount(
      tester,
      repository: repository,
      store: store,
      settings: const NovelReaderSettings(
        mode: NovelReaderMode.paged,
        focusModeEnabled: true,
      ),
    );
    final overlayState = tester.state(find.byType(ReaderStatusOverlay));
    final location = _pagedLocation(tester).anchor;
    await _openSettings(tester);
    final expand = find.byKey(const ValueKey('novel-focus-details-toggle'));
    await tester.ensureVisible(expand);
    await _settle(tester);
    await tester.tap(expand);
    await _settle(tester);
    for (final value in [true, false]) {
      final tile = find.byKey(
        const ValueKey('novel-focus-keep-status-visible'),
      );
      await tester.ensureVisible(tile);
      await _settle(tester);
      await tester.tap(tile);
      await _settle(tester);
      expect(tester.widget<SwitchListTile>(tile).value, value);
      final stack = find.ancestor(
        of: find.byKey(const ValueKey('novel-focus-mask-widget')),
        matching: find.byType(Stack),
      );
      final children = tester.widget<Stack>(stack.first).children;
      final maskAt = children.indexWhere(
        (child) => child.key == const ValueKey('novel-focus-mask-widget'),
      );
      final overlayAt = children.indexWhere(
        (child) => child.key == const ValueKey('novel-status-overlay'),
      );
      expect(overlayAt, value ? greaterThan(maskAt) : lessThan(maskAt));
      expect(
        tester.state(find.byType(ReaderStatusOverlay, skipOffstage: false)),
        same(overlayState),
      );
      final current = _pagedLocation(tester).anchor;
      expect(current.entryIndex, location.entryIndex);
      expect(current.paragraphIndex, location.paragraphIndex);
      expect(current.alignment, closeTo(location.alignment, 1e-6));
      expect(current.volumeId, location.volumeId);
      await tester.runAsync(() async {
        expect(
          (await NovelReaderSettings.load()).focusKeepStatusVisible,
          value,
        );
      });
    }
    expect(tester.takeException(), isNull);
    await _remove(tester);
  });

  testWidgets('focus keep status visible does not enable a disabled overlay', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final status = NovelReaderStatusSettings();
      await status.initFromPrefs(await SharedPreferences.getInstance());
      await status.setStatusOverlay(false);
    });
    await _mount(
      tester,
      repository: repository,
      store: store,
      settings: const NovelReaderSettings(
        mode: NovelReaderMode.paged,
        focusModeEnabled: true,
        focusKeepStatusVisible: true,
      ),
    );
    expect(find.byKey(const ValueKey('novel-focus-mask')), findsOneWidget);
    expect(find.byType(ReaderStatusOverlay), findsNothing);
    expect(tester.takeException(), isNull);
    await _remove(tester);
  });

  testWidgets('focus mode is off by default and hides the mask', (
    tester,
  ) async {
    await _mount(tester, repository: repository, store: store);
    expect(find.byKey(const ValueKey('novel-focus-mask')), findsNothing);
    await _remove(tester);
  });

  testWidgets('toolbar button toggles the focus mask and persists it', (
    tester,
  ) async {
    await _mount(tester, repository: repository, store: store);
    expect(find.byKey(const ValueKey('novel-focus-mask')), findsNothing);
    await _showToolbar(tester);
    await tester.tap(find.byKey(const ValueKey('novel-reader-focus-mode')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('novel-focus-mask')), findsOneWidget);
    await tester.runAsync(() async {
      final prefs = await SharedPreferences.getInstance();
      final saved = NovelReaderSettings.fromJson(
        jsonDecode(prefs.getString(NovelReaderSettings.storageKey)!)
            as Map<String, dynamic>,
      );
      expect(saved.focusModeEnabled, isTrue);
    });
    // 再点一次关闭，遮罩消失。
    await tester.tap(find.byKey(const ValueKey('novel-reader-focus-mode')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('novel-focus-mask')), findsNothing);
    expect(tester.takeException(), isNull);
    await _remove(tester);
  });

  testWidgets('long-press opens the paragraph menu without turning the page', (
    tester,
  ) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _mount(tester, repository: repository, store: store);
    final before = _pagedLocation(tester).progress;
    await tester.longPress(find.text('v1 entry 0 paragraph 0'));
    await _settle(tester);
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('书签'), findsOneWidget);
    await tester.tap(find.text('复制'));
    await _settle(tester);
    expect(clipboard, 'v1 entry 0 paragraph 0');
    // 长按不翻页：菜单关闭后仍在同一页。
    expect(_pagedLocation(tester).progress, closeTo(before, 1e-9));
    expect(tester.takeException(), isNull);
    await _remove(tester);
  });
}
