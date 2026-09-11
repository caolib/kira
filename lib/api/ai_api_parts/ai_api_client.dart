part of '../ai_api.dart';

class AiApi {
  final Dio _dio = AppDio.create(
    source: 'ai_api',
    options: BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 5),
    ),
  );

  /// Fetches model IDs exposed by an OpenAI-compatible provider.
  Future<List<String>> fetchModels({
    required String apiKey,
    required String baseUrl,
    CancelToken? cancelToken,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      _modelsEndpointFor(baseUrl),
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Accept': 'application/json',
        },
      ),
      cancelToken: cancelToken,
    );
    final rawModels = response.data?['data'];
    if (rawModels is! List) return const [];

    final result = <String>[];
    final seen = <String>{};
    for (final item in rawModels) {
      final id = switch (item) {
        final String value => value,
        final Map map => map['id'] as String?,
        _ => null,
      };
      final trimmed = id?.trim();
      if (trimmed != null && trimmed.isNotEmpty && seen.add(trimmed)) {
        result.add(trimmed);
      }
    }
    return result;
  }

  /// Calls the SSE stream and yields text deltas chunk by chunk.
  Stream<String> streamChat({
    required String apiKey,
    required String baseUrl,
    required OpenAiApiFormat apiFormat,
    required String model,
    required List<AiMessage> messages,
    CancelToken? cancelToken,
  }) async* {
    await for (final chunk in streamChatChunks(
      apiKey: apiKey,
      baseUrl: baseUrl,
      apiFormat: apiFormat,
      model: model,
      messages: messages,
      cancelToken: cancelToken,
    )) {
      if (!chunk.isReasoning) yield chunk.text;
    }
  }

  /// Calls the SSE stream and preserves reasoning deltas when available.
  Stream<AiStreamChunk> streamChatChunks({
    required String apiKey,
    required String baseUrl,
    required OpenAiApiFormat apiFormat,
    required String model,
    required List<AiMessage> messages,
    CancelToken? cancelToken,
  }) async* {
    final response = await _dio.post<ResponseBody>(
      _endpointFor(baseUrl, apiFormat),
      data: _requestBody(apiFormat, model, messages),
      options: Options(
        responseType: ResponseType.stream,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
          // Disable compression so Dio does not wait for a full body to decompress.
          'Accept-Encoding': 'identity',
          'Cache-Control': 'no-cache',
        },
      ),
      cancelToken: cancelToken,
    );

    // Streaming UTF-8 decoding preserves split multibyte chars and line breaks.
    final lines = response.data!.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data == '[DONE]') return;
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final chunk = _parseStreamChunk(json, apiFormat);
        if (chunk != null && chunk.text.isNotEmpty) yield chunk;
      } catch (_) {
        // Ignore individual malformed SSE lines.
      }
    }
  }

  String _modelsEndpointFor(String baseUrl) {
    final trimmed = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (trimmed.endsWith('/models')) return trimmed;
    return '$trimmed/models';
  }

  String _endpointFor(String baseUrl, OpenAiApiFormat apiFormat) {
    final trimmed = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (apiFormat == OpenAiApiFormat.chatCompletions) {
      if (trimmed.endsWith('/chat/completions')) return trimmed;
      return '$trimmed/chat/completions';
    }
    if (trimmed.endsWith('/responses')) return trimmed;
    return '$trimmed/responses';
  }

  Map<String, dynamic> _requestBody(
    OpenAiApiFormat apiFormat,
    String model,
    List<AiMessage> messages,
  ) {
    if (apiFormat == OpenAiApiFormat.chatCompletions) {
      return {
        'model': model,
        'messages': messages.map((e) => e.toJson()).toList(),
        'stream': true,
      };
    }
    return {
      'model': model,
      'input': messages
          .map(
            (e) => {
              'role': e.role,
              'content': [
                {'type': 'input_text', 'text': e.content},
              ],
            },
          )
          .toList(),
      'stream': true,
    };
  }

  AiStreamChunk? _parseStreamChunk(
    Map<String, dynamic> json,
    OpenAiApiFormat apiFormat,
  ) {
    if (apiFormat == OpenAiApiFormat.responses) {
      final type = json['type'];
      final delta = json['delta'];
      if (type == 'response.output_text.delta' && delta is String) {
        return AiStreamChunk(text: delta);
      }
      if (type == 'response.refusal.delta' && delta is String) {
        return AiStreamChunk(text: delta);
      }
      if ((type == 'response.reasoning_summary_text.delta' ||
              type == 'response.reasoning_text.delta') &&
          delta is String) {
        return AiStreamChunk(text: delta, isReasoning: true);
      }
    }

    final choices = json['choices'] as List?;
    if (choices == null || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map) return null;
    final delta = first['delta'];
    if (delta is Map) {
      final reasoning = _stringField(delta, const [
        'reasoning_content',
        'reasoning',
        'reasoningContent',
        'thinking',
      ]);
      if (reasoning != null) {
        return AiStreamChunk(text: reasoning, isReasoning: true);
      }
      final content = delta['content'];
      if (content is String) return AiStreamChunk(text: content);
    }
    final message = first['message'];
    if (message is Map) {
      final reasoning = _stringField(message, const [
        'reasoning_content',
        'reasoning',
        'reasoningContent',
        'thinking',
      ]);
      if (reasoning != null) {
        return AiStreamChunk(text: reasoning, isReasoning: true);
      }
      final content = message['content'];
      if (content is String) return AiStreamChunk(text: content);
    }
    return null;
  }

  String? _stringField(Map source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }
}
