import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/remote_notice.dart';
import 'app_dio.dart';
import 'app_logger.dart';
import 'app_storage.dart';
import 'json_helpers.dart';

class RemoteNoticeSyncResult {
  const RemoteNoticeSyncResult({
    required this.notices,
    required this.unseenActive,
  });

  final List<RemoteNotice> notices;
  final List<RemoteNotice> unseenActive;
}

class RemoteNoticeService {
  RemoteNoticeService({
    Dio? dio,
    AppPreferences? preferences,
    DateTime Function()? now,
    this.noticeUrl = defaultNoticeUrl,
  }) : _dio = dio ?? _defaultDio,
       _preferences = preferences ?? AppStorage.preferences,
       _now = now ?? DateTime.now;

  static const defaultNoticeUrl = 'https://cdn.caolib.qzz.io/kira/notices.json';
  static const _seenKeysKey = 'remote_notice_seen_keys_v2';
  static const _syncStateKey = 'remote_notice_sync_state_v1';
  static const _startupCheckInterval = Duration(hours: 6);

  static final ValueNotifier<int> unreadActiveCount = ValueNotifier<int>(0);

  static final Dio _defaultDio = AppDio.create(
    source: 'remote_notice',
    options: BaseOptions(
      headers: const {'Accept': 'application/json', 'User-Agent': 'Kira-App'},
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  final Dio _dio;
  final AppPreferences _preferences;
  final DateTime Function() _now;
  final String noticeUrl;

  Future<List<RemoteNotice>> fetchRemoteNotices() async {
    final uri = Uri.tryParse(noticeUrl.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return const [];
    }

    final response = await _dio.getUri<Object?>(
      _cacheBustedUri(uri),
      options: Options(
        headers: const {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
      ),
    );
    return latestRemoteNotices(
      RemoteNoticePayload.fromData(response.data).notices,
    );
  }

  Future<Set<String>> loadSeenKeys() async {
    final raw = await _preferences.getStringList(_seenKeysKey);
    return raw?.where((id) => id.trim().isNotEmpty).toSet() ?? <String>{};
  }

  Future<void> markSeen(Iterable<RemoteNotice> notices) async {
    final next = await loadSeenKeys();
    next.addAll(notices.map(seenKeyFor));
    await _saveSeenKeys(next);
  }

  Future<RemoteNoticeSyncResult> sync() async {
    final notices = await fetchRemoteNotices();
    final seenKeys = await _retainSeenKeysForNotices(notices);
    final now = _now();
    final unseenActive = _unseenActiveNotices(
      notices: notices,
      seenKeys: seenKeys,
      now: now,
    );
    await _saveSyncState(
      lastSuccessAt: now.millisecondsSinceEpoch,
      unreadCount: unseenActive.length,
    );
    unreadActiveCount.value = unseenActive.length;

    return RemoteNoticeSyncResult(notices: notices, unseenActive: unseenActive);
  }

  Future<void> syncOnStartup() async {
    final state = await _loadSyncState();
    final count = jsonInt(state, 'unreadActiveCount');
    unreadActiveCount.value = count < 0 ? 0 : count;

    final lastSuccessAt = jsonInt(state, 'lastSuccessAt');
    final elapsed = _now().millisecondsSinceEpoch - lastSuccessAt;
    if (lastSuccessAt > 0 &&
        elapsed >= 0 &&
        elapsed < _startupCheckInterval.inMilliseconds) {
      return;
    }
    await sync();
  }

  Future<int> refreshUnreadActiveCount() async {
    final result = await sync();
    return result.unseenActive.length;
  }

  Future<int> updateUnreadActiveCount(List<RemoteNotice> notices) async {
    final seenKeys = await loadSeenKeys();
    final count = _unseenActiveNotices(
      notices: notices,
      seenKeys: seenKeys,
      now: _now(),
    ).length;
    final state = await _loadSyncState();
    await _saveSyncState(
      lastSuccessAt: jsonInt(state, 'lastSuccessAt'),
      unreadCount: count,
    );
    unreadActiveCount.value = count;
    return count;
  }

  static Future<void> syncSilently() async {
    try {
      await RemoteNoticeService().syncOnStartup();
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'remote_notice',
        ),
      );
    }
  }

  static List<RemoteNotice> latestRemoteNotices(Iterable<RemoteNotice> remote) {
    return remote.where((notice) => notice.isValid).toList()
      ..sort(RemoteNotice.compareForTimeline);
  }

  static String seenKeyFor(RemoteNotice notice) {
    return jsonEncode([
      notice.id,
      notice.level.name,
      notice.type.name,
      notice.pinned,
      notice.publishedAt.toUtc().toIso8601String(),
      notice.expiresAt?.toUtc().toIso8601String(),
      notice.title,
      notice.content,
      notice.url,
    ]);
  }

  Future<Set<String>> _retainSeenKeysForNotices(
    List<RemoteNotice> notices,
  ) async {
    final seenKeys = await loadSeenKeys();
    final currentKeys = notices.map(seenKeyFor).toSet();
    final retained = seenKeys.intersection(currentKeys);
    if (retained.length != seenKeys.length) {
      await _saveSeenKeys(retained);
    }
    return retained;
  }

  Future<Map<String, dynamic>?> _loadSyncState() async {
    try {
      final raw = await _preferences.getJson(_syncStateKey);
      return raw is Map<String, dynamic> ? raw : null;
    } on FormatException catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'remote_notice',
        ),
      );
      return null;
    }
  }

  Future<void> _saveSyncState({
    required int lastSuccessAt,
    required int unreadCount,
  }) async {
    final previous = await _preferences.getString(_syncStateKey);
    try {
      final saved = await _preferences.setJson(_syncStateKey, {
        'lastSuccessAt': lastSuccessAt,
        'unreadActiveCount': unreadCount,
      });
      if (!saved) throw StateError('Failed to save remote notice sync state');
    } catch (e, stack) {
      // A failed prefs write can still replace its in-memory value.
      try {
        final restored = previous == null
            ? await _preferences.remove(_syncStateKey)
            : await _preferences.setString(_syncStateKey, previous);
        if (!restored) {
          throw StateError('Failed to restore remote notice sync state');
        }
      } catch (restoreError, restoreStack) {
        unawaited(
          AppLogger.instance.recordWarning(
            restoreError,
            stackTrace: restoreStack,
            source: 'remote_notice',
          ),
        );
      }
      Error.throwWithStackTrace(e, stack);
    }
  }

  Future<void> _saveSeenKeys(Set<String> keys) async {
    final saved = await _preferences.setStringList(
      _seenKeysKey,
      keys.toList()..sort(),
    );
    if (!saved) throw StateError('Failed to save remote notice read state');
  }
}

Uri _cacheBustedUri(Uri uri) {
  return uri.replace(
    queryParameters: {
      ...uri.queryParameters,
      '_t': DateTime.now().millisecondsSinceEpoch.toString(),
    },
  );
}

List<RemoteNotice> _unseenActiveNotices({
  required Iterable<RemoteNotice> notices,
  required Set<String> seenKeys,
  required DateTime now,
}) {
  return notices
      .where((notice) => notice.isActive(now))
      .where(
        (notice) => !seenKeys.contains(RemoteNoticeService.seenKeyFor(notice)),
      )
      .toList()
    ..sort(RemoteNotice.compareForPrompt);
}
