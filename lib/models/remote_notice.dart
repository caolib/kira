import 'dart:convert';

import '../utils/json_helpers.dart';

enum RemoteNoticeLevel {
  normal('Normal'),
  urgent('Urgent'),
  pinned('Pinned');

  const RemoteNoticeLevel(this.label);

  final String label;

  static RemoteNoticeLevel parse(String raw) {
    final value = raw.trim().toLowerCase();
    return switch (value) {
      'urgent' || 'emergency' || 'critical' || '紧急' => urgent,
      'pinned' || 'pin' || 'top' || 'sticky' || '置顶' => pinned,
      _ => normal,
    };
  }
}

enum RemoteNoticeType {
  note('Note'),
  tip('Tip'),
  warning('Warning'),
  important('Important'),
  caution('Caution');

  const RemoteNoticeType(this.label);

  final String label;

  static RemoteNoticeType parse(
    String raw, {
    RemoteNoticeLevel level = RemoteNoticeLevel.normal,
  }) {
    final value = raw.trim().toLowerCase();
    return switch (value) {
      'tip' || 'hint' || 'success' || '提示' => tip,
      'warning' || 'warn' || '警告' => warning,
      'important' || '重要' => important,
      'caution' || 'danger' || 'error' || '注意' => caution,
      'urgent' || 'emergency' || 'critical' || '紧急' => caution,
      'pinned' || 'pin' || 'top' || 'sticky' || '置顶' => important,
      _ => switch (level) {
        RemoteNoticeLevel.urgent => caution,
        RemoteNoticeLevel.pinned => important,
        RemoteNoticeLevel.normal => note,
      },
    };
  }
}

class RemoteNotice {
  const RemoteNotice({
    required this.id,
    required this.title,
    required this.content,
    required this.publishedAt,
    this.level = RemoteNoticeLevel.normal,
    this.type = RemoteNoticeType.note,
    this.pinned = false,
    this.expiresAt,
    this.url,
  });

  final String id;
  final String title;
  final String content;
  final DateTime publishedAt;
  final RemoteNoticeLevel level;
  final RemoteNoticeType type;
  final bool pinned;
  final DateTime? expiresAt;
  final String? url;

  bool get isValid => id.isNotEmpty && title.isNotEmpty && content.isNotEmpty;
  bool get isUrgent => level == RemoteNoticeLevel.urgent;
  bool get isPinned => pinned || level == RemoteNoticeLevel.pinned;

  bool isActive(DateTime now) {
    final expiresAt = this.expiresAt;
    if (expiresAt != null && !now.isBefore(expiresAt)) return false;
    return true;
  }

  int get promptPriority {
    if (isUrgent) return 0;
    if (isPinned) return 1;
    return 2;
  }

  factory RemoteNotice.fromJson(Map<String, dynamic> json) {
    final typeRaw = _firstString(json, const [
      'notice_type',
      'noticeType',
      'type',
      'kind',
      'category',
    ]);
    final levelRaw = _firstString(json, const [
      'level',
      'priority',
    ], fallback: _legacyLevelFromType(typeRaw));
    final level = RemoteNoticeLevel.parse(levelRaw);
    final publishedAt =
        _parseDate(
          _firstString(json, const [
            'published_at',
            'publishedAt',
            'created_at',
            'date',
          ]),
        ) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

    return RemoteNotice(
      id: jsonString(json, 'id').trim(),
      title: jsonString(json, 'title').trim(),
      content: jsonString(json, 'content').trim(),
      level: level,
      type: RemoteNoticeType.parse(typeRaw, level: level),
      pinned:
          jsonBool(json, 'pinned') ||
          jsonBool(json, 'is_pinned') ||
          jsonBool(json, 'sticky'),
      publishedAt: publishedAt,
      expiresAt: _parseDate(
        _firstString(json, const ['expires_at', 'expiresAt', 'expire_at']),
      ),
      url: jsonString(json, 'url').trim().nullIfEmpty(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'level': level.name,
    'type': type.name,
    'title': title,
    'content': content,
    'published_at': _formatDateTime(publishedAt),
    if (pinned) 'pinned': pinned,
    if (expiresAt != null) 'expires_at': _formatDateTime(expiresAt!),
    if (url != null) 'url': url,
  };

  static int compareForPrompt(RemoteNotice a, RemoteNotice b) {
    // Startup prompt: urgent > pinned > normal; same priority by publish time desc.
    final priority = a.promptPriority.compareTo(b.promptPriority);
    if (priority != 0) return priority;
    return b.publishedAt.compareTo(a.publishedAt);
  }

  static int compareForTimeline(RemoteNotice a, RemoteNotice b) {
    // Notice center: active pinned notices first; others by publish time desc.
    final now = DateTime.now();
    final aPinned = a.isPinned && a.isActive(now);
    final bPinned = b.isPinned && b.isActive(now);
    if (aPinned != bPinned) return aPinned ? -1 : 1;
    return b.publishedAt.compareTo(a.publishedAt);
  }
}

class RemoteNoticePayload {
  const RemoteNoticePayload({required this.notices});

  final List<RemoteNotice> notices;

  factory RemoteNoticePayload.fromData(Object? data) {
    Object? decoded = data;
    if (decoded is String) {
      decoded = jsonDecode(decoded);
    }

    if (decoded is List) {
      return RemoteNoticePayload(notices: parseNotices(decoded));
    }

    if (decoded is Map) {
      final json = Map<String, dynamic>.from(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
      final notices = jsonList(json, 'notices').isNotEmpty
          ? jsonList(json, 'notices')
          : jsonList(json, 'notifications').isNotEmpty
          ? jsonList(json, 'notifications')
          : jsonList(json, 'items');
      return RemoteNoticePayload(notices: parseNotices(notices));
    }

    return const RemoteNoticePayload(notices: []);
  }

  static List<RemoteNotice> parseNotices(Iterable<dynamic> rawItems) {
    final notices = <RemoteNotice>[];
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final json = Map<String, dynamic>.from(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      final notice = RemoteNotice.fromJson(json);
      if (notice.isValid) notices.add(notice);
    }
    notices.sort(RemoteNotice.compareForTimeline);
    return notices;
  }
}

String _firstString(
  Map<String, dynamic> json,
  List<String> keys, {
  String fallback = '',
}) {
  for (final key in keys) {
    final value = jsonString(json, key).trim();
    if (value.isNotEmpty) return value;
  }
  return fallback;
}

String _legacyLevelFromType(String raw) {
  final value = raw.trim().toLowerCase();
  return switch (value) {
    'urgent' || 'emergency' || 'critical' || '紧急' => raw,
    'pinned' || 'pin' || 'top' || 'sticky' || '置顶' => raw,
    _ => '',
  };
}

DateTime? _parseDate(String raw) {
  if (raw.trim().isEmpty) return null;
  return DateTime.tryParse(raw.trim());
}

String _formatDateTime(DateTime time) {
  final local = time.toLocal();
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  final second = local.second.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute:$second';
}
