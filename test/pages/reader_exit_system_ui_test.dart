import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kira/api/api_client.dart';
import 'package:kira/api/manga/manga_api.dart';
import 'package:kira/api/novel/novel_api.dart';
import 'package:kira/models/chapter.dart';
import 'package:kira/models/novel.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/novel_reader_page.dart';
import 'package:kira/pages/reader_page.dart';
import 'package:kira/repositories/novel_reader_source.dart';
import 'package:kira/routing/app_router.dart';
import 'package:kira/utils/bookmark_store.dart';
import 'package:kira/utils/reading_history.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

class _Api extends Fake implements ApiClient {
  @override
  final MangaApi manga = _Manga();

  @override
  final NovelApi novel = _NovelApi();
}

class _NovelApi extends Fake implements NovelApi {
  @override
  bool get hasCopyToken => false;
}

class _Manga extends Fake implements MangaApi {
  @override
  Future<ChapterDetail> getChapterDetail(
    String pathWord,
    String chapterUuid, {
    bool forceRefresh = false,
  }) async => ChapterDetail(
    uuid: chapterUuid,
    name: '测试章节',
    index: 0,
    contents: [File('assets/ic_launcher.png').absolute.path],
    isDownloaded: true,
  );
}

class _Source extends Fake implements NovelReaderSource {
  final detail = const NovelVolumeDetail(
    book: NovelBook(pathWord: 'exit-test', name: '测试小说'),
    volume: NovelVolume(
      id: 'volume',
      name: '测试卷',
      bookPathWord: 'exit-test',
      contents: [NovelContentEntry(name: '测试章节', contentType: 1)],
    ),
  );

  @override
  bool get localOnly => false;

  @override
  Future<List<NovelVolume>> loadVolumes(String pathWord) async => [
    detail.volume,
  ];

