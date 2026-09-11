part of '../ai_config_page.dart';

class _AiModelChoice {
  final String providerId;
  final String providerName;
  final String model;

  const _AiModelChoice({
    required this.providerId,
    required this.providerName,
    required this.model,
  });

  String get value => '$providerId::$model';
}

class _AiChatSession {
  final String id;
  final String title;
  final DateTime updatedAt;
  final List<AiMessage> messages;

  const _AiChatSession({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messages,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'updatedAt': updatedAt.toIso8601String(),
    'messages': messages
        .map((message) => message.toJson(includeReasoning: true))
        .toList(),
  };

  factory _AiChatSession.fromJson(Map<String, dynamic> json) {
    final messages = (json['messages'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => AiMessage.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    return _AiChatSession(
      id: json['id'] as String? ?? _newSessionId(),
      title: json['title'] as String? ?? 'New chat',
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      messages: messages,
    );
  }

  _AiChatSession copyWith({
    String? title,
    DateTime? updatedAt,
    List<AiMessage>? messages,
  }) => _AiChatSession(
    id: id,
    title: title ?? this.title,
    updatedAt: updatedAt ?? this.updatedAt,
    messages: messages ?? this.messages,
  );
}

String _newSessionId() => 'session_${DateTime.now().millisecondsSinceEpoch}';
