import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import '../utils/app_logger.dart';
import '../utils/network_proxy.dart';
import 'backup_codec.dart';
import 'backup_error.dart';
import 'webdav_config.dart';
import 'webdav_listing.dart';

/// Deliberately independent from ApiClient/AppDio: no manga token, cookies,
/// auto-login, business interceptors or unredacted request logging.
class WebDavClient {
  static const _xmlLimit = 2 * 1024 * 1024;
  final WebDavConfig config;
  final Dio _dio;
  final Duration timeout;

  WebDavClient({
    required this.config,
    required WebDavCredentials credentials,
    HttpClientAdapter? adapter,
    this.timeout = const Duration(seconds: 30),
  }) : _dio = Dio(
         BaseOptions(
           connectTimeout: timeout,
           sendTimeout: timeout,
           receiveTimeout: timeout,
           followRedirects: false,
           maxRedirects: 0,
           responseType: ResponseType.stream,
           validateStatus: (_) => true,
           headers: {
             HttpHeaders.authorizationHeader:
                 'Basic ${base64Encode(utf8.encode('${credentials.username}:${credentials.password}'))}',
             HttpHeaders.acceptEncodingHeader: 'identity',
             HttpHeaders.userAgentHeader: 'kira-backup',
           },
         ),
       ) {
    if (credentials.username.contains(':') ||
        credentials.username.contains(RegExp(r'[\r\n]'))) {
      throw const WebDavException(WebDavErrorCode.invalidConfiguration);
    }
    _dio.httpClientAdapter =
        adapter ??
        IOHttpClientAdapter(
          createHttpClient: () =>
              NetworkProxy.createHttpClient(connectionTimeout: timeout)
                ..autoUncompress = false,
        );
  }

  void close() => _dio.close(force: true);

  Future<List<WebDavBackupEntry>> list({required CancelToken cancel}) async {
    final response = await _request(
      'PROPFIND',
      config.root,
      cancel: cancel,
      headers: {'Depth': '1', 'Content-Type': 'application/xml; charset=utf-8'},
      body: utf8.encode(webDavPropfindBody),
      accepted: {207, 404},
      limit: _xmlLimit,
    );
    if (response.status == 404) return [];
    return compute(_parseListing, (
      utf8.decode(response.bytes),
      config,
    ), debugLabel: 'backup.webdav_xml');
  }

  Future<void> _ensureDirectory(CancelToken cancel) async {
    final parts = config.server.pathSegments
        .where((s) => s.isNotEmpty)
        .toList();
    for (final segment in config.directorySegments) {
      parts.add(segment);
      final uri = config.server.replace(pathSegments: [...parts, '']);
      final result = await _request(
        'MKCOL',
        uri,
        cancel: cancel,
        accepted: {201, 405},
      );
      if (result.status == 405) {
        final existing = await _request(
          'PROPFIND',
          uri,
          cancel: cancel,
          headers: {
            'Depth': '0',
            'Content-Type': 'application/xml; charset=utf-8',
          },
          body: utf8.encode(webDavPropfindBody),
          accepted: {207},
          limit: _xmlLimit,
        );
        if (!webDavCollectionExists(utf8.decode(existing.bytes), uri, config)) {
          throw const WebDavException(WebDavErrorCode.forbidden);
        }
      }
    }
  }

  Future<void> testConnection({required CancelToken cancel}) async {
    await _ensureDirectory(cancel);
    await list(cancel: cancel);
    final temporary = config.fileUri(
      '.${BackupCodec.uniqueFileName('.probe')}',
    );
    final moved = config.fileUri(
      '.${BackupCodec.uniqueFileName('.probe-moved')}',
    );
    final data = BackupCodec.randomBytes(32);
    try {
      await _put(temporary, data, cancel);
      final downloaded = await _request(
        'GET',
        temporary,
        cancel: cancel,
        accepted: {200},
        limit: 32,
      );
      if (!listEquals(downloaded.bytes, data)) {
        throw const WebDavException(WebDavErrorCode.invalidResponse);
      }
      await _move(temporary, moved, cancel);
      final movedContent = await _request(
        'GET',
        moved,
        cancel: cancel,
        accepted: {200},
        limit: 32,
      );
      if (!listEquals(movedContent.bytes, data)) {
        throw const WebDavException(WebDavErrorCode.invalidResponse);
      }
      await _request(
        'DELETE',
        moved,
        cancel: cancel,
        accepted: {200, 202, 204},
      );
    } finally {
      // Cleanup is intentionally given its own token: cancelling a probe must
      // not strand its generated temporary files. Never deletes user backups.
      await _cleanup(temporary);
      await _cleanup(moved);
    }
  }

  Future<WebDavBackupEntry> upload(
    EncodedBackup backup, {
    required CancelToken cancel,
    ProgressCallback? onProgress,
  }) async {
    if (backup.bytes.length > BackupCodec.maxFileBytes) {
      throw const SettingsBackupException(SettingsBackupErrorCode.tooLarge);
    }
    await _ensureDirectory(cancel);
    final name = BackupCodec.uniqueFileName(backup.extension);
    final temporary = config.fileUri(
      '.${BackupCodec.uniqueFileName('.uploading')}',
    );
    try {
      await _put(temporary, backup.bytes, cancel, onProgress: onProgress);
      await _move(temporary, config.fileUri(name), cancel);
      return WebDavBackupEntry(
        name: name,
        size: backup.bytes.length,
        modified: DateTime.now().toUtc(),
      );
    } finally {
      await _cleanup(temporary);
    }
  }

