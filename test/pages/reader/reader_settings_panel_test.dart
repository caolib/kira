import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/api/api_client.dart';
import 'package:kira/api/manga/manga_api.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/models/chapter.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/reader_page.dart';
import 'package:kira/utils/bookmark_store.dart';
import 'package:kira/utils/reading_history.dart';
import 'package:kira/widgets/app_sheet.dart';
import 'package:kira/widgets/collapsible_content.dart';
import 'package:kira/widgets/reader_settings_fold.dart';
import 'package:kira/widgets/settings_section.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_helpers.dart';

// Decode the plugin's Pigeon ToggleMessage without adding a test dependency.
class _WakelockTestCodec extends StandardMessageCodec {
  const _WakelockTestCodec();

  @override
  Object? readValueOfType(int type, ReadBuffer buffer) {
    return type == 129
        ? readValue(buffer)
        : super.readValueOfType(type, buffer);
  }
}

class _ReaderApi extends Fake implements ApiClient {
  _ReaderApi(this.manga);

  @override
  final MangaApi manga;
}

class _ReaderMangaApi extends Fake implements MangaApi {
  _ReaderMangaApi(this.chapters);

  final Map<String, ChapterDetail> chapters;

  @override
  Future<ChapterDetail> getChapterDetail(
    String pathWord,
    String chapterUuid, {
    bool forceRefresh = false,
  }) async {
    return chapters[chapterUuid]!;
  }
}

ChapterDetail _chapter(String uuid, {String? prev, String? next}) {
  return ChapterDetail(
    uuid: uuid,
    index: 0,
    name: uuid,
    prev: prev,
    next: next,
    contents: [File('assets/ic_launcher.png').absolute.path],
    isDownloaded: true,
  );
}

/// Pumps a real [ReaderPage] backed by a fake API and a local image.
///
/// The [MaterialApp] builder injects the accessibility preferences that the
/// page reads through `MediaQuery`, so tests exercise the same paths as the
/// production app shell.
Future<void> _pumpReader(
  WidgetTester tester, {
  Size size = const Size(800, 600),
  double textScale = 1,
  bool reduceMotion = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  final user = UserManager();
  await user.setReaderMode(0);
  await user.setReaderScrollDirection(2);
  await user.setReaderContinuousReading(false);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion,
        ),
        child: child!,
      ),
      home: const ReaderPage(
        pathWord: 'reader-settings-test',
        comicName: '测试漫画',
        group: 'default',
        chapterUuid: 'last',
        chapterName: 'last',
      ),
    ),
  );

  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    if (find.byType(ScrollablePositionedList).evaluate().isNotEmpty) break;
  }
  expect(find.byType(ReaderPage), findsOneWidget);
  expect(
    find.byType(ScrollablePositionedList),
    findsOneWidget,
    reason: tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .join('; '),
  );
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pumpAndSettle();
}

bool _toolbarShown(WidgetTester tester) {
  final slides = find.ancestor(
    of: find.byTooltip('阅读设置'),
    matching: find.byType(AnimatedSlide),
  );
  return slides.evaluate().any(
    (element) => (element.widget as AnimatedSlide).offset == Offset.zero,
  );
}

/// Taps the reading surface until the reader toolbar slides in.
Future<void> _showToolbar(WidgetTester tester) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    if (_toolbarShown(tester)) return;
    await tester.tapAt(tester.getCenter(find.byType(ScrollablePositionedList)));
    // Images register onTap + onDoubleTap, so the single tap is delayed by
    // the double-tap timeout.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }
  expect(_toolbarShown(tester), isTrue);
}

/// Opens the settings sheet through the real toolbar button.
Future<void> _openSettings(WidgetTester tester) async {
  await _showToolbar(tester);
  await tester.tap(find.byTooltip('阅读设置'));
  await tester.pumpAndSettle();
  expect(find.byType(AppSheet), findsOneWidget);
  expect(find.text('阅读设置'), findsOneWidget);
}

Future<void> _ensureVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Finder _imageLoadingFold() =>
    find.byKey(const ValueKey('reader-image-loading-settings'));

Finder _detailsOf(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byType(CollapsibleContent),
);

