import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/remote_notice.dart';
import 'package:kira/utils/app_logger.dart';
import 'package:kira/utils/app_storage.dart';
import 'package:kira/utils/remote_notice_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _syncStateKey = 'remote_notice_sync_state_v1';

RemoteNotice _notice({
  required String id,
  required String title,
  required String publishedAt,
  String content = 'content',
  RemoteNoticeLevel level = RemoteNoticeLevel.normal,
  bool pinned = false,
}) {
  return RemoteNotice(
    id: id,
    title: title,
    content: content,
    publishedAt: DateTime.parse(publishedAt),
    level: level,
    pinned: pinned,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory logDirectory;

  setUpAll(() async {
    logDirectory = await Directory.systemTemp.createTemp('kira-notice-test-');
    messenger.setMockMethodCallHandler(
      pathChannel,
      (_) async => logDirectory.path,
    );
    SharedPreferences.setMockInitialValues({});
    await AppLogger.instance.init();
  });

  tearDownAll(() async {
    messenger.setMockMethodCallHandler(pathChannel, null);
    await logDirectory.delete(recursive: true);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RemoteNoticeService.unreadActiveCount.value = 0;
  });

  test('uses EdgeOne CDN as the default notice URL', () {
    expect(
      RemoteNoticeService.defaultNoticeUrl,
      'https://cdn.caolib.qzz.io/kira/notices.json',
    );
  });

  test(
    'sync uses only current remote notices without caching content',
    () async {
      final preferences = _MemoryPreferences();
      final remoteNotice = _notice(
        id: 'remote',
        title: '远程新标题',
        publishedAt: '2026-07-03T00:00:00+08:00',
      );
      final remoteOnly = _notice(
        id: 'remote-only',
        title: '远程新增',
        publishedAt: '2026-07-04T00:00:00+08:00',
      );

      final service = RemoteNoticeService(
        dio: _dioReturning({
          'notices': [remoteNotice.toJson(), remoteOnly.toJson()],
        }),
        preferences: preferences,
        noticeUrl: 'https://example.test/notices.json',
      );

      final result = await service.sync();

      expect(result.notices.map((n) => n.id).toSet(), {
        'remote',
        'remote-only',
      });
      expect(
        await preferences.containsKey('remote_notice_history_v1'),
        isFalse,
      );
    },
  );

  test('fetchRemoteNotices bypasses CDN cache', () async {
    RequestOptions? captured;
    final service = RemoteNoticeService(
      dio: _dioReturning({
        'notices': <Object>[],
      }, onRequest: (options) => captured = options),
      preferences: _MemoryPreferences(),
      noticeUrl: 'https://example.test/notices.json?channel=stable',
    );

    await service.fetchRemoteNotices();

    expect(captured?.uri.queryParameters['channel'], 'stable');
    expect(captured?.uri.queryParameters['_t'], isNotEmpty);
    expect(captured?.headers['Cache-Control'], 'no-cache');
    expect(captured?.headers['Pragma'], 'no-cache');
  });

  test('markSeen persists current notice fingerprints', () async {
    final service = RemoteNoticeService(noticeUrl: '');
    final first = _notice(
      id: 'same',
      title: '标题',
      publishedAt: '2026-07-03T00:00:00+08:00',
    );
    final changed = _notice(
      id: 'same',
      title: '标题',
      content: 'changed',
      publishedAt: '2026-07-03T00:00:00+08:00',
    );

    await service.markSeen([first, first]);

    final seenKeys = await service.loadSeenKeys();

    expect(seenKeys, {RemoteNoticeService.seenKeyFor(first)});
    expect(seenKeys, isNot(contains(RemoteNoticeService.seenKeyFor(changed))));
  });

  test(
    'sync prunes seen fingerprints that are not in current remote data',
    () async {
      final preferences = _MemoryPreferences();
      final removed = _notice(
        id: 'removed',
        title: '已删除',
        publishedAt: '2026-07-01T00:00:00+08:00',
      );
      final current = _notice(
        id: 'current',
        title: '当前',
        publishedAt: '2026-07-02T00:00:00+08:00',
      );
      final service = RemoteNoticeService(
        dio: _dioReturning({
          'notices': [current.toJson()],
        }),
        preferences: preferences,
        noticeUrl: 'https://example.test/notices.json',
      );

      await service.markSeen([removed, current]);
      await service.sync();

      expect(await service.loadSeenKeys(), {
        RemoteNoticeService.seenKeyFor(current),
      });
    },
  );

  test(
    'refreshUnreadActiveCount fetches remote notices for unread count',
    () async {
      final preferences = _MemoryPreferences();
      final now = DateTime.now();
      final active = RemoteNotice(
        id: 'active',
        title: 'active',
        content: 'content',
        publishedAt: now,
      );
      final expired = RemoteNotice(
        id: 'expired',
        title: 'expired',
        content: 'content',
        publishedAt: now.subtract(const Duration(days: 2)),
        expiresAt: now.subtract(const Duration(days: 1)),
      );
      final service = RemoteNoticeService(
        dio: _dioReturning({
          'notices': [active.toJson(), expired.toJson()],
        }),
        noticeUrl: 'https://example.test/notices.json',
        preferences: preferences,
      );

      expect(await service.refreshUnreadActiveCount(), 1);
      expect(RemoteNoticeService.unreadActiveCount.value, 1);

      await service.markSeen([active]);
      await service.updateUnreadActiveCount([active, expired]);

      expect(RemoteNoticeService.unreadActiveCount.value, 0);
    },
  );

  group('startup check interval', () {
    final startedAt = DateTime.utc(2026, 11, 6, 9);
    late DateTime now;
    late int requests;
    late Dio dio;
    late bool failRequest;
    late RemoteNotice active;

    RemoteNoticeService createService() => RemoteNoticeService(
      dio: dio,
      now: () => now,
      noticeUrl: 'https://example.test/notices.json',
    );

    setUp(() {
      now = startedAt;
      requests = 0;
      failRequest = false;
      active = RemoteNotice(
        id: 'active',
        title: '通知标题',
        content: '通知正文',
        publishedAt: startedAt,
      );
      dio = _dioReturning(
        {
          'notices': [active.toJson()],
        },
        onRequest: (_) => requests++,
        shouldFail: () => failRequest,
      );
    });

    test(
      'restores unread count across restarts until exactly six hours',
      () async {
        await createService().syncOnStartup();
        expect(requests, 1);
        expect(RemoteNoticeService.unreadActiveCount.value, 1);

        final prefs = await SharedPreferences.getInstance();
        final snapshot = {
          for (final key in prefs.getKeys()) key: prefs.get(key)!,
        };
        expect(jsonDecode(prefs.getString(_syncStateKey)!), {
          'lastSuccessAt': startedAt.millisecondsSinceEpoch,
          'unreadActiveCount': 1,
        });

        for (final elapsed in [
          const Duration(hours: 1),
          const Duration(hours: 5, minutes: 59, seconds: 59),
        ]) {
          SharedPreferences.setMockInitialValues(snapshot);
          RemoteNoticeService.unreadActiveCount.value = 0;
          now = startedAt.add(elapsed);
          await createService().syncOnStartup();
          expect(requests, 1);
          expect(RemoteNoticeService.unreadActiveCount.value, 1);
        }

        now = startedAt.add(const Duration(hours: 6));
        await createService().syncOnStartup();
        expect(requests, 2);
      },
    );

    test('a successful empty response also starts the interval', () async {
      dio = _dioReturning({
        'notices': <Object>[],
      }, onRequest: (_) => requests++);
      await createService().syncOnStartup();
      now = startedAt.add(const Duration(hours: 1));
      await createService().syncOnStartup();
      expect(requests, 1);
      expect(RemoteNoticeService.unreadActiveCount.value, 0);
    });

    test(
      'page loads and manual refresh bypass and reset the interval',
      () async {
        await createService().syncOnStartup();
        for (final hours in [1, 2]) {
          now = startedAt.add(Duration(hours: hours));
          await createService().sync();
        }
        expect(requests, 3);

        now = startedAt.add(const Duration(hours: 6));
        await createService().syncOnStartup();
        expect(requests, 3);

        now = startedAt.add(const Duration(hours: 8));
        await createService().syncOnStartup();
        expect(requests, 4);
      },
    );

    test(
      'failed requests keep the timestamp and restored unread count',
      () async {
        await createService().syncOnStartup();
        final before = await AppStorage.preferences.getString(_syncStateKey);
        now = startedAt.add(const Duration(hours: 6));
        RemoteNoticeService.unreadActiveCount.value = 0;
        failRequest = true;

        await expectLater(
          createService().syncOnStartup(),
          throwsA(isA<DioException>()),
        );
        expect(RemoteNoticeService.unreadActiveCount.value, 1);
        expect(await AppStorage.preferences.getString(_syncStateKey), before);

        failRequest = false;
        await createService().syncOnStartup();
        expect(requests, 3);
      },
    );

    test('failed first startup can retry immediately', () async {
      failRequest = true;
      await expectLater(
        createService().syncOnStartup(),
        throwsA(isA<DioException>()),
      );
      expect(await AppStorage.preferences.containsKey(_syncStateKey), isFalse);

      failRequest = false;
      await createService().syncOnStartup();
      expect(requests, 2);
    });

    test(
      'reading updates persisted unread count without resetting time',
      () async {
        final second = RemoteNotice(
          id: 'second',
          title: '第二条通知',
          content: '内容',
          publishedAt: startedAt,
        );
        dio = _dioReturning({
          'notices': [active.toJson(), second.toJson()],
        }, onRequest: (_) => requests++);
        final service = createService();
        await service.sync();
        now = startedAt.add(const Duration(hours: 1));
        await service.markSeen([active]);
        await service.updateUnreadActiveCount([active, second]);

        RemoteNoticeService.unreadActiveCount.value = 0;
        await createService().syncOnStartup();
        expect(RemoteNoticeService.unreadActiveCount.value, 1);
        expect(requests, 1);

        await service.markSeen([active, second]);
        await service.updateUnreadActiveCount([active, second]);
        RemoteNoticeService.unreadActiveCount.value = 2;
        await createService().syncOnStartup();
        expect(RemoteNoticeService.unreadActiveCount.value, 0);
        expect(requests, 1);

        now = startedAt.add(const Duration(hours: 6));
        await createService().syncOnStartup();
        expect(requests, 2);
        expect(RemoteNoticeService.unreadActiveCount.value, 0);
      },
    );

    test(
      'a future timestamp does not block checks after clock rollback',
      () async {
        await AppStorage.preferences.setJson(_syncStateKey, {
          'lastSuccessAt': startedAt
              .add(const Duration(days: 1))
              .millisecondsSinceEpoch,
          'unreadActiveCount': 1,
        });
        await createService().syncOnStartup();
        expect(requests, 1);
      },
    );

    test('malformed stored state does not block a fresh check', () async {
      await AppStorage.preferences.setString(_syncStateKey, '{broken');
      await createService().syncOnStartup();
      expect(requests, 1);
      expect(RemoteNoticeService.unreadActiveCount.value, 1);
    });

    test('a failed first prefs write leaves startup retryable', () async {
      final platform = _FailingNoticePreferences()..failNextWrite = true;
      SharedPreferencesStorePlatform.instance = platform;
      addTearDown(() => SharedPreferences.setMockInitialValues({}));
      await expectLater(
        createService().syncOnStartup(),
        throwsA(isA<StateError>()),
      );
      expect(await AppStorage.preferences.containsKey(_syncStateKey), isFalse);
      expect(platform.values.containsKey('flutter.$_syncStateKey'), isFalse);

      await createService().syncOnStartup();
      expect(requests, 2);
    });

    for (final throwOnFailure in [false, true]) {
      test(
        'failed prefs writes roll back the timestamp (throws: $throwOnFailure)',
        () async {
          final platform = _FailingNoticePreferences();
          SharedPreferencesStorePlatform.instance = platform;
          addTearDown(() => SharedPreferences.setMockInitialValues({}));
          await createService().syncOnStartup();
          final before = await AppStorage.preferences.getString(_syncStateKey);
          now = startedAt.add(const Duration(hours: 6));
          platform
            ..throwOnFailure = throwOnFailure
            ..failNextWrite = true;

          await expectLater(
            createService().syncOnStartup(),
            throwsA(isA<StateError>()),
          );
          expect(await AppStorage.preferences.getString(_syncStateKey), before);
          expect(platform.values['flutter.$_syncStateKey'], before);
          expect(RemoteNoticeService.unreadActiveCount.value, 1);

          SharedPreferences.setMockInitialValues({});
          SharedPreferencesStorePlatform.instance = platform;
          RemoteNoticeService.unreadActiveCount.value = 0;
          await createService().syncOnStartup();
          expect(requests, 3);
          expect(RemoteNoticeService.unreadActiveCount.value, 1);
        },
      );
    }
  });
}

Dio _dioReturning(
  Object? data, {
  void Function(RequestOptions)? onRequest,
  bool Function()? shouldFail,
}) {
  return Dio()
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          onRequest?.call(options);
          if (shouldFail?.call() ?? false) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
                error: StateError('Injected notice request failure'),
              ),
            );
            return;
          }
          handler.resolve(
            Response<Object?>(
              requestOptions: options,
              data: data,
              statusCode: 200,
            ),
          );
        },
      ),
    );
}

