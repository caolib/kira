import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/remote_notice.dart';
import 'package:kira/utils/app_storage.dart';
import 'package:kira/utils/remote_notice_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}

Dio _dioReturning(Object? data, {void Function(RequestOptions)? onRequest}) {
  return Dio()
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          onRequest?.call(options);
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

class _MemoryPreferences extends AppPreferences {
  final _values = <String, Object?>{};

  @override
  Future<bool> containsKey(String key) async => _values.containsKey(key);

  @override
  Future<dynamic> getJson(String key) async {
    final raw = _values[key];
    if (raw is String) return jsonDecode(raw);
    return raw;
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
  Future<bool> setJson(String key, Object? value) async {
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
