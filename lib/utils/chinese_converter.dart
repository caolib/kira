import 'dart:async';

import 'package:dio/dio.dart';

import 'app_dio.dart';
import 'app_logger.dart';

class ChineseConverter {
  static final Dio _dio = AppDio.create(
    source: 'chinese_converter',
    options: BaseOptions(
      baseUrl: 'https://api.zhconvert.org',
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      sendTimeout: const Duration(seconds: 8),
    ),
  );

  static final Map<String, String> _cache = {};

  static Future<String> convertToSimplifiedChinese(String text) {
    return _convert(text, 'Simplified');
  }

  static Future<String> convertToTraditionalChinese(String text) {
    return _convert(text, 'Traditional');
  }

  static Future<String> _convert(String text, String converter) async {
    if (text.isEmpty) return text;

    final cacheKey = '$converter|$text';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    try {
      final response = await _dio.get(
        '/convert',
        queryParameters: {'text': text, 'converter': converter},
      );
      final converted = _extractConvertedText(response.data);
      if (converted != null && converted.isNotEmpty) {
        _cache[cacheKey] = converted;
        return converted;
      }
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'chinese_converter',
        ),
      );
    }

    return text;
  }

  static String? _extractConvertedText(dynamic data) {
    if (data is Map<String, dynamic>) {
      final nested = data['data'];
      if (nested is Map<String, dynamic>) {
        final text = nested['text'];
        if (text is String) return text;
      }
      final text = data['text'];
      if (text is String) return text;
    }
    return null;
  }
}
