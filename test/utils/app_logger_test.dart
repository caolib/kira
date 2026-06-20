import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kira/utils/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'app_logging_enabled': true});
    tempDir = await Directory.systemTemp.createTemp('kira_app_logger_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('records errors locally and redacts sensitive values', () async {
    final logger = AppLogger(directoryProvider: () async => tempDir);

    await logger.recordError(
      Exception('request failed token=abc123 password:secret'),
      stackTrace: StackTrace.fromString('authorization: Bearer abc123'),
      source: 'test',
      context: {'access_token': 'secret-token', 'screen': 'profile'},
    );

    final entries = await logger.readEntries();
    final exported = await logger.exportText();

    expect(entries, hasLength(1));
    expect(entries.single.source, 'test');
    expect(entries.single.message, contains('token=[REDACTED]'));
    expect(entries.single.message, contains('password:[REDACTED]'));
    expect(entries.single.message, isNot(contains('abc123')));
    expect(entries.single.stackTrace, contains('authorization: [REDACTED]'));
    expect(entries.single.stackTrace, isNot(contains('abc123')));
    expect(entries.single.context['access_token'], '[REDACTED]');
    expect(entries.single.context['screen'], 'profile');
    expect(exported, contains('source: test'));
  });

  test('rotates log files and reads newest entries first', () async {
    final logger = AppLogger(
      directoryProvider: () async => tempDir,
      maxFileSizeBytes: 320,
      maxRotatedFiles: 2,
    );
    final padding = List.filled(80, 'x').join();

    for (var index = 0; index < 8; index++) {
      await logger.recordError(
        Exception('error-$index $padding'),
        stackTrace: StackTrace.fromString('stack-$index'),
        source: 'rotation',
      );
    }

    final fileNames = await tempDir
        .list()
        .where((entity) => entity is File)
        .map((entity) => entity.uri.pathSegments.last)
        .toList();
    final entries = await logger.readEntries();

    expect(fileNames, contains('error.log'));
    expect(fileNames, contains('error.1.log'));
    expect(entries.first.message, contains('error-7'));
    expect(entries.length, greaterThan(1));
  });

  test('clear removes local log files', () async {
    final logger = AppLogger(directoryProvider: () async => tempDir);

    await logger.recordError(Exception('boom'), source: 'test');
    expect(await logger.readEntries(), isNotEmpty);

    await logger.clear();

    expect(await logger.readEntries(), isEmpty);
    expect(
      await tempDir.list().where((entity) => entity is File).isEmpty,
      true,
    );
  });

  test('defaults to warning threshold', () async {
    final logger = AppLogger(directoryProvider: () async => tempDir);

    await logger.recordInfo('info', source: 'level');
    await logger.recordWarning('warning', source: 'level');

    final entries = await logger.readEntries();

    expect(entries, hasLength(1));
    expect(entries.single.level, AppLogLevel.warning);
    expect(entries.single.message, 'warning');
  });

  test('records debug and info when minimum level is debug', () async {
    final logger = AppLogger(directoryProvider: () async => tempDir);

    await logger.setMinimumLevel(AppLogLevel.debug);
    await logger.recordDebug('debug', source: 'level');
    await logger.recordInfo('info', source: 'level');

    final entries = await logger.readEntries();

    expect(entries.map((entry) => entry.level), [
      AppLogLevel.info,
      AppLogLevel.debug,
    ]);
  });

  test('does not write entries when logging is disabled', () async {
    final logger = AppLogger(directoryProvider: () async => tempDir);

    await logger.setLoggingEnabled(false);
    await logger.recordError(Exception('disabled'), source: 'level');

    expect(await logger.readEntries(), isEmpty);
  });
}
