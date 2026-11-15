import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/models/theme_settings.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/appearance_page.dart';
import 'package:kira/utils/font_manager.dart';
import 'package:kira/widgets/select_tile.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

class _Display {
  static const channel = MethodChannel('flutter_display_mode');
  static const windowChannel = MethodChannel(
    'io.github.caolib.kira/display_mode',
  );
  double active = 60;
  List<double> supportedRates = [60, 120];

  /// Native `getSupportedRefreshRates` payload; falls back to
  /// [supportedRates] when left null.
  List<double>? nativeRates;
  int reads = 0;
  bool failActive = false;
  bool failSupported = false;
  bool failNativeRates = false;
  Completer<Map<String, Object>>? pendingRead;
  final requests = <MethodCall>[];

  Map<String, Object> mode(double rate) => {
    'id': rate == 60 ? 1 : 2,
    'width': 1080,
    'height': 2400,
    'refreshRate': rate,
  };

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'getSupportedModes':
        if (failSupported) throw PlatformException(code: 'unavailable');
        return [for (final rate in supportedRates) mode(rate)];
      case 'getSupportedRefreshRates':
        if (failNativeRates) {
          throw PlatformException(
            code: 'display_mode_unavailable',
            message: 'NoSuchMethodError: display API unavailable',
          );
        }
        if (failSupported) throw PlatformException(code: 'unavailable');
        return nativeRates ?? supportedRates;
      case 'getActiveMode':
        reads++;
        if (failActive) throw PlatformException(code: 'unavailable');
        final pending = pendingRead;
        if (pending != null) {
          pendingRead = null;
          return pending.future;
        }
        return mode(active);
      case 'setPreferredMode':
      case 'setPreferredRefreshRate':
        requests.add(call);
        return null;
      default:
        throw MissingPluginException(call.method);
    }
  }
}

final _tile = find.widgetWithText(ListTile, '屏幕刷新率');
final _select = find.descendant(
  of: _tile,
  matching: find.byType(SelectTile<int>),
);

Future<void> _showPage(WidgetTester tester) async {
  await tester.pumpWidget(
    wrapWithApp(const AppearancePage(), wrapInScaffold: false),
  );
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    _tile,
    400,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  // Drain the font card's unrelated directory scan outside fake async.
  await tester.runAsync(() => FontManager().listDownloadedFonts());
}

Future<Finder> _showTextScaleSlider(WidgetTester tester) async {
  await tester.pumpWidget(
    wrapWithApp(const AppearancePage(), wrapInScaffold: false),
  );
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text('全局文字缩放'),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.runAsync(() => FontManager().listDownloadedFonts());
  final card = find.ancestor(
    of: find.text('全局文字缩放'),
    matching: find.byType(Card),
  );
  final slider = find.descendant(of: card, matching: find.byType(Slider));
  await tester.ensureVisible(slider);
  await tester.pumpAndSettle();
  return slider;
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(_select);
  await tester.pumpAndSettle();
}

