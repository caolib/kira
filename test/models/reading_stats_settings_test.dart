import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/reader_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../account_storage_test_support.dart';

const _prefix = 'reader_reading_stats_';
const _defaultOrder = ['overview', 'tags', 'activity'];
const _customOrder = ['activity', 'tags', 'overview'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final settings = ReaderSettings();
  late AccountPreferencesPlatform platform;
  late SharedPreferences prefs;

  setUp(() async {
    platform = AccountPreferencesPlatform()..install();
    settings.resetPrefsCache();
    prefs = await SharedPreferences.getInstance();
    await settings.initFromPrefs(prefs);
  });

  tearDown(() {
    settings.resetPrefsCache();
    platform.dispose();
  });

  Future<void> reload({bool recreate = false}) async {
    if (recreate) {
      SharedPreferences.resetStatic();
      settings.resetPrefsCache();
      prefs = await SharedPreferences.getInstance();
    } else {
      await prefs.reload();
    }
    await ReaderSettings().initFromPrefs(prefs);
  }

  test('missing keys use independent defaults without writes', () async {
    expect(settings.readingStatsEnabled, isFalse);
    expect(settings.readingStatsShowComics, isTrue);
    expect(settings.readingStatsShowNovels, isTrue);
    expect(settings.novelReadingStatsChartStyle, 0);
    expect(settings.novelReadingStatsShowOverview, isTrue);
    expect(settings.novelReadingStatsShowTags, isTrue);
    expect(settings.novelReadingStatsShowActivityChart, isTrue);
    expect(settings.novelReadingStatsSectionOrder, _defaultOrder);
    await reload(recreate: true);
    expect(platform.operations, isEmpty);
    expect(platform.values, isEmpty);
  });

  test(
    'novel defaults and setters never inherit or overwrite comic settings',
    () async {
      await settings.setReadingStatsEnabled(true);
      await settings.setReadingStatsChartStyle(1);
      await settings.setReadingStatsShowOverview(false);
      await settings.setReadingStatsShowTags(false);
      await settings.setReadingStatsShowActivityChart(false);
      await settings.setReadingStatsSectionOrder(_customOrder);
      final comicValues = Map.of(platform.values);
      await reload(recreate: true);
      expect(settings.novelReadingStatsChartStyle, 0);
      expect(settings.novelReadingStatsShowOverview, isTrue);
      expect(settings.novelReadingStatsShowTags, isTrue);
      expect(settings.novelReadingStatsShowActivityChart, isTrue);
      expect(settings.novelReadingStatsSectionOrder, _defaultOrder);

      await settings.setReadingStatsShowComics(false);
      await settings.setNovelReadingStatsChartStyle(1);
      await settings.setNovelReadingStatsShowOverview(false);
      await settings.setNovelReadingStatsShowTags(false);
      await settings.setNovelReadingStatsShowActivityChart(false);
      await settings.setNovelReadingStatsSectionOrder(['tags']);
      for (final entry in comicValues.entries) {
        expect(platform.values[entry.key], entry.value, reason: entry.key);
      }
      for (var boot = 0; boot < 2; boot++) {
        await reload(recreate: true);
        expect(settings.readingStatsEnabled, isTrue);
        expect(settings.readingStatsChartStyle, 1);
        expect(settings.readingStatsShowOverview, isFalse);
        expect(settings.readingStatsShowTags, isFalse);
        expect(settings.readingStatsShowActivityChart, isFalse);
        expect(settings.readingStatsSectionOrder, _customOrder);
        expect(settings.readingStatsShowComics, isFalse);
        expect(settings.readingStatsShowNovels, isTrue);
        expect(settings.novelReadingStatsSectionOrder, [
          'tags',
          'overview',
          'activity',
        ]);
      }
    },
  );

  for (final hideComicsFirst in [true, false]) {
    for (final enabled in [true, false]) {
      test('reject last hidden category (comics first: $hideComicsFirst, '
          'recording: $enabled)', () async {
        await settings.setReadingStatsEnabled(enabled);
        var notifications = 0;
        void listener() => notifications++;
        settings.addListener(listener);
        addTearDown(() => settings.removeListener(listener));
        final hideFirst = hideComicsFirst
            ? settings.setReadingStatsShowComics
            : settings.setReadingStatsShowNovels;
        final hideLast = hideComicsFirst
            ? settings.setReadingStatsShowNovels
            : settings.setReadingStatsShowComics;
        await hideFirst(false);
        final saved = Map.of(platform.values);
        final writes = platform.operations.length;
        await hideLast(false);
        await hideLast(false);
        expect(settings.readingStatsShowComics, !hideComicsFirst);
        expect(settings.readingStatsShowNovels, hideComicsFirst);
        expect(settings.readingStatsEnabled, enabled);
        expect(notifications, 1);
        expect(platform.values, saved);
        expect(platform.operations, hasLength(writes));
        await reload(recreate: true);
        expect(settings.readingStatsShowComics, !hideComicsFirst);
        expect(settings.readingStatsShowNovels, hideComicsFirst);
        expect(settings.readingStatsEnabled, enabled);
      });
    }
  }

  test(
    'concurrent closes keep one category and do not switch the hidden one',
    () async {
      await Future.wait([
        settings.setReadingStatsShowComics(false),
        settings.setReadingStatsShowNovels(false),
      ]);
      expect(settings.readingStatsShowComics, isFalse);
      expect(settings.readingStatsShowNovels, isTrue);
      expect(platform.operations, hasLength(1));
      await settings.setReadingStatsShowComics(true);
      await Future.wait([
        settings.setReadingStatsShowNovels(false),
        settings.setReadingStatsShowComics(false),
      ]);
      await reload(recreate: true);
      expect(settings.readingStatsShowComics, isTrue);
      expect(settings.readingStatsShowNovels, isFalse);
    },
  );

  test(
    'invalid both-hidden storage falls back without rewriting preferences',
    () async {
      await prefs.setBool('${_prefix}show_comics', false);
      await prefs.setBool('${_prefix}show_novels', false);
      final original = Map.of(platform.values);
      platform.operations.clear();
      for (final recreate in [false, true]) {
        await reload(recreate: recreate);
        expect(settings.readingStatsShowComics, isTrue);
        expect(settings.readingStatsShowNovels, isFalse);
        await settings.setReadingStatsShowComics(false);
        expect(settings.readingStatsShowComics, isTrue);
        expect(settings.readingStatsShowNovels, isFalse);
        expect(platform.values, original);
        expect(platform.operations, isEmpty);
      }
      await settings.setReadingStatsShowNovels(true);
      await settings.setReadingStatsShowComics(false);
      await reload(recreate: true);
      expect(settings.readingStatsShowComics, isFalse);
      expect(settings.readingStatsShowNovels, isTrue);
    },
  );

  test(
    'novel order sanitizes on write/load and owns an immutable copy',
    () async {
      final input = ['unknown', 'activity', 'activity'];
      final pending = settings.setNovelReadingStatsSectionOrder(input);
      input.clear();
      await pending;
      expect(settings.novelReadingStatsSectionOrder, [
        'activity',
        'overview',
        'tags',
      ]);
      expect(
        () => settings.novelReadingStatsSectionOrder.clear(),
        throwsUnsupportedError,
      );
      expect(settings.readingStatsSectionOrder, _defaultOrder);
      await prefs.setStringList('${_prefix}novel_section_order', [
        'unknown',
        'tags',
        'tags',
      ]);
      await reload(recreate: true);
      expect(settings.novelReadingStatsSectionOrder, [
        'tags',
        'overview',
        'activity',
      ]);
      await settings.setNovelReadingStatsSectionOrder([]);
      expect(settings.novelReadingStatsSectionOrder, _defaultOrder);
    },
  );

  final cases =
      <
        ({
          String suffix,
          Object initial,
          Object next,
          Object Function() read,
          Future<void> Function() write,
        })
      >[
        (
          suffix: 'show_comics',
          initial: true,
          next: false,
          read: () => settings.readingStatsShowComics,
          write: () => settings.setReadingStatsShowComics(false),
        ),
        (
          suffix: 'show_novels',
          initial: true,
          next: false,
          read: () => settings.readingStatsShowNovels,
          write: () => settings.setReadingStatsShowNovels(false),
        ),
        (
          suffix: 'novel_chart_style',
          initial: 0,
          next: 1,
          read: () => settings.novelReadingStatsChartStyle,
          write: () => settings.setNovelReadingStatsChartStyle(1),
        ),
        (
          suffix: 'novel_show_overview',
          initial: true,
          next: false,
          read: () => settings.novelReadingStatsShowOverview,
          write: () => settings.setNovelReadingStatsShowOverview(false),
        ),
        (
          suffix: 'novel_show_tags',
          initial: true,
          next: false,
          read: () => settings.novelReadingStatsShowTags,
          write: () => settings.setNovelReadingStatsShowTags(false),
        ),
        (
          suffix: 'novel_show_activity_chart',
          initial: true,
          next: false,
          read: () => settings.novelReadingStatsShowActivityChart,
          write: () => settings.setNovelReadingStatsShowActivityChart(false),
        ),
        (
          suffix: 'novel_section_order',
          initial: _defaultOrder,
          next: _customOrder,
          read: () => settings.novelReadingStatsSectionOrder,
          write: () => settings.setNovelReadingStatsSectionOrder(_customOrder),
        ),
      ];

  for (final item in cases) {
    final key = '$_prefix${item.suffix}';
    test(
      '${item.suffix} changes memory/notifies only after durable success',
      () async {
        final started = Completer<void>();
        final release = Completer<void>();
        addTearDown(() {
          if (!release.isCompleted) release.complete();
        });
        platform.beforeWrite = (_, _) async {
          started.complete();
          await release.future;
        };
        var notifications = 0;
        void listener() {
          notifications++;
          expect(item.read(), item.next);
          expect(platform.values['flutter.$key'], item.next);
        }

        settings.addListener(listener);
        addTearDown(() => settings.removeListener(listener));
        final pending = item.write();
        await started.future;
        expect(item.read(), item.initial);
        expect(notifications, 0);
        expect(platform.values.containsKey('flutter.$key'), isFalse);
        release.complete();
        await pending;
        expect(notifications, 1);
        platform.beforeWrite = null;
        await item.write();
        expect(notifications, 1);
        expect(platform.operations, hasLength(1));
        for (final recreate in [false, true, true]) {
          await reload(recreate: recreate);
          expect(item.read(), item.next);
          expect(prefs.get(key), item.next);
        }
        expect(settings.readingStatsEnabled, isFalse);
        expect(prefs.containsKey('${_prefix}enabled'), isFalse);
      },
    );

    for (final throws in [false, true]) {
      for (final existing in [false, true]) {
        test(
          '${item.suffix} write failure (throws: $throws, existing: $existing) '
          'keeps memory/cache/durable value and allows retry',
          () async {
            if (existing) {
              switch (item.initial) {
                case final bool value:
                  await prefs.setBool(key, value);
                case final int value:
                  await prefs.setInt(key, value);
                case final List<String> value:
                  await prefs.setStringList(key, value);
              }
            }
            final original = Map.of(platform.values);
            platform
              ..failKey = key
              ..throwOnFailure = throws
              ..beforeWrite = (_, value) async {
                // Lists are decoded by the channel; match that exact instance.
                platform.failValue = value;
              };
            var notifications = 0;
            void listener() => notifications++;
            settings.addListener(listener);
            addTearDown(() => settings.removeListener(listener));
            await expectLater(
              item.write(),
              throws ? throwsA(isA<PlatformException>()) : throwsStateError,
            );
            expect(item.read(), item.initial);
            expect(notifications, 0);
            expect(prefs.get(key), existing ? item.initial : null);
            expect(platform.values, original);
            await reload(recreate: true);
            expect(item.read(), item.initial);
            platform.beforeWrite = null;
            await item.write();
            expect(item.read(), item.next);
            expect(notifications, 1);
            await reload(recreate: true);
            expect(item.read(), item.next);
          },
        );
      }
    }
  }
}
