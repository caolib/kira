import 'package:dio/dio.dart';

import 'network_error.dart';

/// Centralized Dio setup for app-wide network behavior.
class AppDio {
  const AppDio._();

  /// Fallback timeouts applied when a caller does not specify its own.
  ///
  /// Dio treats a `null` timeout as "wait forever", which would let a request
  /// hang indefinitely on a flaky network. Callers with genuinely long-running
  /// transfers (downloads, AI streaming) still set their own values and are
  /// left untouched.
  static const defaultConnectTimeout = Duration(seconds: 15);
  static const defaultReceiveTimeout = Duration(seconds: 30);

  static Dio create({
    BaseOptions? options,
    required String source,
    bool enableRateLimit = true,
    bool enableErrorLog = true,
    Iterable<Interceptor> interceptors = const [],
  }) {
    final dio = Dio(options);
    dio.options.connectTimeout ??= defaultConnectTimeout;
    dio.options.receiveTimeout ??= defaultReceiveTimeout;
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
