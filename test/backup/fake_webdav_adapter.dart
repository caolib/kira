import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'webdav_listing_test.dart' show davMultistatus, davResponse;

class FakeWebDavAdapter implements HttpClientAdapter {
  final Map<String, Uint8List> files = {};
  final Set<String> directories = {'/dav/'};
  final List<RequestOptions> requests = [];
  final List<Uint8List> requestBodies = [];
  bool moveSupported = true;
  bool writable = true;
  int? forcedStatus;
  bool timeout = false;
  String? listingOverride;
  Future<void> Function(RequestOptions)? beforeResponse;
  ResponseBody Function(RequestOptions)? responseOverride;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final body = BytesBuilder(copy: false);
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        body.add(chunk);
      }
    }
    final bytes = body.takeBytes();
    requestBodies.add(bytes);
    await beforeResponse?.call(options);
    if (timeout) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionTimeout,
      );
    }
    if (responseOverride case final override?) return override(options);
    if (forcedStatus case final status?) {
      return ResponseBody.fromString(
        '',
        status,
        headers: {
          'location': ['https://evil.example/redirected'],
        },
      );
    }
    final path = options.uri.path;
    switch (options.method) {
      case 'MKCOL':
        if (!writable) return _status(403);
        if (!directories.add(path)) return _status(405);
        return _status(201);
      case 'PROPFIND':
        if (!directories.contains(path)) return _status(404);
        return ResponseBody.fromString(
          listingOverride ??
              davMultistatus([
                davResponse(options.uri.toString(), collection: true),
                if (options.headers['Depth'] == '1')
                  for (final entry in files.entries)
                    if (entry.key.startsWith(path))
                      davResponse(
                        entry.key,
                        size: entry.value.length.toString(),
                      ),
              ]),
          207,
          headers: {
            'content-type': ['application/xml; charset=utf-8'],
          },
        );
      case 'PUT':
        if (!writable) return _status(403);
        if (files.containsKey(path)) return _status(412);
        files[path] = bytes;
        return _status(201);
      case 'MOVE':
        if (!moveSupported) return _status(405);
        if (!writable) return _status(403);
        final destination = options.headers['Destination'];
        if (destination is! String) return _status(400);
        final target = Uri.parse(destination).path;
        if (files.containsKey(target)) return _status(412);
        final value = files.remove(path);
        if (value == null) return _status(404);
        files[target] = value;
        return _status(201);
      case 'GET':
        final bytes = files[path];
        return bytes == null
            ? _status(404)
            : ResponseBody.fromBytes(bytes, 200);
      case 'DELETE':
        if (!writable) return _status(403);
        return _status(files.remove(path) == null ? 404 : 204);
      default:
        return _status(501);
    }
  }

  ResponseBody _status(int status) =>
      ResponseBody.fromBytes(utf8.encode(''), status);

  @override
  void close({bool force = false}) {}
}
