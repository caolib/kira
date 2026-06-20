import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/app_logger.dart';
import 'package:kira/utils/network_error.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'app_logging_enabled': true});
    tempDir = await Directory.systemTemp.createTemp('kira_network_error_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('records dio errors with request context and redaction', () async {
    final logger = AppLogger(directoryProvider: () async => tempDir);
    final options = RequestOptions(
      path: 'https://example.com/api?token=abc123',
      method: 'GET',
    );
    final error = DioException(
      requestOptions: options,
      response: Response<dynamic>(
        requestOptions: options,
        statusCode: 500,
        statusMessage: 'Server Error',
        data: {'code': 500, 'message': 'failed password=secret'},
      ),
      message: 'request failed token=abc123',
      error: 'token=abc123',
      type: DioExceptionType.badResponse,
    );

    await NetworkError.recordDioException(error, logger: logger, source: 'api');

    final entries = await logger.readEntries();
    final entry = entries.single;

    expect(entry.source, 'api');
    expect(entry.context['method'], 'GET');
    expect(entry.context['url'], contains('token=[REDACTED]'));
    expect(entry.context['statusCode'], '500');
    expect(entry.context['responseCode'], '500');
    expect(entry.context['responseMessage'], contains('password=[REDACTED]'));
    expect(entry.toPlainText(), isNot(contains('abc123')));
    expect(entry.toPlainText(), isNot(contains('secret')));
  });

  test('throwBadResponse records then throws dio exception', () async {
    final logger = AppLogger(directoryProvider: () async => tempDir);
    final options = RequestOptions(
      path: 'https://example.com/api',
      method: 'POST',
    );
    final response = Response<dynamic>(
      requestOptions: options,
      statusCode: 400,
      data: {'message': 'failed token=abc123'},
    );

    expect(
      () => NetworkError.throwBadResponse(
        response: response,
        message: 'failed token=abc123',
        source: 'test_bad_response',
        logger: logger,
      ),
      throwsA(isA<DioException>()),
    );

    final entries = await logger.readEntries();

    expect(entries, hasLength(1));
    expect(entries.single.source, 'test_bad_response');
    expect(entries.single.context['statusCode'], '400');
    expect(entries.single.toPlainText(), isNot(contains('abc123')));
  });

  test('records non-exception dio responses', () async {
    final logger = AppLogger(directoryProvider: () async => tempDir);
    final options = RequestOptions(
      path: 'https://example.com/video.m3u8?token=abc123',
      method: 'GET',
    );
    final response = Response<dynamic>(
      requestOptions: options,
      statusCode: 403,
      statusMessage: 'Forbidden',
      data: 'forbidden',
    );

    await NetworkError.recordDioResponse(
      response,
      source: 'anime_player',
      message: '视频诊断请求失败',
      logger: logger,
    );

    final entries = await logger.readEntries();
    final entry = entries.single;

    expect(entry.level, AppLogLevel.warning);
    expect(entry.source, 'anime_player');
    expect(entry.message, '视频诊断请求失败');
    expect(entry.context['statusCode'], '403');
    expect(entry.context['statusMessage'], 'Forbidden');
    expect(entry.toPlainText(), isNot(contains('abc123')));
  });
}