Future<void> _tick(WidgetTester tester, [int seconds = 1]) async {
  await tester.pump(Duration(seconds: seconds));
  await tester.pump();
  await tester.pump(); // SelectTile refreshes its open overlay after layout.
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  late _Display display;
  late Directory directory;
  late PathProviderPlatform oldPaths;

  setUp(() async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    setupSecureCredentialStoreForTest();
    SharedPreferences.setMockInitialValues({});
    // 换过 mock 存储后必须丢掉旧的 SharedPreferences 实例，
    // 否则子 store 的写入会落进上一个用例的内存表。
    ThemeSettings().resetPrefsCache();
    await UserManager().init();
    directory = await Directory.systemTemp.createTemp(
      'kira_refresh_rate_test_',
    );
    oldPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    FontManager().reloadFromPrefs();
    await FontManager().listDownloadedFonts();
    display = _Display();
    messenger.setMockMethodCallHandler(_Display.channel, display.handle);
    messenger.setMockMethodCallHandler(_Display.windowChannel, display.handle);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_Display.channel, null);
    messenger.setMockMethodCallHandler(_Display.windowChannel, null);
    teardownSecureCredentialStoreForTest();
    FontManager().reloadFromPrefs();
    PathProviderPlatform.instance = oldPaths;
    directory.deleteSync(recursive: true);
  });

  for (final size in [const Size(420, 900), const Size(1024, 850)]) {
    testWidgets(
      'iOS keeps manual themes visible with a restored dynamic-color preference at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final user = UserManager();
        await user.theme.setUseDynamicColor(true);
        await tester.pumpWidget(
          wrapWithApp(const AppearancePage(), wrapInScaffold: false),
        );
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(AppearancePage)),
        )!;
        await tester.scrollUntilVisible(
          find.text(l10n.appearanceThemeStyle),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() => FontManager().listDownloadedFonts());
        expect(find.text(l10n.appearanceDynamicColor), findsNothing);
        final vibrant = find.widgetWithText(
          ChoiceChip,
          l10n.themeVariantVibrant,
        );
        await tester.ensureVisible(vibrant);
        await tester.tap(vibrant);
        await tester.pumpAndSettle();
        expect(user.themeVariant, DynamicSchemeVariant.vibrant);
        expect(
          user.theme.useDynamicColor,
          isTrue,
          reason: 'Unsupported preferences are retained, not overwritten',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      variant: const TargetPlatformVariant({TargetPlatform.iOS}),
    );
  }

  testWidgets('全局文字缩放以百分比显示，保留原范围与步长', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final sliderFinder = await _showTextScaleSlider(tester);
      final slider = tester.widget<Slider>(sliderFinder);

      expect(slider.label, '100%');
      expect(slider.value, ThemeSettings.defaultAppFontSize);
      expect(slider.min, 8);
      expect(slider.max, 26);
      expect(slider.divisions, 18);
      expect(find.semantics.byValue('100%'), findsOneWidget);
      expect(find.text('应用字体大小'), findsNothing);
      final traditional = await AppLocalizations.delegate.load(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      );
      expect(traditional.appearanceTextScale, '全域文字縮放');
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('全局文字缩放预览百分比，松手后仍写入兼容偏好', (tester) async {
    final sliderFinder = await _showTextScaleSlider(tester);
    tester.widget<Slider>(sliderFinder).onChanged!(21);
    await tester.pumpAndSettle();

    expect(tester.widget<Slider>(sliderFinder).label, '150%');
    expect(UserManager().theme.defaultFontSize, 14);
    tester.widget<Slider>(sliderFinder).onChangeEnd!(21);
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('default_font_size'), 21);
    expect(UserManager().theme.defaultFontSize, 21);

    await tester.pumpWidget(const SizedBox.shrink());
    await ThemeSettings().initFromPrefs(prefs, persistMigrations: false);
    final reopened = await _showTextScaleSlider(tester);
    expect(tester.widget<Slider>(reopened).label, '150%');
    expect(tester.widget<Slider>(reopened).value, 21);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final (storedValue, expectedLabel) in [(8.0, '57%'), (26.0, '186%')]) {
    testWidgets('原字号 $storedValue 保持原缩放并显示为 $expectedLabel', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('default_font_size', storedValue);
      await ThemeSettings().initFromPrefs(prefs, persistMigrations: false);
      final sliderFinder = await _showTextScaleSlider(tester);
      final slider = tester.widget<Slider>(sliderFinder);

      expect(slider.value, storedValue);
      expect(slider.label, expectedLabel);
      expect(slider.semanticFormatterCallback!(storedValue), expectedLabel);
      expect(prefs.getDouble('default_font_size'), storedValue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('auto capsule reads 60/120Hz and keeps the open menu current', (
    tester,
  ) async {
    await _showPage(tester);
    expect(find.text('自动 · 60Hz'), findsOneWidget);
    expect(tester.widget<ListTile>(_tile).subtitle, isNull);
    final l10n = AppLocalizations.of(tester.element(_tile))!;
    expect(find.text(l10n.appearanceRefreshRateDesc), findsNothing);
    expect(display.requests, isEmpty);

    await _openMenu(tester);
    expect(find.text('60Hz（当前）'), findsOneWidget);
    expect(find.text('120 Hz'), findsOneWidget);
    expect(find.text('90 Hz'), findsOneWidget);
    expect(find.text('144 Hz'), findsNothing);
    expect(find.text('165 Hz'), findsNothing);
    display.active = 120;
    await _tick(tester);
    expect(find.text('自动 · 120Hz'), findsOneWidget);
    expect(find.text('120Hz（当前）'), findsOneWidget);
    expect(find.text('60Hz（当前）'), findsNothing);
    expect(display.requests, isEmpty);

    display.active = 60;
    await _tick(tester);
    expect(find.text('自动 · 60Hz'), findsOneWidget);
    expect(find.text('60Hz（当前）'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a rejected request is never marked active and auto clears it', (
    tester,
  ) async {
    // Native report knows the 144Hz panel; plugin enumeration omits 144.
    display.supportedRates = [60, 120];
    display.nativeRates = [60, 120, 144];
    display.active = 120;
    await _showPage(tester);
    await _openMenu(tester);
    final oldRead = Completer<Map<String, Object>>();
    display.pendingRead = oldRead;
    await _tick(tester);
    final before = display.reads;
    await tester.tap(find.text('144 Hz'));
    await tester.pumpAndSettle();
    expect(UserManager().displayModeRefreshRate, 144);
    expect(display.requests.last.arguments, {'refreshRate': 144.0});
    expect(display.reads, greaterThan(before + 1)); // apply + actual read-back
    expect(find.text('144Hz（当前）'), findsNothing);
    oldRead.complete(display.mode(60));
    await tester.pump();
    await _openMenu(tester);
    expect(find.text('120Hz（当前）'), findsOneWidget);
    expect(find.text('60Hz（当前）'), findsNothing);

    await tester.tap(find.text('自动（跟随系统）'));
    await tester.pumpAndSettle();
    expect(UserManager().displayModeRefreshRate, 0);
    expect(display.requests[display.requests.length - 2].arguments, {
      'mode': 0,
    });
    expect(display.requests.last.arguments, {'refreshRate': 0.0});
    expect(find.text('自动 · 120Hz'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'read-back observes a delayed native switch rather than assuming success',
    (tester) async {
      await _showPage(tester);
      await _openMenu(tester);
      await tester.tap(find.text('120 Hz'));
      await tester.pumpAndSettle();
      expect(find.text('120Hz（当前）'), findsNothing);
      await _openMenu(tester);
      expect(find.text('60Hz（当前）'), findsOneWidget);
      display.active = 120;
      await _tick(tester);
      expect(find.text('60Hz（当前）'), findsNothing);
      expect(find.text('120Hz（当前）'), findsNWidgets(2)); // capsule + menu
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'unknown or failed reads fall back to auto and recover without a spinner',
    (tester) async {
      display.failSupported = true;
      display.failActive = true;
      await _showPage(tester);
      expect(
        find.descendant(of: _select, matching: find.text('自动')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _tile,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );
      await _openMenu(tester);
      // The device could not be inspected: keep the full pool, never a
      // collapsed list.
      expect(find.text('165 Hz'), findsOneWidget);
      expect(find.text('144 Hz'), findsOneWidget);
      expect(find.text('120 Hz'), findsOneWidget);
      expect(find.text('90 Hz'), findsOneWidget);
      expect(find.text('60 Hz'), findsOneWidget);
      await tester.tapAt(const Offset(10, 100));
      await tester.pumpAndSettle();

      display.failActive = false;
      display.active = 120;
      await _tick(tester, 5);
      expect(find.text('自动 · 120Hz'), findsOneWidget);
      display.active = 0;
      await _tick(tester);
      expect(
        find.descendant(of: _select, matching: find.text('自动')),
        findsOneWidget,
      );
      expect(find.textContaining('0Hz'), findsNothing);
      display.active = 60;
      await _tick(tester);
      expect(find.text('自动 · 60Hz'), findsOneWidget);
      display.failActive = true;
      await _tick(tester);
      expect(find.text('自动 · 60Hz'), findsNothing);
      expect(
        find.descendant(of: _select, matching: find.text('自动')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'native compatibility errors leave the page and refresh-rate picker usable',
    (tester) async {
      display.failNativeRates = true;
      await _showPage(tester);
      expect(find.text('自动 · 60Hz'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(display.requests, isEmpty);

      await _openMenu(tester);
      expect(find.text('120 Hz'), findsOneWidget);
      expect(find.text('90 Hz'), findsOneWidget);
      expect(find.text('60Hz（当前）'), findsOneWidget);
      expect(find.text('165 Hz'), findsNothing);
      await tester.tap(find.text('120 Hz'));
      await tester.pumpAndSettle();
      expect(UserManager().displayModeRefreshRate, 120);
      expect(display.requests.last.method, 'setPreferredMode');
      expect(display.requests.last.arguments, {'mode': 2});
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('device cap keeps the right rates when enumeration is empty', (
    tester,
  ) async {
    // The plugin's mode list is empty (common on VRR panels) but the native
    // report knows the 120Hz panel — 144/165 must stay hidden.
    display.supportedRates = const [];
    display.nativeRates = [60, 90, 120];
    await _showPage(tester);
    await _openMenu(tester);
    expect(find.text('120 Hz'), findsOneWidget);
    expect(find.text('90 Hz'), findsOneWidget);
    expect(find.text('60Hz（当前）'), findsOneWidget);
    expect(find.text('144 Hz'), findsNothing);
    expect(find.text('165 Hz'), findsNothing);

    await tester.tap(find.text('90 Hz'));
    await tester.pumpAndSettle();
    expect(UserManager().displayModeRefreshRate, 90);
    expect(display.requests.last.arguments, {'refreshRate': 90.0});
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'polling stops in background and ignores stale responses after resuming',
    (tester) async {
      await _showPage(tester);
      final oldRead = Completer<Map<String, Object>>();
      display.pendingRead = oldRead;
      await _tick(tester);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final before = display.reads;
      display.active = 120;
      await _tick(tester, 5);
      expect(display.reads, before);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('自动 · 120Hz'), findsOneWidget);
      oldRead.complete(display.mode(60));
      await tester.pump();
      expect(find.text('自动 · 120Hz'), findsOneWidget);
      final resumedReads = display.reads;
      await _tick(tester);
      expect(display.reads, resumedReads + 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('covered routes stop polling and resume with a fresh reading', (
    tester,
  ) async {
    await _showPage(tester);
    final navigator = Navigator.of(tester.element(_tile));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('other')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = display.reads;
    display.active = 120;
    await _tick(tester, 5);
    expect(display.reads, before);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('自动 · 120Hz'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('dispose cancels polling even with an in-flight platform read', (
    tester,
  ) async {
    await _showPage(tester);
    final pending = Completer<Map<String, Object>>();
    display.pendingRead = pending;
    await _tick(tester);
    final before = display.reads;
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(display.mode(120));
    await _tick(tester, 5);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _tick(tester, 5);
    expect(display.reads, before);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'auto label fits a 320px screen and has a Traditional Chinese label',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      display.active = 120;
      await _showPage(tester);
      final tileRect = tester.getRect(_tile);
      final selectRect = tester.getRect(_select);
      expect(selectRect.left, greaterThan(tileRect.left));
      expect(selectRect.right, lessThanOrEqualTo(tileRect.right));
      expect(find.text('自动 · 120Hz'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final traditional = await AppLocalizations.delegate.load(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      );
      expect(traditional.appearanceAutoRefreshRate(120), '自動 · 120Hz');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final initialMode in [
    BottomNavLabelMode.selectedOnly,
    BottomNavLabelMode.hidden,
  ]) {
    testWidgets('悬浮底栏选择始终显示时提示降级：${initialMode.name}', (tester) async {
      final user = UserManager();
      await user.theme.setFloatingNavEnabled(true);
      await user.setBottomNavLabelMode(initialMode);
      await _showPage(tester);
      final tile = find.widgetWithText(ListTile, '底部导航栏文字');
      await tester.scrollUntilVisible(
        tile,
        -400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final select = find.descendant(
        of: tile,
        matching: find.byType(SelectTile<BottomNavLabelMode>),
      );
      await tester.tap(select);
      await tester.pumpAndSettle();
      await tester.tap(find.text('始终显示文字').last);
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(tester.element(tile))!;
      expect(
        find.text(l10n.appearanceFloatingNavLabelModeHint),
        findsOneWidget,
      );
      expect(user.bottomNavLabelMode, BottomNavLabelMode.selectedOnly);
      expect(user.theme.floatingNavEnabled, isTrue);
      expect(
        find.descendant(of: tile, matching: find.text('选中时显示')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('非悬浮底栏允许始终显示文字且不提示降级', (tester) async {
    final user = UserManager();
    await user.theme.setFloatingNavEnabled(false);
    await _showPage(tester);
    final tile = find.widgetWithText(ListTile, '底部导航栏文字');
    await tester.scrollUntilVisible(
      tile,
      -400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final select = find.descendant(
      of: tile,
      matching: find.byType(SelectTile<BottomNavLabelMode>),
    );
    await tester.tap(select);
    await tester.pumpAndSettle();
    await tester.tap(find.text('始终显示文字').last);
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(tester.element(tile))!;
    expect(find.text(l10n.appearanceFloatingNavLabelModeHint), findsNothing);
    expect(user.bottomNavLabelMode, BottomNavLabelMode.always);
    expect(
      find.descendant(of: tile, matching: find.text('始终显示文字')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('非悬浮始终显示文字后开启悬浮，下拉即时降为选中时显示', (tester) async {
    final user = UserManager();
    await user.theme.setFloatingNavEnabled(false);
    await user.setBottomNavLabelMode(BottomNavLabelMode.always);
    await _showPage(tester);
    final floatingTile = find.widgetWithText(SwitchListTile, '悬浮导航栏');
    await tester.scrollUntilVisible(
      floatingTile,
      -400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(floatingTile).value, isFalse);

    await tester.tap(floatingTile);
    await tester.pumpAndSettle();

    expect(user.theme.floatingNavEnabled, isTrue);
    expect(user.bottomNavLabelMode, BottomNavLabelMode.selectedOnly);
    final labelTile = find.widgetWithText(ListTile, '底部导航栏文字');
    expect(
      find.descendant(of: labelTile, matching: find.text('选中时显示')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<SelectTile<BottomNavLabelMode>>(
            find.descendant(
              of: labelTile,
              matching: find.byType(SelectTile<BottomNavLabelMode>),
            ),
          )
          .value,
      BottomNavLabelMode.selectedOnly,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('底部导航栏文字改为下拉列表，选中即生效且不再弹底部选择层', (tester) async {
    await _showPage(tester);
    final tile = find.widgetWithText(ListTile, '底部导航栏文字');
    await tester.scrollUntilVisible(
      tile,
      -400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final select = find.descendant(
      of: tile,
      matching: find.byType(SelectTile<BottomNavLabelMode>),
    );
    expect(select, findsOneWidget);
    expect(tester.widget<ListTile>(tile).onTap, isNull);
    expect(
      find.descendant(of: tile, matching: find.text('选中时显示')),
      findsOneWidget,
    );

    await tester.tap(select);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    await tester.tap(find.text('不显示文字').last);
    await tester.pumpAndSettle();

    expect(UserManager().bottomNavLabelMode, BottomNavLabelMode.hidden);
    expect(
      find.descendant(of: tile, matching: find.text('不显示文字')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'phone puts theme, font and motion before navigation without extra copy',
    (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        wrapWithApp(const AppearancePage(), wrapInScaffold: false),
      );
      await tester.pumpAndSettle();
      final theme = find.widgetWithText(ListTile, '主题模式');
      final font = find.text('全局文字缩放');
      final motion = find.widgetWithText(SwitchListTile, '减少动画');
      final nav = find.widgetWithText(ListTile, '底部导航栏文字');
      final scrollable = find.byType(Scrollable).first;
      double? previousOffset;
      for (final target in [theme, font, motion, nav]) {
        await tester.scrollUntilVisible(target, 250, scrollable: scrollable);
        await tester.pumpAndSettle();
        final offset = tester
            .state<ScrollableState>(scrollable)
            .position
            .pixels;
        if (previousOffset != null) {
          expect(offset, greaterThanOrEqualTo(previousOffset));
        }
        previousOffset = offset;
      }
      expect(find.text('关闭后只能点击底部导航按钮切换页面'), findsNothing);
      expect(find.text('暗色模式下降低各个界面的卡片封面亮度'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('子 store 修改主题模式和变体会即时更新外观页', (tester) async {
    await _showPage(tester);
    final user = UserManager();
    await user.theme.setThemeMode(ThemeMode.dark);
    await user.theme.setThemeVariant(DynamicSchemeVariant.vibrant);
    await tester.pumpAndSettle();

    expect(user.themeMode, ThemeMode.dark);
    expect(user.themeVariant, DynamicSchemeVariant.vibrant);
    expect(
      tester
          .widget<SelectTile<ThemeMode>>(find.byType(SelectTile<ThemeMode>))
          .value,
      ThemeMode.dark,
    );
    final selected = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .where((chip) => chip.selected);
    expect(selected, hasLength(1));
    final label = selected.single.label;
    final l10n = AppLocalizations.of(
      tester.element(find.byType(AppearancePage)),
    )!;
    expect(
      label,
      isA<Text>().having((text) => text.data, 'text', l10n.themeVariantVibrant),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('减少动画开关落盘并即时更新页面', (tester) async {
    await _showPage(tester);
    final tile = find.widgetWithText(SwitchListTile, '减少动画');
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(UserManager().theme.reduceMotion, isTrue);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);

    // 重新载入仍是开启状态，说明写进了同一份偏好。
    final prefs = await SharedPreferences.getInstance();
    await UserManager().theme.initFromPrefs(prefs);
    expect(UserManager().theme.reduceMotion, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