  @override
  Future<NovelVolumeContent?> loadContent(
    String pathWord,
    String volumeId, {
    bool refresh = false,
    bool cachedOnly = false,
  }) async => NovelVolumeContent(
    detail: detail,
    entries: [
      NovelReaderEntry(
        entryIndex: 0,
        entry: detail.volume.contents.first,
        paragraphs: ['测试正文'],
      ),
    ],
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const volumeChannel = MethodChannel('io.github.caolib.kira/volume');
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  late ApiClient originalApi;
  late List<MethodCall> calls;

  setUp(() async {
    setupSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({});
    await ReadingHistory.flush();
    BookmarkStore().debugReset();
    originalApi = ApiClient();
    ApiClient.setTestInstance(_Api());
    UserManager().reader.resetPrefsCache();
    await UserManager().init();
    directory = await Directory.systemTemp.createTemp('kira-reader-exit-');
    messenger.setMockMethodCallHandler(
      pathChannel,
      (_) async => directory.path,
    );
    calls = [];
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(volumeChannel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() async {
    await ReadingHistory.flush();
    BookmarkStore().debugReset();
    ApiClient.setTestInstance(originalApi);
    messenger.setMockMethodCallHandler(pathChannel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    messenger.setMockMethodCallHandler(volumeChannel, null);
    await directory.delete(recursive: true);
    teardownSecureCredentialStoreForTest();
  });

  bool restored() => calls.any((call) => call.method == 'disableImmersive');

  void expectRestoredOnce() {
    expect(
      calls.where((call) => call.method == 'disableImmersive'),
      hasLength(1),
    );
    final systemCalls = calls
        .where((call) => call.method.startsWith('SystemChrome.setEnabled'))
        .toList();
    expect(systemCalls, hasLength(1));
    expect(
      systemCalls.single.method,
      'SystemChrome.setEnabledSystemUIOverlays',
    );
    expect(systemCalls.single.arguments, [
      'SystemUiOverlay.top',
      'SystemUiOverlay.bottom',
    ]);
  }

  for (final novel in [false, true]) {
    final label = novel ? '小说' : '漫画';
    Widget reader({Key? key, bool directEntry = false}) => novel
        ? NovelReaderPage(
            key: key,
            pathWord: 'exit-test',
            volumeId: 'volume',
            noDetailBelow: directEntry,
            source: _Source(),
          )
        : ReaderPage(
            key: key,
            pathWord: 'exit-test',
            comicName: '测试漫画',
            group: 'default',
            chapterUuid: 'chapter',
            chapterName: '测试章节',
            noCatalogBelow: directEntry,
          );

    for (final toolbarBack in [false, true]) {
      testWidgets('$label：${toolbarBack ? '顶栏' : '系统'}返回开始即恢复，dispose 不重复恢复', (
        tester,
      ) async {
        late BuildContext homeContext;
        final key = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            child: wrapWithApp(
              Builder(
                builder: (context) {
                  homeContext = context;
                  return const Text('详情页');
                },
              ),
            ),
          ),
        );
        final route = PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 400),
          reverseTransitionDuration: const Duration(milliseconds: 400),
          pageBuilder: (_, _, _) => reader(key: key),
        );
        unawaited(Navigator.of(homeContext).push(route));
        await _settle(tester);
        final state = key.currentState!;
        final back = tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.arrow_back),
            )
            .onPressed!;
        calls.clear();

        if (toolbarBack) {
          back();
        } else {
          await tester.binding.handlePopRoute();
        }
        await tester.pump();
        // 400ms 退场动画尚未播放，页面仍存活，但窗口恢复必须已发出。
        expect(state.mounted, isTrue);
        expect(route.animation!.status, AnimationStatus.reverse);
        expectRestoredOnce();
        await _settle(tester);
        expect(state.mounted, isFalse);
        expectRestoredOnce();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    testWidgets('$label：关闭弹层或拒绝返回不释放阅读窗口，直接移除仍恢复', (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          child: wrapWithApp(reader(key: key), wrapInScaffold: false),
        ),
      );
      await _settle(tester);
      final state = key.currentState!;
      final popScope = tester.widget<PopScope<dynamic>>(
        find
            .descendant(
              of: find.byKey(key),
              matching: find.byWidgetPredicate((widget) => widget is PopScope),
            )
            .first,
      );
      calls.clear();
      popScope.onPopInvokedWithResult!(false, null);
      unawaited(
        showDialog<void>(
          context: key.currentContext!,
          builder: (_) => const AlertDialog(content: Text('阅读弹层')),
        ),
      );
      await _settle(tester);
      Navigator.of(tester.element(find.text('阅读弹层'))).pop();
      await _settle(tester);
      expect(state.mounted, isTrue);
      expect(restored(), isFalse);
      calls.clear();
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
      expectRestoredOnce();
      expect(tester.takeException(), isNull);
    });

    testWidgets('$label：直达阅读后返回总目录，在详情页构建前恢复', (tester) async {
      var destinationBuilt = false;
      final router = GoRouter(
        initialLocation: '/read',
        routes: [
          GoRoute(path: '/read', builder: (_, _) => reader(directEntry: true)),
          GoRoute(
            path: '/detail/:pathWord',
            name: novel ? AppRoutes.novelDetail : AppRoutes.comicDetail,
            builder: (_, _) {
              expect(restored(), isTrue);
              destinationBuilt = true;
              return const Scaffold(body: Text('总目录目标页'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          child: wrapWithApp(
            Router.withConfig(config: router),
            wrapInScaffold: false,
          ),
        ),
      );
      await _settle(tester);
      final catalog = tester.widget<IconButton>(
        novel
            ? find.byKey(const ValueKey('novel-reader-contents'))
            : find.widgetWithIcon(IconButton, Icons.list),
      );
      calls.clear();
      catalog.onPressed!();
      if (novel) {
        await _settle(tester);
        calls.clear();
        await tester.tap(find.text('总目录'));
      }
      await _settle(tester);
      expect(destinationBuilt, isTrue);
      expect(restored(), isTrue);
      expect(
        calls.where((call) => call.method == 'disableImmersive'),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
    });
  }
}