  Future<Uint8List> download(
    WebDavBackupEntry entry, {
    required CancelToken cancel,
    ProgressCallback? onProgress,
  }) async {
    _checkEntry(entry);
    if ((entry.size ?? 0) > BackupCodec.maxFileBytes) {
      throw const SettingsBackupException(SettingsBackupErrorCode.tooLarge);
    }
    return (await _request(
      'GET',
      config.fileUri(entry.name),
      cancel: cancel,
      accepted: {200},
      limit: BackupCodec.maxFileBytes,
      onReceiveProgress: onProgress,
    )).bytes;
  }

  Future<void> delete(
    WebDavBackupEntry entry, {
    required CancelToken cancel,
  }) async {
    _checkEntry(entry);
    await _request(
      'DELETE',
      config.fileUri(entry.name),
      cancel: cancel,
      accepted: {200, 202, 204, 404},
    );
  }

  void _checkEntry(WebDavBackupEntry entry) {
    if (!WebDavBackupEntry.isBackupName(entry.name)) {
      throw const WebDavException(WebDavErrorCode.unsafePath);
    }
  }

  Future<void> _put(
    Uri uri,
    Uint8List bytes,
    CancelToken cancel, {
    ProgressCallback? onProgress,
  }) async {
    await _request(
      'PUT',
      uri,
      cancel: cancel,
      accepted: {200, 201, 204},
      headers: {
        'If-None-Match': '*',
        'Content-Type': 'application/octet-stream',
      },
      body: bytes,
      onSendProgress: onProgress,
    );
  }

  Future<void> _move(Uri source, Uri destination, CancelToken cancel) async {
    await _request(
      'MOVE',
      source,
      cancel: cancel,
      accepted: {201, 204},
      headers: {'Destination': destination.toString(), 'Overwrite': 'F'},
    );
  }

  Future<void> _cleanup(Uri uri) async {
    final token = CancelToken();
    final timer = Timer(const Duration(seconds: 5), token.cancel);
    try {
      await _request(
        'DELETE',
        uri,
        cancel: token,
        accepted: {200, 202, 204, 404},
      );
    } catch (_, stack) {
      // Do not log DioException: it contains URLs, Authorization and bodies.
      unawaited(
        AppLogger.instance.recordWarning(
          const WebDavException(WebDavErrorCode.connection),
          stackTrace: stack,
          source: 'backup.webdav_temporary_cleanup',
        ),
      );
    } finally {
      timer.cancel();
    }
  }

  Future<({int status, Uint8List bytes})> _request(
    String method,
    Uri uri, {
    required CancelToken cancel,
    required Set<int> accepted,
    Map<String, Object>? headers,
    List<int>? body,
    int limit = 16384,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    if (cancel.isCancelled) backupCancelled();
    if (!config.sameOrigin(uri)) {
      throw const WebDavException(WebDavErrorCode.unsafePath);
    }
    try {
      final response = await _dio.requestUri<ResponseBody>(
        uri,
        options: Options(
          method: method,
          headers: {
            ...?headers,
            if (body != null) HttpHeaders.contentLengthHeader: body.length,
          },
        ),
        data: body == null ? null : Stream.value(body),
        cancelToken: cancel,
        onSendProgress: onSendProgress,
      );
      final status = response.statusCode ?? 0;
      final stream = response.data;
      if (stream == null) {
        throw const WebDavException(WebDavErrorCode.invalidResponse);
      }
      if (!accepted.contains(status)) {
        await stream.stream.listen(null).cancel();
        throw _statusError(method, status);
      }
      final encoding = response.headers.value(
        HttpHeaders.contentEncodingHeader,
      );
      final length = int.tryParse(
        response.headers.value(HttpHeaders.contentLengthHeader) ?? '',
      );
      if ((encoding != null && encoding != 'identity') ||
          (length != null && length > limit)) {
        await stream.stream.listen(null).cancel();
        throw const SettingsBackupException(SettingsBackupErrorCode.tooLarge);
      }
      final output = BytesBuilder(copy: false);
      final chunks = StreamIterator(stream.stream.timeout(timeout));
      final cancelled = cancel.whenCancel.then((_) => false);
      try {
        while (await Future.any([chunks.moveNext(), cancelled])) {
          if (cancel.isCancelled) backupCancelled();
          final chunk = chunks.current;
          if (output.length + chunk.length > limit) {
            throw const SettingsBackupException(
              SettingsBackupErrorCode.tooLarge,
            );
          }
          output.add(chunk);
          onReceiveProgress?.call(output.length, length ?? -1);
        }
      } finally {
        await chunks.cancel();
      }
      if (cancel.isCancelled) backupCancelled();
      return (status: status, bytes: output.takeBytes());
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) backupCancelled();
      final timedOut = const {
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      }.contains(error.type);
      throw WebDavException(
        timedOut ? WebDavErrorCode.timeout : WebDavErrorCode.connection,
      );
    } on TimeoutException {
      throw const WebDavException(WebDavErrorCode.timeout);
    } on SocketException {
      throw const WebDavException(WebDavErrorCode.connection);
    }
  }

  WebDavException _statusError(String method, int status) =>
      WebDavException(switch (status) {
        >= 300 && < 400 => WebDavErrorCode.redirectRefused,
        401 => WebDavErrorCode.authentication,
        403 => WebDavErrorCode.forbidden,
        404 => WebDavErrorCode.notFound,
        405 || 501 when method == 'MOVE' => WebDavErrorCode.moveUnsupported,
        405 || 501 => WebDavErrorCode.methodUnsupported,
        409 || 412 => WebDavErrorCode.conflict,
        _ => WebDavErrorCode.invalidResponse,
      }, status: status);
}

List<WebDavBackupEntry> _parseListing((String, WebDavConfig) args) =>
    parseWebDavListing(args.$1, args.$2);
