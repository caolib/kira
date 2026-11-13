import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/api/copy_settings_remote.dart';

/// Keeps every request in memory; no sockets, DNS or real APIs.
class _TestAdapter implements HttpClientAdapter {
  _TestAdapter(this.respond);

  final FutureOr<ResponseBody> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object? data) => ResponseBody.fromString(
  jsonEncode(data),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

CopySettingsRemote _remote(Object? payload) {
  final adapter = _TestAdapter((_) => _json(payload));
  return CopySettingsRemote(dio: Dio()..httpClientAdapter = adapter);
}

void main() {
  test('reads version_code with cache busting headers', () async {
    final adapter = _TestAdapter((_) => _json({'version_code': '85'}));
    final remote = CopySettingsRemote(dio: Dio()..httpClientAdapter = adapter);

    expect(await remote.fetchVersionCode(), '85');
    final request = adapter.requests.single;
    expect(request.uri.host, 'cdn.caolib.qzz.io');
    expect(request.uri.path, '/kira/copy-settings.json');
    expect(request.uri.queryParameters['_t'], isNotEmpty);
    expect(request.headers['Cache-Control'], 'no-cache');
    expect(request.headers['Pragma'], 'no-cache');
  });

  test('accepts versionCode alias and numeric JSON values', () async {
    expect(await _remote({'versionCode': '86'}).fetchVersionCode(), '86');
    expect(await _remote({'version_code': 87}).fetchVersionCode(), '87');
  });

  test('returns null when the field is missing or not digits', () async {
    expect(
      await _remote({'updated_at': '2026-11-13'}).fetchVersionCode(),
      isNull,
    );
    expect(await _remote({'version_code': ''}).fetchVersionCode(), isNull);
    expect(await _remote({'version_code': 'abc'}).fetchVersionCode(), isNull);
    expect(
      await _remote({'version_code': '12345678901'}).fetchVersionCode(),
      isNull,
    );
  });

  test('parses a JSON string body and ignores invalid JSON', () async {
    final body = _TestAdapter(
      (_) => ResponseBody.fromString(
        '{"version_code":"88"}',
        200,
        headers: {
          Headers.contentTypeHeader: ['text/plain'],
        },
      ),
    );
    expect(
      await CopySettingsRemote(
        dio: Dio()..httpClientAdapter = body,
      ).fetchVersionCode(),
      '88',
    );

    final invalid = _TestAdapter(
      (_) => ResponseBody.fromString('<html>error</html>', 200),
    );
    expect(
      await CopySettingsRemote(
        dio: Dio()..httpClientAdapter = invalid,
      ).fetchVersionCode(),
      isNull,
    );
  });

  test('propagates request failures for the caller to handle', () async {
    final adapter = _TestAdapter(
      (_) => throw DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.connectionError,
      ),
    );
    expect(
      CopySettingsRemote(
        dio: Dio()..httpClientAdapter = adapter,
      ).fetchVersionCode(),
      throwsA(isA<DioException>()),
    );
  });
}
