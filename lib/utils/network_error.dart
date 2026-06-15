import 'dart:async';

import 'package:dio/dio.dart';

import 'app_logger.dart';

/// App-wide network error helpers.
class NetworkError {
  static const rateLimitMessage = '请求过于频繁，已被限速，请稍后再试';

  static Interceptor rateLimitInterceptor() {
    return InterceptorsWrapper(
      onResponse: (response, handler) {
        if (response.statusCode == 429) {
          return handler.reject(_rateLimitFromResponse(response));
        }
        handler.next(response);
      },
      onError: (error, handler) {
        if (isRateLimited(error)) {
          return handler.reject(_rateLimitFromError(error));
        }
        handler.next(error);
      },
    );
  }

  static Interceptor loggingInterceptor({
    String source = 'network',
    AppLogger? logger,
  }) {
    return InterceptorsWrapper(
      onError: (error, handler) {
        unawaited(recordDioException(error, source: source, logger: logger));
        handler.next(error);
      },
    );
  }

  static Future<void> recordDioException(
    DioException error, {
    String source = 'network',
    AppLogger? logger,
  }) {
    if (CancelToken.isCancel(error)) return Future<void>.value();
    return (logger ?? AppLogger.instance).recordError(
      error,
      stackTrace: error.stackTrace,
      source: source,
      context: _dioErrorContext(error),
    );
  }

  static Future<void> recordDioResponse(
    Response<dynamic> response, {
    String source = 'network',
    AppLogLevel level = AppLogLevel.warning,
    String? message,
    AppLogger? logger,
  }) {
    return (logger ?? AppLogger.instance).record(
      message ?? _dioResponseMessage(response),
      level: level,
      source: source,
      context: _dioResponseContext(response),
    );
  }

  static Never throwBadResponse({
    required Response<dynamic> response,
    required String message,
    required String source,
    Object? error,
    AppLogger? logger,
  }) {
    final exception = DioException(
      requestOptions: response.requestOptions,
      response: response,
      message: message,
      error: error ?? message,
      type: DioExceptionType.badResponse,
    );
    unawaited(recordDioException(exception, source: source, logger: logger));
    throw exception;
  }

  static bool isRateLimited(Object? error) {
    if (error is RateLimitDioException) return true;
    if (error is DioException) return error.response?.statusCode == 429;
    if (error is Response) return error.statusCode == 429;
    return false;
  }

  static String message(Object error) {
    if (isRateLimited(error)) return rateLimitMessage;
    if (error is DioException) {
      final dataMessage = _messageFromData(error.response?.data);
      if (dataMessage != null) return dataMessage;
      final message = error.message;
      if (message != null && message.isNotEmpty) return message;
    }
    return error.toString();
  }

  static String? _messageFromData(Object? data) {
    if (data is Map) {
      final error = data['error'];
      if (error is Map && error['message'] is String) {
        return error['message'] as String;
      }
      final message = data['message'];
      if (message is String && message.isNotEmpty) return message;
    }
    if (data is String && data.isNotEmpty) return data;
    return null;
  }

  static String _dioResponseMessage(Response<dynamic> response) {
    final method = response.requestOptions.method;
    final uri = response.requestOptions.uri;
    final statusCode = response.statusCode?.toString() ?? 'unknown';
    return 'HTTP $statusCode $method $uri';
  }

  static Map<String, Object?> _dioResponseContext(Response<dynamic> response) {
    final data = response.data;
    final context = <String, Object?>{
      'method': response.requestOptions.method,
      'url': response.requestOptions.uri.toString(),
    };

    final statusCode = response.statusCode;
    if (statusCode != null) context['statusCode'] = statusCode;
    final statusMessage = response.statusMessage;
    if (statusMessage != null) context['statusMessage'] = statusMessage;
    final responseCode = _codeFromData(data);
    if (responseCode != null) context['responseCode'] = responseCode;
    final responseMessage = _messageFromData(data);
    if (responseMessage != null) context['responseMessage'] = responseMessage;

    return context;
  }

  static Map<String, Object?> _dioErrorContext(DioException error) {
    final response = error.response;
    final data = response?.data;
    final context = <String, Object?>{
      'method': error.requestOptions.method,
      'url': error.requestOptions.uri.toString(),
      'type': error.type.name,
    };

    final errorMessage = error.message;
    if (errorMessage != null && errorMessage.isNotEmpty) {
      context['message'] = errorMessage;
    }
    final rawError = error.error;
    if (rawError != null) context['error'] = rawError;
    final responseCode = _codeFromData(data);
    if (responseCode != null) context['responseCode'] = responseCode;
    final responseMessage = _messageFromData(data);
    if (responseMessage != null) context['responseMessage'] = responseMessage;
    final statusCode = response?.statusCode;
    if (statusCode != null) context['statusCode'] = statusCode;
    final statusMessage = response?.statusMessage;
    if (statusMessage != null) context['statusMessage'] = statusMessage;

    return context;
  }

  static Object? _codeFromData(Object? data) {
    if (data is Map) return data['code'];
    return null;
  }

  static RateLimitDioException _rateLimitFromResponse(
    Response<dynamic> response,
  ) {
    return RateLimitDioException(
      requestOptions: response.requestOptions,
      response: response,
    );
  }

  static RateLimitDioException _rateLimitFromError(DioException error) {
    return RateLimitDioException(
      requestOptions: error.requestOptions,
      response: error.response,
      type: error.type,
      stackTrace: error.stackTrace,
    );
  }
}

class RateLimitDioException extends DioException {
  RateLimitDioException({
    required super.requestOptions,
    super.response,
    super.type = DioExceptionType.badResponse,
    super.stackTrace,
  }) : super(
         error: NetworkError.rateLimitMessage,
         message: NetworkError.rateLimitMessage,
       );

  @override
  String toString() => NetworkError.rateLimitMessage;
}
