import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/remote_notice.dart';

void main() {
  test('parses notice payload with supported levels and date windows', () {
    final payload = RemoteNoticePayload.fromData({
      'notices': [
        {
          'id': 'normal-1',
          'level': '普通',
          'title': '普通通知',
          'content': '内容',
          'published_at': '2026-07-05 10:00:00',
        },
        {
          'id': 'urgent-1',
          'type': 'urgent',
          'title': '紧急通知',
          'content': '内容',
          'published_at': '2026-07-05 11:00:00',
          'expires_at': '2026-07-06 11:00:00',
        },
        {
          'id': 'pinned-1',
          'level': 'top',
          'title': '置顶通知',
          'content': '内容',
          'published_at': '2026-07-05 09:00:00',
        },
      ],
    });

    expect(payload.notices, hasLength(3));
    expect(payload.notices.first.id, 'pinned-1');

    final urgent = payload.notices.firstWhere((n) => n.id == 'urgent-1');
    expect(urgent.level, RemoteNoticeLevel.urgent);
    expect(urgent.type, RemoteNoticeType.caution);
    expect(urgent.isUrgent, isTrue);
    expect(urgent.isActive(DateTime.parse('2026-07-05 12:00:00')), isTrue);
    expect(urgent.isActive(DateTime.parse('2026-07-06 12:00:00')), isFalse);

    final pinned = payload.notices.firstWhere((n) => n.id == 'pinned-1');
    expect(pinned.level, RemoteNoticeLevel.pinned);
    expect(pinned.type, RemoteNoticeType.important);
    expect(pinned.isPinned, isTrue);
  });

  test('parses supported notice types from json aliases', () {
    final payload = RemoteNoticePayload.fromData({
      'notices': [
        {'id': 'note', 'type': 'note', 'title': '说明通知', 'content': '内容'},
        {'id': 'tip', 'notice_type': 'tip', 'title': '提示通知', 'content': '内容'},
        {
          'id': 'warning',
          'noticeType': 'warning',
          'title': '警告通知',
          'content': '内容',
        },
        {
          'id': 'important',
          'kind': 'important',
          'title': '重要通知',
          'content': '内容',
        },
        {
          'id': 'caution',
          'category': 'caution',
          'title': '注意通知',
          'content': '内容',
        },
      ],
    });

    expect(
      {for (final notice in payload.notices) notice.id: notice.type},
      {
        'note': RemoteNoticeType.note,
        'tip': RemoteNoticeType.tip,
        'warning': RemoteNoticeType.warning,
        'important': RemoteNoticeType.important,
        'caution': RemoteNoticeType.caution,
      },
    );
  });

  test('filters malformed notice items', () {
    final payload = RemoteNoticePayload.fromData({
      'notices': [
        {
          'id': 'valid',
          'title': '有效通知',
          'content': '内容',
          'published_at': '2026-07-05 10:00:00',
        },
        {'id': '', 'title': '无效通知', 'content': '内容'},
        {'id': 'missing-content', 'title': '无效通知'},
      ],
    });

    expect(payload.notices.map((n) => n.id), ['valid']);
  });

  test('prompt sorting prioritizes urgent, pinned, then newest normal', () {
    final notices = [
      _notice(
        id: 'normal-new',
        level: RemoteNoticeLevel.normal,
        publishedAt: '2026-07-05 12:00:00',
      ),
      _notice(
        id: 'pinned',
        level: RemoteNoticeLevel.pinned,
        publishedAt: '2026-07-04 12:00:00',
      ),
      _notice(
        id: 'urgent-old',
        level: RemoteNoticeLevel.urgent,
        publishedAt: '2026-07-03 12:00:00',
      ),
      _notice(
        id: 'urgent-new',
        level: RemoteNoticeLevel.urgent,
        publishedAt: '2026-07-05 11:00:00',
      ),
    ]..sort(RemoteNotice.compareForPrompt);

    expect(notices.map((n) => n.id), [
      'urgent-new',
      'urgent-old',
      'pinned',
      'normal-new',
    ]);
  });

  test('timeline sorting keeps active pinned first then newest', () {
    final notices = [
      _notice(
        id: 'normal-new',
        level: RemoteNoticeLevel.normal,
        publishedAt: '2026-07-05 12:00:00',
      ),
      _notice(
        id: 'pinned-old',
        level: RemoteNoticeLevel.pinned,
        publishedAt: '2026-07-01 12:00:00',
      ),
      _notice(
        id: 'normal-old',
        level: RemoteNoticeLevel.normal,
        publishedAt: '2026-07-04 12:00:00',
      ),
    ]..sort(RemoteNotice.compareForTimeline);

    expect(notices.map((n) => n.id), [
      'pinned-old',
      'normal-new',
      'normal-old',
    ]);
  });
}

RemoteNotice _notice({
  required String id,
  required RemoteNoticeLevel level,
  required String publishedAt,
}) {
  return RemoteNotice(
    id: id,
    title: id,
    content: 'content',
    publishedAt: DateTime.parse(publishedAt),
    level: level,
  );
}
