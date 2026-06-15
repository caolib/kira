import 'package:dio/dio.dart';

import 'network_error.dart';

/// Centralized Dio setup for app-wide network behavior.
class AppDio {
  const AppDio._();

  static Dio create({
    BaseOptions? options,
    required String source,
    bool enableRateLimit = true,
    bool enableErrorLog = true,
    Iterable<Interceptor> interceptors = const [],
  }) {
    final dio = Dio(options);
    attachCommonInterceptors(
      dio,
      source: source,
      enableRateLimit: enableRateLimit,
      enableErrorLog: false,
    );
    dio.interceptors.addAll(interceptors);
    if (enableErrorLog) {
      attachCommonInterceptors(dio, source: source, enableRateLimit: false);
    }
    return dio;
  }

  static void attachCommonInterceptors(
    Dio dio, {
    required String source,
    bool enableRateLimit = true,
    bool enableErrorLog = true,
  }) {
    if (enableRateLimit) {
      dio.interceptors.add(NetworkError.rateLimitInterceptor());
    }
    if (enableErrorLog) {
      dio.interceptors.add(NetworkError.loggingInterceptor(source: source));
    }
  }
}