class _FailingNoticePreferences extends SharedPreferencesStorePlatform {
  final values = <String, Object>{};
  bool failNextWrite = false;
  bool throwOnFailure = false;

  @override
  Future<Map<String, Object>> getAll() async => {...values};

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.$_syncStateKey' && failNextWrite) {
      failNextWrite = false;
      if (throwOnFailure) throw StateError('Injected preference write failure');
      return false;
    }
    values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    values.clear();
    return true;
  }
}

class _MemoryPreferences extends AppPreferences {
  final _values = <String, Object?>{};

  @override
  Future<bool> containsKey(String key) async => _values.containsKey(key);

  @override
  Future<String?> getString(String key) async {
    final raw = _values[key];
    return raw is String ? raw : null;
  }

  @override
  Future<List<String>?> getStringList(String key) async {
    final raw = _values[key];
    if (raw is List<String>) return raw;
    return null;
  }

  @override
  Future<bool?> getBool(String key) async {
    final raw = _values[key];
    if (raw is bool) return raw;
    return null;
  }

  @override
  Future<bool> setString(String key, String value) async {
    _values[key] = value;
    return true;
  }

  @override
  Future<bool> setBool(String key, bool value) async {
    _values[key] = value;
    return true;
  }

  @override
  Future<bool> setStringList(String key, List<String> value) async {
    _values[key] = List<String>.from(value);
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    _values.remove(key);
    return true;
  }
}
