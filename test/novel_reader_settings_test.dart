import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/novel_reader_settings.dart';
import 'package:kira/theme/novel_reader_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'reader_mode': 1,
      'theme_mode': 'system',
      'novel_reading_history_book': 'untouched history',
    });
    prefs = await SharedPreferences.getInstance();
  });

  test('idle queue does not retain a completed FakeAsync zone', () {
    for (var index = 0; index < 3; index++) {
      fakeAsync((async) {
        final settings = NovelReaderSettings(fontSize: 20.0 + index);
        var saved = false;
        var loaded = false;
        unawaited(
          settings.save(prefs: Future.value(prefs)).then((_) {
            saved = true;
          }),
        );
        unawaited(
          NovelReaderSettings.load(prefs: Future.value(prefs)).then((result) {
            expect(result, settings);
            loaded = true;
          }),
        );
        async.flushMicrotasks();
        expect(saved, isTrue, reason: 'save in FakeAsync zone $index');
        expect(loaded, isTrue, reason: 'load in FakeAsync zone $index');
      });
    }
  });

  test(
    'defaults follow system light/dark bindings without any writes',
    () async {
      const defaults = NovelReaderSettings();
      expect(defaults.fontSize, 20);
      expect(defaults.lineHeight, 1.8);
      expect(defaults.paragraphSpacing, 16);
      expect(defaults.contentWidth, 720);
      expect(defaults.lightThemeId, 'white');
      expect(defaults.darkThemeId, 'gray');
      expect(defaults.customThemes, isEmpty);
      expect(defaults.keepScreenOn, isTrue);
      expect(defaults.mode, NovelReaderMode.scroll);
      expect(defaults.realisticPageTurn, isTrue);
      expect(defaults.toJson()['realisticPageTurn'], isTrue);
      expect(defaults.instantPageTurn, isFalse);
      expect(defaults.volumeKey, isTrue);
      expect(defaults.ignoreBlankParagraphs, isFalse);
      expect(defaults.toJson()['ignoreBlankParagraphs'], isFalse);
      expect(defaults.focusModeEnabled, isFalse);
      expect(defaults.focusTopRatio, 0.2);
      expect(defaults.focusBottomRatio, 0.55);
      expect(defaults.focusOpacity, 0.5);
      expect(
        await NovelReaderSettings.load(prefs: Future.value(prefs)),
        defaults,
      );
      expect(prefs.containsKey(NovelReaderSettings.storageKey), isFalse);
    },
  );

  test('content width defaults safely and clamps invalid values', () {
    expect(NovelReaderSettings.fromJson(const {}).contentWidth, 720);
    for (final value in [null, 'wide', [], {}]) {
      expect(
        NovelReaderSettings.fromJson({'contentWidth': value}).contentWidth,
        720,
      );
    }
    const defaults = NovelReaderSettings();
    for (final (value, expected) in [
      (0.0, 320.0),
      (320.0, 320.0),
      (960.0, 960.0),
      (1200.0, 1200.0),
      (2000.0, 1200.0),
      (double.nan, 720.0),
      (double.negativeInfinity, 320.0),
      (double.infinity, 1200.0),
    ]) {
      final settings = NovelReaderSettings(contentWidth: value);
      expect(settings.contentWidth, expected);
      expect(defaults.copyWith(contentWidth: value).contentWidth, expected);
      expect(NovelReaderSettings.fromJson(settings.toJson()), settings);
    }
    expect(defaults.contentWidth, 720);
    const wide = NovelReaderSettings(contentWidth: 960);
    expect(wide, isNot(defaults));
    expect(wide.hashCode, isNot(defaults.hashCode));
    expect(wide.copyWith(contentWidth: 720), defaults);
  });

  test('content width survives copies and recreated prefs instances', () async {
    for (final width in [320.0, 720.0, 960.0, 1200.0]) {
      final settings = NovelReaderSettings(contentWidth: width)
          .copyWith(fontSize: 24, mode: NovelReaderMode.paged)
          .upsertCustomTheme(const NovelReaderCustomTheme(id: 'c1', name: '米黄'))
          .removeCustomTheme('c1');
      expect(settings.contentWidth, width);
      expect(settings.toJson()['contentWidth'], width);
      await settings.save();
      SharedPreferences.setMockInitialValues({
        for (final key in prefs.getKeys())
          if (prefs.get(key) case final Object value) key: value,
      });
      prefs = await SharedPreferences.getInstance();
      final restored = await NovelReaderSettings.load();
      expect(restored.contentWidth, width);
      expect(restored, settings);
      expect(restored.hashCode, settings.hashCode);
      expect(prefs.get('reader_mode'), 1);
      expect(prefs.get('novel_reading_history_book'), 'untouched history');
    }
  });

  test('page mode, instant turn and volume key round-trip', () {
    const settings = NovelReaderSettings(
      mode: NovelReaderMode.paged,
      instantPageTurn: true,
      volumeKey: false,
    );
    expect(settings.mode, NovelReaderMode.paged);
    expect(NovelReaderSettings.fromJson(settings.toJson()), settings);
    expect(settings.toJson()['mode'], 'paged');
    expect(settings.toJson()['instantPageTurn'], isTrue);
    expect(settings.toJson()['volumeKey'], isFalse);
    final copied = settings.copyWith(
      mode: NovelReaderMode.scroll,
      instantPageTurn: false,
      volumeKey: true,
    );
    expect(copied.mode, NovelReaderMode.scroll);
    expect(copied.instantPageTurn, isFalse);
    expect(copied.volumeKey, isTrue);
    expect(settings.mode, NovelReaderMode.paged);
    expect(settings.instantPageTurn, isTrue);
    expect(settings.volumeKey, isFalse);
  });

  test('entering paged mode disables focus but permits manual re-enabling', () {
    const scrolling = NovelReaderSettings(focusModeEnabled: true);
    final paged = scrolling.copyWith(mode: NovelReaderMode.paged);
    expect(paged.mode, NovelReaderMode.paged);
    expect(paged.focusModeEnabled, isFalse);
    final enabled = paged.copyWith(focusModeEnabled: true);
    expect(enabled.focusModeEnabled, isTrue);
    expect(enabled.copyWith(fontSize: 24).focusModeEnabled, isTrue);
    expect(
      enabled.copyWith(mode: NovelReaderMode.paged).focusModeEnabled,
      isTrue,
    );
    expect(NovelReaderSettings.fromJson(enabled.toJson()), enabled);
    expect(
      enabled
          .copyWith(mode: NovelReaderMode.scroll)
          .copyWith(mode: NovelReaderMode.paged)
          .focusModeEnabled,
      isFalse,
    );
  });

  test('ignore blank paragraphs round-trips and falls back for old data', () {
    for (final value in [true, false]) {
      final settings = NovelReaderSettings(ignoreBlankParagraphs: value);
      expect(settings.toJson()['ignoreBlankParagraphs'], value);
      expect(NovelReaderSettings.fromJson(settings.toJson()), settings);
      expect(settings.copyWith().ignoreBlankParagraphs, value);
      expect(
        settings.copyWith(ignoreBlankParagraphs: !value).ignoreBlankParagraphs,
        !value,
      );
      expect(settings.ignoreBlankParagraphs, value);
    }
    // 旧记录没有该键：回退默认（保留空行），而不是擅自隐藏。
    expect(
      NovelReaderSettings.fromJson(const {}).ignoreBlankParagraphs,
      isFalse,
    );
  });

  test('realistic page turn persists and survives unrelated copies', () async {
    for (final realistic in [true, false]) {
      final settings = NovelReaderSettings(
        mode: NovelReaderMode.paged,
        realisticPageTurn: realistic,
        instantPageTurn: true,
      );
      expect(settings.toJson()['realisticPageTurn'], realistic);
      expect(NovelReaderSettings.fromJson(settings.toJson()), settings);
      expect(settings.copyWith().realisticPageTurn, realistic);
      final copied = settings
          .copyWith(fontSize: 24, mode: NovelReaderMode.scroll)
          .upsertCustomTheme(const NovelReaderCustomTheme(id: 'c1', name: '米黄'))
          .removeCustomTheme('c1');
      expect(copied.realisticPageTurn, realistic);
      expect(copied.instantPageTurn, isTrue);
      expect(
        settings.copyWith(realisticPageTurn: !realistic).realisticPageTurn,
        !realistic,
      );
      expect(settings.realisticPageTurn, realistic);

      await settings.save();
      // 使用默认 prefs 后端，重建实例后仍能恢复显式 false。
      SharedPreferences.setMockInitialValues({
        for (final key in prefs.getKeys())
          if (prefs.get(key) case final Object value) key: value,
      });
      prefs = await SharedPreferences.getInstance();
      final restored = await NovelReaderSettings.load();
      expect(restored.realisticPageTurn, realistic);
      expect(restored.instantPageTurn, isTrue);
      expect(restored, settings);
      expect(restored.hashCode, settings.hashCode);
    }
  });

  test('realistic page turn only accepts JSON booleans', () {
    for (final value in [null, 0, 1, 'true', 'false', [], {}]) {
      expect(
        NovelReaderSettings.fromJson({
          'realisticPageTurn': value,
        }).realisticPageTurn,
        isTrue,
        reason: 'invalid value: $value',
      );
    }
  });

  test('realistic page turn participates in equality and hashCode', () {
    const enabled = NovelReaderSettings();
    const disabled = NovelReaderSettings(realisticPageTurn: false);
    expect(enabled == disabled, isFalse);
    expect(enabled.hashCode == disabled.hashCode, isFalse);
    expect(disabled.copyWith(realisticPageTurn: true), enabled);
  });

  test('unknown reading mode and malformed toggles fall back safely', () {
    final unknown = NovelReaderSettings.fromJson(const {
      'mode': 'curl',
      'realisticPageTurn': 'false',
      'instantPageTurn': 'yes',
      'volumeKey': 1,
    });
    expect(unknown.mode, NovelReaderMode.scroll);
    expect(unknown.realisticPageTurn, isTrue);
    expect(unknown.instantPageTurn, isFalse);
    expect(unknown.volumeKey, isTrue);
    final legacy = NovelReaderSettings.fromJson(const {'fontSize': 22});
    expect(legacy.mode, NovelReaderMode.scroll);
    expect(legacy.realisticPageTurn, isTrue);
    expect(legacy.instantPageTurn, isFalse);
    expect(legacy.volumeKey, isTrue);
  });

  test('reading mode participates in equality and hashCode', () {
    const scroll = NovelReaderSettings();
    const paged = NovelReaderSettings(mode: NovelReaderMode.paged);
    expect(scroll == paged, isFalse);
    expect(scroll.hashCode == paged.hashCode, isFalse);
    expect(paged.copyWith(mode: NovelReaderMode.scroll) == scroll, isTrue);
  });

  test('named themes, bindings, and false keepScreenOn round-trip', () async {
    const custom = NovelReaderCustomTheme(
      id: 'custom-1',
      name: '夜航',
      backgroundColor: 0xFF182331,
      textColor: 0xFFE8DFC7,
    );
    final settings = const NovelReaderSettings(
      fontSize: 25,
      lineHeight: 1.05,
      paragraphSpacing: 3,
      lightThemeId: 'paper',
      darkThemeId: 'custom-1',
      keepScreenOn: false,
    ).upsertCustomTheme(custom);
    expect(NovelReaderSettings.fromJson(settings.toJson()), settings);
    await settings.save(prefs: Future.value(prefs));
    final restored = await NovelReaderSettings.load(prefs: Future.value(prefs));
    expect(restored, settings);
    expect(restored.hashCode, settings.hashCode);
    expect(
      jsonDecode(prefs.getString(NovelReaderSettings.storageKey)!),
      settings.toJson(),
    );
  });

  test(
    'default persistence uses shared MockPrefs and touches only its key',
    () async {
      final settings = const NovelReaderSettings(
        fontSize: 24,
      ).upsertCustomTheme(const NovelReaderCustomTheme(id: 'c9', name: '米黄'));
      await settings.save();
      expect(await NovelReaderSettings.load(), settings);
      expect(NovelReaderSettings.storageKey, 'reader_novel_settings_v1');
      expect(prefs.get('reader_mode'), 1);
      expect(prefs.get('theme_mode'), 'system');
      expect(prefs.get('novel_reading_history_book'), 'untouched history');
      expect(prefs.getKeys(), {
        'reader_mode',
        'theme_mode',
        'novel_reading_history_book',
        NovelReaderSettings.storageKey,
      });
    },
  );

  test(
    'constructor and copyWith clamp values without modifying the original',
    () {
      const original = NovelReaderSettings(
        darkThemeId: 'green',
        keepScreenOn: false,
      );
      final lower = original.copyWith(
        fontSize: 1,
        lineHeight: 0.1,
        paragraphSpacing: -9,
      );
      expect(lower.fontSize, 10);
      expect(lower.lineHeight, 1.0);
      expect(lower.paragraphSpacing, 0);
      expect(lower.darkThemeId, 'green');
      expect(lower.keepScreenOn, isFalse);
      const upper = NovelReaderSettings(
        fontSize: 100,
        lineHeight: 4,
        paragraphSpacing: 1000,
      );
      expect(upper.fontSize, 48);
      expect(upper.lineHeight, 3.0);
      expect(upper.paragraphSpacing, 64);
      expect(original.fontSize, 20);
      expect(original.copyWith(), original);
      expect(original.copyWith(keepScreenOn: true).keepScreenOn, isTrue);
    },
  );

  test('valid range endpoints and fractional settings are retained', () {
    const min = NovelReaderSettings(
      fontSize: 10,
      lineHeight: 1.0,
      paragraphSpacing: 0,
    );
    const max = NovelReaderSettings(
      fontSize: 48,
      lineHeight: 3.0,
      paragraphSpacing: 64,
    );
    const fractional = NovelReaderSettings(
      fontSize: 20.5,
      lineHeight: 1.05,
      paragraphSpacing: 16.25,
    );
    for (final settings in [min, max, fractional]) {
      expect(NovelReaderSettings.fromJson(settings.toJson()), settings);
    }
    expect(fractional.fontSize, 20.5);
    expect(fractional.lineHeight, 1.05);
    expect(fractional.paragraphSpacing, 16.25);
  });

  test('light and dark bindings stay independent', () {
    const settings = NovelReaderSettings(
      lightThemeId: 'green',
      darkThemeId: 'paper',
    );
    final lightOnly = settings.copyWith(lightThemeId: 'white');
    expect(lightOnly.darkThemeId, 'paper');
    final darkOnly = settings.copyWith(darkThemeId: 'dark');
    expect(darkOnly.lightThemeId, 'green');
  });

  test('unknown or deleted theme ids fall back per mode', () {
    const settings = NovelReaderSettings(
      lightThemeId: 'missing',
      darkThemeId: 'paper',
    );
    expect(settings.themeIdFor(dark: false), 'white');
    expect(settings.themeIdFor(dark: true), 'paper');
    final removed = settings
        .upsertCustomTheme(const NovelReaderCustomTheme(id: 'gone', name: '临时'))
        .copyWith(darkThemeId: 'gone')
        .removeCustomTheme('gone');
    expect(removed.themeIdFor(dark: true), 'gray');
  });

  test(
    'rename keeps both bindings, upsert replaces by id, remove drops only one',
    () {
      const a = NovelReaderCustomTheme(id: 'a', name: 'A');
      const b = NovelReaderCustomTheme(id: 'b', name: 'B');
      final base = const NovelReaderSettings()
          .upsertCustomTheme(a)
          .upsertCustomTheme(b);
      final bound = base.copyWith(lightThemeId: 'a', darkThemeId: 'b');
      final renamed = bound.upsertCustomTheme(
        const NovelReaderCustomTheme(id: 'a', name: '甲'),
      );
      expect(renamed.customThemes.map((t) => '${t.id}:${t.name}'), [
        'b:B',
        'a:甲',
      ]);
      expect(renamed.lightThemeId, 'a');
      expect(renamed.darkThemeId, 'b');
      final removedA = renamed.removeCustomTheme('a');
      expect(removedA.customThemes.single.id, 'b');
      // 绑定保留原 ID，展示时由 themeIdFor 兜底回退。
      expect(removedA.themeIdFor(dark: false), 'white');
      expect(removedA.darkThemeId, 'b');
    },
  );

  test('invalid custom theme entries are dropped on load', () async {
    await prefs.setString(
      NovelReaderSettings.storageKey,
      jsonEncode({
        'fontSize': 22,
        'customThemes': [
          {'id': '', 'name': '无 id'},
          {'id': 'ok', 'name': ''},
          {
            'id': 'ok',
            'name': '有效',
            'backgroundColor': 0xFF101820,
            'textColor': 0xFFEAE7DC,
          },
          {'id': 'ok', 'name': '重复'},
          'not-a-map',
        ],
      }),
    );
    final settings = await NovelReaderSettings.load(prefs: Future.value(prefs));
    expect(settings.customThemes, hasLength(1));
    expect(settings.customThemes.single.id, 'ok');
    expect(settings.customThemes.single.name, '有效');
  });

  test(
    'legacy single custom colors migrate into a named theme and both bindings',
    () async {
      await prefs.setString(
        NovelReaderSettings.storageKey,
        jsonEncode({
          'fontSize': 30,
          'theme': 'custom',
          'customBackgroundColor': 0xFF182331,
          'customTextColor': 0xFFE8DFC7,
          'keepScreenOn': false,
        }),
      );
      final settings = await NovelReaderSettings.load(
        prefs: Future.value(prefs),
      );
      expect(settings.fontSize, 30);
      expect(settings.customThemes, hasLength(1));
      expect(
        settings.customThemes.single.id,
        NovelReaderSettings.legacyCustomThemeId,
      );
      expect(settings.customThemes.single.backgroundColor, 0xFF182331);
      expect(settings.customThemes.single.textColor, 0xFFE8DFC7);
      expect(settings.lightThemeId, NovelReaderSettings.legacyCustomThemeId);
      expect(settings.darkThemeId, NovelReaderSettings.legacyCustomThemeId);
      expect(settings.keepScreenOn, isFalse);
    },
  );

  test('legacy preset theme seeds both bindings', () async {
    await prefs.setString(
      NovelReaderSettings.storageKey,
      jsonEncode({'theme': 'green'}),
    );
    final settings = await NovelReaderSettings.load(prefs: Future.value(prefs));
    expect(settings.lightThemeId, 'green');
    expect(settings.darkThemeId, 'green');
    expect(settings.customThemes, isEmpty);
  });

  test(
    'legacy settings load new defaults without rewriting saved values',
    () async {
      final legacy = {
        'fontSize': 31.5,
        'lineHeight': 2.0,
        'paragraphSpacing': 20,
        'theme': 'paper',
        'keepScreenOn': false,
      };
      final raw = jsonEncode(legacy);
      await prefs.setString(NovelReaderSettings.storageKey, raw);
      final settings = await NovelReaderSettings.load(
        prefs: Future.value(prefs),
      );
      expect(settings.fontSize, 31.5);
      expect(settings.lineHeight, 2);
      expect(settings.paragraphSpacing, 20);
      expect(settings.lightThemeId, 'paper');
      expect(settings.darkThemeId, 'paper');
      expect(settings.keepScreenOn, isFalse);
      expect(settings.realisticPageTurn, isTrue);
      expect(prefs.getString(NovelReaderSettings.storageKey), raw);
    },
  );

  test('palette resolves by system brightness, not the app theme', () {
    const settings = NovelReaderSettings(lightThemeId: 'paper');
    final light = NovelReaderPalette.resolve(settings, Brightness.light);
    expect(
      light.background,
      const Color(NovelReaderSettings.defaultCustomBackgroundColor),
    );
    final dark = NovelReaderPalette.resolve(settings, Brightness.dark);
    // 深色模式默认绑定为内置「灰」主题（#222222）。
    expect(dark.background, const Color(0xFF222222));
    // 改浅色绑定为 white：浅色模式即用白底（深色绑定不受影响）。
    final lightWhite = NovelReaderPalette.resolve(
      settings.copyWith(lightThemeId: 'white'),
      Brightness.light,
    );
    expect(lightWhite.background, const Color(0xFFFFFFFF));
  });

  test('custom palette colors and brightness derivation', () {
    final settings =
        const NovelReaderSettings(
              lightThemeId: 'custom-1',
              darkThemeId: 'custom-2',
            )
            .upsertCustomTheme(
              const NovelReaderCustomTheme(
                id: 'custom-1',
                name: '米色',
                backgroundColor: 0xFFF5F5E8,
                textColor: 0xFF202020,
              ),
            )
            .upsertCustomTheme(
              const NovelReaderCustomTheme(
                id: 'custom-2',
                name: '夜航',
                backgroundColor: 0xFF152337,
                textColor: 0xFFE8DDBA,
              ),
            );
    final light = NovelReaderPalette.resolve(settings, Brightness.light);
    expect(light.background, const Color(0xFFF5F5E8));
    expect(light.foreground, const Color(0xFF202020));
    expect(light.applyTo(ThemeData()).brightness, Brightness.light);
    final dark = NovelReaderPalette.resolve(settings, Brightness.dark);
    expect(dark.background, const Color(0xFF152337));
    expect(dark.applyTo(ThemeData()).brightness, Brightness.dark);
    expect(
      dark.applyTo(ThemeData()).textTheme.bodyLarge?.color,
      const Color(0xFFE8DDBA),
    );
  });

  test(
    'fromJson supports partial data and safely parses malformed field types',
    () {
      expect(
        NovelReaderSettings.fromJson(const {}),
        const NovelReaderSettings(),
      );
      final malformed = NovelReaderSettings.fromJson(const {
        'fontSize': '24.5',
        'lineHeight': [],
        'paragraphSpacing': {'unexpected': true},
        'lightThemeId': 9,
        'keepScreenOn': 'false',
      });
      expect(malformed.fontSize, 24.5);
      expect(malformed.lineHeight, 1.8);
      expect(malformed.paragraphSpacing, 16);
      expect(malformed.lightThemeId, '9');
      expect(
        malformed.themeIdFor(dark: false),
        NovelReaderSettings.defaultLightThemeId,
      );
      expect(malformed.keepScreenOn, isTrue);
      final clamped = NovelReaderSettings.fromJson(const {
        'fontSize': '-100',
        'lineHeight': 9000,
        'paragraphSpacing': -500,
      });
      expect(clamped.fontSize, 10);
      expect(clamped.lineHeight, 3.0);
      expect(clamped.paragraphSpacing, 0);
    },
  );

  test('NaN uses defaults and infinite values cannot escape valid ranges', () {
    const nan = NovelReaderSettings(
      fontSize: double.nan,
      lineHeight: double.nan,
      paragraphSpacing: double.nan,
    );
    expect(nan, const NovelReaderSettings());
    for (final value in [
      double.infinity,
      double.negativeInfinity,
      double.nan,
    ]) {
      final settings = NovelReaderSettings.fromJson({
        'fontSize': value,
        'lineHeight': value,
        'paragraphSpacing': value,
      });
      expect(settings.fontSize, inInclusiveRange(10, 48));
      expect(settings.lineHeight, inInclusiveRange(1.0, 3.0));
      expect(settings.paragraphSpacing, inInclusiveRange(0, 64));
      expect(() => jsonEncode(settings.toJson()), returnsNormally);
    }
  });

  test('focus mode fields round-trip, clamp, and fall back for old data', () {
    const custom = NovelReaderSettings(
      focusModeEnabled: true,
      focusTopRatio: 0.1,
      focusBottomRatio: 0.9,
      focusOpacity: 0.8,
    );
    expect(custom.toJson()['focusModeEnabled'], isTrue);
    expect(custom.toJson()['focusTopRatio'], 0.1);
    expect(custom.toJson()['focusBottomRatio'], 0.9);
    expect(custom.toJson()['focusOpacity'], 0.8);
    expect(NovelReaderSettings.fromJson(custom.toJson()), custom);
    // 越界与非法值安全回退，交叉边界仍保持至少 10% 间距。
    const over = NovelReaderSettings(
      focusTopRatio: 0.8,
      focusBottomRatio: 0.3,
      focusOpacity: 2,
    );
    expect(over.focusTopRatio, 0.8);
    expect(over.focusBottomRatio, closeTo(0.9, 1e-12));
    expect(over.focusOpacity, 0.9);
    const under = NovelReaderSettings(
      focusTopRatio: -1,
      focusBottomRatio: 0.1,
      focusOpacity: -3,
    );
    expect(under.focusTopRatio, 0);
    expect(under.focusBottomRatio, 0.1);
    expect(under.focusOpacity, 0.1);
    const nan = NovelReaderSettings(
      focusTopRatio: double.nan,
      focusBottomRatio: double.nan,
      focusOpacity: double.nan,
    );
    expect(nan.focusTopRatio, 0.2);
    expect(nan.focusBottomRatio, 0.55);
    expect(nan.focusOpacity, 0.5);
    // 旧记录无键：默认关闭 + 默认区域。
    final legacy = NovelReaderSettings.fromJson(const {});
    expect(legacy.focusModeEnabled, isFalse);
    expect(legacy.focusTopRatio, 0.2);
    expect(legacy.focusBottomRatio, 0.55);
    expect(legacy.focusOpacity, 0.5);
    // copyWith 保留原值、定向改写。
    expect(custom.copyWith().focusTopRatio, 0.1);
    expect(custom.copyWith(focusOpacity: 0.3).focusOpacity, 0.3);
    expect(custom.copyWith(focusOpacity: 0.3).focusTopRatio, 0.1);
    expect(custom.copyWith(focusModeEnabled: false).focusModeEnabled, isFalse);
    // 参与相等与 hashCode：仅一个字段不同即不相等。
    const base = NovelReaderSettings();
    for (final changed in [
      const NovelReaderSettings(focusModeEnabled: true),
      const NovelReaderSettings(focusTopRatio: 0.3),
      const NovelReaderSettings(focusBottomRatio: 0.8),
      const NovelReaderSettings(focusOpacity: 0.6),
    ]) {
      expect(base == changed, isFalse, reason: '$changed');
      expect(base.hashCode == changed.hashCode, isFalse);
    }
    // 主题 copyWith 路径（_withThemes 转发）不丢专注字段。
    final themed = custom.upsertCustomTheme(
      const NovelReaderCustomTheme(id: 'f1', name: '灰蓝'),
    );
    expect(themed.focusModeEnabled, isTrue);
    expect(themed.focusTopRatio, 0.1);
    expect(themed.focusBottomRatio, 0.9);
    expect(themed.focusOpacity, 0.8);
    expect(themed.removeCustomTheme('f1'), custom);
  });

  test('focus status visibility defaults off and preserves other settings', () {
    const defaults = NovelReaderSettings();
    expect(defaults.focusKeepStatusVisible, isFalse);
    expect(defaults.toJson()['focusKeepStatusVisible'], isFalse);
    expect(
      NovelReaderSettings.fromJson(const {}).focusKeepStatusVisible,
      isFalse,
    );
    expect(
      NovelReaderSettings.fromJson(const {
        'focusKeepStatusVisible': [],
      }).focusKeepStatusVisible,
      isFalse,
    );
    final enabled = defaults.copyWith(focusKeepStatusVisible: true);
    expect(enabled.focusKeepStatusVisible, isTrue);
    expect(enabled.focusModeEnabled, isFalse);
    expect(enabled.toJson()['focusKeepStatusVisible'], isTrue);
    expect(NovelReaderSettings.fromJson(enabled.toJson()), enabled);
    expect(enabled, isNot(defaults));
    expect(enabled.hashCode, isNot(defaults.hashCode));
    expect(enabled.copyWith(fontSize: 24).focusKeepStatusVisible, isTrue);
    expect(
      enabled.copyWith(mode: NovelReaderMode.paged).focusKeepStatusVisible,
      isTrue,
    );
    expect(
      enabled.copyWith(focusModeEnabled: false).focusKeepStatusVisible,
      isTrue,
    );
    expect(enabled.copyWith(focusKeepStatusVisible: false), defaults);
    final themed = enabled.upsertCustomTheme(
      const NovelReaderCustomTheme(id: 'focus', name: '专注'),
    );
    expect(themed.focusKeepStatusVisible, isTrue);
    expect(themed.removeCustomTheme('focus'), enabled);
  });

  test('focus status visibility persists across recreated prefs', () async {
    for (final value in [true, false]) {
      final settings = NovelReaderSettings(
        focusModeEnabled: true,
        focusKeepStatusVisible: value,
      );
      await settings.save();
      SharedPreferences.setMockInitialValues({
        for (final key in prefs.getKeys())
          if (prefs.get(key) case final Object value) key: value,
      });
      prefs = await SharedPreferences.getInstance();
      expect(await NovelReaderSettings.load(), settings);
    }
  });

  test('focus bounds keep the minimum gap across the full ranges', () {
    for (final top in [-1.0, 0.0, 0.45, 0.9, 2.0, double.nan]) {
      for (final bottom in [-1.0, 0.1, 0.55, 1.0, 2.0, double.nan]) {
        final settings = NovelReaderSettings(
          focusTopRatio: top,
          focusBottomRatio: bottom,
        );
        expect(settings.focusTopRatio, inInclusiveRange(0.0, 0.9));
        expect(settings.focusBottomRatio, inInclusiveRange(0.1, 1.0));
        expect(
          settings.focusBottomRatio,
          greaterThanOrEqualTo(settings.focusTopRatio + 0.1),
        );
        expect(settings.copyWith(), settings);
        expect(NovelReaderSettings.fromJson(settings.toJson()), settings);
      }
    }
    final raised = const NovelReaderSettings().copyWith(focusTopRatio: 0.9);
    expect(raised.focusTopRatio, 0.9);
    expect(raised.focusBottomRatio, 1.0);
    final lowered = raised.copyWith(focusBottomRatio: 0.1);
    expect(lowered.focusTopRatio, 0.0);
    expect(lowered.focusBottomRatio, 0.1);
  });

  test(
    'focus boundaries persist beyond the old limits after recreation',
    () async {
      for (final settings in [
        const NovelReaderSettings(
          focusModeEnabled: true,
        ).copyWith(focusTopRatio: 0.9),
        const NovelReaderSettings(
          focusModeEnabled: true,
        ).copyWith(focusBottomRatio: 0.1),
      ]) {
        await settings.save();
        SharedPreferences.setMockInitialValues({
          for (final key in prefs.getKeys())
            if (prefs.get(key) case final Object value) key: value,
        });
        prefs = await SharedPreferences.getInstance();
        expect(await NovelReaderSettings.load(), settings);
      }
    },
  );

  test(
    'corrupt JSON and wrong root types load defaults without rewriting prefs',
    () async {
      for (final raw in ['{', '[]', 'null', '7', '"text"']) {
        await prefs.setString(NovelReaderSettings.storageKey, raw);
        expect(
          await NovelReaderSettings.load(prefs: Future.value(prefs)),
          const NovelReaderSettings(),
        );
        expect(prefs.get(NovelReaderSettings.storageKey), raw);
      }
      await prefs.setBool(NovelReaderSettings.storageKey, true);
      expect(
        await NovelReaderSettings.load(prefs: Future.value(prefs)),
        const NovelReaderSettings(),
      );
      expect(prefs.get(NovelReaderSettings.storageKey), isTrue);
    },
  );

  test(
    'external restoration and removal are visible on the next load',
    () async {
      const original = NovelReaderSettings(fontSize: 24);
      await original.save(prefs: Future.value(prefs));
      expect(
        await NovelReaderSettings.load(prefs: Future.value(prefs)),
        original,
      );
      const restored = NovelReaderSettings(fontSize: 29, darkThemeId: 'green');
      await prefs.setString(
        NovelReaderSettings.storageKey,
        jsonEncode(restored.toJson()),
      );
      expect(
        await NovelReaderSettings.load(prefs: Future.value(prefs)),
        restored,
      );
      await prefs.remove(NovelReaderSettings.storageKey);
      expect(
        await NovelReaderSettings.load(prefs: Future.value(prefs)),
        const NovelReaderSettings(),
      );
    },
  );

  test(
    'rapid saves and a following load remain ordered with delayed prefs',
    () async {
      final delayed = Completer<SharedPreferences>();
      final first = const NovelReaderSettings(
        fontSize: 21,
      ).save(prefs: delayed.future);
      const latest = NovelReaderSettings(fontSize: 28);
      final second = latest.save(prefs: Future.value(prefs));
      final reading = NovelReaderSettings.load(prefs: Future.value(prefs));
      await Future<void>.delayed(Duration.zero);
      expect(prefs.containsKey(NovelReaderSettings.storageKey), isFalse);
      delayed.complete(prefs);
      await Future.wait([first, second]);
      expect(await reading, latest);
    },
  );

  test(
    'a failed save is reported but subsequent save and load still succeed',
    () async {
      final failure = Completer<SharedPreferences>();
      final saving = const NovelReaderSettings().save(prefs: failure.future);
      final expectation = expectLater(saving, throwsStateError);
      failure.completeError(StateError('MockPrefs unavailable'));
      await expectation;
      const settings = NovelReaderSettings(lightThemeId: 'paper');
      await settings.save(prefs: Future.value(prefs));
      expect(
        await NovelReaderSettings.load(prefs: Future.value(prefs)),
        settings,
      );
    },
  );
}