bool _isExpanded(WidgetTester tester, Finder details) {
  return tester.widget<CollapsibleContent>(details.first).expanded;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient originalApi;
  late Directory tempDirectory;
  late List<bool> wakeRequests;
  Completer<void>? wakeBlocker;
  const wakeChannel =
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
  const wakeCodec = _WakelockTestCodec();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');

  setUpAll(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'kira-reader-settings-',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProvider,
          (_) async => tempDirectory.path,
        );
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await tempDirectory.delete(recursive: true);
  });

  setUp(() async {
    await ReadingHistory.flush();
    SharedPreferences.setMockInitialValues({});
    setupSecureCredentialStoreForTest();
    BookmarkStore().debugReset();
    originalApi = ApiClient();
    ApiClient.setTestInstance(
      _ReaderApi(_ReaderMangaApi({'last': _chapter('last')})),
    );
    UserManager().reader.resetPrefsCache();
    await UserManager().reader.initFromPrefs(
      await SharedPreferences.getInstance(),
    );
    wakeRequests = [];
    wakeBlocker = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(wakeChannel, (message) async {
          final decoded = wakeCodec.decodeMessage(message);
          if (decoded case [[final bool enabled]]) {
            wakeRequests.add(enabled);
          } else {
            throw StateError('Unexpected wakelock message: $decoded');
          }
          await wakeBlocker?.future;
          return wakeCodec.encodeMessage([null]);
        });
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  tearDown(() async {
    if (wakeBlocker case final blocker? when !blocker.isCompleted) {
      blocker.complete();
    }
    wakeBlocker = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(wakeChannel, null);
    await ReadingHistory.flush();
    BookmarkStore().debugReset();
    ApiClient.setTestInstance(originalApi);
    teardownSecureCredentialStoreForTest();
  });

  testWidgets('工具栏设置入口打开真实阅读设置面板', (tester) async {
    await _pumpReader(tester);
    await _openSettings(tester);

    expect(find.byType(ReaderSettingsFold), findsOneWidget);
    expect(find.text('滚动'), findsOneWidget);
    expect(find.text('翻页'), findsOneWidget);
    expect(find.text('图片加载'), findsOneWidget);
    expect(find.text('长按缩放'), findsOneWidget);
    for (final label in ['自动滚动', '长按缩放', '状态显示', '图片加载']) {
      expect(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(SettingsSection),
        ),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('reader-auto-scroll-card')),
        matching: find.text('滚动幅度'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('reader-auto-scroll-card')),
        matching: find.text('长按缩放'),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  for (final mode in [0, 1]) {
    testWidgets('阅读时屏幕常亮默认开启，模式 $mode 的开关立即生效并持久化', (tester) async {
      await _pumpReader(tester);
      expect(wakeRequests.last, isTrue);
      await _openSettings(tester);
      if (mode == 1) {
        await tester.tap(find.text('翻页'));
        await tester.pumpAndSettle();
        expect(UserManager().readerMode, 1);
      }
      final tile = find.byKey(const ValueKey('reader-keep-screen-on'));
      await _ensureVisible(tester, tile);
      expect(tester.widget<SwitchListTile>(tile).value, isTrue);
      expect(find.text('阅读时屏幕常亮'), findsOneWidget);

      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);
      expect(UserManager().reader.keepScreenOn, isFalse);
      expect(wakeRequests.last, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('reader_keep_screen_on'), isFalse);

      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(tile).value, isTrue);
      expect(wakeRequests.last, isTrue);
      expect(prefs.getBool('reader_keep_screen_on'), isTrue);
      await tester.pumpWidget(wrapWithApp(const SizedBox()));
      await tester.pump();
      expect(wakeRequests.last, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('切到后台取消常亮，恢复前台遵循当前开关，退出释放常亮', (tester) async {
    await _pumpReader(tester);
    expect(wakeRequests.last, isTrue);

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
      expect(wakeRequests.last, isFalse);
    }
    await UserManager().reader.setKeepScreenOn(false);
    await UserManager().reader.setKeepScreenOn(true);
    await tester.pump();
    expect(wakeRequests.last, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(wakeRequests.last, isTrue);

    await UserManager().reader.setKeepScreenOn(false);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(wakeRequests.last, isFalse);

    await UserManager().reader.setKeepScreenOn(true);
    await tester.pump();
    expect(wakeRequests.last, isTrue);
    await tester.pumpWidget(wrapWithApp(const SizedBox()));
    await tester.pump();
    expect(wakeRequests.last, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('常亮请求串行执行，快速开关后退出不会留下未释放的锁', (tester) async {
    wakeBlocker = Completer<void>();
    await _pumpReader(tester);
    expect(wakeRequests, [true]);
    await UserManager().reader.setKeepScreenOn(false);
    await UserManager().reader.setKeepScreenOn(true);
    await tester.pumpWidget(wrapWithApp(const SizedBox()));
    expect(wakeRequests, [true]);

    wakeBlocker!.complete();
    await tester.pump();
    await tester.pump();
    expect(wakeRequests, [true, false, true, false]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('自动滚动开关不覆盖屏幕常亮偏好', (tester) async {
    final chapter = _chapter('last');
    chapter.contents.addAll(List.filled(7, chapter.contents.single));
    ApiClient.setTestInstance(_ReaderApi(_ReaderMangaApi({'last': chapter})));
    await UserManager().setReaderAutoScrollEnabled(true);
    await _pumpReader(tester);
    await _showToolbar(tester);

    for (final keepScreenOn in [true, false]) {
      await UserManager().reader.setKeepScreenOn(keepScreenOn);
      await tester.pumpAndSettle();
      wakeRequests.clear();
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.play_circle_outline),
          )
          .onPressed!();
      await tester.pump();
      expect(find.byTooltip('暂停自动滚动'), findsOneWidget);
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.pause_circle_filled),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      expect(wakeRequests, isEmpty);
      expect(UserManager().reader.keepScreenOn, keepScreenOn);
    }
    await tester.pumpWidget(wrapWithApp(const SizedBox()));
    await tester.pump();
    expect(wakeRequests.last, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('图片加载分组默认折叠，展开后调整超时与重试并写入原偏好', (tester) async {
    await _pumpReader(tester);
    await _openSettings(tester);

    final fold = _imageLoadingFold();
    await _ensureVisible(tester, fold);
    final sliders = find.descendant(of: fold, matching: find.byType(Slider));
    expect(sliders, findsNWidgets(2));
    expect(sliders.hitTestable(), findsNothing);

    await tester.tap(find.text('图片加载'));
    await tester.pumpAndSettle();

    final timeoutSlider = sliders.first;
    await _ensureVisible(tester, timeoutSlider);
    expect(timeoutSlider.hitTestable(), findsOneWidget);
    expect(tester.widget<Slider>(timeoutSlider).value, 15);
    expect(tester.widget<Slider>(sliders.last).value, 1);

    await tester.drag(
      timeoutSlider,
      Offset(tester.getSize(timeoutSlider).width, 0),
    );
    await tester.pumpAndSettle();
    expect(UserManager().imageLoadTimeout, 60);
    expect(find.text('60 s'), findsOneWidget);

    final retrySlider = sliders.last;
    await _ensureVisible(tester, retrySlider);
    await tester.drag(
      retrySlider,
      Offset(tester.getSize(retrySlider).width, 0),
    );
    await tester.pumpAndSettle();
    expect(UserManager().imageRetryCount, 5);
    expect(find.text('5 次'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('image_load_timeout'), 60);
    expect(prefs.getInt('image_retry_count'), 5);

    await _ensureVisible(tester, fold);
    await tester.tap(find.text('图片加载'));
    await tester.pumpAndSettle();
    expect(sliders.hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('自动滚动主开关与细调折叠互相独立，细调值写入原偏好', (tester) async {
    await _pumpReader(tester);
    await _openSettings(tester);

    final switchTile = find.byKey(const ValueKey('reader-auto-scroll-switch'));
    final expand = find.byKey(
      const ValueKey('reader-auto-scroll-details-toggle'),
    );
    await _ensureVisible(tester, switchTile);
    expect(tester.widget<Switch>(switchTile).value, isFalse);
    expect(expand, findsOneWidget);

    final autoDetails = _detailsOf('滚动幅度');
    expect(_isExpanded(tester, autoDetails), isFalse);
    expect(find.text('滚动幅度').hitTestable(), findsNothing);
    await tester.tap(find.text('自动滚动'));
    await tester.pumpAndSettle();
    expect(_isExpanded(tester, autoDetails), isTrue);
    expect(UserManager().reader.autoScrollEnabled, isFalse);

    await _ensureVisible(tester, switchTile);
    await tester.tap(switchTile);
    await tester.pumpAndSettle();
    expect(UserManager().reader.autoScrollEnabled, isTrue);
    expect(tester.widget<Switch>(switchTile).value, isTrue);
    expect(_isExpanded(tester, autoDetails), isTrue);
    expect(_isExpanded(tester, _detailsOf('拖动灵敏度')), isFalse);

    await _ensureVisible(tester, find.text('滚动幅度'));
    expect(find.text('滚动幅度').hitTestable(), findsOneWidget);
    expect(find.text('停顿时长').hitTestable(), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    expect(find.text('3.0 秒'), findsOneWidget);

    final resumeTile = find.widgetWithText(SwitchListTile, '自动恢复');
    await _ensureVisible(tester, resumeTile);
    await tester.tap(resumeTile);
    await tester.pumpAndSettle();
    expect(UserManager().reader.autoScrollResume, isTrue);
    await _ensureVisible(tester, find.text('恢复延迟'));
    expect(find.text('恢复延迟').hitTestable(), findsOneWidget);
    expect(find.text('2.0 秒'), findsOneWidget);

    await _ensureVisible(
      tester,
      find.byKey(const ValueKey('reader-auto-scroll-details-toggle')),
    );
    await tester.tap(
      find.byKey(const ValueKey('reader-auto-scroll-details-toggle')),
    );
    await tester.pumpAndSettle();
    expect(_isExpanded(tester, autoDetails), isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('reader_auto_scroll_enabled'), isTrue);
    expect(prefs.getBool('reader_auto_scroll_resume'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('长按缩放主开关与灵敏度折叠独立，灵敏度写入原偏好', (tester) async {
    await _pumpReader(tester);
    await _openSettings(tester);

    final switchTile = find.byKey(
      const ValueKey('reader-long-press-zoom-switch'),
    );
    await _ensureVisible(tester, switchTile);
    expect(tester.widget<Switch>(switchTile).value, isTrue);
    expect(
      find.byKey(const ValueKey('reader-long-press-zoom-details-toggle')),
      findsOneWidget,
    );

    final zoomDetails = _detailsOf('拖动灵敏度');
    expect(_isExpanded(tester, zoomDetails), isFalse);
    expect(find.text('拖动灵敏度').hitTestable(), findsNothing);

    await tester.tap(find.text('长按缩放'));
    await tester.pumpAndSettle();
    expect(_isExpanded(tester, zoomDetails), isTrue);
    expect(tester.widget<Switch>(switchTile).value, isTrue);
    expect(_isExpanded(tester, _detailsOf('滚动幅度')), isFalse);

    final sensitivitySlider = find.descendant(
      of: zoomDetails,
      matching: find.byType(Slider),
    );
    await _ensureVisible(tester, sensitivitySlider);
    expect(sensitivitySlider.hitTestable(), findsOneWidget);
    await tester.drag(
      sensitivitySlider,
      Offset(tester.getSize(sensitivitySlider).width, 0),
    );
    await tester.pumpAndSettle();

    expect(UserManager().reader.longPressZoomPanSensitivity, 3.0);
    expect(find.text('3.0×'), findsOneWidget);

    // Collapse the details before toggling the master switch so re-enabling
    // cannot be mistaken for "the switch forced the details open".
    await _ensureVisible(
      tester,
      find.byKey(const ValueKey('reader-long-press-zoom-details-toggle')),
    );
    await tester.tap(
      find.byKey(const ValueKey('reader-long-press-zoom-details-toggle')),
    );
    await tester.pumpAndSettle();
    expect(_isExpanded(tester, zoomDetails), isFalse);

    await _ensureVisible(tester, switchTile);
    await tester.tap(switchTile);
    await tester.pumpAndSettle();
    expect(UserManager().reader.longPressZoomEnabled, isFalse);
    expect(
      find.byKey(const ValueKey('reader-long-press-zoom-details-toggle')),
      findsOneWidget,
    );
    expect(_isExpanded(tester, zoomDetails), isFalse);

    await _ensureVisible(tester, switchTile);
    await tester.tap(switchTile);
    await tester.pumpAndSettle();
    expect(UserManager().reader.longPressZoomEnabled, isTrue);
    expect(
      find.byKey(const ValueKey('reader-long-press-zoom-details-toggle')),
      findsOneWidget,
    );
    expect(_isExpanded(tester, zoomDetails), isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('reader_long_press_zoom_enabled'), isTrue);
    expect(prefs.getDouble('reader_long_press_zoom_pan_sensitivity'), 3.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('减少动画时设置面板无过渡', (tester) async {
    await _pumpReader(tester, reduceMotion: true);
    await _showToolbar(tester);

    await tester.tap(find.byTooltip('阅读设置'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(AppSheet), findsOneWidget);
    final route = ModalRoute.of(tester.element(find.byType(AppSheet)))!;
    expect(route.animation!.value, 1);
    expect(route.animation!.isAnimating, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏大字下设置面板与展开分组不溢出', (tester) async {
    await _pumpReader(
      tester,
      size: const Size(320, 640),
      textScale: 1.5,
      reduceMotion: true,
    );
    await _openSettings(tester);
    expect(tester.takeException(), isNull);

    final fold = _imageLoadingFold();
    await _ensureVisible(tester, fold);
    await tester.tap(find.text('图片加载'));
    await tester.pumpAndSettle();

    final sliders = find.descendant(of: fold, matching: find.byType(Slider));
    await _ensureVisible(tester, sliders.first);
    expect(sliders.first.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    for (final label in ['自动滚动', '长按缩放', '状态显示']) {
      final header = find.text(label);
      await _ensureVisible(tester, header);
      await tester.tap(header);
      await tester.pumpAndSettle();
      final card = find.ancestor(
        of: header,
        matching: find.byType(SettingsSection),
      );
      final controls = find.descendant(of: card, matching: find.byType(Slider));
      await _ensureVisible(tester, controls.first);
      expect(controls.first.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
